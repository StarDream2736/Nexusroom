package handler

import (
	"fmt"
	"net"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/ws"
	"nexusroom-server/pkg/util"
)

type RoomHandler struct {
	roomRepo    *repository.RoomRepository
	userRepo    *repository.UserRepository
	ingressRepo *repository.IngressRepository
	hub         *ws.Hub
	cfg         *config.Config
}

func NewRoomHandler(roomRepo *repository.RoomRepository, userRepo *repository.UserRepository,
	ingressRepo *repository.IngressRepository, hub *ws.Hub, cfg *config.Config) *RoomHandler {
	return &RoomHandler{
		roomRepo:    roomRepo,
		userRepo:    userRepo,
		ingressRepo: ingressRepo,
		hub:         hub,
		cfg:         cfg,
	}
}

type CreateRoomRequest struct {
	Name string `json:"name" validate:"required,min=1,max=128"`
}

type UpdateRoomRequest struct {
	Name string `json:"name" validate:"required,min=1,max=128"`
}

type JoinRoomRequest struct {
	InviteCode string `json:"invite_code" validate:"required,len=6"`
}

type RoomResponse struct {
	ID              uint64            `json:"id"`
	Name            string            `json:"name"`
	RoomCode        string            `json:"room_code"`
	InviteCode      string            `json:"invite_code"`
	OwnerID         uint64            `json:"owner_id"`
	LiveKitRoomName string            `json:"livekit_room_name"`
	Members         []MemberResponse  `json:"members"`
	Ingresses       []IngressResponse `json:"ingresses"`
	LiveKitUrl      string            `json:"livekit_url"`
}

type MemberResponse struct {
	UserID    uint64 `json:"user_id"`
	Nickname  string `json:"nickname"`
	AvatarURL string `json:"avatar_url"`
	Role      string `json:"role"`
}

type IngressResponse struct {
	ID        uint64 `json:"id"`
	IngressID string `json:"ingress_id"`
	RTMPURL   string `json:"rtmp_url"`
	StreamKey string `json:"stream_key"`
	Label     string `json:"label"`
	IsActive  bool   `json:"is_active"`
}

func (h *RoomHandler) Create(c *gin.Context) {
	var req CreateRoomRequest
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

	room := &model.Room{
		Name:    req.Name,
		OwnerID: userID,
	}

	if err := h.roomRepo.Create(room); err != nil {
		util.Error(c, 50001, "创建房间失败")
		return
	}

	// 创建者自动成为成员
	if err := h.roomRepo.AddMember(room.ID, userID, "admin"); err != nil {
		util.Error(c, 50001, "添加成员失败")
		return
	}

	util.Success(c, gin.H{
		"id":                room.ID,
		"name":              room.Name,
		"room_code":         room.RoomCode,
		"invite_code":       room.InviteCode,
		"livekit_room_name": room.LiveKitRoomName,
	})
}

func (h *RoomHandler) Join(c *gin.Context) {
	var req JoinRoomRequest
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

	room, err := h.roomRepo.FindByInviteCode(req.InviteCode)
	if err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 检查是否已是成员
	if h.roomRepo.IsMember(room.ID, userID) {
		util.Error(c, 40901, "已是房间成员")
		return
	}

	// 添加成员
	if err := h.roomRepo.AddMember(room.ID, userID, "member"); err != nil {
		util.Error(c, 50001, "加入房间失败")
		return
	}

	util.Success(c, gin.H{
		"id":                room.ID,
		"name":              room.Name,
		"room_code":         room.RoomCode,
		"invite_code":       room.InviteCode,
		"livekit_room_name": room.LiveKitRoomName,
	})
}

func (h *RoomHandler) GetDetail(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	// 检查是否是成员
	if !h.roomRepo.IsMember(roomID, userID) {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权访问该房间")
		return
	}

	room, err := h.roomRepo.FindByID(roomID)
	if err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	ingresses, _ := h.ingressRepo.ListByRoom(roomID)

	// 构建响应
	members := make([]MemberResponse, 0, len(room.Members))
	for _, m := range room.Members {
		members = append(members, MemberResponse{
			UserID:    m.UserID,
			Nickname:  m.User.Nickname,
			AvatarURL: m.User.AvatarURL,
			Role:      m.Role,
		})
	}

	ingressList := make([]IngressResponse, 0, len(ingresses))
	for _, ing := range ingresses {
		ingressList = append(ingressList, IngressResponse{
			ID:        ing.ID,
			IngressID: ing.IngressID,
			RTMPURL:   ing.RTMPURL,
			StreamKey: ing.StreamKey,
			Label:     ing.Label,
			IsActive:  ing.IsActive,
		})
	}

	// 构建客户端应该连接的 LiveKit URL
	// 优先使用 config 中配置的 public_url（排除 localhost/127.0.0.1）
	var liveKitUrl string
	publicURL := h.cfg.LiveKit.PublicURL
	if publicURL != "" &&
		!strings.Contains(publicURL, "localhost") &&
		!strings.Contains(publicURL, "127.0.0.1") &&
		!strings.Contains(publicURL, "livekit:") {
		// config 中设置了有效的公网 URL，直接使用
		liveKitUrl = publicURL
	} else {
		// 自动推导：从请求 Host 头提取 IP，使用 LiveKit 默认端口 7880
		host := c.GetHeader("X-Forwarded-Host")
		if host == "" {
			host = c.Request.Host
		}
		// 剥离端口（API 服务器的 8080 等），只保留 IP/域名
		hostOnly, _, err := net.SplitHostPort(host)
		if err != nil {
			// 本身没有端口，直接使用
			hostOnly = host
		}
		scheme := c.GetHeader("X-Forwarded-Proto")
		if scheme == "https" {
			liveKitUrl = fmt.Sprintf("wss://%s:7880", hostOnly)
		} else {
			liveKitUrl = fmt.Sprintf("ws://%s:7880", hostOnly)
		}
	}

	util.Success(c, RoomResponse{
		ID:              room.ID,
		Name:            room.Name,
		RoomCode:        room.RoomCode,
		InviteCode:      room.InviteCode,
		OwnerID:         room.OwnerID,
		LiveKitRoomName: room.LiveKitRoomName,
		Members:         members,
		Ingresses:       ingressList,
		LiveKitUrl:      liveKitUrl,
	})
}

func (h *RoomHandler) List(c *gin.Context) {
	userID := c.GetUint64("userID")

	rooms, err := h.roomRepo.ListByUser(userID)
	if err != nil {
		util.Error(c, 50001, "获取房间列表失败")
		return
	}

	result := make([]gin.H, 0, len(rooms))
	for _, room := range rooms {
		result = append(result, gin.H{
			"id":                room.ID,
			"name":              room.Name,
			"room_code":         room.RoomCode,
			"invite_code":       room.InviteCode,
			"owner_id":          room.OwnerID,
			"livekit_room_name": room.LiveKitRoomName,
		})
	}

	util.Success(c, result)
}

func (h *RoomHandler) KickMember(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	targetUserID, err := strconv.ParseUint(c.Param("userId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "用户ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	// 获取房间信息
	room, err := h.roomRepo.FindByID(roomID)
	if err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 检查权限（房主或超管）
	if room.OwnerID != userID && c.GetString("role") != "super_admin" {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权踢出成员")
		return
	}

	// 不能踢出房主
	if targetUserID == room.OwnerID {
		util.Error(c, 40301, "不能踢出房主")
		return
	}

	if err := h.roomRepo.RemoveMember(roomID, targetUserID); err != nil {
		util.Error(c, 50001, "踢出成员失败")
		return
	}

	// 通过 WebSocket 通知被踢用户和房间其他成员
	h.hub.KickUserFromRoom(roomID, targetUserID, "你已被房主踢出房间")

	util.Success(c, nil)
}

func (h *RoomHandler) UpdateRoom(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	var req UpdateRoomRequest
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

	room, err := h.roomRepo.FindByID(roomID)
	if err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 检查权限（房主或超管）
	if room.OwnerID != userID && c.GetString("role") != "super_admin" {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权修改房间")
		return
	}

	room.Name = req.Name
	if err := h.roomRepo.Update(room); err != nil {
		util.Error(c, 50001, "修改房间失败")
		return
	}

	util.Success(c, gin.H{
		"id":   room.ID,
		"name": room.Name,
	})
}

// Leave DELETE /rooms/:roomId/leave — 成员主动退出房间
func (h *RoomHandler) Leave(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	// 获取房间信息
	room, err := h.roomRepo.FindByID(roomID)
	if err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 检查是否是成员
	if !h.roomRepo.IsMember(roomID, userID) {
		util.Error(c, 40401, "你不是该房间成员")
		return
	}

	// 房主不能退出，必须先解散房间
	if room.OwnerID == userID {
		util.Error(c, 40301, "房主不能退出房间，请先解散房间")
		return
	}

	if err := h.roomRepo.RemoveMember(roomID, userID); err != nil {
		util.Error(c, 50001, "退出房间失败")
		return
	}

	// 通过 WebSocket 通知房间其他成员
	h.hub.BroadcastToRoom(roomID, ws.EventRoomMemberLeave, ws.RoomMemberLeavePayload{
		UserID: userID,
		RoomID: roomID,
	}, userID)

	util.Success(c, nil)
}

// Delete DELETE /rooms/:roomId — 房主或超管解散房间
func (h *RoomHandler) Delete(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	// 获取房间信息
	room, err := h.roomRepo.FindByID(roomID)
	if err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 检查权限（房主或超管）
	if room.OwnerID != userID && c.GetString("role") != "super_admin" {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权解散房间")
		return
	}

	// 通知所有房间成员（在删除前发送）
	h.hub.BroadcastToRoom(roomID, ws.EventRoomDisbanded, ws.RoomDisbandedPayload{
		RoomID: roomID,
	}, 0)

	if err := h.roomRepo.Delete(roomID); err != nil {
		util.Error(c, 50001, "解散房间失败")
		return
	}

	util.Success(c, nil)
}

// OnlineUsers GET /rooms/:roomId/online-users — 获取房间在线用户列表
func (h *RoomHandler) OnlineUsers(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	// 检查是否为房间成员
	if !h.roomRepo.IsMember(roomID, userID) {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权访问")
		return
	}

	onlineUserIDs := h.hub.GetOnlineUsersInRoom(roomID)
	if onlineUserIDs == nil {
		onlineUserIDs = []uint64{}
	}

	util.Success(c, gin.H{
		"online_user_ids": onlineUserIDs,
	})
}
