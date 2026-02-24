package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/wg"
	"nexusroom-server/internal/ws"
	"nexusroom-server/pkg/util"
)

type VLANHandler struct {
	roomRepo    *repository.RoomRepository
	userRepo    *repository.UserRepository
	coordinator *wg.Coordinator
	hub         *ws.Hub
}

func NewVLANHandler(
	roomRepo *repository.RoomRepository,
	userRepo *repository.UserRepository,
	coordinator *wg.Coordinator,
	hub *ws.Hub,
) *VLANHandler {
	return &VLANHandler{
		roomRepo:    roomRepo,
		userRepo:    userRepo,
		coordinator: coordinator,
		hub:         hub,
	}
}

type VLANJoinRequest struct {
	PublicKey string `json:"public_key" binding:"required"`
}

// Join POST /rooms/:roomId/vlan/join — 加入 VLAN
func (h *VLANHandler) Join(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	// 检查是否是房间成员
	if !h.roomRepo.IsMember(roomID, userID) {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "不是房间成员")
		return
	}

	var req VLANJoinRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败：需要 public_key")
		return
	}

	// 注册 Peer 并分配 IP
	peer, err := h.coordinator.RegisterPeer(roomID, userID, req.PublicKey)
	if err != nil {
		util.Error(c, 50001, "VLAN 加入失败: "+err.Error())
		return
	}

	// 获取服务器配置
	serverCfg := h.coordinator.GetServerConfig()

	// 获取房间内所有 Peers
	peers, _ := h.coordinator.GetPeers(roomID)
	peerList := make([]gin.H, 0, len(peers))
	for _, p := range peers {
		if p.UserID == userID {
			continue // 排除自己
		}
		nickname := ""
		if p.User.ID != 0 {
			nickname = p.User.Nickname
		}
		peerList = append(peerList, gin.H{
			"user_id":     p.UserID,
			"nickname":    nickname,
			"public_key":  p.PublicKey,
			"allowed_ips": p.AssignedIP,
		})
	}

	// 通过 WebSocket 广播 vlan.peer_update 给房间
	user, _ := h.userRepo.FindByID(userID)
	nickname := ""
	if user != nil {
		nickname = user.Nickname
	}
	h.hub.BroadcastToRoom(roomID, ws.EventVlanPeerUpdate, ws.VlanPeerUpdatePayload{
		RoomID: roomID,
		Action: "join",
		PeerInfo: ws.PeerInfo{
			UserID:     userID,
			Nickname:   nickname,
			PublicKey:  req.PublicKey,
			AssignedIP: peer.AssignedIP,
		},
	}, userID)

	util.Success(c, gin.H{
		"assigned_ip":       peer.AssignedIP,
		"server_public_key": serverCfg.ServerPublicKey,
		"server_endpoint":   serverCfg.ServerEndpoint,
		"dns":               serverCfg.DNS,
		"peers":             peerList,
	})
}

// Leave DELETE /rooms/:roomId/vlan/leave — 离开 VLAN
func (h *VLANHandler) Leave(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	if err := h.coordinator.UnregisterPeer(roomID, userID); err != nil {
		util.Error(c, 50001, "VLAN 离开失败")
		return
	}

	// 广播离开事件
	h.hub.BroadcastToRoom(roomID, ws.EventVlanPeerUpdate, ws.VlanPeerUpdatePayload{
		RoomID: roomID,
		Action: "leave",
		PeerInfo: ws.PeerInfo{
			UserID: userID,
		},
	}, userID)

	util.Success(c, nil)
}

// Peers GET /rooms/:roomId/vlan/peers — 获取 VLAN Peer 列表
func (h *VLANHandler) Peers(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	if !h.roomRepo.IsMember(roomID, userID) {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "不是房间成员")
		return
	}

	peers, err := h.coordinator.GetPeers(roomID)
	if err != nil {
		util.Error(c, 50001, "获取 Peer 列表失败")
		return
	}

	result := make([]gin.H, 0, len(peers))
	for _, p := range peers {
		nickname := ""
		if p.User.ID != 0 {
			nickname = p.User.Nickname
		}
		result = append(result, gin.H{
			"user_id":        p.UserID,
			"nickname":       nickname,
			"public_key":     p.PublicKey,
			"assigned_ip":    p.AssignedIP,
			"last_handshake": p.LastHandshakeAt,
		})
	}

	util.Success(c, result)
}
