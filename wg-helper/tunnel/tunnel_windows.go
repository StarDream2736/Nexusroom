package tunnel

import (
	"encoding/base64"
	"fmt"
	"log"
	"net"
	"os/exec"
	"strings"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/ipc"
	"golang.zx2c4.com/wireguard/tun"
)

// Config represents a WireGuard tunnel configuration received from the client.
type Config struct {
	InterfaceName string `json:"interface_name"` // e.g. "NexusRoom0"
	PrivateKey    string `json:"private_key"`    // base64
	Address       string `json:"address"`        // CIDR, e.g. "10.0.8.2/24"
	DNS           string `json:"dns,omitempty"`  // optional
	ListenPort    int    `json:"listen_port,omitempty"`
	Peers         []Peer `json:"peers"`
}

// Peer represents a WireGuard peer.
type Peer struct {
	PublicKey           string `json:"public_key"`                     // base64
	Endpoint            string `json:"endpoint"`                       // host:port
	AllowedIPs          string `json:"allowed_ips"`                    // comma-separated CIDRs
	PersistentKeepalive int    `json:"persistent_keepalive,omitempty"` // seconds
}

// Tunnel wraps a running WireGuard tunnel instance.
type Tunnel struct {
	device *device.Device
	uapi   net.Listener
	tunDev tun.Device
	name   string
}

// Up creates and starts a WireGuard tunnel with the given config.
func Up(cfg *Config) (*Tunnel, error) {
	ifname := cfg.InterfaceName
	if ifname == "" {
		ifname = "NexusRoom0"
	}

	// Create TUN device via wintun
	tunDev, err := tun.CreateTUN(ifname, device.DefaultMTU)
	if err != nil {
		return nil, fmt.Errorf("failed to create TUN device: %w", err)
	}

	// Get the real interface name
	realName, err := tunDev.Name()
	if err != nil {
		tunDev.Close()
		return nil, fmt.Errorf("failed to get TUN name: %w", err)
	}
	log.Printf("Created TUN device: %s", realName)

	// Build UAPI config string
	uapiConf, err := buildUAPIConfig(cfg)
	if err != nil {
		tunDev.Close()
		return nil, fmt.Errorf("invalid config: %w", err)
	}

	// Create the device
	logger := device.NewLogger(device.LogLevelVerbose, fmt.Sprintf("(%s) ", ifname))
	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), logger)

	// Apply configuration via IPC
	if err := dev.IpcSet(uapiConf); err != nil {
		dev.Close()
		return nil, fmt.Errorf("failed to set device config: %w", err)
	}

	// Bring the device up
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, fmt.Errorf("failed to bring device up: %w", err)
	}

	// Configure the IP address on the interface
	if err := configureInterface(realName, cfg.Address); err != nil {
		dev.Close()
		return nil, fmt.Errorf("failed to configure IP: %w", err)
	}

	// Add routes for peer allowed IPs
	for _, peer := range cfg.Peers {
		if peer.AllowedIPs != "" {
			for _, cidr := range strings.Split(peer.AllowedIPs, ",") {
				cidr = strings.TrimSpace(cidr)
				if cidr != "" && cidr != cfg.Address {
					addRoute(cidr, realName)
				}
			}
		}
	}

	// Set up UAPI socket for external management
	uapiListener, err := ipc.UAPIListen(ifname)
	if err != nil {
		log.Printf("Warning: failed to create UAPI listener: %v", err)
		return &Tunnel{
			device: dev,
			tunDev: tunDev,
			name:   realName,
		}, nil
	}

	go func() {
		for {
			c, err := uapiListener.Accept()
			if err != nil {
				return
			}
			go dev.IpcHandle(c)
		}
	}()

	return &Tunnel{
		device: dev,
		uapi:   uapiListener,
		tunDev: tunDev,
		name:   realName,
	}, nil
}

// Down tears down the tunnel.
func (t *Tunnel) Down() {
	if t.uapi != nil {
		t.uapi.Close()
	}
	if t.device != nil {
		t.device.Close()
	}
	// tunDev is closed by device.Close()
}

// Name returns the interface name.
func (t *Tunnel) Name() string {
	return t.name
}

// buildUAPIConfig converts Config to a WireGuard UAPI configuration string.
func buildUAPIConfig(cfg *Config) (string, error) {
	var sb strings.Builder

	// Private key (hex-encoded)
	privKeyBytes, err := base64.StdEncoding.DecodeString(cfg.PrivateKey)
	if err != nil {
		return "", fmt.Errorf("invalid private key: %w", err)
	}
	sb.WriteString(fmt.Sprintf("private_key=%x\n", privKeyBytes))

	if cfg.ListenPort > 0 {
		sb.WriteString(fmt.Sprintf("listen_port=%d\n", cfg.ListenPort))
	}

	// Peers
	for _, peer := range cfg.Peers {
		pubKeyBytes, err := base64.StdEncoding.DecodeString(peer.PublicKey)
		if err != nil {
			return "", fmt.Errorf("invalid peer public key: %w", err)
		}
		sb.WriteString(fmt.Sprintf("public_key=%x\n", pubKeyBytes))

		if peer.Endpoint != "" {
			sb.WriteString(fmt.Sprintf("endpoint=%s\n", peer.Endpoint))
		}

		if peer.AllowedIPs != "" {
			for _, cidr := range strings.Split(peer.AllowedIPs, ",") {
				cidr = strings.TrimSpace(cidr)
				if cidr != "" {
					sb.WriteString(fmt.Sprintf("allowed_ip=%s\n", cidr))
				}
			}
		}

		if peer.PersistentKeepalive > 0 {
			sb.WriteString(fmt.Sprintf("persistent_keepalive_interval=%d\n", peer.PersistentKeepalive))
		}
	}

	return sb.String(), nil
}

// configureInterface sets the IP address on the WireGuard interface using netsh.
func configureInterface(ifname string, address string) error {
	ip, ipNet, err := net.ParseCIDR(address)
	if err != nil {
		return fmt.Errorf("invalid address %q: %w", address, err)
	}

	mask := net.IP(ipNet.Mask)

	cmd := exec.Command("netsh",
		"interface", "ip", "set", "address",
		fmt.Sprintf("name=%s", ifname),
		"source=static",
		fmt.Sprintf("addr=%s", ip.String()),
		fmt.Sprintf("mask=%s", mask.String()),
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("netsh set address failed: %s: %w", string(output), err)
	}
	log.Printf("Interface %s configured with %s", ifname, address)
	return nil
}

// addRoute adds a route for a given CIDR through the WireGuard interface.
func addRoute(cidr string, ifname string) {
	_, ipNet, err := net.ParseCIDR(cidr)
	if err != nil {
		log.Printf("Warning: invalid CIDR for route: %s", cidr)
		return
	}

	mask := net.IP(ipNet.Mask)

	cmd := exec.Command("netsh",
		"interface", "ip", "add", "route",
		fmt.Sprintf("prefix=%s", cidr),
		fmt.Sprintf("interface=%s", ifname),
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		// Try alternative: route add
		cmd2 := exec.Command("route", "add",
			ipNet.IP.String(),
			"mask", mask.String(),
			"0.0.0.0",
			"if", ifname,
		)
		output2, err2 := cmd2.CombinedOutput()
		if err2 != nil {
			log.Printf("Warning: failed to add route for %s: %s / %s", cidr, string(output), string(output2))
		}
	}
}
