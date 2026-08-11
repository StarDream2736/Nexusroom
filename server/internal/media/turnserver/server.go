package turnserver

import (
	"errors"
	"fmt"
	"net"
	"strconv"

	"github.com/pion/turn/v2"
)

type Options struct {
	Enabled          bool
	PublicIP         string
	PublicIPProvider func() string
	Port             int
	Realm            string
	Username         string
	Password         string
	RelayPortMin     uint16
	RelayPortMax     uint16
}

type Server struct {
	server   *turn.Server
	listener net.PacketConn
}

func Start(options Options) (*Server, error) {
	if !options.Enabled {
		return nil, nil
	}
	if options.Username == "" || options.Password == "" {
		return nil, errors.New("TURN requires username and password")
	}
	publicIPProvider := options.PublicIPProvider
	if publicIPProvider == nil {
		publicIP := options.PublicIP
		publicIPProvider = func() string { return publicIP }
	}
	if options.Port == 0 {
		options.Port = 3478
	}
	if options.Realm == "" {
		options.Realm = "nexusroom"
	}
	if options.RelayPortMin == 0 || options.RelayPortMax < options.RelayPortMin {
		options.RelayPortMin, options.RelayPortMax = 51000, 51100
	}
	listener, err := net.ListenPacket("udp4", ":"+strconv.Itoa(options.Port))
	if err != nil {
		return nil, fmt.Errorf("listen TURN: %w", err)
	}
	authKey := turn.GenerateAuthKey(options.Username, options.Realm, options.Password)
	server, err := turn.NewServer(turn.ServerConfig{
		Realm: options.Realm,
		AuthHandler: func(username, _ string, _ net.Addr) ([]byte, bool) {
			if username != options.Username {
				return nil, false
			}
			return authKey, true
		},
		PacketConnConfigs: []turn.PacketConnConfig{{
			PacketConn: listener,
			RelayAddressGenerator: &dynamicRelayAddressGenerator{
				publicIP: publicIPProvider, address: "0.0.0.0",
				minPort: options.RelayPortMin, maxPort: options.RelayPortMax,
			},
		}},
	})
	if err != nil {
		_ = listener.Close()
		return nil, fmt.Errorf("start TURN: %w", err)
	}
	return &Server{server: server, listener: listener}, nil
}

type dynamicRelayAddressGenerator struct {
	publicIP func() string
	address  string
	minPort  uint16
	maxPort  uint16
}

func (g *dynamicRelayAddressGenerator) Validate() error {
	if g.publicIP == nil {
		return errors.New("TURN public IPv4 provider is unavailable")
	}
	if g.address == "" || g.minPort == 0 || g.maxPort < g.minPort {
		return errors.New("invalid TURN relay address or port range")
	}
	return nil
}

func (g *dynamicRelayAddressGenerator) AllocatePacketConn(network string, requestedPort int) (net.PacketConn, net.Addr, error) {
	publicIP := net.ParseIP(g.publicIP())
	if publicIP == nil || publicIP.To4() == nil {
		return nil, nil, errors.New("TURN public IPv4 address is not available")
	}
	generator := &turn.RelayAddressGeneratorPortRange{
		RelayAddress: publicIP.To4(),
		Address:      g.address,
		MinPort:      g.minPort,
		MaxPort:      g.maxPort,
	}
	if err := generator.Validate(); err != nil {
		return nil, nil, err
	}
	return generator.AllocatePacketConn(network, requestedPort)
}

func (g *dynamicRelayAddressGenerator) AllocateConn(string, int) (net.Conn, net.Addr, error) {
	return nil, nil, errors.New("TCP TURN relay allocation is not supported")
}

func (s *Server) Close() error {
	if s == nil {
		return nil
	}
	if s.server != nil {
		return s.server.Close()
	}
	if s.listener != nil {
		return s.listener.Close()
	}
	return nil
}
