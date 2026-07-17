package stream

import (
	"errors"
	"sync"
	"time"
)

var ErrNotFound = errors.New("media stream not found")

type Frame struct {
	PTS      time.Duration
	DTS      time.Duration
	NALUs    [][]byte
	KeyFrame bool
}

type AudioFrame struct {
	PTS  time.Duration
	Data []byte
}

type Info struct {
	Key         string    `json:"key"`
	Active      bool      `json:"active"`
	Viewers     int       `json:"viewers"`
	BitrateKbps float64   `json:"bitrate_kbps"`
	StartedAt   time.Time `json:"started_at"`
}

type Subscription struct {
	Frames <-chan Frame
	Audio  <-chan AudioFrame
	SPS    []byte
	PPS    []byte
	AAC    []byte
	close  func()
}

func (s *Subscription) Close() {
	if s.close != nil {
		s.close()
		s.close = nil
	}
}

type Registry struct {
	mu      sync.RWMutex
	streams map[string]*entry
}

type entry struct {
	mu          sync.RWMutex
	key         string
	sps         []byte
	pps         []byte
	startedAt   time.Time
	totalBytes  uint64
	aac         []byte
	subscribers map[uint64]subscriber
	nextID      uint64
	closed      bool
}

func NewRegistry() *Registry {
	return &Registry{streams: make(map[string]*entry)}
}

type subscriber struct {
	video chan Frame
	audio chan AudioFrame
}

func (r *Registry) Start(key string, sps, pps []byte, aac ...[]byte) {
	var audioConfig []byte
	if len(aac) != 0 {
		audioConfig = aac[0]
	}
	e := &entry{
		key:         key,
		sps:         append([]byte(nil), sps...),
		pps:         append([]byte(nil), pps...),
		startedAt:   time.Now(),
		aac:         append([]byte(nil), audioConfig...),
		subscribers: make(map[uint64]subscriber),
	}
	r.mu.Lock()
	previous := r.streams[key]
	r.streams[key] = e
	r.mu.Unlock()
	if previous != nil {
		previous.shutdown()
	}
}

func (r *Registry) PublishAudio(key string, frame AudioFrame) error {
	r.mu.RLock()
	e := r.streams[key]
	r.mu.RUnlock()
	if e == nil {
		return ErrNotFound
	}
	return e.publishAudio(frame)
}

func (r *Registry) Stop(key string) {
	r.mu.Lock()
	e := r.streams[key]
	if e != nil {
		delete(r.streams, key)
	}
	r.mu.Unlock()
	if e != nil {
		e.shutdown()
	}
}

func (r *Registry) Publish(key string, frame Frame) error {
	r.mu.RLock()
	e := r.streams[key]
	r.mu.RUnlock()
	if e == nil {
		return ErrNotFound
	}
	return e.publish(frame)
}

func (r *Registry) Subscribe(key string) (*Subscription, error) {
	r.mu.RLock()
	e := r.streams[key]
	r.mu.RUnlock()
	if e == nil {
		return nil, ErrNotFound
	}
	return e.subscribe()
}

func (r *Registry) Snapshot() []Info {
	r.mu.RLock()
	entries := make([]*entry, 0, len(r.streams))
	for _, e := range r.streams {
		entries = append(entries, e)
	}
	r.mu.RUnlock()
	result := make([]Info, 0, len(entries))
	for _, e := range entries {
		result = append(result, e.info())
	}
	return result
}

func (r *Registry) Get(key string) (Info, bool) {
	r.mu.RLock()
	e := r.streams[key]
	r.mu.RUnlock()
	if e == nil {
		return Info{}, false
	}
	return e.info(), true
}

func (e *entry) publish(frame Frame) error {
	e.mu.Lock()
	if e.closed {
		e.mu.Unlock()
		return ErrNotFound
	}
	copyFrame := cloneFrame(frame)
	for _, nalu := range copyFrame.NALUs {
		e.totalBytes += uint64(len(nalu))
	}
	for _, subscriber := range e.subscribers {
		select {
		case subscriber.video <- copyFrame:
		default:
			// Live video favors low latency. A slow reader drops frames and
			// resumes at the next available frame instead of blocking ingest.
		}
	}
	e.mu.Unlock()
	return nil
}

func (e *entry) publishAudio(frame AudioFrame) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return ErrNotFound
	}
	frame.Data = append([]byte(nil), frame.Data...)
	e.totalBytes += uint64(len(frame.Data))
	for _, subscriber := range e.subscribers {
		select {
		case subscriber.audio <- frame:
		default:
		}
	}
	return nil
}

func (e *entry) subscribe() (*Subscription, error) {
	e.mu.Lock()
	if e.closed {
		e.mu.Unlock()
		return nil, ErrNotFound
	}
	id := e.nextID
	e.nextID++
	frames := make(chan Frame, 256)
	audio := make(chan AudioFrame, 512)
	e.subscribers[id] = subscriber{video: frames, audio: audio}
	sps := append([]byte(nil), e.sps...)
	pps := append([]byte(nil), e.pps...)
	aac := append([]byte(nil), e.aac...)
	e.mu.Unlock()

	var once sync.Once
	return &Subscription{
		Frames: frames,
		Audio:  audio,
		SPS:    sps,
		PPS:    pps,
		AAC:    aac,
		close: func() {
			once.Do(func() {
				e.mu.Lock()
				if current, ok := e.subscribers[id]; ok {
					delete(e.subscribers, id)
					close(current.video)
					close(current.audio)
				}
				e.mu.Unlock()
			})
		},
	}, nil
}

func (e *entry) info() Info {
	e.mu.RLock()
	defer e.mu.RUnlock()
	elapsed := time.Since(e.startedAt).Seconds()
	bitrate := float64(0)
	if elapsed > 0 {
		bitrate = float64(e.totalBytes*8) / elapsed / 1000
	}
	return Info{
		Key: e.key, Active: !e.closed, Viewers: len(e.subscribers),
		BitrateKbps: bitrate, StartedAt: e.startedAt,
	}
}

func (e *entry) shutdown() {
	e.mu.Lock()
	if !e.closed {
		e.closed = true
		for id, subscriber := range e.subscribers {
			close(subscriber.video)
			close(subscriber.audio)
			delete(e.subscribers, id)
		}
	}
	e.mu.Unlock()
}

func cloneFrame(frame Frame) Frame {
	copyFrame := frame
	copyFrame.NALUs = make([][]byte, len(frame.NALUs))
	for i, nalu := range frame.NALUs {
		copyFrame.NALUs[i] = append([]byte(nil), nalu...)
	}
	return copyFrame
}
