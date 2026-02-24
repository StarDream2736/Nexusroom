package handler

import (
	"nexusroom-server/internal/config"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/ws"
	"nexusroom-server/pkg/util"
	"time"

	"github.com/gin-gonic/gin"

	"nexusroom-server/internal/model"
)

type WebhookHandler struct {
	msgRepo  *repository.MessageRepository
	roomRepo *repository.RoomRepository
	hub      *ws.Hub
	cfg      *config.Config
}

func NewWebhookHandler(
	msgRepo *repository.MessageRepository,
	roomRepo *repository.RoomRepository,
	hub *ws.Hub,
	cfg *config.Config,
) *WebhookHandler {
	return &WebhookHandler{
		msgRepo:  msgRepo,
		roomRepo: roomRepo,
		hub:      hub,
		cfg:      cfg,
	}
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

// QQWebhook POST /webhook/qq — QQ 机器人消息推送
func (h *WebhookHandler) QQWebhook(c *gin.Context) {
	// 校验 Webhook Secret
	authHeader := c.GetHeader("Authorization")
	expectedToken := h.cfg.Auth.AdminToken // 复用 admin_token 作为 webhook secret
	if expectedToken == "" {
		// admin_token 未配置时拒绝所有 webhook 请求
		util.ErrorWithStatus(c, 403, 40301, "Webhook 未配置认证密钥，拒绝访问")
		return
	}
	if authHeader != "Bearer "+expectedToken {
		util.ErrorWithStatus(c, 401, 40101, "Webhook 认证失败")
		return
	}

	var req QQWebhookRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}

	// 校验房间存在
	_, err := h.roomRepo.FindByID(req.RoomID)
	if err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 构造系统消息，标注来源为 QQ
	content := "[QQ] " + req.Sender.Nickname + ": " + req.Content

	msg := &model.Message{
		RoomID:    req.RoomID,
		SenderID:  0, // 系统消息，sender_id 为 0
		Type:      "system",
		Content:   content,
		CreatedAt: time.Now(),
	}

	if err := h.msgRepo.Create(msg); err != nil {
		util.Error(c, 50001, "保存消息失败")
		return
	}

	// 通过 WebSocket 广播到房间
	chatMsg := ws.ChatMessagePayload{
		ID:        msg.ID,
		RoomID:    msg.RoomID,
		SenderID:  0,
		Type:      "system",
		Content:   content,
		CreatedAt: msg.CreatedAt,
		Sender: ws.SenderInfo{
			ID:       0,
			Nickname: "[QQ] " + req.Sender.Nickname,
		},
	}

	h.hub.BroadcastToRoom(req.RoomID, ws.EventChatMessage, chatMsg, 0)

	util.Success(c, nil)
}
