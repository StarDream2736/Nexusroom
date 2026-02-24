package handler

import (
	"errors"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/ws"
	"nexusroom-server/pkg/util"
)

type FriendHandler struct {
	friendRepo *repository.FriendshipRepository
	userRepo   *repository.UserRepository
	roomRepo   *repository.RoomRepository
	hub        *ws.Hub
}

func NewFriendHandler(
	friendRepo *repository.FriendshipRepository,
	userRepo *repository.UserRepository,
	roomRepo *repository.RoomRepository,
	hub *ws.Hub,
) *FriendHandler {
	return &FriendHandler{
		friendRepo: friendRepo,
		userRepo:   userRepo,
		roomRepo:   roomRepo,
		hub:        hub,
	}
}

type SendFriendRequestReq struct {
	DisplayID string `json:"display_id" binding:"required"`
}

type HandleFriendRequestReq struct {
	Action string `json:"action" binding:"required,oneof=accept reject"` // accept / reject
}

// SendRequest POST /friends/request — 发送好友申请
func (h *FriendHandler) SendRequest(c *gin.Context) {
	var req SendFriendRequestReq
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}

	userID := c.GetUint64("userID")

	// 查找目标用户
	target, err := h.userRepo.FindByDisplayID(req.DisplayID)
	if err != nil {
		util.Error(c, 40401, "用户不存在")
		return
	}

	if target.ID == userID {
		util.Error(c, 40001, "不能添加自己为好友")
		return
	}

	// 检查是否已存在好友关系
	existing, err := h.friendRepo.FindByUsers(userID, target.ID)
	if err == nil && existing != nil {
		switch existing.Status {
		case "accepted":
			util.Error(c, 40901, "已是好友关系")
			return
		case "pending":
			util.Error(c, 40901, "已有待处理的好友申请")
			return
		case "rejected":
			// 被拒绝后允许重新申请：删除旧记录，重新创建
			_ = h.friendRepo.DeleteFriendship(userID, target.ID)
		}
	}

	friendship := &model.Friendship{
		RequesterID: userID,
		AddresseeID: target.ID,
		Status:      "pending",
	}
	if err := h.friendRepo.Create(friendship); err != nil {
		util.Error(c, 50001, "发送好友申请失败")
		return
	}

	// 通过 WebSocket 通知对方
	requester, _ := h.userRepo.FindByID(userID)
	nickname := ""
	if requester != nil {
		nickname = requester.Nickname
	}
	h.hub.SendToUser(target.ID, ws.EventFriendRequest, ws.FriendRequestPayload{
		FromUserID: userID,
		Nickname:   nickname,
	})

	util.Success(c, nil)
}

// HandleRequest PATCH /friends/request/:requestId — 接受/拒绝好友申请
// requestId = requester 的 user_id
func (h *FriendHandler) HandleRequest(c *gin.Context) {
	requesterID, err := strconv.ParseUint(c.Param("requestId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "请求ID格式错误")
		return
	}

	var req HandleFriendRequestReq
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败: action 必须为 accept 或 reject")
		return
	}

	userID := c.GetUint64("userID")

	// 查找好友申请
	friendship, err := h.friendRepo.FindByUsers(requesterID, userID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			util.Error(c, 40401, "好友申请不存在")
		} else {
			util.Error(c, 50001, "查询失败")
		}
		return
	}

	// 必须是收件人才能处理
	if friendship.AddresseeID != userID {
		util.Error(c, 40301, "无权处理此申请")
		return
	}

	if friendship.Status != "pending" {
		util.Error(c, 40001, "该申请已处理")
		return
	}

	status := "rejected"
	if req.Action == "accept" {
		status = "accepted"
	}

	if err := h.friendRepo.UpdateStatus(friendship.RequesterID, friendship.AddresseeID, status); err != nil {
		util.Error(c, 50001, "处理好友申请失败")
		return
	}

	// 如果接受，通知申请方
	if status == "accepted" {
		addressee, _ := h.userRepo.FindByID(userID)
		nickname := ""
		if addressee != nil {
			nickname = addressee.Nickname
		}
		h.hub.SendToUser(requesterID, ws.EventFriendAccepted, ws.FriendAcceptedPayload{
			UserID:   userID,
			Nickname: nickname,
		})
	}

	util.Success(c, nil)
}

// ListFriends GET /friends — 获取好友列表
func (h *FriendHandler) ListFriends(c *gin.Context) {
	userID := c.GetUint64("userID")

	friends, err := h.friendRepo.ListFriends(userID)
	if err != nil {
		util.Error(c, 50001, "获取好友列表失败")
		return
	}

	list := make([]gin.H, 0, len(friends))
	for _, f := range friends {
		list = append(list, gin.H{
			"user_id":         f.ID,
			"user_display_id": f.UserDisplayID,
			"nickname":        f.Nickname,
			"avatar_url":      f.AvatarURL,
			"is_online":       h.hub.IsUserOnline(f.ID),
		})
	}

	util.Success(c, list)
}

// ListPendingRequests GET /friends/pending — 获取待处理好友申请
func (h *FriendHandler) ListPendingRequests(c *gin.Context) {
	userID := c.GetUint64("userID")

	requests, err := h.friendRepo.ListPendingRequests(userID)
	if err != nil {
		util.Error(c, 50001, "获取好友申请列表失败")
		return
	}

	list := make([]gin.H, 0, len(requests))
	for _, r := range requests {
		list = append(list, gin.H{
			"requester_id":         r.RequesterID,
			"requester_display_id": r.Requester.UserDisplayID,
			"requester_nickname":   r.Requester.Nickname,
			"requester_avatar_url": r.Requester.AvatarURL,
			"status":               r.Status,
			"created_at":           r.CreatedAt,
		})
	}

	util.Success(c, list)
}
