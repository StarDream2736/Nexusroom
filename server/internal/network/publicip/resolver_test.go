package publicip

import (
	"context"
	"net"
	"testing"
	"time"
)

func TestManualIPv4OverridesAutomaticDiscovery(t *testing.T) {
	probeCalled := false
	resolver, err := New(Options{
		ManualIP: "198.51.100.20",
		Enabled:  true,
		Probe: func(context.Context, string) (net.IP, error) {
			probeCalled = true
			return net.ParseIP("203.0.113.10"), nil
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := resolver.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if probeCalled {
		t.Fatal("automatic discovery ran despite manual override")
	}
	if got := resolver.Current(); got != "198.51.100.20" {
		t.Fatalf("current IP = %q", got)
	}
}

func TestResolverUsesIPv4OnlyAndRefreshesChanges(t *testing.T) {
	responses := []net.IP{net.ParseIP("2001:db8::1"), net.ParseIP("8.8.8.8"), net.ParseIP("1.1.1.1")}
	index := 0
	var changes [][2]string
	resolver, err := New(Options{
		Enabled:         true,
		RefreshInterval: time.Minute,
		STUNServers:     []string{"first:3478", "second:3478"},
		InterfaceIPs: func() ([]net.IP, error) {
			return []net.IP{net.ParseIP("192.168.1.2"), net.ParseIP("2001:db8::2")}, nil
		},
		Probe: func(context.Context, string) (net.IP, error) {
			result := responses[index]
			index++
			return result, nil
		},
		OnChange: func(previous, current string) {
			changes = append(changes, [2]string{previous, current})
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := resolver.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := resolver.Current(); got != "8.8.8.8" {
		t.Fatalf("first IPv4 = %q", got)
	}
	if err := resolver.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := resolver.Current(); got != "1.1.1.1" {
		t.Fatalf("refreshed IPv4 = %q", got)
	}
	if len(changes) != 2 || changes[1] != [2]string{"8.8.8.8", "1.1.1.1"} {
		t.Fatalf("changes = %#v", changes)
	}
}

func TestResolverRejectsIPv6ManualOverride(t *testing.T) {
	if _, err := New(Options{ManualIP: "2001:db8::1", Enabled: true}); err == nil {
		t.Fatal("IPv6 manual override must be rejected")
	}
}

func TestCGNATAddressIsNotPublic(t *testing.T) {
	if isPublicIPv4(net.ParseIP("100.64.10.1")) {
		t.Fatal("CGNAT address must not be advertised")
	}
}
