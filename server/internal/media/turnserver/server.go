package turnserver

import (
	"errors"
	"fmt"
	"net"
	"strconv"

	"github.com/pion/turn/v2"
)

type Options struct {
	Enabled      bool
	PublicIP     string
	Port         int
	Realm        string
	Username     string
	Password     string
	RelayPortMin uint16
	RelayPortMax uint16
}

type Server struct {
	server   *turn.Server
	listener net.PacketConn
}

func Start(options Options) (*Server, error) {
	if !options.Enabled {
		return nil, nil
	}
	publicIP := net.ParseIP(options.PublicIP)
	if publicIP == nil || options.Username == "" || options.Password == "" {
		return nil, errors.New("TURN requires media.public_ip, username, and password")
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
			RelayAddressGenerator: &turn.RelayAddressGeneratorPortRange{
				RelayAddress: publicIP, Address: "0.0.0.0",
				MinPort: options.RelayPortMin, MaxPort: options.RelayPortMax,
			},
		}},
	})
	if err != nil {
		_ = listener.Close()
		return nil, fmt.Errorf("start TURN: %w", err)
	}
	return &Server{server: server, listener: listener}, nil
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
