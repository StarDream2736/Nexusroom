package handler

import (
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/ws"
	"nexusroom-server/pkg/util"
)

type AdminHandler struct {
	userRepo *repository.UserRepository
	roomRepo *repository.RoomRepository
	msgRepo  *repository.MessageRepository
	hub      *ws.Hub
	cfg      *config.Config
}

func NewAdminHandler(
	userRepo *repository.UserRepository,
	roomRepo *repository.RoomRepository,
	msgRepo *repository.MessageRepository,
	hub *ws.Hub,
	cfg *config.Config,
) *AdminHandler {
	return &AdminHandler{
		userRepo: userRepo,
		roomRepo: roomRepo,
		msgRepo:  msgRepo,
		hub:      hub,
		cfg:      cfg,
	}
}

// ListUsers GET /admin/users?page=1&page_size=50&keyword=
func (h *AdminHandler) ListUsers(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 50
	}

	users, total, err := h.userRepo.List(page, pageSize)
	if err != nil {
		util.Error(c, 50001, "获取用户列表失败")
		return
	}

	list := make([]gin.H, 0, len(users))
	for _, u := range users {
		list = append(list, gin.H{
			"id":              u.ID,
			"user_display_id": u.UserDisplayID,
			"username":        u.Username,
			"nickname":        u.Nickname,
			"avatar_url":      u.AvatarURL,
			"role":            u.Role,
			"is_active":       u.IsActive,
			"created_at":      u.CreatedAt,
			"last_login_at":   u.LastLoginAt,
		})
	}

	util.Success(c, gin.H{
		"users": list,
		"total": total,
	})
}

// ToggleUser PATCH /admin/users/:userId — 禁用/启用用户
func (h *AdminHandler) ToggleUser(c *gin.Context) {
	userID, err := strconv.ParseUint(c.Param("userId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "用户ID格式错误")
		return
	}

	var req struct {
		IsActive bool `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}

	if err := h.userRepo.SetActive(userID, req.IsActive); err != nil {
		util.Error(c, 50001, "操作失败")
		return
	}

	util.Success(c, nil)
}

// ListRooms GET /admin/rooms?page=1&page_size=50
func (h *AdminHandler) ListRooms(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 50
	}

	rooms, total, err := h.roomRepo.List(page, pageSize)
	if err != nil {
		util.Error(c, 50001, "获取房间列表失败")
		return
	}

	list := make([]gin.H, 0, len(rooms))
	for _, r := range rooms {
		ownerName := ""
		if r.Owner.ID != 0 {
			ownerName = r.Owner.Nickname
		}
		list = append(list, gin.H{
			"id":                r.ID,
			"name":              r.Name,
			"room_code":         r.RoomCode,
			"invite_code":       r.InviteCode,
			"owner_id":          r.OwnerID,
			"owner_nickname":    ownerName,
			"livekit_room_name": r.LiveKitRoomName,
			"created_at":        r.CreatedAt,
		})
	}

	util.Success(c, gin.H{
		"rooms": list,
		"total": total,
	})
}

// DeleteRoom DELETE /admin/rooms/:roomId — 强制解散房间
func (h *AdminHandler) DeleteRoom(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	if err := h.roomRepo.Delete(roomID); err != nil {
		util.Error(c, 50001, "解散房间失败")
		return
	}

	util.Success(c, nil)
}

// GetConfig GET /admin/config — 获取当前服务器配置（脱敏）
func (h *AdminHandler) GetConfig(c *gin.Context) {
	util.Success(c, gin.H{
		"server_port":               h.cfg.Server.Port,
		"server_mode":               h.cfg.Server.Mode,
		"server_domain":             h.cfg.Server.Domain,
		"message_retention_days":    h.cfg.Message.RetentionDays,
		"livekit_url":               h.cfg.LiveKit.URL,
		"livekit_ingress_rtmp_port": h.cfg.LiveKitIngress.RTMPPort,
		"wireguard_subnet":          h.cfg.WireGuard.Subnet,
		"wireguard_gateway_ip":      h.cfg.WireGuard.GatewayIP,
		"wireguard_listen_port":     h.cfg.WireGuard.ListenPort,
		"storage_path":              h.cfg.Storage.Path,
		"storage_max_file_size_mb":  h.cfg.Storage.MaxFileSizeMB,
	})
}

// UpdateConfig PATCH /admin/config — 修改运行时配置
func (h *AdminHandler) UpdateConfig(c *gin.Context) {
	var req struct {
		MessageRetentionDays *int `json:"message_retention_days,omitempty"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}

	if req.MessageRetentionDays != nil {
		h.cfg.Message.RetentionDays = *req.MessageRetentionDays
		viper.Set("message.retention_days", *req.MessageRetentionDays)
		if err := viper.WriteConfig(); err != nil {
			util.Error(c, 50001, "配置持久化失败")
			return
		}
	}

	util.Success(c, nil)
}

// GetStats GET /admin/stats — 服务器统计信息
func (h *AdminHandler) GetStats(c *gin.Context) {
	// 在线用户数（通过 Hub 线程安全方法统计）
	onlineUsers := h.hub.OnlineCount()

	// 总房间数
	_, totalRooms, _ := h.roomRepo.List(1, 1)

	// 总消息数
	totalMessages := h.msgRepo.Count()

	// 总用户数
	_, totalUsers, _ := h.userRepo.List(1, 1)

	util.Success(c, gin.H{
		"online_users":   onlineUsers,
		"total_users":    totalUsers,
		"total_rooms":    totalRooms,
		"total_messages": totalMessages,
	})
}
