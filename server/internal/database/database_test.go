package database

import (
	"path/filepath"
	"testing"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/model"
)

func TestOpenMigrateAndJSONRoundTrip(t *testing.T) {
	cfg := &config.Config{
		Database: config.DatabaseConfig{Path: filepath.Join(t.TempDir(), "nexusroom.db")},
	}
	db, err := Open(cfg)
	if err != nil {
		t.Fatal(err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	if err := Migrate(db); err != nil {
		t.Fatal(err)
	}

	user := &model.User{Username: "alice", PasswordHash: "hash", Nickname: "Alice"}
	if err := db.Create(user).Error; err != nil {
		t.Fatal(err)
	}
	room := &model.Room{Name: "room", OwnerID: user.ID}
	if err := db.Create(room).Error; err != nil {
		t.Fatal(err)
	}
	meta := model.JSON{"filename": "test.txt", "size": float64(42)}
	message := &model.Message{
		RoomID: room.ID, SenderID: user.ID, Type: "file", Content: "file", Meta: &meta,
	}
	if err := db.Create(message).Error; err != nil {
		t.Fatal(err)
	}

	var got model.Message
	if err := db.First(&got, message.ID).Error; err != nil {
		t.Fatal(err)
	}
	if got.Meta == nil || (*got.Meta)["filename"] != "test.txt" {
		t.Fatalf("unexpected JSON metadata: %#v", got.Meta)
	}
	if err := Check(db); err != nil {
		t.Fatal(err)
	}
}
