package repository

import (
	"nexusroom-server/internal/model"

	"gorm.io/gorm"
)

type WGPeerRepository struct {
	db *gorm.DB
}

func NewWGPeerRepository(db *gorm.DB) *WGPeerRepository {
	return &WGPeerRepository{db: db}
}

func (r *WGPeerRepository) Create(peer *model.WGPeer) error {
	return r.db.Create(peer).Error
}

func (r *WGPeerRepository) FindByRoomAndUser(roomID, userID uint64) (*model.WGPeer, error) {
	var peer model.WGPeer
	err := r.db.Where("room_id = ? AND user_id = ?", roomID, userID).First(&peer).Error
	if err != nil {
		return nil, err
	}
	return &peer, nil
}

func (r *WGPeerRepository) Update(peer *model.WGPeer) error {
	return r.db.Save(peer).Error
}

func (r *WGPeerRepository) ListByRoom(roomID uint64) ([]model.WGPeer, error) {
	var peers []model.WGPeer
	err := r.db.Where("room_id = ?", roomID).Preload("User").Find(&peers).Error
	return peers, err
}

func (r *WGPeerRepository) Delete(roomID, userID uint64) error {
	return r.db.Where("room_id = ? AND user_id = ?", roomID, userID).Delete(&model.WGPeer{}).Error
}

// GetMaxAssignedIP 获取房间内已分配的最大 IP 后缀
func (r *WGPeerRepository) CountByRoom(roomID uint64) (int64, error) {
	var count int64
	err := r.db.Model(&model.WGPeer{}).Where("room_id = ?", roomID).Count(&count).Error
	return count, err
}

// GetAllAssignedIPs 获取房间内已分配的所有 IP
func (r *WGPeerRepository) GetAllAssignedIPs(roomID uint64) ([]string, error) {
	var ips []string
	err := r.db.Model(&model.WGPeer{}).Where("room_id = ?", roomID).Pluck("assigned_ip", &ips).Error
	return ips, err
}
