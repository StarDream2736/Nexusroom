package handler

import (
	"net/http"
	"strconv"
	
	"github.com/gin-gonic/gin"
	
	"nexusroom-server/internal/repository"
	"nexusroom-server/pkg/util"
)

type MessageHandler struct {
	msgRepo  *repository.MessageRepository
	roomRepo *repository.RoomRepository
}

func NewMessageHandler(msgRepo *repository.MessageRepository, roomRepo *repository.RoomRepository) *MessageHandler {
	return &MessageHandler{
		msgRepo:  msgRepo,
		roomRepo: roomRepo,
	}
}

func (h *MessageHandler) GetMessages(c *gin.Context) {
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
	
	// 解析分页参数
	afterID, _ := strconv.ParseUint(c.Query("after_id"), 10, 64)
	beforeID, _ := strconv.ParseUint(c.Query("before_id"), 10, 64)
	limit, _ := strconv.Atoi(c.Query("limit"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	
	var messages interface{}
	var getErr error
	
	if afterID > 0 {
		// 增量同步：获取 after_id 之后的消息
		msgs, err := h.msgRepo.GetMessagesAfter(roomID, afterID, limit)
		messages = msgs
		getErr = err
	} else if beforeID > 0 {
		// 加载更早消息
		msgs, err := h.msgRepo.GetMessagesBefore(roomID, beforeID, limit)
		messages = msgs
		getErr = err
	} else {
		// 获取最新消息
		msgs, err := h.msgRepo.GetLatestMessages(roomID, limit)
		messages = msgs
		getErr = err
	}
	
	if getErr != nil {
		util.Error(c, 50001, "获取消息失败")
		return
	}
	
	util.Success(c, messages)
}
