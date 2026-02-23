package model

import (
	"time"
)

type WGPeer struct {
	ID              uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	RoomID          uint64     `gorm:"not null;index" json:"room_id"`
	UserID          uint64     `gorm:"not null;index" json:"user_id"`
	PublicKey       string     `gorm:"size:64;not null" json:"public_key"`
	AssignedIP      string     `gorm:"size:18;not null" json:"assigned_ip"`
	LastHandshakeAt *time.Time `json:"last_handshake_at"`
	CreatedAt       time.Time  `json:"created_at"`
	
	// 关联
	User User `gorm:"foreignKey:UserID" json:"user,omitempty"`
}

func (WGPeer) TableName() string {
	return "wg_peers"
}
