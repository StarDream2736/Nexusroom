package rtmp

import "testing"

func TestValidStreamKey(t *testing.T) {
	tests := []struct {
		name string
		key  string
		want bool
	}{
		{name: "letters numbers separators", key: "temporary_stream-01", want: true},
		{name: "minimum length", key: "12345678", want: true},
		{name: "too short", key: "short", want: false},
		{name: "slash", key: "temporary/stream", want: false},
		{name: "space", key: "temporary stream", want: false},
		{name: "unicode", key: "临时直播stream", want: false},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := validStreamKey(test.key); got != test.want {
				t.Fatalf("validStreamKey(%q) = %v, want %v", test.key, got, test.want)
			}
		})
	}
}
