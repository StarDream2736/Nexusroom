package repository

import (
	"nexusroom-server/internal/model"

	"gorm.io/gorm"
)

type RoomRepository struct {
	db *gorm.DB
}

func NewRoomRepository(db *gorm.DB) *RoomRepository {
	return &RoomRepository{db: db}
}

func (r *RoomRepository) Create(room *model.Room) error {
	return r.db.Create(room).Error
}

func (r *RoomRepository) FindByID(id uint64) (*model.Room, error) {
	var room model.Room
	err := r.db.Preload("Owner").Preload("Members.User").First(&room, id).Error
	if err != nil {
		return nil, err
	}
	return &room, nil
}

func (r *RoomRepository) FindByInviteCode(code string) (*model.Room, error) {
	var room model.Room
	err := r.db.Where("invite_code = ?", code).First(&room).Error
	if err != nil {
		return nil, err
	}
	return &room, nil
}

func (r *RoomRepository) FindByRoomCode(code string) (*model.Room, error) {
	var room model.Room
	err := r.db.Where("room_code = ?", code).First(&room).Error
	if err != nil {
		return nil, err
	}
	return &room, nil
}

func (r *RoomRepository) Update(room *model.Room) error {
	return r.db.Save(room).Error
}

func (r *RoomRepository) Delete(id uint64) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		// 级联删除相关数据
		if err := tx.Where("room_id = ?", id).Delete(&model.RoomMember{}).Error; err != nil {
			return err
		}
		if err := tx.Where("room_id = ?", id).Delete(&model.Message{}).Error; err != nil {
			return err
		}
		if err := tx.Where("room_id = ?", id).Delete(&model.RoomIngress{}).Error; err != nil {
			return err
		}
		if err := tx.Where("room_id = ?", id).Delete(&model.WGPeer{}).Error; err != nil {
			return err
		}
		return tx.Delete(&model.Room{}, id).Error
	})
}

func (r *RoomRepository) List(page, pageSize int) ([]model.Room, int64, error) {
	var rooms []model.Room
	var total int64

	offset := (page - 1) * pageSize

	r.db.Model(&model.Room{}).Count(&total)
	err := r.db.Preload("Owner").Offset(offset).Limit(pageSize).Find(&rooms).Error

	return rooms, total, err
}

func (r *RoomRepository) ListByUser(userID uint64) ([]model.Room, error) {
	var rooms []model.Room
	err := r.db.Joins("JOIN room_members ON rooms.id = room_members.room_id").
		Where("room_members.user_id = ?", userID).
		Preload("Owner").
		Find(&rooms).Error
	return rooms, err
}

// RoomMember 相关操作

func (r *RoomRepository) AddMember(roomID, userID uint64, role string) error {
	member := &model.RoomMember{
		RoomID: roomID,
		UserID: userID,
		Role:   role,
	}
	return r.db.Create(member).Error
}

func (r *RoomRepository) RemoveMember(roomID, userID uint64) error {
	return r.db.Where("room_id = ? AND user_id = ?", roomID, userID).Delete(&model.RoomMember{}).Error
}

func (r *RoomRepository) IsMember(roomID, userID uint64) bool {
	var count int64
	r.db.Model(&model.RoomMember{}).Where("room_id = ? AND user_id = ?", roomID, userID).Count(&count)
	return count > 0
}

func (r *RoomRepository) GetMember(roomID, userID uint64) (*model.RoomMember, error) {
	var member model.RoomMember
	err := r.db.Where("room_id = ? AND user_id = ?", roomID, userID).First(&member).Error
	if err != nil {
		return nil, err
	}
	return &member, nil
}
