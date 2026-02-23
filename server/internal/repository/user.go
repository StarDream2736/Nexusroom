package repository

import (
	"time"
	
	"gorm.io/gorm"
	"nexusroom-server/internal/model"
)

type UserRepository struct {
	db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(user *model.User) error {
	return r.db.Create(user).Error
}

func (r *UserRepository) FindByID(id uint64) (*model.User, error) {
	var user model.User
	err := r.db.First(&user, id).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) FindByUsername(username string) (*model.User, error) {
	var user model.User
	err := r.db.Where("username = ?", username).First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) FindByDisplayID(displayID string) (*model.User, error) {
	var user model.User
	err := r.db.Where("user_display_id = ?", displayID).First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *UserRepository) Update(user *model.User) error {
	return r.db.Save(user).Error
}

func (r *UserRepository) UpdateLastLogin(userID uint64) error {
	now := time.Now()
	return r.db.Model(&model.User{}).Where("id = ?", userID).Update("last_login_at", &now).Error
}

func (r *UserRepository) UpdateProfile(userID uint64, nickname, avatarURL string) error {
	updates := map[string]interface{}{}
	if nickname != "" {
		updates["nickname"] = nickname
	}
	if avatarURL != "" {
		updates["avatar_url"] = avatarURL
	}
	return r.db.Model(&model.User{}).Where("id = ?", userID).Updates(updates).Error
}

func (r *UserRepository) List(page, pageSize int) ([]model.User, int64, error) {
	var users []model.User
	var total int64
	
	offset := (page - 1) * pageSize
	
	r.db.Model(&model.User{}).Count(&total)
	err := r.db.Offset(offset).Limit(pageSize).Find(&users).Error
	
	return users, total, err
}

func (r *UserRepository) SetActive(userID uint64, active bool) error {
	return r.db.Model(&model.User{}).Where("id = ?", userID).Update("is_active", active).Error
}
