package handler

import (
	"os"
	"path/filepath"
	"strings"
	
	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
	
	"nexusroom-server/internal/config"
	"nexusroom-server/internal/repository"
	"nexusroom-server/pkg/util"
)

type UserHandler struct {
	userRepo    *repository.UserRepository
	storagePath string
	maxSize     int64
}

func NewUserHandler(userRepo *repository.UserRepository, cfg *config.Config) *UserHandler {
	return &UserHandler{
		userRepo:    userRepo,
		storagePath: cfg.Storage.Path,
		maxSize:     int64(cfg.Storage.MaxFileSizeMB) * 1024 * 1024,
	}
}

type UpdateProfileRequest struct {
	Nickname string `json:"nickname" validate:"omitempty,min=1,max=64"`
}

func (h *UserHandler) GetMe(c *gin.Context) {
	userID := c.GetUint64("userID")
	
	user, err := h.userRepo.FindByID(userID)
	if err != nil {
		util.Error(c, 40401, "用户不存在")
		return
	}
	
	util.Success(c, gin.H{
		"id":              user.ID,
		"user_display_id": user.UserDisplayID,
		"username":        user.Username,
		"nickname":        user.Nickname,
		"avatar_url":      user.AvatarURL,
		"role":            user.Role,
		"created_at":      user.CreatedAt,
	})
}

func (h *UserHandler) UpdateProfile(c *gin.Context) {
	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}
	
	validate := validator.New()
	if err := validate.Struct(req); err != nil {
		util.Error(c, 40001, err.Error())
		return
	}
	
	userID := c.GetUint64("userID")
	
	if err := h.userRepo.UpdateProfile(userID, req.Nickname, ""); err != nil {
		util.Error(c, 50001, "更新资料失败")
		return
	}
	
	util.Success(c, nil)
}

func (h *UserHandler) SearchByDisplayID(c *gin.Context) {
	displayID := c.Query("display_id")
	if displayID == "" {
		util.Error(c, 40001, "display_id 不能为空")
		return
	}
	
	user, err := h.userRepo.FindByDisplayID(displayID)
	if err != nil {
		util.Error(c, 40401, "用户不存在")
		return
	}
	
	util.Success(c, gin.H{
		"id":              user.ID,
		"user_display_id": user.UserDisplayID,
		"nickname":        user.Nickname,
		"avatar_url":      user.AvatarURL,
	})
}

// UploadAvatar 处理头像上传
func (h *UserHandler) UploadAvatar(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		util.Error(c, 40001, "文件不能为空")
		return
	}

	if h.maxSize > 0 && file.Size > h.maxSize {
		util.Error(c, 40001, "文件大小超出限制")
		return
	}

	mimeType := file.Header.Get("Content-Type")
	if !strings.HasPrefix(mimeType, "image/") {
		util.Error(c, 40001, "仅支持图片类型")
		return
	}

	if err := os.MkdirAll(h.storagePath, 0755); err != nil {
		util.Error(c, 50001, "创建存储目录失败")
		return
	}

	ext := filepath.Ext(file.Filename)
	fileName := "avatar_" + uuid.NewString() + ext
	avatarDir := filepath.Join(h.storagePath, "avatars")
	if err := os.MkdirAll(avatarDir, 0755); err != nil {
		util.Error(c, 50001, "创建头像目录失败")
		return
	}

	destPath := filepath.Join(avatarDir, fileName)
	if err := c.SaveUploadedFile(file, destPath); err != nil {
		util.Error(c, 50001, "保存头像失败")
		return
	}

	userID := c.GetUint64("userID")
	avatarURL := "/uploads/avatars/" + fileName
	if err := h.userRepo.UpdateProfile(userID, "", avatarURL); err != nil {
		util.Error(c, 50001, "更新头像失败")
		return
	}

	util.Success(c, gin.H{
		"avatar_url": avatarURL,
	})
}
