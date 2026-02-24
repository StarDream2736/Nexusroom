package repository

import (
	"nexusroom-server/internal/model"

	"gorm.io/gorm"
)

type FriendshipRepository struct {
	db *gorm.DB
}

func NewFriendshipRepository(db *gorm.DB) *FriendshipRepository {
	return &FriendshipRepository{db: db}
}

func (r *FriendshipRepository) Create(friendship *model.Friendship) error {
	return r.db.Create(friendship).Error
}

// FindByUsers 查找两人之间的好友关系（不区分方向）
func (r *FriendshipRepository) FindByUsers(userA, userB uint64) (*model.Friendship, error) {
	var f model.Friendship
	err := r.db.Where(
		"(requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)",
		userA, userB, userB, userA,
	).First(&f).Error
	if err != nil {
		return nil, err
	}
	return &f, nil
}

// UpdateStatus 更新好友申请状态
func (r *FriendshipRepository) UpdateStatus(requesterID, addresseeID uint64, status string) error {
	return r.db.Model(&model.Friendship{}).
		Where("requester_id = ? AND addressee_id = ?", requesterID, addresseeID).
		Update("status", status).Error
}

// ListFriends 获取已接受的好友列表
func (r *FriendshipRepository) ListFriends(userID uint64) ([]model.User, error) {
	var users []model.User

	// 查找所有 accepted 的好友关系，返回对方的用户信息
	err := r.db.Raw(`
		SELECT u.* FROM users u
		INNER JOIN friendships f ON
			(f.requester_id = ? AND f.addressee_id = u.id AND f.status = 'accepted')
			OR
			(f.addressee_id = ? AND f.requester_id = u.id AND f.status = 'accepted')
	`, userID, userID).Scan(&users).Error
	return users, err
}

// ListPendingRequests 获取待处理的好友申请（收到的）
func (r *FriendshipRepository) ListPendingRequests(userID uint64) ([]model.Friendship, error) {
	var requests []model.Friendship
	err := r.db.Where("addressee_id = ? AND status = 'pending'", userID).
		Preload("Requester").
		Find(&requests).Error
	return requests, err
}

// DeleteFriendship 删除好友关系
func (r *FriendshipRepository) DeleteFriendship(userA, userB uint64) error {
	return r.db.Where(
		"(requester_id = ? AND addressee_id = ?) OR (requester_id = ? AND addressee_id = ?)",
		userA, userB, userB, userA,
	).Delete(&model.Friendship{}).Error
}
