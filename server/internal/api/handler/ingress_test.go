package handler

import "testing"

func TestBuildRTMPURL(t *testing.T) {
	tests := []struct {
		name  string
		value string
		port  int
		want  string
	}{
		{name: "hostname", value: "media.example.com", port: 1935, want: "rtmp://media.example.com:1935/live"},
		{name: "http URL", value: "https://media.example.com:8443/api", port: 1935, want: "rtmp://media.example.com:1935/live"},
		{name: "forwarded host", value: "media.example.com:18080", port: 1936, want: "rtmp://media.example.com:1936/live"},
		{name: "IPv4", value: "127.0.0.1", port: 1935, want: "rtmp://127.0.0.1:1935/live"},
		{name: "IPv6", value: "[2001:db8::1]:8080", port: 1935, want: "rtmp://[2001:db8::1]:1935/live"},
		{name: "proxy list", value: "chat.example.com:443, internal:8080", port: 1935, want: "rtmp://chat.example.com:1935/live"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := buildRTMPURL(test.value, test.port); got != test.want {
				t.Fatalf("buildRTMPURL(%q, %d) = %q, want %q", test.value, test.port, got, test.want)
			}
		})
	}
}

func TestJoinRTMPPublishURL(t *testing.T) {
	if got := joinRTMPPublishURL("rtmp://127.0.0.1:1935/live/", "/stream-key"); got != "rtmp://127.0.0.1:1935/live/stream-key" {
		t.Fatalf("unexpected publish URL: %s", got)
	}
}
