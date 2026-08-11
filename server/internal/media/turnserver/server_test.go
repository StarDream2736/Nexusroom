package turnserver

import (
	"net"
	"testing"
)

func TestDynamicRelayAddressGeneratorReadsCurrentIPv4(t *testing.T) {
	current := ""
	generator := &dynamicRelayAddressGenerator{
		publicIP: func() string { return current },
		address:  "127.0.0.1",
		minPort:  52100,
		maxPort:  52110,
	}
	if err := generator.Validate(); err != nil {
		t.Fatal(err)
	}
	if _, _, err := generator.AllocatePacketConn("udp4", 0); err == nil {
		t.Fatal("allocation must fail while public IPv4 is unavailable")
	}
	current = "198.51.100.40"
	connection, address, err := generator.AllocatePacketConn("udp4", 0)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	udpAddress, ok := address.(*net.UDPAddr)
	if !ok || !udpAddress.IP.Equal(net.ParseIP("198.51.100.40")) {
		t.Fatalf("relay address = %v", address)
	}
}
