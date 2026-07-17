package ws

import (
	"encoding/json"
	"testing"
	"time"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
)

func TestHandleChatSendPersistsAndBroadcastsClientMessageID(t *testing.T) {
	db := newChatTestDB(t)
	user := model.User{Username: "alice", Nickname: "Alice", IsActive: true}
	if err := db.Create(&user).Error; err != nil {
		t.Fatal(err)
	}
	room := model.Room{Name: "General", OwnerID: user.ID}
	if err := db.Create(&room).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&model.RoomMember{RoomID: room.ID, UserID: user.ID}).Error; err != nil {
		t.Fatal(err)
	}

	hub := NewHub(
		repository.NewMessageRepository(db),
		repository.NewRoomRepository(db),
		repository.NewUserRepository(db),
	)
	client := NewClient(hub, nil, user.ID, user.Username, "user")
	client.JoinRoom(room.ID)

	done := make(chan struct{})
	go func() {
		hub.HandleChatSend(client, ChatSendPayload{
			RoomID:          room.ID,
			Type:            "text",
			Content:         "hello",
			ClientMessageID: "client-1",
		})
		close(done)
	}()

	select {
	case broadcast := <-hub.Broadcast:
		if broadcast.Event != EventChatMessage {
			t.Fatalf("unexpected event %s", broadcast.Event)
		}
		payload, ok := broadcast.Payload.(ChatMessagePayload)
		if !ok {
			t.Fatalf("unexpected payload type %T", broadcast.Payload)
		}
		if payload.ClientMessageID != "client-1" || payload.Content != "hello" {
			t.Fatalf("unexpected payload: %+v", payload)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("chat broadcast timed out")
	}
	<-done

	var count int64
	if err := db.Model(&model.Message{}).Where("room_id = ? AND content = ?", room.ID, "hello").Count(&count).Error; err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("expected one persisted message, got %d", count)
	}
}

func TestHandleChatSendReturnsCorrelatedErrorWhenNotJoined(t *testing.T) {
	db := newChatTestDB(t)
	hub := NewHub(
		repository.NewMessageRepository(db),
		repository.NewRoomRepository(db),
		repository.NewUserRepository(db),
	)
	client := NewClient(hub, nil, 9, "alice", "user")

	hub.HandleChatSend(client, ChatSendPayload{
		RoomID:          42,
		Type:            "text",
		Content:         "hello",
		ClientMessageID: "client-error",
	})

	select {
	case raw := <-client.Send:
		var envelope Envelope
		if err := json.Unmarshal(raw, &envelope); err != nil {
			t.Fatal(err)
		}
		if envelope.Event != EventChatError {
			t.Fatalf("unexpected event %s", envelope.Event)
		}
		var payload ChatErrorPayload
		if err := json.Unmarshal(envelope.Payload, &payload); err != nil {
			t.Fatal(err)
		}
		if payload.Reason != "not_in_room" || payload.ClientMessageID != "client-error" {
			t.Fatalf("unexpected payload: %+v", payload)
		}
	case <-time.After(time.Second):
		t.Fatal("chat error timed out")
	}
}

func newChatTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := "file:" + t.Name() + "?mode=memory&cache=shared&_foreign_keys=on"
	db, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&model.User{}, &model.Room{}, &model.RoomMember{}, &model.Message{}); err != nil {
		t.Fatal(err)
	}
	return db
}
