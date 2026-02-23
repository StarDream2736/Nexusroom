package model

import (
	"time"
)

type RoomMember struct {
	RoomID    uint64    `gorm:"primaryKey" json:"room_id"`
	UserID    uint64    `gorm:"primaryKey" json:"user_id"`
	Role      string    `gorm:"size:16;not null;default:'member'" json:"role"`
	JoinedAt  time.Time `json:"joined_at"`
	
	// 关联
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (RoomMember) TableName() string {
	return "room_members"
}
