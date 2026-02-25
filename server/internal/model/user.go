package model

import (
	cryptorand "crypto/rand"
	"math/big"
	"strconv"
	"time"

	"gorm.io/gorm"
)

type User struct {
	ID            uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserDisplayID string     `gorm:"uniqueIndex;size:12;not null" json:"user_display_id"`
	Username      string     `gorm:"uniqueIndex;size:64;not null" json:"username"`
	PasswordHash  string     `gorm:"size:255;not null" json:"-"`
	Nickname      string     `gorm:"size:64;not null" json:"nickname"`
	AvatarURL     string     `gorm:"size:512" json:"avatar_url"`
	Role          string     `gorm:"size:16;not null;default:'user'" json:"role"`
	IsActive      bool       `gorm:"not null;default:true" json:"is_active"`
	CreatedAt     time.Time  `json:"created_at"`
	LastLoginAt   *time.Time `json:"last_login_at"`
}

func (User) TableName() string {
	return "users"
}

func (u *User) BeforeCreate(tx *gorm.DB) error {
	if u.UserDisplayID == "" {
		u.UserDisplayID = GenerateDisplayID()
	}
	return nil
}

func GenerateDisplayID() string {
	// 固定 5 位数字 (10000-99999)
	n, _ := cryptorand.Int(cryptorand.Reader, big.NewInt(90000))
	return strconv.Itoa(10000 + int(n.Int64()))
}
