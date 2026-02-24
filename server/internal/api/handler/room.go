package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"

	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/service"
	"nexusroom-server/internal/ws"
	"nexusroom-server/pkg/util"
)

type RoomHandler struct {
	roomRepo    *repository.RoomRepository
	userRepo    *repository.UserRepository
	ingressRepo *repository.IngressRepository
	livekitSvc  *service.LiveKitService
	hub         *ws.Hub
}

func NewRoomHandler(roomRepo *repository.RoomRepository, userRepo *repository.UserRepository,
	ingressRepo *repository.IngressRepository, livekitSvc *service.LiveKitService, hub *ws.Hub) *RoomHandler {
	return &RoomHandler{
		roomRepo:    roomRepo,
		userRepo:    userRepo,
		ingressRepo: ingressRepo,
		livekitSvc:  livekitSvc,
		hub:         hub,
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

	// 创建默认 Ingress
	var ingressList []IngressResponse
	ingress, err := h.livekitSvc.CreateIngress(room.LiveKitRoomName, "默认推流入口")
	if err != nil {
		// 不阻断房间创建，仅记录日志
		// log.Printf("创建 Ingress 失败: %v", err)
	} else {
		rmIngress := &model.RoomIngress{
			RoomID:    room.ID,
			IngressID: ingress.IngressId,
			StreamKey: ingress.StreamKey,
			RTMPURL:   ingress.Url,
			Label:     "默认推流入口",
			CreatedBy: userID,
		}
		h.ingressRepo.Create(rmIngress)
		ingressList = append(ingressList, IngressResponse{
			ID:        rmIngress.ID,
			IngressID: ingress.IngressId,
			RTMPURL:   ingress.Url,
			StreamKey: ingress.StreamKey,
			Label:     "默认推流入口",
			IsActive:  false,
		})
	}

	util.Success(c, gin.H{
		"id":                room.ID,
		"name":              room.Name,
		"room_code":         room.RoomCode,
		"invite_code":       room.InviteCode,
		"livekit_room_name": room.LiveKitRoomName,
		"ingresses":         ingressList,
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

	util.Success(c, RoomResponse{
		ID:              room.ID,
		Name:            room.Name,
		RoomCode:        room.RoomCode,
		InviteCode:      room.InviteCode,
		OwnerID:         room.OwnerID,
		LiveKitRoomName: room.LiveKitRoomName,
		Members:         members,
		Ingresses:       ingressList,
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
