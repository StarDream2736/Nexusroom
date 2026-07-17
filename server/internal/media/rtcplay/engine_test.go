package rtcplay

import (
	"context"
	"testing"
	"time"

	"github.com/pion/interceptor"
	"github.com/pion/webrtc/v3"

	"nexusroom-server/internal/media/stream"
)

func TestEngineAnswersAndSendsH264(t *testing.T) {
	registry := stream.NewRegistry()
	registry.Start("camera", []byte{0x67, 0x42, 0xe0, 0x1f}, []byte{0x68, 0xce, 0x06, 0xe2})
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
	packets := make(chan struct{}, 1)
	client.OnTrack(func(track *webrtc.TrackRemote, _ *webrtc.RTPReceiver) {
		if _, _, readErr := track.ReadRTP(); readErr == nil {
			packets <- struct{}{}
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

	for index := 0; index < 30; index++ {
		dts := time.Duration(index) * (time.Second / 30)
		if err := registry.Publish("camera", stream.Frame{
			DTS: dts, PTS: dts, KeyFrame: index == 0,
			NALUs: [][]byte{{0x65, 0x88, 0x84, byte(index)}},
		}); err != nil {
			t.Fatal(err)
		}
		select {
		case <-packets:
			return
		case <-time.After(20 * time.Millisecond):
		}
	}
	t.Fatal("browser peer did not receive H264 RTP")
}

func TestEngineUsesFLVFallbackForAAC(t *testing.T) {
	registry := stream.NewRegistry()
	registry.Start("camera", []byte{1, 2, 3, 4}, []byte{5}, []byte{0x12, 0x10})
	engine, err := New(Options{}, registry)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := engine.Answer(context.Background(), "camera", "not-empty"); err != ErrAudioRequiresFLV {
		t.Fatalf("expected FLV fallback, got %v", err)
	}
}
