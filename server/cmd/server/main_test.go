package main

import (
	"errors"
	"testing"

	"nexusroom-server/internal/config"
	mediastream "nexusroom-server/internal/media/stream"
)

type fakeStreamKeyLookup struct {
	exists bool
	err    error
}

func (f fakeStreamKeyLookup) ExistsByStreamKey(string) (bool, error) {
	return f.exists, f.err
}

func TestRTMPAuthorizer(t *testing.T) {
	tests := []struct {
		name           string
		allowTemporary bool
		lookup         fakeStreamKeyLookup
		want           bool
	}{
		{name: "known ingress", lookup: fakeStreamKeyLookup{exists: true}, want: true},
		{name: "temporary enabled", allowTemporary: true, lookup: fakeStreamKeyLookup{}, want: true},
		{name: "temporary disabled", lookup: fakeStreamKeyLookup{}, want: false},
		{name: "repository error", allowTemporary: true, lookup: fakeStreamKeyLookup{err: errors.New("database unavailable")}, want: false},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			authorize := newRTMPAuthorizer(test.allowTemporary, mediastream.NewRegistry(), test.lookup)
			if got := authorize("temporary-stream"); got != test.want {
				t.Fatalf("authorize() = %v, want %v", got, test.want)
			}
		})
	}
}

func TestRTMPAuthorizerRejectsActiveKey(t *testing.T) {
	streams := mediastream.NewRegistry()
	streams.Start("active-stream", nil, nil)
	authorize := newRTMPAuthorizer(true, streams, fakeStreamKeyLookup{exists: true})
	if authorize("active-stream") {
		t.Fatal("active stream key must not be authorized twice")
	}
}

func TestRTCClientConfigUsesCurrentPublicIPv4(t *testing.T) {
	cfg := &config.Config{}
	cfg.Media.TURN.Port = 3478
	cfg.Media.TURN.Username = "user"
	cfg.Media.TURN.Password = "password"

	withoutAddress := buildRTCClientConfig("", cfg, true)
	if len(withoutAddress.ICEServers) != 0 {
		t.Fatalf("ICE servers without public IPv4 = %#v", withoutAddress.ICEServers)
	}

	withAddress := buildRTCClientConfig("198.51.100.9", cfg, true)
	if len(withAddress.ICEServers) != 2 {
		t.Fatalf("ICE servers = %#v", withAddress.ICEServers)
	}
	if got := withAddress.ICEServers[0].URLs[0]; got != "stun:198.51.100.9:3478" {
		t.Fatalf("STUN URL = %q", got)
	}
	if got := withAddress.ICEServers[1].URLs[0]; got != "turn:198.51.100.9:3478?transport=udp" {
		t.Fatalf("TURN URL = %q", got)
	}
}
