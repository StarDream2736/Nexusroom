package audiotranscode

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os/exec"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/pion/rtp"
)

type OpusPacket struct {
	SequenceNumber uint16
	Timestamp      uint32
	Marker         bool
	Payload        []byte
}

type AACToOpus struct {
	stdin     io.WriteCloser
	conn      *net.UDPConn
	cancel    context.CancelFunc
	done      chan struct{}
	adts      adtsConfig
	writeMu   sync.Mutex
	closeOnce sync.Once
	stopped   atomic.Bool
}

func StartAACToOpus(
	ffmpegPath string,
	audioSpecificConfig []byte,
	onPacket func(OpusPacket),
	onFailure func(error),
) (*AACToOpus, error) {
	if ffmpegPath == "" {
		return nil, errors.New("FFmpeg path is empty")
	}
	adts, err := parseAudioSpecificConfig(audioSpecificConfig)
	if err != nil {
		return nil, err
	}
	ffmpegExecutable, err := exec.LookPath(ffmpegPath)
	if err != nil {
		return nil, fmt.Errorf("find FFmpeg: %w", err)
	}
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		return nil, fmt.Errorf("listen for Opus RTP: %w", err)
	}
	port := conn.LocalAddr().(*net.UDPAddr).Port
	ctx, cancel := context.WithCancel(context.Background())
	command := exec.CommandContext(ctx, ffmpegExecutable,
		"-nostdin", "-hide_banner", "-loglevel", "error",
		"-fflags", "+nobuffer", "-flags", "+low_delay",
		"-probesize", "32", "-analyzeduration", "0",
		"-f", "aac", "-i", "pipe:0", "-vn",
		"-c:a", "libopus", "-application", "lowdelay",
		"-frame_duration", "20", "-ar", "48000", "-ac", "1",
		"-b:a", "64000", "-vbr", "off",
		"-flush_packets", "1", "-muxdelay", "0", "-f", "rtp", "-payload_type", "111",
		"rtp://127.0.0.1:"+strconv.Itoa(port)+"?pkt_size=1200",
	)
	stdin, err := command.StdinPipe()
	if err != nil {
		cancel()
		_ = conn.Close()
		return nil, fmt.Errorf("open FFmpeg AAC input: %w", err)
	}
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	if err := command.Start(); err != nil {
		cancel()
		_ = stdin.Close()
		_ = conn.Close()
		return nil, fmt.Errorf("start FFmpeg AAC to Opus transcoder: %w", err)
	}

	transcoder := &AACToOpus{
		stdin: stdin, conn: conn, cancel: cancel, done: make(chan struct{}), adts: adts,
	}
	var failureOnce sync.Once
	reportFailure := func(failure error) {
		if transcoder.stopped.Load() || onFailure == nil {
			return
		}
		failureOnce.Do(func() { onFailure(failure) })
	}
	go transcoder.readRTP(onPacket, reportFailure)
	go func() {
		waitErr := command.Wait()
		close(transcoder.done)
		if waitErr != nil {
			reportFailure(fmt.Errorf("FFmpeg AAC to Opus stopped: %w", waitErr))
		} else {
			reportFailure(errors.New("FFmpeg AAC to Opus stopped unexpectedly"))
		}
	}()
	return transcoder, nil
}

func (t *AACToOpus) Write(accessUnit []byte) error {
	if len(accessUnit) == 0 {
		return nil
	}
	if t.stopped.Load() {
		return io.ErrClosedPipe
	}
	header, err := t.adts.header(len(accessUnit))
	if err != nil {
		return err
	}
	t.writeMu.Lock()
	defer t.writeMu.Unlock()
	if err := writeAll(t.stdin, header[:]); err != nil {
		return err
	}
	return writeAll(t.stdin, accessUnit)
}

func (t *AACToOpus) Close() {
	t.closeOnce.Do(func() {
		t.stopped.Store(true)
		_ = t.stdin.Close()
		t.cancel()
		_ = t.conn.Close()
		select {
		case <-t.done:
		case <-time.After(2 * time.Second):
		}
	})
}

func (t *AACToOpus) readRTP(onPacket func(OpusPacket), onFailure func(error)) {
	buffer := make([]byte, 2048)
	for {
		n, _, err := t.conn.ReadFromUDP(buffer)
		if err != nil {
			onFailure(fmt.Errorf("read transcoded Opus RTP: %w", err))
			return
		}
		var packet rtp.Packet
		if err := packet.Unmarshal(buffer[:n]); err != nil || len(packet.Payload) == 0 {
			continue
		}
		if onPacket != nil {
			onPacket(OpusPacket{
				SequenceNumber: packet.SequenceNumber,
				Timestamp:      packet.Timestamp,
				Marker:         packet.Marker,
				Payload:        append([]byte(nil), packet.Payload...),
			})
		}
	}
}

type adtsConfig struct {
	profile         byte
	sampleRateIndex byte
	channelConfig   byte
}

func parseAudioSpecificConfig(config []byte) (adtsConfig, error) {
	if len(config) < 2 {
		return adtsConfig{}, errors.New("invalid AAC AudioSpecificConfig")
	}
	audioObjectType := (config[0] >> 3) & 0x1f
	if audioObjectType < 1 || audioObjectType > 4 {
		return adtsConfig{}, fmt.Errorf("unsupported AAC object type %d", audioObjectType)
	}
	sampleRateIndex := ((config[0] & 0x07) << 1) | (config[1] >> 7)
	if sampleRateIndex > 12 {
		return adtsConfig{}, fmt.Errorf("unsupported AAC sample rate index %d", sampleRateIndex)
	}
	channelConfig := (config[1] >> 3) & 0x0f
	if channelConfig == 0 || channelConfig > 7 {
		return adtsConfig{}, fmt.Errorf("unsupported AAC channel configuration %d", channelConfig)
	}
	return adtsConfig{
		profile: audioObjectType - 1, sampleRateIndex: sampleRateIndex, channelConfig: channelConfig,
	}, nil
}

func (c adtsConfig) header(payloadSize int) ([7]byte, error) {
	var header [7]byte
	frameLength := payloadSize + len(header)
	if frameLength > 0x1fff {
		return header, fmt.Errorf("AAC access unit is too large: %d bytes", payloadSize)
	}
	header[0] = 0xff
	header[1] = 0xf1
	header[2] = (c.profile << 6) | (c.sampleRateIndex << 2) | (c.channelConfig >> 2)
	header[3] = ((c.channelConfig & 0x03) << 6) | byte(frameLength>>11)
	header[4] = byte(frameLength >> 3)
	header[5] = byte((frameLength&0x07)<<5) | 0x1f
	header[6] = 0xfc
	return header, nil
}

func writeAll(writer io.Writer, data []byte) error {
	for len(data) > 0 {
		written, err := writer.Write(data)
		if err != nil {
			return err
		}
		if written == 0 {
			return io.ErrShortWrite
		}
		data = data[written:]
	}
	return nil
}
