package model

import (
	"math/rand"
	"time"
	
	"gorm.io/gorm"
)

type Room struct {
	ID              uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	RoomCode        string    `gorm:"uniqueIndex;size:16;not null" json:"room_code"`
	InviteCode      string    `gorm:"uniqueIndex;size:8;not null" json:"invite_code"`
	Name            string    `gorm:"size:128;not null" json:"name"`
	OwnerID         uint64    `gorm:"not null;index" json:"owner_id"`
	LiveKitRoomName string    `gorm:"uniqueIndex;size:128;not null" json:"livekit_room_name"`
	CreatedAt       time.Time `json:"created_at"`
	
	// 关联
	Owner   User          `gorm:"foreignKey:OwnerID" json:"owner,omitempty"`
	Members []RoomMember  `gorm:"foreignKey:RoomID" json:"members,omitempty"`
}

func (Room) TableName() string {
	return "rooms"
}

func (r *Room) BeforeCreate(tx *gorm.DB) error {
	if r.RoomCode == "" {
		r.RoomCode = "rm_" + GenerateRandomString(8)
	}
	if r.InviteCode == "" {
		r.InviteCode = GenerateInviteCode()
	}
	if r.LiveKitRoomName == "" {
		r.LiveKitRoomName = "nexusroom_" + r.RoomCode
	}
	return nil
}

func GenerateInviteCode() string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 排除易混淆字符
	rand.Seed(time.Now().UnixNano())
	result := make([]byte, 6)
	for i := range result {
		result[i] = chars[rand.Intn(len(chars))]
	}
	return string(result)
}

func GenerateRandomString(length int) string {
	const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	rand.Seed(time.Now().UnixNano())
	result := make([]byte, length)
	for i := range result {
		result[i] = chars[rand.Intn(len(chars))]
	}
	return string(result)
}
