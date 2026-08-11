package publicip

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strings"
	"sync/atomic"
	"time"

	"github.com/pion/stun"
)

const defaultProbeTimeout = 3 * time.Second

type ProbeFunc func(context.Context, string) (net.IP, error)

type Options struct {
	ManualIP        string
	Enabled         bool
	RefreshInterval time.Duration
	STUNServers     []string
	OnChange        func(previous, current string)
	Probe           ProbeFunc
	InterfaceIPs    func() ([]net.IP, error)
}

// Resolver owns the current IPv4 address advertised by NexusRoom. A configured
// address always wins; otherwise the resolver checks local interfaces and STUN.
type Resolver struct {
	manual          string
	enabled         bool
	refreshInterval time.Duration
	stunServers     []string
	onChange        func(previous, current string)
	probe           ProbeFunc
	interfaceIPs    func() ([]net.IP, error)
	current         atomic.Value
}

func New(options Options) (*Resolver, error) {
	manual := strings.TrimSpace(options.ManualIP)
	if manual != "" {
		parsed := net.ParseIP(manual)
		if parsed == nil || parsed.To4() == nil {
			return nil, fmt.Errorf("media.public_ip must be an IPv4 address: %q", manual)
		}
		manual = parsed.To4().String()
	}
	if options.RefreshInterval <= 0 {
		options.RefreshInterval = 5 * time.Minute
	}
	if options.Probe == nil {
		options.Probe = probeSTUN
	}
	if options.InterfaceIPs == nil {
		options.InterfaceIPs = interfaceIPv4s
	}
	resolver := &Resolver{
		manual:          manual,
		enabled:         options.Enabled,
		refreshInterval: options.RefreshInterval,
		stunServers:     append([]string(nil), options.STUNServers...),
		onChange:        options.OnChange,
		probe:           options.Probe,
		interfaceIPs:    options.InterfaceIPs,
	}
	resolver.current.Store(manual)
	return resolver, nil
}

func (r *Resolver) Current() string {
	value, _ := r.current.Load().(string)
	return value
}

func (r *Resolver) Automatic() bool {
	return r.manual == "" && r.enabled
}

func (r *Resolver) Refresh(ctx context.Context) error {
	if r.manual != "" {
		return nil
	}
	if !r.enabled {
		return errors.New("automatic public IPv4 discovery is disabled")
	}

	if addresses, err := r.interfaceIPs(); err == nil {
		for _, address := range addresses {
			if isPublicIPv4(address) {
				r.set(address.To4().String())
				return nil
			}
		}
	}

	var failures []string
	for _, server := range r.stunServers {
		server = strings.TrimSpace(server)
		if server == "" {
			continue
		}
		probeCtx, cancel := context.WithTimeout(ctx, defaultProbeTimeout)
		address, err := r.probe(probeCtx, server)
		cancel()
		if err != nil {
			failures = append(failures, server+": "+err.Error())
			continue
		}
		if !isPublicIPv4(address) {
			failures = append(failures, server+": returned a non-public IPv4 address")
			continue
		}
		r.set(address.To4().String())
		return nil
	}
	if len(failures) == 0 {
		return errors.New("no STUN server is configured for public IPv4 discovery")
	}
	return fmt.Errorf("public IPv4 discovery failed: %s", strings.Join(failures, "; "))
}

func (r *Resolver) Run(ctx context.Context, onError func(error)) {
	if !r.Automatic() {
		return
	}
	ticker := time.NewTicker(r.refreshInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := r.Refresh(ctx); err != nil && onError != nil {
				onError(err)
			}
		}
	}
}

func (r *Resolver) set(value string) {
	previous := r.Current()
	if previous == value {
		return
	}
	r.current.Store(value)
	if r.onChange != nil {
		r.onChange(previous, value)
	}
}

func interfaceIPv4s() ([]net.IP, error) {
	addresses, err := net.InterfaceAddrs()
	if err != nil {
		return nil, err
	}
	result := make([]net.IP, 0, len(addresses))
	for _, address := range addresses {
		var ip net.IP
		switch value := address.(type) {
		case *net.IPNet:
			ip = value.IP
		case *net.IPAddr:
			ip = value.IP
		}
		if ip != nil && ip.To4() != nil {
			result = append(result, ip.To4())
		}
	}
	return result, nil
}

func probeSTUN(ctx context.Context, server string) (net.IP, error) {
	address := strings.TrimPrefix(strings.TrimSpace(server), "stun:")
	if _, _, err := net.SplitHostPort(address); err != nil {
		address = net.JoinHostPort(strings.Trim(address, "[]"), "3478")
	}
	connection, err := (&net.Dialer{}).DialContext(ctx, "udp4", address)
	if err != nil {
		return nil, err
	}
	if deadline, ok := ctx.Deadline(); ok {
		_ = connection.SetDeadline(deadline)
	}
	client, err := stun.NewClient(connection)
	if err != nil {
		_ = connection.Close()
		return nil, err
	}
	defer client.Close()

	var mapped net.IP
	var responseErr error
	err = client.Do(stun.MustBuild(stun.TransactionID, stun.BindingRequest), func(event stun.Event) {
		if event.Error != nil {
			responseErr = event.Error
			return
		}
		var address stun.XORMappedAddress
		if decodeErr := address.GetFrom(event.Message); decodeErr != nil {
			responseErr = decodeErr
			return
		}
		mapped = append(net.IP(nil), address.IP...)
	})
	if err != nil {
		return nil, err
	}
	if responseErr != nil {
		return nil, responseErr
	}
	if mapped == nil || mapped.To4() == nil {
		return nil, errors.New("STUN response did not contain an IPv4 address")
	}
	return mapped.To4(), nil
}

func isPublicIPv4(ip net.IP) bool {
	ip = ip.To4()
	if ip == nil || !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
		return false
	}
	// Carrier-grade NAT space is not reachable as a public server address.
	return !(ip[0] == 100 && ip[1] >= 64 && ip[1] <= 127)
}
