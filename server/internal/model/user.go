package model

import (
	"math/rand"
	"strconv"
	"time"
	
	"gorm.io/gorm"
)

type User struct {
	ID            uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UserDisplayID string         `gorm:"uniqueIndex;size:12;not null" json:"user_display_id"`
	Username      string         `gorm:"uniqueIndex;size:64;not null" json:"username"`
	PasswordHash  string         `gorm:"size:255;not null" json:"-"`
	Nickname      string         `gorm:"size:64;not null" json:"nickname"`
	AvatarURL     string         `gorm:"size:512" json:"avatar_url"`
	Role          string         `gorm:"size:16;not null;default:'user'" json:"role"`
	IsActive      bool           `gorm:"not null;default:true" json:"is_active"`
	CreatedAt     time.Time      `json:"created_at"`
	LastLoginAt   *time.Time     `json:"last_login_at"`
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
	// 6-12位随机数字
	rand.Seed(time.Now().UnixNano())
	length := 6 + rand.Intn(7) // 6-12位
	result := ""
	for i := 0; i < length; i++ {
		result += strconv.Itoa(rand.Intn(10))
	}
	return result
}
