package rtcplay

import (
	"context"
	"errors"
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/pion/interceptor"
	"github.com/pion/webrtc/v3"
	"github.com/pion/webrtc/v3/pkg/media"

	"nexusroom-server/internal/media/stream"
)

type Options struct {
	PublicIP string
	UDPMin   uint16
	UDPMax   uint16
}

type Engine struct {
	api      *webrtc.API
	registry *stream.Registry
}

var ErrAudioRequiresFLV = errors.New("AAC streams use the HTTP-FLV player to preserve audio")

func New(options Options, registry *stream.Registry) (*Engine, error) {
	mediaEngine := &webrtc.MediaEngine{}
	if err := mediaEngine.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType: webrtc.MimeTypeH264, ClockRate: 90000,
			SDPFmtpLine:  "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f",
			RTCPFeedback: []webrtc.RTCPFeedback{{Type: "nack"}, {Type: "nack", Parameter: "pli"}},
		},
		PayloadType: 96,
	}, webrtc.RTPCodecTypeVideo); err != nil {
		return nil, fmt.Errorf("register H264 codec: %w", err)
	}
	interceptors := &interceptor.Registry{}
	if err := webrtc.RegisterDefaultInterceptors(mediaEngine, interceptors); err != nil {
		return nil, fmt.Errorf("register WebRTC interceptors: %w", err)
	}
	settings := webrtc.SettingEngine{}
	if options.UDPMin != 0 && options.UDPMax >= options.UDPMin {
		if err := settings.SetEphemeralUDPPortRange(options.UDPMin, options.UDPMax); err != nil {
			return nil, fmt.Errorf("configure RTC UDP ports: %w", err)
		}
	}
	if options.PublicIP != "" {
		settings.SetNAT1To1IPs([]string{options.PublicIP}, webrtc.ICECandidateTypeHost)
	}
	return &Engine{
		api:      webrtc.NewAPI(webrtc.WithMediaEngine(mediaEngine), webrtc.WithInterceptorRegistry(interceptors), webrtc.WithSettingEngine(settings)),
		registry: registry,
	}, nil
}

// Answer creates a browser playback peer and keeps it attached to the stream
// until the publisher, subscriber, or peer connection ends.
func (e *Engine) Answer(ctx context.Context, streamKey, offerSDP string) (string, error) {
	if offerSDP == "" {
		return "", errors.New("empty WebRTC offer")
	}
	subscription, err := e.registry.Subscribe(streamKey)
	if err != nil {
		return "", err
	}
	if len(subscription.AAC) != 0 {
		subscription.Close()
		return "", ErrAudioRequiresFLV
	}
	pc, err := e.api.NewPeerConnection(webrtc.Configuration{})
	if err != nil {
		subscription.Close()
		return "", err
	}
	track, err := webrtc.NewTrackLocalStaticSample(webrtc.RTPCodecCapability{
		MimeType: webrtc.MimeTypeH264, ClockRate: 90000,
		SDPFmtpLine: "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f",
	}, "video", "nexusroom")
	if err != nil {
		subscription.Close()
		_ = pc.Close()
		return "", err
	}
	sender, err := pc.AddTrack(track)
	if err != nil {
		subscription.Close()
		_ = pc.Close()
		return "", err
	}
	go func() {
		buffer := make([]byte, 1500)
		for {
			if _, _, readErr := sender.Read(buffer); readErr != nil {
				return
			}
		}
	}()

	var closeOnce sync.Once
	closePeer := func() {
		closeOnce.Do(func() {
			subscription.Close()
			_ = pc.Close()
		})
	}
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		if state == webrtc.PeerConnectionStateFailed || state == webrtc.PeerConnectionStateClosed || state == webrtc.PeerConnectionStateDisconnected {
			closePeer()
		}
	})
	connectDeadline := time.AfterFunc(20*time.Second, func() {
		if pc.ConnectionState() != webrtc.PeerConnectionStateConnected {
			closePeer()
		}
	})
	defer func() {
		if pc.ConnectionState() == webrtc.PeerConnectionStateClosed {
			connectDeadline.Stop()
		}
	}()
	if err := pc.SetRemoteDescription(webrtc.SessionDescription{Type: webrtc.SDPTypeOffer, SDP: offerSDP}); err != nil {
		closePeer()
		return "", err
	}
	answer, err := pc.CreateAnswer(nil)
	if err != nil {
		closePeer()
		return "", err
	}
	gatheringComplete := webrtc.GatheringCompletePromise(pc)
	if err := pc.SetLocalDescription(answer); err != nil {
		closePeer()
		return "", err
	}
	select {
	case <-ctx.Done():
		closePeer()
		return "", ctx.Err()
	case <-gatheringComplete:
	case <-time.After(8 * time.Second):
		closePeer()
		return "", errors.New("WebRTC ICE gathering timed out")
	}
	local := pc.LocalDescription()
	if local == nil {
		closePeer()
		return "", errors.New("missing WebRTC answer")
	}
	go writeStream(track, subscription, closePeer)
	return local.SDP, nil
}

func writeStream(track *webrtc.TrackLocalStaticSample, subscription *stream.Subscription, closePeer func()) {
	defer closePeer()
	started := false
	lastDTS := time.Duration(-1)
	for frame := range subscription.Frames {
		if !started {
			if !frame.KeyFrame {
				continue
			}
			started = true
		}
		duration := time.Second / 30
		if lastDTS >= 0 && frame.DTS > lastDTS {
			duration = frame.DTS - lastDTS
		}
		lastDTS = frame.DTS
		payload := annexB(frame, subscription.SPS, subscription.PPS)
		if err := track.WriteSample(media.Sample{Data: payload, Duration: duration}); err != nil && !errors.Is(err, io.ErrClosedPipe) {
			return
		}
	}
}

func annexB(frame stream.Frame, sps, pps []byte) []byte {
	count := len(frame.NALUs)
	if frame.KeyFrame {
		count += 2
	}
	parts := make([][]byte, 0, count)
	if frame.KeyFrame {
		parts = append(parts, sps, pps)
	}
	parts = append(parts, frame.NALUs...)
	size := 0
	for _, part := range parts {
		size += 4 + len(part)
	}
	result := make([]byte, 0, size)
	for _, part := range parts {
		result = append(result, 0, 0, 0, 1)
		result = append(result, part...)
	}
	return result
}
