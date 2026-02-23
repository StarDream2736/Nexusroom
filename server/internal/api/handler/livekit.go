package handler

import (
	"net/http"
	"strconv"
	
	"github.com/gin-gonic/gin"
	
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/service"
	"nexusroom-server/pkg/util"
)

type LiveKitHandler struct {
	roomRepo   *repository.RoomRepository
	livekitSvc *service.LiveKitService
}

func NewLiveKitHandler(roomRepo *repository.RoomRepository, livekitSvc *service.LiveKitService) *LiveKitHandler {
	return &LiveKitHandler{
		roomRepo:   roomRepo,
		livekitSvc: livekitSvc,
	}
}

func (h *LiveKitHandler) GenerateToken(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}
	
	userID := c.GetUint64("userID")
	username := c.GetString("username")
	
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
	
	token, err := h.livekitSvc.GenerateToken(room.LiveKitRoomName, strconv.FormatUint(userID, 10), username)
	if err != nil {
		util.Error(c, 50001, "生成 Token 失败")
		return
	}
	
	util.Success(c, gin.H{
		"token":    token,
		"url":      "ws://your-server-ip:7880", // 客户端连接 LiveKit 的地址
		"room_name": room.LiveKitRoomName,
	})
}
