package wg

import (
	"fmt"
	"net"
	"strings"
	"sync"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"

	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
)

// Coordinator 管理 WireGuard Peer 注册、IP 分配
type Coordinator struct {
	cfg      *config.WireGuardConfig
	peerRepo *repository.WGPeerRepository
	mu       sync.Mutex
}

func NewCoordinator(cfg *config.WireGuardConfig, peerRepo *repository.WGPeerRepository) *Coordinator {
	return &Coordinator{
		cfg:      cfg,
		peerRepo: peerRepo,
	}
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

// RegisterPeer 注册新 Peer 并分配 IP
func (c *Coordinator) RegisterPeer(roomID, userID uint64, publicKey string) (*model.WGPeer, error) {
	// 检查是否已注册
	existing, err := c.peerRepo.FindByRoomAndUser(roomID, userID)
	if err == nil && existing != nil {
		return existing, nil // 已存在则直接返回
	}

	// 分配 IP
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

	return peer, nil
}

// UnregisterPeer 注销 Peer 并释放 IP
func (c *Coordinator) UnregisterPeer(roomID, userID uint64) error {
	return c.peerRepo.Delete(roomID, userID)
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
		DNS:             c.cfg.GatewayIP,
	}
}

type ServerConfig struct {
	ServerPublicKey string `json:"server_public_key"`
	ServerEndpoint  string `json:"server_endpoint"`
	DNS             string `json:"dns"`
}
