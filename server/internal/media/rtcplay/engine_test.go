package rtcplay

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/pion/interceptor"
	"github.com/pion/webrtc/v3"

	"nexusroom-server/internal/media/stream"
)

func TestEngineAnswersAndSendsH264WhenSourceHasAAC(t *testing.T) {
	registry := stream.NewRegistry()
	registry.Start("camera", []byte{0x67, 0x42, 0xe0, 0x1f}, []byte{0x68, 0xce, 0x06, 0xe2}, []byte{0x12, 0x10})
	if err := registry.SetOpusAvailable("camera", true); err != nil {
		t.Fatal(err)
	}
	defer registry.Stop("camera")
	engine, err := New(Options{}, registry)
	if err != nil {
		t.Fatal(err)
	}

	mediaEngine := &webrtc.MediaEngine{}
	if err := mediaEngine.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType: webrtc.MimeTypeH264, ClockRate: 90000,
			SDPFmtpLine: "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f",
		},
		PayloadType: 96,
	}, webrtc.RTPCodecTypeVideo); err != nil {
		t.Fatal(err)
	}
	if err := mediaEngine.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2,
			SDPFmtpLine: "minptime=10;useinbandfec=1",
		},
		PayloadType: 111,
	}, webrtc.RTPCodecTypeAudio); err != nil {
		t.Fatal(err)
	}
	interceptors := &interceptor.Registry{}
	if err := webrtc.RegisterDefaultInterceptors(mediaEngine, interceptors); err != nil {
		t.Fatal(err)
	}
	api := webrtc.NewAPI(webrtc.WithMediaEngine(mediaEngine), webrtc.WithInterceptorRegistry(interceptors))
	client, err := api.NewPeerConnection(webrtc.Configuration{})
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	if _, err := client.AddTransceiverFromKind(webrtc.RTPCodecTypeVideo, webrtc.RtpTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly}); err != nil {
		t.Fatal(err)
	}
	if _, err := client.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RtpTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly}); err != nil {
		t.Fatal(err)
	}
	videoPackets := make(chan struct{}, 1)
	audioPackets := make(chan struct{}, 1)
	client.OnTrack(func(track *webrtc.TrackRemote, _ *webrtc.RTPReceiver) {
		if _, _, readErr := track.ReadRTP(); readErr == nil {
			if track.Kind() == webrtc.RTPCodecTypeAudio {
				audioPackets <- struct{}{}
			} else {
				videoPackets <- struct{}{}
			}
		}
	})
	offer, err := client.CreateOffer(nil)
	if err != nil {
		t.Fatal(err)
	}
	gathering := webrtc.GatheringCompletePromise(client)
	if err := client.SetLocalDescription(offer); err != nil {
		t.Fatal(err)
	}
	<-gathering

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	answerSDP, err := engine.Answer(ctx, "camera", client.LocalDescription().SDP)
	if err != nil {
		t.Fatal(err)
	}
	if err := client.SetRemoteDescription(webrtc.SessionDescription{Type: webrtc.SDPTypeAnswer, SDP: answerSDP}); err != nil {
		t.Fatal(err)
	}

	for index := 0; index < 60; index++ {
		dts := time.Duration(index) * (time.Second / 30)
		if err := registry.Publish("camera", stream.Frame{
			DTS: dts, PTS: dts, KeyFrame: index == 0,
			NALUs: [][]byte{{0x65, 0x88, 0x84, byte(index)}},
		}); err != nil {
			t.Fatal(err)
		}
		if err := registry.PublishOpus("camera", stream.OpusFrame{
			SequenceNumber: uint16(index), Timestamp: uint32(index * 960), Payload: []byte{0xf8, 0xff, 0xfe},
		}); err != nil {
			t.Fatal(err)
		}
		time.Sleep(20 * time.Millisecond)
	}
	select {
	case <-videoPackets:
	default:
		t.Fatal("browser peer did not receive H264 RTP")
	}
	select {
	case <-audioPackets:
	default:
		t.Fatal("browser peer did not receive Opus RTP")
	}
}

func TestEngineRejectsAACWhenOpusTranscoderIsUnavailable(t *testing.T) {
	registry := stream.NewRegistry()
	registry.Start("camera", []byte{0x67, 0x42, 0xe0, 0x1f}, []byte{0x68, 0xce, 0x06, 0xe2}, []byte{0x12, 0x10})
	defer registry.Stop("camera")
	engine, err := New(Options{}, registry)
	if err != nil {
		t.Fatal(err)
	}

	client, err := webrtc.NewPeerConnection(webrtc.Configuration{})
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	if _, err := client.AddTransceiverFromKind(webrtc.RTPCodecTypeVideo, webrtc.RtpTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly}); err != nil {
		t.Fatal(err)
	}
	if _, err := client.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RtpTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly}); err != nil {
		t.Fatal(err)
	}
	offer, err := client.CreateOffer(nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := engine.Answer(context.Background(), "camera", offer.SDP); !errors.Is(err, ErrAudioTranscoderUnavailable) {
		t.Fatalf("got %v, want %v", err, ErrAudioTranscoderUnavailable)
	}
}

func TestH264ProfileLevelID(t *testing.T) {
	tests := []struct {
		name string
		sps  []byte
		want string
	}{
		{name: "constrained baseline", sps: []byte{0x67, 0x42, 0xc0, 0x1e}, want: "42e01e"},
		{name: "main", sps: []byte{0x67, 0x4d, 0x00, 0x29}, want: "4d0029"},
		{name: "high", sps: []byte{0x67, 0x64, 0x00, 0x2a}, want: "64002a"},
		{name: "invalid", sps: []byte{0x67}, want: "42e01f"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := h264ProfileLevelID(test.sps); got != test.want {
				t.Fatalf("got %s, want %s", got, test.want)
			}
		})
	}
}

func TestRTCPublicIPv4RejectsIPv6(t *testing.T) {
	if got := rtcPublicIPv4(func() string { return "2001:db8::1" }); got != "" {
		t.Fatalf("IPv6 address must be ignored, got %q", got)
	}
	if got := rtcPublicIPv4(func() string { return "198.51.100.13" }); got != "198.51.100.13" {
		t.Fatalf("IPv4 address = %q", got)
	}
}

func TestNewPeerConnectionReadsLatestPublicIPv4(t *testing.T) {
	current := "198.51.100.21"
	engine, err := New(Options{PublicIPProvider: func() string { return current }}, stream.NewRegistry())
	if err != nil {
		t.Fatal(err)
	}
	first := gatherCandidateSDP(t, engine)
	if !strings.Contains(first, "198.51.100.21") {
		t.Fatalf("first SDP does not contain current public IPv4:\n%s", first)
	}
	assertIPv4Candidates(t, first)

	current = "198.51.100.22"
	second := gatherCandidateSDP(t, engine)
	if !strings.Contains(second, "198.51.100.22") || strings.Contains(second, "198.51.100.21") {
		t.Fatalf("second SDP did not refresh public IPv4:\n%s", second)
	}
	assertIPv4Candidates(t, second)
}

func assertIPv4Candidates(t *testing.T, sdp string) {
	t.Helper()
	for _, line := range strings.Split(sdp, "\n") {
		if !strings.HasPrefix(line, "a=candidate:") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 5 || strings.Contains(fields[4], ":") {
			t.Fatalf("non-IPv4 ICE candidate: %q", line)
		}
	}
}

func gatherCandidateSDP(t *testing.T, engine *Engine) string {
	t.Helper()
	peer, err := engine.newPeerConnection()
	if err != nil {
		t.Fatal(err)
	}
	defer peer.Close()
	if _, err := peer.AddTransceiverFromKind(webrtc.RTPCodecTypeVideo, webrtc.RtpTransceiverInit{
		Direction: webrtc.RTPTransceiverDirectionRecvonly,
	}); err != nil {
		t.Fatal(err)
	}
	offer, err := peer.CreateOffer(nil)
	if err != nil {
		t.Fatal(err)
	}
	gathering := webrtc.GatheringCompletePromise(peer)
	if err := peer.SetLocalDescription(offer); err != nil {
		t.Fatal(err)
	}
	select {
	case <-gathering:
	case <-time.After(5 * time.Second):
		t.Fatal("ICE gathering timed out")
	}
	return peer.LocalDescription().SDP
}
