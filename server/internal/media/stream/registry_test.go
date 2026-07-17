package stream

import (
	"testing"
	"time"
)

func TestRegistryLifecycle(t *testing.T) {
	registry := NewRegistry()
	registry.Start("camera", []byte{1, 2, 3, 4}, []byte{5, 6}, []byte{0x12, 0x10})
	subscription, err := registry.Subscribe("camera")
	if err != nil {
		t.Fatal(err)
	}
	defer subscription.Close()

	frame := Frame{DTS: time.Second, PTS: time.Second, NALUs: [][]byte{{0x65, 1, 2}}, KeyFrame: true}
	if err := registry.Publish("camera", frame); err != nil {
		t.Fatal(err)
	}
	select {
	case received := <-subscription.Frames:
		if !received.KeyFrame || len(received.NALUs) != 1 {
			t.Fatalf("unexpected frame: %#v", received)
		}
	case <-time.After(time.Second):
		t.Fatal("subscriber did not receive frame")
	}
	if err := registry.PublishAudio("camera", AudioFrame{PTS: time.Second, Data: []byte{7, 8}}); err != nil {
		t.Fatal(err)
	}
	select {
	case received := <-subscription.Audio:
		if len(received.Data) != 2 || len(subscription.AAC) != 2 {
			t.Fatalf("unexpected audio frame/config: %#v %#v", received, subscription.AAC)
		}
	case <-time.After(time.Second):
		t.Fatal("subscriber did not receive audio")
	}

	info, ok := registry.Get("camera")
	if !ok || info.Viewers != 1 || !info.Active {
		t.Fatalf("unexpected stream info: %#v", info)
	}
	registry.Stop("camera")
	if _, ok := registry.Get("camera"); ok {
		t.Fatal("stopped stream remains registered")
	}
	if err := registry.Publish("camera", frame); err != ErrNotFound {
		t.Fatalf("publish after stop: %v", err)
	}
}
