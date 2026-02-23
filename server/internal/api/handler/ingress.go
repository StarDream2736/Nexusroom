package handler

import (
	"net/http"
	"strconv"
	
	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	
	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/service"
	"nexusroom-server/pkg/util"
)

type IngressHandler struct {
	roomRepo    *repository.RoomRepository
	ingressRepo *repository.IngressRepository
	livekitSvc  *service.LiveKitService
}

func NewIngressHandler(roomRepo *repository.RoomRepository, ingressRepo *repository.IngressRepository, 
	livekitSvc *service.LiveKitService) *IngressHandler {
	return &IngressHandler{
		roomRepo:    roomRepo,
		ingressRepo: ingressRepo,
		livekitSvc:  livekitSvc,
	}
}

type CreateIngressRequest struct {
	Label string `json:"label" validate:"required,min=1,max=64"`
}

func (h *IngressHandler) Create(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}
	
	var req CreateIngressRequest
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
	
	// 获取房间信息
	room, err := h.roomRepo.FindByID(roomID)
	if err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}
	
	// 检查权限（房主或超管）
	if room.OwnerID != userID && c.GetString("role") != "super_admin" {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权创建推流入口")
		return
	}
	
	// 调用 LiveKit API 创建 Ingress
	ingressInfo, err := h.livekitSvc.CreateIngress(room.LiveKitRoomName, req.Label)
	if err != nil {
		util.Error(c, 50001, "创建推流入口失败")
		return
	}
	
	// 保存到数据库
	rmIngress := &model.RoomIngress{
		RoomID:    roomID,
		IngressID: ingressInfo.IngressId,
		StreamKey: ingressInfo.StreamKey,
		RTMPURL:   ingressInfo.Url,
		Label:     req.Label,
		CreatedBy: userID,
	}
	
	if err := h.ingressRepo.Create(rmIngress); err != nil {
		// 尝试删除 LiveKit 端的 Ingress
		h.livekitSvc.DeleteIngress(ingressInfo.IngressId)
		util.Error(c, 50001, "保存推流入口失败")
		return
	}
	
	util.Success(c, gin.H{
		"id":         rmIngress.ID,
		"ingress_id": rmIngress.IngressID,
		"rtmp_url":   rmIngress.RTMPURL,
		"stream_key": rmIngress.StreamKey,
		"label":      rmIngress.Label,
	})
}

func (h *IngressHandler) List(c *gin.Context) {
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
	
	ingresses, err := h.ingressRepo.ListByRoom(roomID)
	if err != nil {
		util.Error(c, 50001, "获取推流入口失败")
		return
	}
	
	result := make([]gin.H, 0, len(ingresses))
	for _, ing := range ingresses {
		result = append(result, gin.H{
			"id":         ing.ID,
			"ingress_id": ing.IngressID,
			"rtmp_url":   ing.RTMPURL,
			"stream_key": ing.StreamKey,
			"label":      ing.Label,
			"is_active":  ing.IsActive,
		})
	}
	
	util.Success(c, result)
}

func (h *IngressHandler) Delete(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}
	
	ingressID, err := strconv.ParseUint(c.Param("ingressId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "Ingress ID格式错误")
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
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权删除推流入口")
		return
	}
	
	// 获取 Ingress 信息
	ingress, err := h.ingressRepo.FindByID(ingressID)
	if err != nil {
		util.Error(c, 40401, "推流入口不存在")
		return
	}
	
	// 删除 LiveKit 端的 Ingress
	if err := h.livekitSvc.DeleteIngress(ingress.IngressID); err != nil {
		// 继续删除数据库记录
	}
	
	// 删除数据库记录
	if err := h.ingressRepo.Delete(ingressID); err != nil {
		util.Error(c, 50001, "删除推流入口失败")
		return
	}
	
	util.Success(c, nil)
}
