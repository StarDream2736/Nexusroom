package repository

import (
	"nexusroom-server/internal/model"

	"gorm.io/gorm"
)

type StreamRoomRef struct {
	StreamKey string
	RoomID    uint64
	RoomName  string
	Label     string
}

type IngressRepository struct {
	db *gorm.DB
}

func NewIngressRepository(db *gorm.DB) *IngressRepository {
	return &IngressRepository{db: db}
}

func (r *IngressRepository) Create(ingress *model.RoomIngress) error {
	return r.db.Create(ingress).Error
}

func (r *IngressRepository) FindByID(id uint64) (*model.RoomIngress, error) {
	var ingress model.RoomIngress
	err := r.db.First(&ingress, id).Error
	if err != nil {
		return nil, err
	}
	return &ingress, nil
}

func (r *IngressRepository) FindByIngressID(ingressID string) (*model.RoomIngress, error) {
	var ingress model.RoomIngress
	err := r.db.Where("ingress_id = ?", ingressID).First(&ingress).Error
	if err != nil {
		return nil, err
	}
	return &ingress, nil
}

func (r *IngressRepository) FindByStreamKey(streamKey string) (*model.RoomIngress, error) {
	var ingress model.RoomIngress
	err := r.db.Where("stream_key = ?", streamKey).First(&ingress).Error
	if err != nil {
		return nil, err
	}
	return &ingress, nil
}

func (r *IngressRepository) ListByRoom(roomID uint64) ([]model.RoomIngress, error) {
	var ingresses []model.RoomIngress
	err := r.db.Where("room_id = ?", roomID).Find(&ingresses).Error
	return ingresses, err
}

func (r *IngressRepository) Delete(id uint64) error {
	return r.db.Delete(&model.RoomIngress{}, id).Error
}

func (r *IngressRepository) SetActive(id uint64, active bool) error {
	return r.db.Model(&model.RoomIngress{}).Where("id = ?", id).Update("is_active", active).Error
}

func (r *IngressRepository) ListRoomRefsByStreamKeys(streamKeys []string) ([]StreamRoomRef, error) {
	if len(streamKeys) == 0 {
		return []StreamRoomRef{}, nil
	}

	refs := make([]StreamRoomRef, 0, len(streamKeys))
	err := r.db.Table("room_ingresses AS ri").
		Select("ri.stream_key AS stream_key, ri.room_id AS room_id, rooms.name AS room_name, ri.label AS label").
		Joins("JOIN rooms ON rooms.id = ri.room_id").
		Where("ri.stream_key IN ?", streamKeys).
		Scan(&refs).Error

	return refs, err
}
