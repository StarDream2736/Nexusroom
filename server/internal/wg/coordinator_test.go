package wg

import (
	"path/filepath"
	"testing"

	"nexusroom-server/internal/config"
)

func TestPersistentPrivateKey(t *testing.T) {
	keyPath := filepath.Join(t.TempDir(), "wireguard.key")
	first := &Coordinator{cfg: &config.WireGuardConfig{PrivateKeyPath: keyPath}}
	if err := first.loadOrCreatePrivateKey(); err != nil {
		t.Fatal(err)
	}
	if first.cfg.ServerPrivateKey == "" {
		t.Fatal("private key was not generated")
	}
	second := &Coordinator{cfg: &config.WireGuardConfig{PrivateKeyPath: keyPath}}
	if err := second.loadOrCreatePrivateKey(); err != nil {
		t.Fatal(err)
	}
	if second.cfg.ServerPrivateKey != first.cfg.ServerPrivateKey {
		t.Fatal("private key changed after reload")
	}
}
