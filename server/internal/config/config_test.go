package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/spf13/viper"
)

func TestTemporaryRTMPStreamsAreEnabledByDefault(t *testing.T) {
	viper.Reset()
	t.Cleanup(viper.Reset)
	path := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(path, []byte("media:\n  rtmp:\n    port: 1935\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.Media.RTMP.AllowTemporaryStreams {
		t.Fatal("temporary RTMP streams must be enabled by default")
	}
	if cfg.Media.RTC.FFmpegPath != "ffmpeg" {
		t.Fatalf("default FFmpeg path = %q, want ffmpeg", cfg.Media.RTC.FFmpegPath)
	}
	if !cfg.Media.PublicIPDiscovery.Enabled {
		t.Fatal("public IPv4 discovery must be enabled by default")
	}
	if cfg.Media.PublicIPDiscovery.RefreshIntervalSeconds != 300 {
		t.Fatalf("public IPv4 refresh interval = %d", cfg.Media.PublicIPDiscovery.RefreshIntervalSeconds)
	}
	if len(cfg.Media.PublicIPDiscovery.STUNServers) == 0 {
		t.Fatal("default STUN discovery server list must not be empty")
	}
}

func TestPublicIPDiscoveryCanBeDisabledForManualConfiguration(t *testing.T) {
	viper.Reset()
	t.Cleanup(viper.Reset)
	path := filepath.Join(t.TempDir(), "config.yaml")
	content := "media:\n  public_ip: 198.51.100.8\n  public_ip_discovery:\n    enabled: false\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Media.PublicIP != "198.51.100.8" {
		t.Fatalf("manual public IP = %q", cfg.Media.PublicIP)
	}
	if cfg.Media.PublicIPDiscovery.Enabled {
		t.Fatal("explicit false must disable public IPv4 discovery")
	}
}

func TestFFmpegPathCanBeConfigured(t *testing.T) {
	viper.Reset()
	t.Cleanup(viper.Reset)
	path := filepath.Join(t.TempDir(), "config.yaml")
	content := "media:\n  rtc:\n    ffmpeg_path: /opt/nexusroom/bin/ffmpeg\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Media.RTC.FFmpegPath != "/opt/nexusroom/bin/ffmpeg" {
		t.Fatalf("FFmpeg path = %q", cfg.Media.RTC.FFmpegPath)
	}
}

func TestTemporaryRTMPStreamsCanBeDisabled(t *testing.T) {
	viper.Reset()
	t.Cleanup(viper.Reset)
	path := filepath.Join(t.TempDir(), "config.yaml")
	content := "media:\n  rtmp:\n    port: 1935\n    allow_temporary_streams: false\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Media.RTMP.AllowTemporaryStreams {
		t.Fatal("explicit false must disable temporary RTMP streams")
	}
}
