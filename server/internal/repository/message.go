package repository

import (
	"time"

	"nexusroom-server/internal/model"

	"gorm.io/gorm"
)

type MessageRepository struct {
	db *gorm.DB
}

func NewMessageRepository(db *gorm.DB) *MessageRepository {
	return &MessageRepository{db: db}
}

func (r *MessageRepository) Create(msg *model.Message) error {
	return r.db.Create(msg).Error
}

func (r *MessageRepository) FindByID(id uint64) (*model.Message, error) {
	var msg model.Message
	err := r.db.Preload("Sender").First(&msg, id).Error
	if err != nil {
		return nil, err
	}
	return &msg, nil
}

// GetMessagesAfter 获取 after_id 之后的消息（增量同步）
func (r *MessageRepository) GetMessagesAfter(roomID uint64, afterID uint64, limit int) ([]model.Message, error) {
	var messages []model.Message
	err := r.db.Where("room_id = ? AND id > ?", roomID, afterID).
		Order("id ASC").
		Limit(limit).
		Preload("Sender").
		Find(&messages).Error
	return messages, err
}

// GetMessagesBefore 获取 before_id 之前的消息（加载更早消息）
func (r *MessageRepository) GetMessagesBefore(roomID uint64, beforeID uint64, limit int) ([]model.Message, error) {
	var messages []model.Message
	err := r.db.Where("room_id = ? AND id < ?", roomID, beforeID).
		Order("id DESC").
		Limit(limit).
		Preload("Sender").
		Find(&messages).Error

	// 反转顺序
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	return messages, err
}

// GetLatestMessages 获取最新消息
func (r *MessageRepository) GetLatestMessages(roomID uint64, limit int) ([]model.Message, error) {
	var messages []model.Message
	err := r.db.Where("room_id = ?", roomID).
		Order("id DESC").
		Limit(limit).
		Preload("Sender").
		Find(&messages).Error

	// 反转顺序
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	return messages, err
}

// Count 统计消息总数
func (r *MessageRepository) Count() int64 {
	var total int64
	r.db.Model(&model.Message{}).Count(&total)
	return total
}

// CleanupOldMessages 清理过期消息
func (r *MessageRepository) CleanupOldMessages(retentionDays int) error {
	if retentionDays <= 0 {
		return nil // 0 表示永久保留
	}

	cutoffTime := time.Now().AddDate(0, 0, -retentionDays)
	return r.db.Where("created_at < ?", cutoffTime).Delete(&model.Message{}).Error
}
