package voice

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"sync"

	"github.com/pion/interceptor"
	"github.com/pion/webrtc/v3"
)

const (
	EventAnswer       = "rtc.answer"
	EventOffer        = "rtc.offer"
	EventICE          = "rtc.ice"
	EventParticipants = "rtc.participants"
	EventState        = "rtc.state"
)

type SignalFunc func(userID, roomID uint64, event string, payload any)

type Options struct {
	PublicIP   string
	UDPMin     uint16
	UDPMax     uint16
	ICEServers []webrtc.ICEServer
	Signal     SignalFunc
}

type Description struct {
	Type string `json:"type"`
	SDP  string `json:"sdp"`
}

type Candidate struct {
	Candidate     string  `json:"candidate"`
	SDPMid        *string `json:"sdp_mid,omitempty"`
	SDPMLineIndex *uint16 `json:"sdp_mline_index,omitempty"`
}

type Participant struct {
	UserID   uint64 `json:"user_id"`
	Muted    bool   `json:"muted"`
	Speaking bool   `json:"speaking"`
}

type Engine struct {
	mu     sync.RWMutex
	api    *webrtc.API
	config webrtc.Configuration
	signal SignalFunc
	rooms  map[uint64]*room
}

type room struct {
	id     uint64
	peers  map[uint64]*peer
	tracks map[uint64]*webrtc.TrackLocalStaticRTP
}

type peer struct {
	mu                 sync.Mutex
	userID             uint64
	roomID             uint64
	pc                 *webrtc.PeerConnection
	senders            map[uint64]*webrtc.RTPSender
	muted              bool
	speaking           bool
	closed             bool
	renegotiatePending bool
}

func New(options Options) (*Engine, error) {
	mediaEngine := &webrtc.MediaEngine{}
	if err := mediaEngine.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType:     webrtc.MimeTypeOpus,
			ClockRate:    48000,
			Channels:     2,
			SDPFmtpLine:  "minptime=10;useinbandfec=1",
			RTCPFeedback: nil,
		},
		PayloadType: 111,
	}, webrtc.RTPCodecTypeAudio); err != nil {
		return nil, fmt.Errorf("register opus codec: %w", err)
	}

	registry := &interceptor.Registry{}
	if err := webrtc.RegisterDefaultInterceptors(mediaEngine, registry); err != nil {
		return nil, fmt.Errorf("register WebRTC interceptors: %w", err)
	}

	settingEngine := webrtc.SettingEngine{}
	if options.UDPMin != 0 && options.UDPMax >= options.UDPMin {
		if err := settingEngine.SetEphemeralUDPPortRange(options.UDPMin, options.UDPMax); err != nil {
			return nil, fmt.Errorf("configure RTC UDP port range: %w", err)
		}
	}
	if options.PublicIP != "" {
		settingEngine.SetNAT1To1IPs([]string{options.PublicIP}, webrtc.ICECandidateTypeHost)
	}

	return &Engine{
		api: webrtc.NewAPI(
			webrtc.WithMediaEngine(mediaEngine),
			webrtc.WithInterceptorRegistry(registry),
			webrtc.WithSettingEngine(settingEngine),
		),
		config: webrtc.Configuration{ICEServers: options.ICEServers},
		signal: options.Signal,
		rooms:  make(map[uint64]*room),
	}, nil
}

func (e *Engine) HandleOffer(roomID, userID uint64, description Description) error {
	if description.SDP == "" {
		return errors.New("empty RTC offer")
	}
	p, created, err := e.ensurePeer(roomID, userID)
	if err != nil {
		return err
	}

	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return errors.New("RTC peer is closed")
	}
	if err := p.pc.SetRemoteDescription(webrtc.SessionDescription{Type: webrtc.SDPTypeOffer, SDP: description.SDP}); err != nil {
		p.mu.Unlock()
		if created {
			e.Leave(roomID, userID)
		}
		return fmt.Errorf("set RTC offer: %w", err)
	}
	if created {
		e.addExistingTracks(p)
	}
	answer, err := p.pc.CreateAnswer(nil)
	if err != nil {
		p.mu.Unlock()
		return fmt.Errorf("create RTC answer: %w", err)
	}
	if err := p.pc.SetLocalDescription(answer); err != nil {
		p.mu.Unlock()
		return fmt.Errorf("set RTC answer: %w", err)
	}
	p.mu.Unlock()
	e.emit(userID, roomID, EventAnswer, Description{Type: answer.Type.String(), SDP: answer.SDP})
	e.broadcastParticipants(roomID)
	return nil
}

func (e *Engine) HandleAnswer(roomID, userID uint64, description Description) error {
	p := e.findPeer(roomID, userID)
	if p == nil {
		return errors.New("RTC peer not found")
	}
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return errors.New("RTC peer is closed")
	}
	if err := p.pc.SetRemoteDescription(webrtc.SessionDescription{Type: webrtc.SDPTypeAnswer, SDP: description.SDP}); err != nil {
		p.mu.Unlock()
		return fmt.Errorf("set RTC answer: %w", err)
	}
	pending := p.renegotiatePending
	p.renegotiatePending = false
	p.mu.Unlock()
	if pending {
		go e.renegotiate(p)
	}
	return nil
}

func (e *Engine) AddICECandidate(roomID, userID uint64, candidate Candidate) error {
	p := e.findPeer(roomID, userID)
	if p == nil {
		return errors.New("RTC peer not found")
	}
	return p.pc.AddICECandidate(webrtc.ICECandidateInit{
		Candidate:     candidate.Candidate,
		SDPMid:        candidate.SDPMid,
		SDPMLineIndex: candidate.SDPMLineIndex,
	})
}

func (e *Engine) SetVoiceState(roomID, userID uint64, muted, speaking bool) {
	p := e.findPeer(roomID, userID)
	if p == nil {
		return
	}
	p.mu.Lock()
	p.muted = muted
	p.speaking = speaking && !muted
	p.mu.Unlock()
	e.broadcastParticipants(roomID)
}

func (e *Engine) SetMuted(roomID, userID uint64, muted bool) {
	p := e.findPeer(roomID, userID)
	if p == nil {
		return
	}
	p.mu.Lock()
	p.muted = muted
	if muted {
		p.speaking = false
	}
	p.mu.Unlock()
	e.broadcastParticipants(roomID)
}

func (e *Engine) SetSpeaking(roomID, userID uint64, speaking bool) {
	p := e.findPeer(roomID, userID)
	if p == nil {
		return
	}
	p.mu.Lock()
	p.speaking = speaking && !p.muted
	p.mu.Unlock()
	e.broadcastParticipants(roomID)
}

func (e *Engine) Leave(roomID, userID uint64) {
	var p *peer
	var subscribers []*peer

	e.mu.Lock()
	r := e.rooms[roomID]
	if r == nil {
		e.mu.Unlock()
		return
	}
	p = r.peers[userID]
	if p == nil {
		e.mu.Unlock()
		return
	}
	delete(r.peers, userID)
	delete(r.tracks, userID)
	for _, subscriber := range r.peers {
		subscribers = append(subscribers, subscriber)
	}
	if len(r.peers) == 0 {
		delete(e.rooms, roomID)
	}
	e.mu.Unlock()

	p.mu.Lock()
	p.closed = true
	p.mu.Unlock()
	_ = p.pc.Close()

	for _, subscriber := range subscribers {
		subscriber.mu.Lock()
		if sender := subscriber.senders[userID]; sender != nil {
			_ = subscriber.pc.RemoveTrack(sender)
			delete(subscriber.senders, userID)
		}
		subscriber.mu.Unlock()
		e.renegotiate(subscriber)
	}
	e.broadcastParticipants(roomID)
}

func (e *Engine) LeaveUser(userID uint64) {
	e.mu.RLock()
	var rooms []uint64
	for roomID, r := range e.rooms {
		if _, ok := r.peers[userID]; ok {
			rooms = append(rooms, roomID)
		}
	}
	e.mu.RUnlock()
	for _, roomID := range rooms {
		e.Leave(roomID, userID)
	}
}

func (e *Engine) Close() {
	e.mu.RLock()
	var peers []*peer
	for _, r := range e.rooms {
		for _, p := range r.peers {
			peers = append(peers, p)
		}
	}
	e.mu.RUnlock()
	for _, p := range peers {
		e.Leave(p.roomID, p.userID)
	}
}

func (e *Engine) ensurePeer(roomID, userID uint64) (*peer, bool, error) {
	if existing := e.findPeer(roomID, userID); existing != nil {
		return existing, false, nil
	}
	pc, err := e.api.NewPeerConnection(e.config)
	if err != nil {
		return nil, false, fmt.Errorf("create RTC peer: %w", err)
	}
	p := &peer{userID: userID, roomID: roomID, pc: pc, senders: make(map[uint64]*webrtc.RTPSender), muted: true}

	pc.OnICECandidate(func(candidate *webrtc.ICECandidate) {
		if candidate == nil {
			return
		}
		jsonCandidate := candidate.ToJSON()
		e.emit(userID, roomID, EventICE, Candidate{
			Candidate: jsonCandidate.Candidate, SDPMid: jsonCandidate.SDPMid, SDPMLineIndex: jsonCandidate.SDPMLineIndex,
		})
	})
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		e.emit(userID, roomID, EventState, map[string]string{"state": state.String()})
		if state == webrtc.PeerConnectionStateFailed || state == webrtc.PeerConnectionStateClosed {
			go e.Leave(roomID, userID)
		}
	})
	pc.OnTrack(func(track *webrtc.TrackRemote, _ *webrtc.RTPReceiver) {
		if track.Kind() != webrtc.RTPCodecTypeAudio {
			return
		}
		e.forwardAudio(p, track)
	})

	e.mu.Lock()
	r := e.rooms[roomID]
	if r == nil {
		r = &room{id: roomID, peers: make(map[uint64]*peer), tracks: make(map[uint64]*webrtc.TrackLocalStaticRTP)}
		e.rooms[roomID] = r
	}
	if existing := r.peers[userID]; existing != nil {
		e.mu.Unlock()
		_ = pc.Close()
		return existing, false, nil
	}
	r.peers[userID] = p
	e.mu.Unlock()
	return p, true, nil
}

func (e *Engine) forwardAudio(publisher *peer, remote *webrtc.TrackRemote) {
	local, err := webrtc.NewTrackLocalStaticRTP(remote.Codec().RTPCodecCapability,
		fmt.Sprintf("audio-%d", publisher.userID), fmt.Sprintf("room-%d", publisher.roomID))
	if err != nil {
		return
	}

	e.mu.Lock()
	r := e.rooms[publisher.roomID]
	if r == nil || r.peers[publisher.userID] != publisher {
		e.mu.Unlock()
		return
	}
	r.tracks[publisher.userID] = local
	var subscribers []*peer
	for userID, subscriber := range r.peers {
		if userID != publisher.userID {
			subscribers = append(subscribers, subscriber)
		}
	}
	e.mu.Unlock()

	for _, subscriber := range subscribers {
		e.addTrack(subscriber, publisher.userID, local)
		e.renegotiate(subscriber)
	}

	for {
		packet, _, readErr := remote.ReadRTP()
		if readErr != nil {
			if !errors.Is(readErr, io.EOF) {
				e.emit(publisher.userID, publisher.roomID, EventState, map[string]string{"state": "track-ended"})
			}
			return
		}
		publisher.mu.Lock()
		muted := publisher.muted
		closed := publisher.closed
		publisher.mu.Unlock()
		if closed {
			return
		}
		if muted {
			continue
		}
		if writeErr := local.WriteRTP(packet); writeErr != nil && !errors.Is(writeErr, io.ErrClosedPipe) {
			return
		}
	}
}

func (e *Engine) addExistingTracks(p *peer) {
	e.mu.RLock()
	r := e.rooms[p.roomID]
	tracks := make(map[uint64]*webrtc.TrackLocalStaticRTP)
	if r != nil {
		for publisherID, track := range r.tracks {
			if publisherID != p.userID {
				tracks[publisherID] = track
			}
		}
	}
	e.mu.RUnlock()
	for publisherID, track := range tracks {
		e.addTrackLocked(p, publisherID, track)
	}
}

func (e *Engine) addTrack(p *peer, publisherID uint64, track *webrtc.TrackLocalStaticRTP) {
	p.mu.Lock()
	defer p.mu.Unlock()
	e.addTrackLocked(p, publisherID, track)
}

func (e *Engine) addTrackLocked(p *peer, publisherID uint64, track *webrtc.TrackLocalStaticRTP) {
	if p.closed || p.senders[publisherID] != nil {
		return
	}
	sender, err := p.pc.AddTrack(track)
	if err != nil {
		return
	}
	p.senders[publisherID] = sender
	go func() {
		buffer := make([]byte, 1500)
		for {
			if _, _, err := sender.Read(buffer); err != nil {
				return
			}
		}
	}()
}

func (e *Engine) renegotiate(p *peer) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.closed {
		return
	}
	if p.pc.SignalingState() != webrtc.SignalingStateStable {
		p.renegotiatePending = true
		return
	}
	offer, err := p.pc.CreateOffer(nil)
	if err != nil {
		return
	}
	if err := p.pc.SetLocalDescription(offer); err != nil {
		return
	}
	e.emit(p.userID, p.roomID, EventOffer, Description{Type: offer.Type.String(), SDP: offer.SDP})
}

func (e *Engine) findPeer(roomID, userID uint64) *peer {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if r := e.rooms[roomID]; r != nil {
		return r.peers[userID]
	}
	return nil
}

func (e *Engine) broadcastParticipants(roomID uint64) {
	e.mu.RLock()
	r := e.rooms[roomID]
	if r == nil {
		e.mu.RUnlock()
		return
	}
	peers := make([]*peer, 0, len(r.peers))
	for _, p := range r.peers {
		peers = append(peers, p)
	}
	e.mu.RUnlock()

	participants := make([]Participant, 0, len(peers))
	for _, p := range peers {
		p.mu.Lock()
		participants = append(participants, Participant{UserID: p.userID, Muted: p.muted, Speaking: p.speaking})
		p.mu.Unlock()
	}
	for _, p := range peers {
		e.emit(p.userID, roomID, EventParticipants, map[string]any{"participants": participants})
	}
}

func (e *Engine) emit(userID, roomID uint64, event string, payload any) {
	if e.signal != nil {
		e.signal(userID, roomID, event, payload)
	}
}

func DecodeDescription(data json.RawMessage) (Description, error) {
	var description Description
	err := json.Unmarshal(data, &description)
	return description, err
}

func DecodeCandidate(data json.RawMessage) (Candidate, error) {
	var candidate Candidate
	err := json.Unmarshal(data, &candidate)
	return candidate, err
}
