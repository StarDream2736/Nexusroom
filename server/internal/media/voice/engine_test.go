package voice

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/pion/interceptor"
	"github.com/pion/rtp"
	"github.com/pion/webrtc/v3"
)

func TestEngineForwardsUnmutedOpusAudio(t *testing.T) {
	var engine *Engine
	var shuttingDown atomic.Bool
	clients := make(map[uint64]*webrtc.PeerConnection)
	answerApplied := make(map[uint64]chan struct{})
	renegotiated := make(chan struct{}, 1)
	var clientsMu sync.RWMutex

	signal := func(userID, roomID uint64, event string, payload any) {
		if shuttingDown.Load() {
			return
		}
		clientsMu.RLock()
		client := clients[userID]
		answerDone := answerApplied[userID]
		clientsMu.RUnlock()
		if client == nil {
			return
		}
		switch event {
		case EventAnswer:
			description := payload.(Description)
			if err := client.SetRemoteDescription(webrtc.SessionDescription{
				Type: webrtc.SDPTypeAnswer,
				SDP:  description.SDP,
			}); err != nil {
				t.Errorf("set client answer: %v", err)
				return
			}
			select {
			case <-answerDone:
			default:
				close(answerDone)
			}
		case EventICE:
			candidate := payload.(Candidate)
			if err := client.AddICECandidate(webrtc.ICECandidateInit{
				Candidate:     candidate.Candidate,
				SDPMid:        candidate.SDPMid,
				SDPMLineIndex: candidate.SDPMLineIndex,
			}); err != nil {
				t.Errorf("add server candidate: %v", err)
			}
		case EventOffer:
			description := payload.(Description)
			go func() {
				if err := client.SetRemoteDescription(webrtc.SessionDescription{
					Type: webrtc.SDPTypeOffer,
					SDP:  description.SDP,
				}); err != nil {
					t.Errorf("set renegotiation offer: %v", err)
					return
				}
				answer, err := client.CreateAnswer(nil)
				if err != nil {
					t.Errorf("create renegotiation answer: %v", err)
					return
				}
				if err := client.SetLocalDescription(answer); err != nil {
					t.Errorf("set renegotiation answer: %v", err)
					return
				}
				if err := engine.HandleAnswer(roomID, userID, Description{
					Type: "answer",
					SDP:  client.LocalDescription().SDP,
				}); err != nil {
					t.Errorf("handle renegotiation answer: %v", err)
					return
				}
				select {
				case renegotiated <- struct{}{}:
				default:
				}
			}()
		}
	}

	var err error
	engine, err = New(Options{Signal: signal})
	if err != nil {
		t.Fatal(err)
	}
	publisher, publisherTrack := newVoiceTestClient(t, true)
	subscriber, _ := newVoiceTestClient(t, false)
	defer func() {
		shuttingDown.Store(true)
		engine.Close()
		_ = publisher.Close()
		_ = subscriber.Close()
	}()

	received := make(chan struct{}, 1)
	subscriber.OnTrack(func(track *webrtc.TrackRemote, _ *webrtc.RTPReceiver) {
		if track.Kind() != webrtc.RTPCodecTypeAudio {
			return
		}
		if _, _, err := track.ReadRTP(); err == nil {
			received <- struct{}{}
		}
	})

	clientsMu.Lock()
	clients[1] = publisher
	clients[2] = subscriber
	answerApplied[1] = make(chan struct{})
	answerApplied[2] = make(chan struct{})
	clientsMu.Unlock()

	connectVoiceTestClient(t, engine, publisher, 10, 1, answerApplied[1])
	connectVoiceTestClient(t, engine, subscriber, 10, 2, answerApplied[2])
	engine.SetMuted(10, 1, false)

	deadline := time.Now().Add(10 * time.Second)
	for sequence := uint16(1); time.Now().Before(deadline); sequence++ {
		if err := publisherTrack.WriteRTP(&rtp.Packet{
			Header: rtp.Header{
				Version:        2,
				PayloadType:    111,
				SequenceNumber: sequence,
				Timestamp:      uint32(sequence) * 960,
				SSRC:           1234,
			},
			Payload: []byte{0xf8, 0xff, 0xfe},
		}); err != nil {
			t.Fatal(err)
		}
		select {
		case <-received:
			return
		case <-renegotiated:
		case <-time.After(20 * time.Millisecond):
		}
	}
	t.Fatal("subscriber did not receive forwarded Opus RTP")
}

func newVoiceTestClient(t *testing.T, publish bool) (*webrtc.PeerConnection, *webrtc.TrackLocalStaticRTP) {
	t.Helper()
	mediaEngine := &webrtc.MediaEngine{}
	if err := mediaEngine.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType:    webrtc.MimeTypeOpus,
			ClockRate:   48000,
			Channels:    2,
			SDPFmtpLine: "minptime=10;useinbandfec=1",
		},
		PayloadType: 111,
	}, webrtc.RTPCodecTypeAudio); err != nil {
		t.Fatal(err)
	}
	registry := &interceptor.Registry{}
	if err := webrtc.RegisterDefaultInterceptors(mediaEngine, registry); err != nil {
		t.Fatal(err)
	}
	api := webrtc.NewAPI(
		webrtc.WithMediaEngine(mediaEngine),
		webrtc.WithInterceptorRegistry(registry),
	)
	client, err := api.NewPeerConnection(webrtc.Configuration{})
	if err != nil {
		t.Fatal(err)
	}
	if !publish {
		if _, err := client.AddTransceiverFromKind(
			webrtc.RTPCodecTypeAudio,
			webrtc.RtpTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly},
		); err != nil {
			t.Fatal(err)
		}
		return client, nil
	}
	track, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{
			MimeType:    webrtc.MimeTypeOpus,
			ClockRate:   48000,
			Channels:    2,
			SDPFmtpLine: "minptime=10;useinbandfec=1",
		},
		"microphone",
		"voice-test",
	)
	if err != nil {
		t.Fatal(err)
	}
	sender, err := client.AddTrack(track)
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		buffer := make([]byte, 1500)
		for {
			if _, _, err := sender.Read(buffer); err != nil {
				return
			}
		}
	}()
	return client, track
}

func connectVoiceTestClient(
	t *testing.T,
	engine *Engine,
	client *webrtc.PeerConnection,
	roomID uint64,
	userID uint64,
	answerApplied <-chan struct{},
) {
	t.Helper()
	offer, err := client.CreateOffer(nil)
	if err != nil {
		t.Fatal(err)
	}
	gathering := webrtc.GatheringCompletePromise(client)
	if err := client.SetLocalDescription(offer); err != nil {
		t.Fatal(err)
	}
	select {
	case <-gathering:
	case <-time.After(5 * time.Second):
		t.Fatal("ICE gathering timed out")
	}
	if err := engine.HandleOffer(roomID, userID, Description{
		Type: "offer",
		SDP:  client.LocalDescription().SDP,
	}); err != nil {
		t.Fatal(err)
	}
	select {
	case <-answerApplied:
	case <-time.After(5 * time.Second):
		t.Fatal("RTC answer timed out")
	}
}
