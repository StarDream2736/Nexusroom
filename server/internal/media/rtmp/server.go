package rtmp

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/bluenviron/gortmplib"
	"github.com/bluenviron/gortmplib/pkg/codecs"

	"nexusroom-server/internal/media/audiotranscode"
	"nexusroom-server/internal/media/stream"
)

type AuthorizeFunc func(streamKey string) bool
type StateFunc func(streamKey string, active bool)

type Server struct {
	address    string
	registry   *stream.Registry
	ffmpegPath string
	authorize  AuthorizeFunc
	onState    StateFunc

	mu       sync.Mutex
	listener net.Listener
	closed   bool
}

func New(address string, registry *stream.Registry, ffmpegPath string, authorize AuthorizeFunc, onState StateFunc) *Server {
	return &Server{address: address, registry: registry, ffmpegPath: ffmpegPath, authorize: authorize, onState: onState}
}

func (s *Server) Run(ctx context.Context) error {
	listener, err := net.Listen("tcp", s.address)
	if err != nil {
		return fmt.Errorf("listen RTMP on %s: %w", s.address, err)
	}
	s.mu.Lock()
	s.listener = listener
	s.mu.Unlock()
	go func() {
		<-ctx.Done()
		_ = s.Close()
	}()

	for {
		conn, acceptErr := listener.Accept()
		if acceptErr != nil {
			s.mu.Lock()
			closed := s.closed
			s.mu.Unlock()
			if closed || errors.Is(acceptErr, net.ErrClosed) {
				return nil
			}
			return acceptErr
		}
		go s.handle(conn)
	}
}

func (s *Server) Close() error {
	s.mu.Lock()
	s.closed = true
	listener := s.listener
	s.mu.Unlock()
	if listener != nil {
		return listener.Close()
	}
	return nil
}

func (s *Server) handle(conn net.Conn) {
	defer conn.Close()
	if err := s.handleInner(conn); err != nil {
		log.Printf("[RTMP] %s: %v", conn.RemoteAddr(), err)
	}
}

func (s *Server) handleInner(conn net.Conn) error {
	_ = conn.SetDeadline(time.Now().Add(15 * time.Second))
	serverConn := &gortmplib.ServerConn{RW: conn}
	if err := serverConn.Initialize(); err != nil {
		return err
	}
	if err := serverConn.Accept(); err != nil {
		return err
	}
	if !serverConn.Publish {
		return errors.New("RTMP playback is served through HTTP-FLV or WebRTC")
	}
	if serverConn.URL == nil || strings.Trim(serverConn.URL.Path, "/") == "" {
		return errors.New("missing RTMP stream key")
	}
	parts := strings.Split(strings.Trim(serverConn.URL.Path, "/"), "/")
	if len(parts) != 2 || parts[0] != "live" {
		return errors.New("RTMP publish path must be /live/{streamKey}")
	}
	streamKey := parts[1]
	if !validStreamKey(streamKey) {
		return errors.New("invalid RTMP stream key")
	}
	if s.authorize != nil && !s.authorize(streamKey) {
		return errors.New("unknown or unauthorized stream key")
	}
	if _, active := s.registry.Get(streamKey); active {
		return errors.New("stream key is already publishing")
	}

	reader := &gortmplib.Reader{Conn: serverConn}
	if err := reader.Initialize(); err != nil {
		return err
	}
	var h264Track *gortmplib.Track
	var h264Codec *codecs.H264
	var audioTrack *gortmplib.Track
	var audioConfig []byte
	for _, track := range reader.Tracks() {
		switch codec := track.Codec.(type) {
		case *codecs.H264:
			h264Track = track
			h264Codec = codec
		case *codecs.MPEG4Audio:
			if codec.Config != nil {
				if encoded, marshalErr := codec.Config.Marshal(); marshalErr == nil {
					audioTrack = track
					audioConfig = encoded
				}
			}
		}
	}
	if h264Track == nil || h264Codec == nil {
		return errors.New("NexusRoom currently accepts H.264 RTMP video")
	}

	s.registry.Start(streamKey, h264Codec.SPS, h264Codec.PPS, audioConfig)
	var audioTranscoder *audiotranscode.AACToOpus
	if len(audioConfig) != 0 {
		transcoder, transcodeErr := audiotranscode.StartAACToOpus(
			s.ffmpegPath,
			audioConfig,
			func(packet audiotranscode.OpusPacket) {
				_ = s.registry.PublishOpus(streamKey, stream.OpusFrame{
					SequenceNumber: packet.SequenceNumber,
					Timestamp:      packet.Timestamp,
					Marker:         packet.Marker,
					Payload:        packet.Payload,
				})
			},
			func(failure error) {
				_ = s.registry.SetOpusAvailable(streamKey, false)
				log.Printf("[RTMP] audio transcoding stopped for %s: %v", streamKey, failure)
			},
		)
		if transcodeErr != nil {
			log.Printf("[RTMP] WebRTC audio unavailable for %s: %v", streamKey, transcodeErr)
		} else {
			audioTranscoder = transcoder
			_ = s.registry.SetOpusAvailable(streamKey, true)
		}
	}
	if s.onState != nil {
		s.onState(streamKey, true)
	}
	defer func() {
		if audioTranscoder != nil {
			audioTranscoder.Close()
		}
		s.registry.Stop(streamKey)
		if s.onState != nil {
			s.onState(streamKey, false)
		}
	}()

	reader.OnDataH264(h264Track, func(pts, dts time.Duration, accessUnit [][]byte) {
		_ = s.registry.Publish(streamKey, stream.Frame{
			PTS: pts, DTS: dts, NALUs: accessUnit, KeyFrame: isKeyFrame(accessUnit),
		})
	})
	if audioTrack != nil {
		reader.OnDataMPEG4Audio(audioTrack, func(pts time.Duration, accessUnit []byte) {
			_ = s.registry.PublishAudio(streamKey, stream.AudioFrame{PTS: pts, Data: accessUnit})
			if audioTranscoder != nil {
				if writeErr := audioTranscoder.Write(accessUnit); writeErr != nil {
					_ = s.registry.SetOpusAvailable(streamKey, false)
				}
			}
		})
	}
	_ = conn.SetDeadline(time.Time{})
	for {
		if err := reader.Read(); err != nil {
			return err
		}
	}
}

func validStreamKey(streamKey string) bool {
	if len(streamKey) < 8 || len(streamKey) > 128 {
		return false
	}
	for _, char := range streamKey {
		if (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') ||
			(char >= '0' && char <= '9') || char == '-' || char == '_' {
			continue
		}
		return false
	}
	return true
}

func isKeyFrame(accessUnit [][]byte) bool {
	for _, nalu := range accessUnit {
		if len(nalu) > 0 && nalu[0]&0x1f == 5 {
			return true
		}
	}
	return false
}
