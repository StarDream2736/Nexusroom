package model

import (
	"time"
)

type RoomIngress struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	RoomID     uint64    `gorm:"not null;index" json:"room_id"`
	IngressID  string    `gorm:"uniqueIndex;size:128;not null" json:"ingress_id"`
	StreamKey  string    `gorm:"uniqueIndex;size:128;not null" json:"stream_key"`
	RTMPURL    string    `gorm:"size:256;not null" json:"rtmp_url"`
	Label      string    `gorm:"size:64" json:"label"`
	IsActive   bool      `gorm:"not null;default:false" json:"is_active"`
	CreatedBy  uint64    `gorm:"not null" json:"created_by"`
	CreatedAt  time.Time `json:"created_at"`
}

func (RoomIngress) TableName() string {
	return "room_ingresses"
}
