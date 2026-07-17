package flv

import (
	"encoding/binary"
	"errors"
	"io"
	"time"

	"nexusroom-server/internal/media/stream"
)

var ErrInvalidH264Config = errors.New("invalid H264 configuration")

type Muxer struct {
	w io.Writer
}

func New(w io.Writer) *Muxer { return &Muxer{w: w} }

func (m *Muxer) WriteHeader(sps, pps []byte, aac ...[]byte) error {
	if len(sps) < 4 || len(pps) == 0 || len(sps) > 0xffff || len(pps) > 0xffff {
		return ErrInvalidH264Config
	}
	flags := byte(1)
	var audioConfig []byte
	if len(aac) != 0 && len(aac[0]) != 0 {
		flags = 5
		audioConfig = aac[0]
	}
	header := []byte{'F', 'L', 'V', 1, flags, 0, 0, 0, 9, 0, 0, 0, 0}
	if _, err := m.w.Write(header); err != nil {
		return err
	}

	config := make([]byte, 0, 16+len(sps)+len(pps))
	config = append(config, 0x17, 0, 0, 0, 0)
	config = append(config, 1, sps[1], sps[2], sps[3], 0xff, 0xe1)
	config = binary.BigEndian.AppendUint16(config, uint16(len(sps)))
	config = append(config, sps...)
	config = append(config, 1)
	config = binary.BigEndian.AppendUint16(config, uint16(len(pps)))
	config = append(config, pps...)
	if err := m.writeTag(9, 0, config); err != nil {
		return err
	}
	if len(audioConfig) != 0 {
		return m.writeTag(8, 0, append([]byte{0xaf, 0}, audioConfig...))
	}
	return nil
}

func (m *Muxer) WriteAudio(frame stream.AudioFrame) error {
	if len(frame.Data) == 0 {
		return nil
	}
	body := make([]byte, 2, 2+len(frame.Data))
	body[0], body[1] = 0xaf, 1
	body = append(body, frame.Data...)
	return m.writeTag(8, uint32(frame.PTS/time.Millisecond), body)
}

func (m *Muxer) WriteFrame(frame stream.Frame) error {
	if len(frame.NALUs) == 0 {
		return nil
	}
	body := make([]byte, 0, 5+frameSize(frame.NALUs))
	if frame.KeyFrame {
		body = append(body, 0x17)
	} else {
		body = append(body, 0x27)
	}
	body = append(body, 1)
	composition := int64((frame.PTS - frame.DTS) / time.Millisecond)
	body = append(body, byte(composition>>16), byte(composition>>8), byte(composition))
	for _, nalu := range frame.NALUs {
		body = binary.BigEndian.AppendUint32(body, uint32(len(nalu)))
		body = append(body, nalu...)
	}
	return m.writeTag(9, uint32(frame.DTS/time.Millisecond), body)
}

func (m *Muxer) writeTag(tagType byte, timestamp uint32, body []byte) error {
	header := make([]byte, 11)
	header[0] = tagType
	putUint24(header[1:4], uint32(len(body)))
	putUint24(header[4:7], timestamp&0xffffff)
	header[7] = byte(timestamp >> 24)
	if _, err := m.w.Write(header); err != nil {
		return err
	}
	if _, err := m.w.Write(body); err != nil {
		return err
	}
	var previous [4]byte
	binary.BigEndian.PutUint32(previous[:], uint32(len(header)+len(body)))
	_, err := m.w.Write(previous[:])
	return err
}

func putUint24(dst []byte, value uint32) {
	dst[0] = byte(value >> 16)
	dst[1] = byte(value >> 8)
	dst[2] = byte(value)
}

func frameSize(nalus [][]byte) int {
	size := 0
	for _, nalu := range nalus {
		size += 4 + len(nalu)
	}
	return size
}
