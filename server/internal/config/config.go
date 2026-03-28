package config

import (
	"fmt"

	"github.com/spf13/viper"
)

type Config struct {
	Server    ServerConfig    `mapstructure:"server"`
	Database  DatabaseConfig  `mapstructure:"database"`
	Redis     RedisConfig     `mapstructure:"redis"`
	Auth      AuthConfig      `mapstructure:"auth"`
	Message   MessageConfig   `mapstructure:"message"`
	LiveKit   LiveKitConfig   `mapstructure:"livekit"`
	SRS       SRSConfig       `mapstructure:"srs"`
	WireGuard WireGuardConfig `mapstructure:"wireguard"`
	Storage   StorageConfig   `mapstructure:"storage"`
}

type ServerConfig struct {
	Port   int    `mapstructure:"port"`
	Mode   string `mapstructure:"mode"`
	Domain string `mapstructure:"domain"`
}

type DatabaseConfig struct {
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	Name     string `mapstructure:"name"`
	User     string `mapstructure:"user"`
	Password string `mapstructure:"password"`
}

type RedisConfig struct {
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	Password string `mapstructure:"password"`
}

type AuthConfig struct {
	JWTSecret      string `mapstructure:"jwt_secret"`
	JWTExpireHours int    `mapstructure:"jwt_expire_hours"`
	AdminToken     string `mapstructure:"admin_token"`
}

type MessageConfig struct {
	RetentionDays int `mapstructure:"retention_days"`
}

type LiveKitConfig struct {
	URL       string `mapstructure:"url"`
	PublicURL string `mapstructure:"public_url"`
	APIKey    string `mapstructure:"api_key"`
	APISecret string `mapstructure:"api_secret"`
}

type SRSConfig struct {
	RTMPPort int    `mapstructure:"rtmp_port"`
	HTTPPort int    `mapstructure:"http_port"`
	APIPort  int    `mapstructure:"api_port"`
	Host     string `mapstructure:"host"` // SRS Docker 服务名（内网），默认 srs
}

type WireGuardConfig struct {
	ServerIP         string `mapstructure:"server_ip"`
	ListenPort       int    `mapstructure:"listen_port"`
	ServerPrivateKey string `mapstructure:"server_private_key"`
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

func (c *Config) GetDSN() string {
	return fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
		c.Database.Host, c.Database.Port, c.Database.User, c.Database.Password, c.Database.Name)
}

func (c *Config) GetRedisAddr() string {
	return fmt.Sprintf("%s:%d", c.Redis.Host, c.Redis.Port)
}
