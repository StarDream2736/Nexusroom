package model

import (
	"encoding/json"
	"errors"
	"time"
)

type Message struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	RoomID    uint64    `gorm:"not null;index" json:"room_id"`
	SenderID  uint64    `gorm:"not null;index" json:"sender_id"`
	Type      string    `gorm:"size:16;not null" json:"type"` // text / image / system / file
	Content   string    `gorm:"type:text;not null" json:"content"`
	Meta      *JSON     `gorm:"type:jsonb" json:"meta,omitempty"` // 额外元数据，如文件名、大小等
	CreatedAt time.Time `json:"created_at"`
	
	// 关联
	Sender User `gorm:"foreignKey:SenderID" json:"sender,omitempty"`
}

func (Message) TableName() string {
	return "messages"
}

// JSON 类型用于 PostgreSQL jsonb
type JSON map[string]interface{}

func (j JSON) Value() (interface{}, error) {
	if j == nil {
		return nil, nil
	}
	return json.Marshal(j)
}

func (j *JSON) Scan(value interface{}) error {
	if value == nil {
		*j = nil
		return nil
	}
	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed")
	}
	return json.Unmarshal(bytes, j)
}
