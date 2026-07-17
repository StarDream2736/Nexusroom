package flv

import (
	"bytes"
	"encoding/binary"
	"testing"
	"time"

	"nexusroom-server/internal/media/stream"
)

func TestMuxerWritesFLVHeaderAndVideoTags(t *testing.T) {
	var out bytes.Buffer
	muxer := New(&out)
	sps := []byte{0x67, 0x64, 0x00, 0x1f, 0xac, 0xd9}
	pps := []byte{0x68, 0xee, 0x3c, 0x80}
	if err := muxer.WriteHeader(sps, pps); err != nil {
		t.Fatal(err)
	}
	if err := muxer.WriteFrame(stream.Frame{
		PTS: 40 * time.Millisecond, DTS: 40 * time.Millisecond,
		NALUs: [][]byte{{0x65, 1, 2, 3}}, KeyFrame: true,
	}); err != nil {
		t.Fatal(err)
	}
	data := out.Bytes()
	if string(data[:3]) != "FLV" {
		t.Fatalf("invalid FLV signature: %x", data[:3])
	}
	if data[13] != 9 || data[24] != 0x17 || data[25] != 0 {
		t.Fatalf("invalid AVC sequence header: %x", data[13:30])
	}
	firstSize := int(binary.BigEndian.Uint32(data[9:13]))
	if firstSize != 0 {
		t.Fatalf("expected PreviousTagSize0, got %d", firstSize)
	}
}

func TestMuxerWritesAAC(t *testing.T) {
	var out bytes.Buffer
	muxer := New(&out)
	if err := muxer.WriteHeader(
		[]byte{0x67, 0x42, 0xe0, 0x1f}, []byte{0x68, 0xce, 0x06, 0xe2}, []byte{0x12, 0x10},
	); err != nil {
		t.Fatal(err)
	}
	if out.Bytes()[4] != 5 {
		t.Fatalf("expected audio/video FLV flags, got %d", out.Bytes()[4])
	}
	beforeAudioFrame := out.Len()
	if err := muxer.WriteAudio(stream.AudioFrame{PTS: 23 * time.Millisecond, Data: []byte{1, 2, 3}}); err != nil {
		t.Fatal(err)
	}
	data := out.Bytes()
	if data[beforeAudioFrame] != 8 || data[beforeAudioFrame+11] != 0xaf || data[beforeAudioFrame+12] != 1 {
		t.Fatalf("invalid AAC raw tag: %x", data[beforeAudioFrame:])
	}
}
