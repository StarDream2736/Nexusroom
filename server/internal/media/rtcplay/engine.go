package rtcplay

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/pion/interceptor"
	"github.com/pion/rtp"
	"github.com/pion/webrtc/v3"
	"github.com/pion/webrtc/v3/pkg/media"

	"nexusroom-server/internal/media/stream"
)

type Options struct {
	PublicIP         string
	PublicIPProvider func() string
	UDPMin           uint16
	UDPMax           uint16
}

type Engine struct {
	mediaEngine      *webrtc.MediaEngine
	interceptors     *interceptor.Registry
	publicIPProvider func() string
	udpMin           uint16
	udpMax           uint16
	registry         *stream.Registry
}

var ErrAudioTranscoderUnavailable = errors.New("WebRTC audio transcoder is unavailable")

func New(options Options, registry *stream.Registry) (*Engine, error) {
	mediaEngine := &webrtc.MediaEngine{}
	feedback := []webrtc.RTCPFeedback{{Type: "nack"}, {Type: "nack", Parameter: "pli"}}
	for index, profileLevelID := range []string{"42001f", "42e01f", "4d001f", "64001f"} {
		if err := mediaEngine.RegisterCodec(webrtc.RTPCodecParameters{
			RTPCodecCapability: webrtc.RTPCodecCapability{
				MimeType: webrtc.MimeTypeH264, ClockRate: 90000,
				SDPFmtpLine: h264FMTP(profileLevelID), RTCPFeedback: feedback,
			},
			PayloadType: webrtc.PayloadType(96 + index),
		}, webrtc.RTPCodecTypeVideo); err != nil {
			return nil, fmt.Errorf("register H264 codec %s: %w", profileLevelID, err)
		}
	}
	if err := mediaEngine.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2,
			SDPFmtpLine: "minptime=10;useinbandfec=1",
		},
		PayloadType: 111,
	}, webrtc.RTPCodecTypeAudio); err != nil {
		return nil, fmt.Errorf("register Opus codec: %w", err)
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
	publicIPProvider := options.PublicIPProvider
	if publicIPProvider == nil {
		publicIP := options.PublicIP
		publicIPProvider = func() string { return publicIP }
	}
	return &Engine{
		mediaEngine:      mediaEngine,
		interceptors:     interceptors,
		publicIPProvider: publicIPProvider,
		udpMin:           options.UDPMin,
		udpMax:           options.UDPMax,
		registry:         registry,
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
	if len(subscription.AAC) != 0 && !subscription.HasOpus {
		subscription.Close()
		return "", ErrAudioTranscoderUnavailable
	}
	pc, err := e.newPeerConnection()
	if err != nil {
		subscription.Close()
		return "", err
	}
	track, err := webrtc.NewTrackLocalStaticSample(webrtc.RTPCodecCapability{
		MimeType: webrtc.MimeTypeH264, ClockRate: 90000,
		SDPFmtpLine: h264FMTP(h264ProfileLevelID(subscription.SPS)),
	}, "video", "nexusroom")
	if err != nil {
		subscription.Close()
		_ = pc.Close()
		return "", err
	}
	videoSender, err := pc.AddTrack(track)
	if err != nil {
		subscription.Close()
		_ = pc.Close()
		return "", err
	}
	drainRTCP(videoSender)

	var audioTrack *webrtc.TrackLocalStaticRTP
	if subscription.HasOpus {
		audioTrack, err = webrtc.NewTrackLocalStaticRTP(webrtc.RTPCodecCapability{
			MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2,
			SDPFmtpLine: "minptime=10;useinbandfec=1",
		}, "audio", "nexusroom")
		if err != nil {
			subscription.Close()
			_ = pc.Close()
			return "", err
		}
		audioSender, addErr := pc.AddTrack(audioTrack)
		if addErr != nil {
			subscription.Close()
			_ = pc.Close()
			return "", addErr
		}
		drainRTCP(audioSender)
	}

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
	if audioTrack != nil {
		go writeOpus(audioTrack, subscription, closePeer)
	}
	return local.SDP, nil
}

func (e *Engine) newPeerConnection() (*webrtc.PeerConnection, error) {
	settings := webrtc.SettingEngine{}
	settings.SetNetworkTypes([]webrtc.NetworkType{webrtc.NetworkTypeUDP4})
	if e.udpMin != 0 && e.udpMax >= e.udpMin {
		if err := settings.SetEphemeralUDPPortRange(e.udpMin, e.udpMax); err != nil {
			return nil, fmt.Errorf("configure RTC UDP ports: %w", err)
		}
	}
	if publicIP := rtcPublicIPv4(e.publicIPProvider); publicIP != "" {
		settings.SetNAT1To1IPs([]string{publicIP}, webrtc.ICECandidateTypeSrflx)
	}
	api := webrtc.NewAPI(
		webrtc.WithMediaEngine(e.mediaEngine),
		webrtc.WithInterceptorRegistry(e.interceptors),
		webrtc.WithSettingEngine(settings),
	)
	return api.NewPeerConnection(webrtc.Configuration{})
}

func rtcPublicIPv4(provider func() string) string {
	if provider == nil {
		return ""
	}
	ip := net.ParseIP(strings.TrimSpace(provider()))
	if ip == nil || ip.To4() == nil {
		return ""
	}
	return ip.To4().String()
}

func drainRTCP(sender *webrtc.RTPSender) {
	go func() {
		buffer := make([]byte, 1500)
		for {
			if _, _, err := sender.Read(buffer); err != nil {
				return
			}
		}
	}()
}

func h264FMTP(profileLevelID string) string {
	return "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=" + profileLevelID
}

func h264ProfileLevelID(sps []byte) string {
	if len(sps) < 4 {
		return "42e01f"
	}
	level := fmt.Sprintf("%02x", sps[3])
	switch sps[1] {
	case 0x42:
		if sps[2]&0x40 != 0 {
			return "42e0" + level
		}
		return "4200" + level
	case 0x4d:
		return "4d00" + level
	case 0x64:
		return "6400" + level
	default:
		return "42e01f"
	}
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

func writeOpus(track *webrtc.TrackLocalStaticRTP, subscription *stream.Subscription, closePeer func()) {
	defer closePeer()
	for frame := range subscription.Opus {
		packet := &rtp.Packet{
			Header: rtp.Header{
				Version:        2,
				Marker:         frame.Marker,
				PayloadType:    111,
				SequenceNumber: frame.SequenceNumber,
				Timestamp:      frame.Timestamp,
			},
			Payload: frame.Payload,
		}
		if err := track.WriteRTP(packet); err != nil && !errors.Is(err, io.ErrClosedPipe) {
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
