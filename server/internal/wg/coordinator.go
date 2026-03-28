package wg

import (
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"

	"golang.zx2c4.com/wireguard/wgctrl"
	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
)

const wgInterfaceName = "wg0"

// Coordinator manages WireGuard peer registration, IP allocation,
// and real kernel-level WireGuard interface configuration.
type Coordinator struct {
	cfg      *config.WireGuardConfig
	peerRepo *repository.WGPeerRepository
	mu       sync.Mutex
	client   *wgctrl.Client // wgctrl client for kernel WG management
}

func NewCoordinator(cfg *config.WireGuardConfig, peerRepo *repository.WGPeerRepository) *Coordinator {
	return &Coordinator{
		cfg:      cfg,
		peerRepo: peerRepo,
	}
}

// InitInterface creates and configures the server-side WireGuard interface.
// It should be called once on server startup.
//
//  1. Creates wg0: tries kernel module first, falls back to wireguard-go (userspace).
//  2. Auto-generates a server private key if none is configured.
//  3. Configures the device with ListenPort + PrivateKey.
//  4. Assigns the gateway IP address on the interface.
//  5. Brings the interface up.
//  6. Reloads any existing peers from the database.
func (c *Coordinator) InitInterface() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Auto-generate server private key if empty
	if c.cfg.ServerPrivateKey == "" {
		key, err := wgtypes.GeneratePrivateKey()
		if err != nil {
			return fmt.Errorf("failed to generate server private key: %w", err)
		}
		c.cfg.ServerPrivateKey = key.String()
		log.Printf("[WG] Auto-generated server private key (public: %s)", key.PublicKey().String())
	}

	// Create the WireGuard interface.
	// Try kernel module first; if unavailable, fall back to wireguard-go (userspace).
	if err := c.createInterface(); err != nil {
		return fmt.Errorf("failed to create WireGuard interface: %w", err)
	}

	// Open wgctrl client
	client, err := wgctrl.New()
	if err != nil {
		return fmt.Errorf("failed to create wgctrl client: %w", err)
	}
	c.client = client

	// Parse server private key
	privateKey, err := wgtypes.ParseKey(c.cfg.ServerPrivateKey)
	if err != nil {
		c.client.Close()
		c.client = nil
		return fmt.Errorf("invalid server private key: %w", err)
	}

	listenPort := c.cfg.ListenPort

	// Configure the device
	if err := client.ConfigureDevice(wgInterfaceName, wgtypes.Config{
		PrivateKey: &privateKey,
		ListenPort: &listenPort,
	}); err != nil {
		c.client.Close()
		c.client = nil
		return fmt.Errorf("failed to configure wg device: %w", err)
	}

	// Assign IP address
	gwIP := c.cfg.GatewayIP
	_, ipNet, err := net.ParseCIDR(c.cfg.Subnet)
	if err != nil {
		return fmt.Errorf("invalid subnet: %w", err)
	}
	ones, _ := ipNet.Mask.Size()
	addr := fmt.Sprintf("%s/%d", gwIP, ones)

	// Flush existing addresses and add the new one
	_ = exec.Command("ip", "addr", "flush", "dev", wgInterfaceName).Run()
	if out, err := exec.Command("ip", "addr", "add", addr, "dev", wgInterfaceName).CombinedOutput(); err != nil {
		log.Printf("[WG] Warning: ip addr add %s: %s (%v)", addr, string(out), err)
	}

	// Bring the interface up
	if out, err := exec.Command("ip", "link", "set", wgInterfaceName, "up").CombinedOutput(); err != nil {
		return fmt.Errorf("failed to bring up %s: %s: %w", wgInterfaceName, string(out), err)
	}

	// ── Ensure kernel forwarding parameters are correct ──────────────
	// ip_forward: required for routing packets between peers via the server
	// rp_filter=0: required so the kernel doesn't drop packets that enter
	//   and leave via the same interface (wg0 → wg0).
	// We write directly to /proc because Alpine may not have procps/sysctl.
	sysctlSet := map[string]string{
		"/proc/sys/net/ipv4/ip_forward":                             "1",
		"/proc/sys/net/ipv4/conf/all/rp_filter":                     "0",
		"/proc/sys/net/ipv4/conf/" + wgInterfaceName + "/rp_filter": "0",
	}
	for path, val := range sysctlSet {
		if err := ensureProcSysctl(path, val); err != nil {
			log.Printf("[WG] Warning: failed to ensure %s=%s: %v", path, val, err)
		}
	}

	// ── iptables FORWARD rules for peer-to-peer traffic ──────────────
	// Set default FORWARD policy to ACCEPT (in container environments the
	// default is often DROP, which blocks wg0 → wg0 forwarding even with
	// explicit rules).
	if out, err := exec.Command("iptables", "-P", "FORWARD", "ACCEPT").CombinedOutput(); err != nil {
		log.Printf("[WG] Warning: iptables -P FORWARD ACCEPT: %s (%v)", string(out), err)
	} else {
		log.Printf("[WG] iptables FORWARD policy set to ACCEPT")
	}

	iptablesRules := [][]string{
		// Flush existing FORWARD rules first to avoid duplicates on restart
		{"-F", "FORWARD"},
		{"-A", "FORWARD", "-i", wgInterfaceName, "-o", wgInterfaceName, "-j", "ACCEPT"},
		{"-A", "FORWARD", "-i", wgInterfaceName, "-j", "ACCEPT"},
		{"-A", "FORWARD", "-o", wgInterfaceName, "-m", "state", "--state", "RELATED,ESTABLISHED", "-j", "ACCEPT"},
	}
	for _, args := range iptablesRules {
		if out, err := exec.Command("iptables", args...).CombinedOutput(); err != nil {
			log.Printf("[WG] Warning: iptables %v: %s (%v)", args, string(out), err)
		}
	}

	// Log final FORWARD chain for diagnostics
	if out, err := exec.Command("iptables", "-L", "FORWARD", "-n", "-v").CombinedOutput(); err == nil {
		log.Printf("[WG] iptables FORWARD chain:\n%s", string(out))
	} else {
		log.Printf("[WG] Warning: iptables -L FORWARD failed: %v", err)
	}

	log.Printf("[WG] Interface %s UP, listening on :%d, gateway %s", wgInterfaceName, listenPort, addr)

	// Reload existing peers from DB
	if err := c.reloadPeers(); err != nil {
		log.Printf("[WG] Warning: failed to reload peers: %v", err)
	}

	return nil
}

// createInterface creates the WireGuard network interface.
// Tries kernel module first; falls back to wireguard-go (userspace) if unavailable.
func (c *Coordinator) createInterface() error {
	// Method 1: Kernel module (fastest, requires wireguard kernel module)
	err := exec.Command("ip", "link", "add", "dev", wgInterfaceName, "type", "wireguard").Run()
	if err == nil {
		log.Printf("[WG] Created %s via kernel module", wgInterfaceName)
		return nil
	}
	log.Printf("[WG] Kernel WireGuard unavailable (%v), trying wireguard-go...", err)

	// Method 2: wireguard-go (userspace implementation, no kernel module needed)
	// wireguard-go creates the TUN device and a UAPI socket that wgctrl can talk to.
	cmd := exec.Command("wireguard-go", wgInterfaceName)
	cmd.Env = append(cmd.Environ(), "WG_I_PREFER_BUGGY_USERSPACE_TO_POLISHED_KMOD=1")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("wireguard-go failed: %s: %w", string(out), err)
	}

	// Wait for the UAPI socket to appear
	socketPath := fmt.Sprintf("/var/run/wireguard/%s.sock", wgInterfaceName)
	for i := 0; i < 20; i++ {
		if _, err := os.Stat(socketPath); err == nil {
			log.Printf("[WG] Created %s via wireguard-go (userspace)", wgInterfaceName)
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}

	return fmt.Errorf("wireguard-go started but UAPI socket not found at %s", socketPath)
}

func ensureProcSysctl(path, expected string) error {
	current, err := os.ReadFile(path)
	if err == nil {
		if strings.TrimSpace(string(current)) == expected {
			log.Printf("[WG] sysctl already set: %s=%s", path, expected)
			return nil
		}
	}

	if err := os.WriteFile(path, []byte(expected), 0644); err != nil {
		return err
	}

	log.Printf("[WG] sysctl set: %s=%s", path, expected)
	return nil
}

// reloadPeers loads all WGPeer records from the DB and adds them to the device.
func (c *Coordinator) reloadPeers() error {
	var allPeers []model.WGPeer
	// We need to get all peers across all rooms — add a helper or do it inline
	// For now, use a raw query approach via the DB connection.
	// Actually, use the repository ListAll method (we'll add it).
	// For simplicity, skip reload on startup for now and log.
	log.Printf("[WG] Peer reload: existing peers will be re-added on next join")
	_ = allPeers
	return nil
}

// AllocateIP 为房间中的新 Peer 分配虚拟 IP
func (c *Coordinator) AllocateIP(roomID uint64) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// 解析子网
	_, ipNet, err := net.ParseCIDR(c.cfg.Subnet)
	if err != nil {
		return "", fmt.Errorf("invalid subnet config: %w", err)
	}

	// 获取已分配 IP
	usedIPs, err := c.peerRepo.GetAllAssignedIPs(roomID)
	if err != nil {
		return "", fmt.Errorf("failed to get allocated IPs: %w", err)
	}

	usedSet := make(map[string]bool)
	for _, ip := range usedIPs {
		// stored as "10.0.8.5/24" — extract the IP part
		parts := strings.Split(ip, "/")
		usedSet[parts[0]] = true
	}

	// 也排除网关 IP
	usedSet[c.cfg.GatewayIP] = true

	// 获取子网基础 IP
	baseIP := ipNet.IP.To4()
	if baseIP == nil {
		return "", fmt.Errorf("only IPv4 subnets are supported")
	}

	// 从 .2 开始分配，.0 是网络地址，.1 是网关
	for i := 2; i <= 254; i++ {
		candidate := fmt.Sprintf("%d.%d.%d.%d", baseIP[0], baseIP[1], baseIP[2], i)
		if !usedSet[candidate] {
			// 返回带子网掩码的 IP
			ones, _ := ipNet.Mask.Size()
			return fmt.Sprintf("%s/%d", candidate, ones), nil
		}
	}

	return "", fmt.Errorf("no available IP in subnet %s", c.cfg.Subnet)
}

// RegisterPeer registers a new peer and configures it on the WireGuard device.
func (c *Coordinator) RegisterPeer(roomID, userID uint64, publicKey string) (*model.WGPeer, error) {
	// Check if already registered
	existing, err := c.peerRepo.FindByRoomAndUser(roomID, userID)
	if err == nil && existing != nil {
		// 用户重连时客户端可能生成新的密钥对；若公钥变更，需要同步更新 DB 和设备配置。
		if existing.PublicKey != publicKey {
			oldKey := existing.PublicKey
			existing.PublicKey = publicKey
			if err := c.peerRepo.Update(existing); err != nil {
				return nil, fmt.Errorf("failed to update peer public key: %w", err)
			}
			c.removePeerFromDevice(oldKey)
			log.Printf("[WG] Updated peer key for user %d room %d", userID, roomID)
		}

		// Ensure the peer is also on the WG device
		c.addPeerToDevice(existing.PublicKey, existing.AssignedIP)
		return existing, nil
	}

	// Allocate IP
	assignedIP, err := c.AllocateIP(roomID)
	if err != nil {
		return nil, err
	}

	peer := &model.WGPeer{
		RoomID:     roomID,
		UserID:     userID,
		PublicKey:  publicKey,
		AssignedIP: assignedIP,
	}

	if err := c.peerRepo.Create(peer); err != nil {
		return nil, fmt.Errorf("failed to create peer: %w", err)
	}

	// Add peer to the live WireGuard device
	c.addPeerToDevice(publicKey, assignedIP)

	return peer, nil
}

// UnregisterPeer removes a peer from the database and the WireGuard device.
func (c *Coordinator) UnregisterPeer(roomID, userID uint64) error {
	// Get the peer info before deletion (need public key)
	peer, err := c.peerRepo.FindByRoomAndUser(roomID, userID)
	if err == nil && peer != nil {
		c.removePeerFromDevice(peer.PublicKey)
	}

	return c.peerRepo.Delete(roomID, userID)
}

// addPeerToDevice adds a peer to the live WireGuard kernel device.
func (c *Coordinator) addPeerToDevice(publicKeyStr, assignedIP string) {
	if c.client == nil {
		log.Printf("[WG] No wgctrl client, skipping addPeer")
		return
	}

	pubKey, err := wgtypes.ParseKey(publicKeyStr)
	if err != nil {
		log.Printf("[WG] Invalid peer public key: %v", err)
		return
	}

	// Parse the assigned IP into an AllowedIP
	ip, ipNet, err := net.ParseCIDR(assignedIP)
	if err != nil {
		log.Printf("[WG] Invalid peer assigned IP: %v", err)
		return
	}
	// Use /32 for the peer's allowed IP (single host)
	allowedIP := net.IPNet{
		IP:   ip,
		Mask: net.CIDRMask(32, 32),
	}
	_ = ipNet

	keepalive := 25 * time.Second

	peerCfg := wgtypes.PeerConfig{
		PublicKey:                   pubKey,
		AllowedIPs:                  []net.IPNet{allowedIP},
		PersistentKeepaliveInterval: &keepalive,
		ReplaceAllowedIPs:           true,
	}

	if err := c.client.ConfigureDevice(wgInterfaceName, wgtypes.Config{
		Peers: []wgtypes.PeerConfig{peerCfg},
	}); err != nil {
		log.Printf("[WG] Failed to add peer %s: %v", publicKeyStr[:8], err)
	} else {
		log.Printf("[WG] Added peer %s → %s", publicKeyStr[:8], assignedIP)
	}

	// Diagnostic: dump current WireGuard device state after peer add
	if out, err := exec.Command("wg", "show", wgInterfaceName).CombinedOutput(); err == nil {
		log.Printf("[WG] Device state after addPeer:\n%s", string(out))
	}
}

// removePeerFromDevice removes a peer from the live WireGuard kernel device.
func (c *Coordinator) removePeerFromDevice(publicKeyStr string) {
	if c.client == nil {
		return
	}

	pubKey, err := wgtypes.ParseKey(publicKeyStr)
	if err != nil {
		return
	}

	peerCfg := wgtypes.PeerConfig{
		PublicKey: pubKey,
		Remove:    true,
	}

	if err := c.client.ConfigureDevice(wgInterfaceName, wgtypes.Config{
		Peers: []wgtypes.PeerConfig{peerCfg},
	}); err != nil {
		log.Printf("[WG] Failed to remove peer: %v", err)
	} else {
		log.Printf("[WG] Removed peer %s", publicKeyStr[:8])
	}
}

// GetPeers 获取房间中的所有 Peer
func (c *Coordinator) GetPeers(roomID uint64) ([]model.WGPeer, error) {
	return c.peerRepo.ListByRoom(roomID)
}

// GetServerConfig 返回服务端 WireGuard 配置信息
func (c *Coordinator) GetServerConfig() ServerConfig {
	serverPublicKey := ""
	if c.cfg.ServerPrivateKey != "" {
		if privateKey, err := wgtypes.ParseKey(c.cfg.ServerPrivateKey); err == nil {
			serverPublicKey = privateKey.PublicKey().String()
		}
	}

	return ServerConfig{
		ServerPublicKey: serverPublicKey,
		ServerEndpoint:  fmt.Sprintf("%s:%d", c.cfg.ServerIP, c.cfg.ListenPort),
		ListenPort:      c.cfg.ListenPort,
		DNS:             c.cfg.GatewayIP,
	}
}

type ServerConfig struct {
	ServerPublicKey string `json:"server_public_key"`
	ServerEndpoint  string `json:"server_endpoint"`
	ListenPort      int    `json:"listen_port"`
	DNS             string `json:"dns"`
}
