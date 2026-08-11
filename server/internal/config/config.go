package config

import (
	"fmt"

	"github.com/spf13/viper"
)

type Config struct {
	Server    ServerConfig    `mapstructure:"server"`
	Database  DatabaseConfig  `mapstructure:"database"`
	Auth      AuthConfig      `mapstructure:"auth"`
	Message   MessageConfig   `mapstructure:"message"`
	Media     MediaConfig     `mapstructure:"media"`
	WireGuard WireGuardConfig `mapstructure:"wireguard"`
	Storage   StorageConfig   `mapstructure:"storage"`
}

type ServerConfig struct {
	Port   int    `mapstructure:"port"`
	Mode   string `mapstructure:"mode"`
	Domain string `mapstructure:"domain"`
}

type DatabaseConfig struct {
	Path string `mapstructure:"path"`
}

type AuthConfig struct {
	JWTSecret      string `mapstructure:"jwt_secret"`
	JWTExpireHours int    `mapstructure:"jwt_expire_hours"`
	AdminToken     string `mapstructure:"admin_token"`
}

type MessageConfig struct {
	RetentionDays int `mapstructure:"retention_days"`
}

type MediaConfig struct {
	PublicIP          string                  `mapstructure:"public_ip"`
	PublicIPDiscovery PublicIPDiscoveryConfig `mapstructure:"public_ip_discovery"`
	RTC               RTCConfig               `mapstructure:"rtc"`
	RTMP              RTMPConfig              `mapstructure:"rtmp"`
	TURN              TURNConfig              `mapstructure:"turn"`
}

type PublicIPDiscoveryConfig struct {
	Enabled                bool     `mapstructure:"enabled"`
	RefreshIntervalSeconds int      `mapstructure:"refresh_interval_seconds"`
	STUNServers            []string `mapstructure:"stun_servers"`
}

type RTCConfig struct {
	UDPPortMin uint16 `mapstructure:"udp_port_min"`
	UDPPortMax uint16 `mapstructure:"udp_port_max"`
	FFmpegPath string `mapstructure:"ffmpeg_path"`
}

type RTMPConfig struct {
	Port                  int  `mapstructure:"port"`
	AllowTemporaryStreams bool `mapstructure:"allow_temporary_streams"`
}

type TURNConfig struct {
	Enabled      bool   `mapstructure:"enabled"`
	Port         int    `mapstructure:"port"`
	Realm        string `mapstructure:"realm"`
	Username     string `mapstructure:"username"`
	Password     string `mapstructure:"password"`
	RelayPortMin uint16 `mapstructure:"relay_port_min"`
	RelayPortMax uint16 `mapstructure:"relay_port_max"`
}

type WireGuardConfig struct {
	ServerIP         string `mapstructure:"server_ip"`
	ListenPort       int    `mapstructure:"listen_port"`
	ServerPrivateKey string `mapstructure:"server_private_key"`
	PrivateKeyPath   string `mapstructure:"private_key_path"`
	Subnet           string `mapstructure:"subnet"`
	GatewayIP        string `mapstructure:"gateway_ip"`
}

type StorageConfig struct {
	Path          string `mapstructure:"path"`
	MaxFileSizeMB int    `mapstructure:"max_file_size_mb"`
}

var GlobalConfig *Config

func Load(configPath string) (*Config, error) {
	viper.SetConfigFile(configPath)
	viper.SetConfigType("yaml")
	viper.SetDefault("database.path", "./data/nexusroom.db")
	viper.SetDefault("media.public_ip_discovery.enabled", true)
	viper.SetDefault("media.public_ip_discovery.refresh_interval_seconds", 300)
	viper.SetDefault("media.public_ip_discovery.stun_servers", []string{
		"stun.cloudflare.com:3478",
		"stun.l.google.com:19302",
	})
	viper.SetDefault("media.rtc.udp_port_min", 50000)
	viper.SetDefault("media.rtc.udp_port_max", 50050)
	viper.SetDefault("media.rtc.ffmpeg_path", "ffmpeg")
	viper.SetDefault("media.rtmp.port", 1935)
	viper.SetDefault("media.rtmp.allow_temporary_streams", true)
	viper.SetDefault("media.turn.enabled", true)
	viper.SetDefault("media.turn.port", 3478)
	viper.SetDefault("media.turn.realm", "nexusroom")
	viper.SetDefault("media.turn.relay_port_min", 51000)
	viper.SetDefault("media.turn.relay_port_max", 51100)
	viper.SetDefault("wireguard.private_key_path", "./data/wireguard.key")
	if err := viper.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}
	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}
	GlobalConfig = &cfg
	return &cfg, nil
}

func (c *Config) GetDatabasePath() string {
	if c.Database.Path == "" {
		return "./data/nexusroom.db"
	}
	return c.Database.Path
}
