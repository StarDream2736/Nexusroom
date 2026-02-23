package handler

import (
	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"golang.org/x/crypto/bcrypt"
	
	"nexusroom-server/internal/config"
	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
	"nexusroom-server/pkg/jwt"
	"nexusroom-server/pkg/util"
)

type AuthHandler struct {
	userRepo *repository.UserRepository
}

func NewAuthHandler(userRepo *repository.UserRepository) *AuthHandler {
	return &AuthHandler{userRepo: userRepo}
}

type RegisterRequest struct {
	Username   string `json:"username" validate:"required,min=3,max=32,alphanum"`
	Password   string `json:"password" validate:"required,min=6,max=128"`
	Nickname   string `json:"nickname" validate:"required,min=1,max=64"`
	AdminToken string `json:"admin_token"`
}

type LoginRequest struct {
	Username string `json:"username" validate:"required"`
	Password string `json:"password" validate:"required"`
}

type AuthResponse struct {
	UserID        uint64 `json:"user_id"`
	UserDisplayID string `json:"user_display_id"`
	Token         string `json:"token"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}
	
	validate := validator.New()
	if err := validate.Struct(req); err != nil {
		util.Error(c, 40001, err.Error())
		return
	}
	
	// 检查用户名是否已存在
	existingUser, _ := h.userRepo.FindByUsername(req.Username)
	if existingUser != nil {
		util.Error(c, 40901, "用户名已存在")
		return
	}
	
	// 密码哈希
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	if err != nil {
		util.Error(c, 50001, "密码加密失败")
		return
	}
	
	// 确定角色
	role := "user"
	if req.AdminToken != "" && req.AdminToken == config.GlobalConfig.Auth.AdminToken {
		role = "super_admin"
	}
	
	// 创建用户
	user := &model.User{
		Username:     req.Username,
		PasswordHash: string(hashedPassword),
		Nickname:     req.Nickname,
		Role:         role,
	}
	
	if err := h.userRepo.Create(user); err != nil {
		util.Error(c, 50001, "创建用户失败")
		return
	}
	
	// 生成 Token
	token, err := jwt.GenerateToken(user.ID, user.Username, user.Role)
	if err != nil {
		util.Error(c, 50001, "Token 生成失败")
		return
	}
	
	util.Success(c, AuthResponse{
		UserID:        user.ID,
		UserDisplayID: user.UserDisplayID,
		Token:         token,
	})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}
	
	// 查找用户
	user, err := h.userRepo.FindByUsername(req.Username)
	if err != nil {
		util.Error(c, 40101, "用户名或密码错误")
		return
	}
	
	// 验证密码
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		util.Error(c, 40101, "用户名或密码错误")
		return
	}
	
	// 检查账户是否启用
	if !user.IsActive {
		util.Error(c, 40301, "账户已被禁用")
		return
	}
	
	// 更新最后登录时间
	h.userRepo.UpdateLastLogin(user.ID)
	
	// 生成 Token
	token, err := jwt.GenerateToken(user.ID, user.Username, user.Role)
	if err != nil {
		util.Error(c, 50001, "Token 生成失败")
		return
	}
	
	util.Success(c, AuthResponse{
		UserID:        user.ID,
		UserDisplayID: user.UserDisplayID,
		Token:         token,
	})
}
