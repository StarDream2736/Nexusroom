package audiotranscode

import (
	"os"
	"os/exec"
	"testing"
	"time"
)

func TestAACLCADTSHeader(t *testing.T) {
	config, err := parseAudioSpecificConfig([]byte{0x12, 0x10})
	if err != nil {
		t.Fatal(err)
	}
	header, err := config.header(100)
	if err != nil {
		t.Fatal(err)
	}
	want := [7]byte{0xff, 0xf1, 0x50, 0x80, 0x0d, 0x7f, 0xfc}
	if header != want {
		t.Fatalf("got %x, want %x", header, want)
	}
}

func TestRejectsUnsupportedAACConfig(t *testing.T) {
	if _, err := parseAudioSpecificConfig([]byte{0x2a, 0x10}); err == nil {
		t.Fatal("expected unsupported AAC object type error")
	}
}

func TestAACToOpusWithFFmpeg(t *testing.T) {
	ffmpegPath := os.Getenv("NEXUSROOM_TEST_FFMPEG")
	if ffmpegPath == "" {
		t.Skip("set NEXUSROOM_TEST_FFMPEG to run the FFmpeg integration test")
	}
	aac, err := exec.Command(ffmpegPath,
		"-nostdin", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
		"-t", "0.5", "-c:a", "aac", "-f", "adts", "pipe:1",
	).Output()
	if err != nil {
		t.Fatal(err)
	}

	packets := make(chan OpusPacket, 1)
	transcoder, err := StartAACToOpus(ffmpegPath, []byte{0x12, 0x08}, func(packet OpusPacket) {
		select {
		case packets <- packet:
		default:
		}
	}, func(err error) {
		t.Logf("transcoder stopped: %v", err)
	})
	if err != nil {
		t.Fatal(err)
	}
	defer transcoder.Close()

	for len(aac) >= 7 {
		frameLength := int(aac[3]&0x03)<<11 | int(aac[4])<<3 | int(aac[5]>>5)
		if frameLength < 7 || frameLength > len(aac) {
			t.Fatalf("invalid generated ADTS frame length %d", frameLength)
		}
		if err := transcoder.Write(aac[7:frameLength]); err != nil {
			t.Fatal(err)
		}
		aac = aac[frameLength:]
	}

	select {
	case packet := <-packets:
		if len(packet.Payload) == 0 {
			t.Fatal("received empty Opus RTP payload")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for transcoded Opus RTP")
	}
}
