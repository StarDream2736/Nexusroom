package handler

import (
	"time"

	"github.com/gin-gonic/gin"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/ws"
	"nexusroom-server/pkg/util"
)

type WebhookHandler struct {
	msgRepo  *repository.MessageRepository
	roomRepo *repository.RoomRepository
	hub      *ws.Hub
	cfg      *config.Config
}

func NewWebhookHandler(msgRepo *repository.MessageRepository, roomRepo *repository.RoomRepository, hub *ws.Hub, cfg *config.Config) *WebhookHandler {
	return &WebhookHandler{msgRepo: msgRepo, roomRepo: roomRepo, hub: hub, cfg: cfg}
}

type QQWebhookRequest struct {
	RoomID      uint64   `json:"room_id" binding:"required"`
	Sender      QQSender `json:"sender" binding:"required"`
	MessageType string   `json:"message_type" binding:"required"`
	Content     string   `json:"content" binding:"required"`
}

type QQSender struct {
	UserID   string `json:"user_id"`
	Nickname string `json:"nickname"`
}

func (h *WebhookHandler) QQWebhook(c *gin.Context) {
	expectedToken := h.cfg.Auth.AdminToken
	if expectedToken == "" {
		util.ErrorWithStatus(c, 403, 40301, "Webhook 未配置认证密钥，拒绝访问")
		return
	}
	if c.GetHeader("Authorization") != "Bearer "+expectedToken {
		util.ErrorWithStatus(c, 401, 40101, "Webhook 认证失败")
		return
	}
	var request QQWebhookRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}
	if _, err := h.roomRepo.FindByID(request.RoomID); err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}
	content := "[QQ] " + request.Sender.Nickname + ": " + request.Content
	message := &model.Message{
		RoomID: request.RoomID, SenderID: 0, Type: "system", Content: content, CreatedAt: time.Now(),
	}
	if err := h.msgRepo.Create(message); err != nil {
		util.Error(c, 50001, "保存消息失败")
		return
	}
	h.hub.BroadcastToRoom(request.RoomID, ws.EventChatMessage, ws.ChatMessagePayload{
		ID: message.ID, RoomID: message.RoomID, SenderID: 0, Type: "system", Content: content,
		CreatedAt: message.CreatedAt, Sender: ws.SenderInfo{ID: 0, Nickname: "[QQ] " + request.Sender.Nickname},
	}, 0)
	util.Success(c, nil)
}
