package model

import (
	"time"
)

type Friendship struct {
	RequesterID uint64    `gorm:"primaryKey" json:"requester_id"`
	AddresseeID uint64    `gorm:"primaryKey" json:"addressee_id"`
	Status      string    `gorm:"size:16;not null;default:'pending'" json:"status"` // pending / accepted / rejected
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	
	// 关联
	Requester User `gorm:"foreignKey:RequesterID" json:"requester,omitempty"`
	Addressee User `gorm:"foreignKey:AddresseeID" json:"addressee,omitempty"`
}

func (Friendship) TableName() string {
	return "friendships"
}
