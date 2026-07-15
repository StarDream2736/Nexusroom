package keygen

import (
	"encoding/base64"

	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
)

// Result holds a WireGuard key pair.
type Result struct {
	PrivateKey string `json:"private_key"`
	PublicKey  string `json:"public_key"`
}

// Generate creates a new WireGuard private/public key pair.
func Generate() (*Result, error) {
	privateKey, err := wgtypes.GeneratePrivateKey()
	if err != nil {
		return nil, err
	}
	publicKey := privateKey.PublicKey()

	return &Result{
		PrivateKey: base64.StdEncoding.EncodeToString(privateKey[:]),
		PublicKey:  base64.StdEncoding.EncodeToString(publicKey[:]),
	}, nil
}
