package handler

import (
	"testing"
	"time"

	mediastream "nexusroom-server/internal/media/stream"
)

func TestBuildWebLiveRoomsCreatesTemporaryWebEntry(t *testing.T) {
	rooms := buildWebLiveRooms([]mediastream.Info{{
		Key: "temporary-stream", Active: true, StartedAt: time.Now(),
	}}, nil)

	if len(rooms) != 1 {
		t.Fatalf("got %d rooms, want 1", len(rooms))
	}
	room := rooms[0]
	if room.ID != "virtual-temporary-stream" || room.Type != "virtual" || room.Name != "临时直播-temporar" {
		t.Fatalf("unexpected temporary room: %#v", room)
	}
	if room.RoomID != 0 || len(room.Streams) != 1 || room.Streams[0].StreamKey != "temporary-stream" {
		t.Fatalf("unexpected temporary stream: %#v", room)
	}
}
