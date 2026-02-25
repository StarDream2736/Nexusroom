package ws

import (
	"log"
	"sync"
	"time"

	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
)

// Hub 管理所有 WebSocket 连接
type Hub struct {
	Clients    map[uint64]*Client // userID -> Client
	Broadcast  chan *BroadcastMessage
	Register   chan *Client
	Unregister chan *Client

	mu sync.RWMutex

	// 依赖
	msgRepo  *repository.MessageRepository
	roomRepo *repository.RoomRepository
	userRepo *repository.UserRepository
}

type BroadcastMessage struct {
	RoomID        uint64
	Event         MessageType
	Payload       interface{}
	ExcludeUserID uint64 // 0 表示不排除
}

func NewHub(msgRepo *repository.MessageRepository, roomRepo *repository.RoomRepository, userRepo *repository.UserRepository) *Hub {
	return &Hub{
		Clients:    make(map[uint64]*Client),
		Broadcast:  make(chan *BroadcastMessage),
		Register:   make(chan *Client),
		Unregister: make(chan *Client),
		msgRepo:    msgRepo,
		roomRepo:   roomRepo,
		userRepo:   userRepo,
	}
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.Register:
			h.mu.Lock()
			h.Clients[client.UserID] = client
			h.mu.Unlock()

			// 发送连接成功事件
			client.SendEvent(EventConnected, ConnectedPayload{
				UserID:        client.UserID,
				ServerVersion: "1.3.1",
			})

			log.Printf("User %d connected", client.UserID)

		case client := <-h.Unregister:
			// 收集需要通知的房间，在释放写锁后再广播，
			// 避免在持有 mu.Lock 的同时调用 BroadcastToRoom（发送到 h.Broadcast channel），
			// 因为 Hub.Run() 是唯一读取 h.Broadcast 的 goroutine，会导致自死锁。
			var roomsToNotify []uint64

			h.mu.Lock()
			// 只有当前 map 中存储的是同一个 client 指针时才删除
			// 防止用户快速重连时，旧连接的 Unregister 误删新连接
			if existing, ok := h.Clients[client.UserID]; ok && existing == client {
				roomsToNotify = client.GetRooms()
				delete(h.Clients, client.UserID)
			}
			// 始终关闭该 client 的 Send channel（使用 sync.Once 防止重复关闭）
			client.closeSend()
			h.mu.Unlock()

			// 释放写锁后再广播「成员离开」事件
			// 注意：直接调用 broadcastToRoom（小写，内部获取读锁），
			// 而非 BroadcastToRoom（大写，通过 channel 发送，会导致自死锁）
			for _, roomID := range roomsToNotify {
				h.broadcastToRoom(roomID, EventRoomMemberLeave, RoomMemberLeavePayload{
					UserID: client.UserID,
				}, client.UserID)
			}

			log.Printf("User %d disconnected", client.UserID)

		case msg := <-h.Broadcast:
			h.broadcastToRoom(msg.RoomID, msg.Event, msg.Payload, msg.ExcludeUserID)
		}
	}
}

// BroadcastToRoom 向房间广播消息
func (h *Hub) BroadcastToRoom(roomID uint64, event MessageType, payload interface{}, excludeUserID uint64) {
	h.Broadcast <- &BroadcastMessage{
		RoomID:        roomID,
		Event:         event,
		Payload:       payload,
		ExcludeUserID: excludeUserID,
	}
}

func (h *Hub) broadcastToRoom(roomID uint64, event MessageType, payload interface{}, excludeUserID uint64) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for userID, client := range h.Clients {
		if userID == excludeUserID {
			continue
		}

		if client.IsInRoom(roomID) {
			client.SendEvent(event, payload)
		}
	}
}

// GetOnlineUsersInRoom 获取房间在线用户
func (h *Hub) GetOnlineUsersInRoom(roomID uint64) []uint64 {
	h.mu.RLock()
	defer h.mu.RUnlock()

	var users []uint64
	for userID, client := range h.Clients {
		if client.IsInRoom(roomID) {
			users = append(users, userID)
		}
	}
	return users
}

// IsUserOnline 检查用户是否在线
func (h *Hub) IsUserOnline(userID uint64) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()

	_, ok := h.Clients[userID]
	return ok
}

// OnlineCount 返回当前在线用户数（线程安全）
func (h *Hub) OnlineCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.Clients)
}

// SendToUser 发送消息给指定用户
func (h *Hub) SendToUser(userID uint64, event MessageType, payload interface{}) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	if client, ok := h.Clients[userID]; ok {
		client.SendEvent(event, payload)
	}
}

// HandleChatSend 处理聊天消息发送
func (h *Hub) HandleChatSend(client *Client, payload ChatSendPayload) {
	log.Printf("[Chat] User %d sending to room %d, isInRoom=%v",
		client.UserID, payload.RoomID, client.IsInRoom(payload.RoomID))

	// 检查用户是否在房间中
	if !client.IsInRoom(payload.RoomID) {
		log.Printf("User %d tried to send chat to room %d but is not in room", client.UserID, payload.RoomID)
		client.SendEvent(EventChatError, ChatErrorPayload{
			RoomID: payload.RoomID,
			Reason: "not_in_room",
		})
		return
	}

	// 检查用户是否是房间成员
	if !h.roomRepo.IsMember(payload.RoomID, client.UserID) {
		return
	}

	// 保存消息到数据库
	var meta *model.JSON
	if payload.Meta != nil {
		m := model.JSON(*payload.Meta)
		meta = &m
	}

	msg := &model.Message{
		RoomID:    payload.RoomID,
		SenderID:  client.UserID,
		Type:      payload.Type,
		Content:   payload.Content,
		Meta:      meta,
		CreatedAt: time.Now(),
	}

	if err := h.msgRepo.Create(msg); err != nil {
		log.Printf("Failed to save message: %v", err)
		return
	}

	// 获取发送者信息
	user, err := h.userRepo.FindByID(client.UserID)
	if err != nil {
		log.Printf("Failed to fetch user info: %v", err)
		return
	}

	sender := SenderInfo{
		ID:        client.UserID,
		Nickname:  user.Nickname,
		AvatarURL: user.AvatarURL,
	}

	// 广播消息给房间所有成员
	chatMsg := ChatMessagePayload{
		ID:        msg.ID,
		RoomID:    msg.RoomID,
		SenderID:  msg.SenderID,
		Type:      msg.Type,
		Content:   msg.Content,
		Meta:      payload.Meta,
		CreatedAt: msg.CreatedAt,
		Sender:    sender,
	}

	h.BroadcastToRoom(payload.RoomID, EventChatMessage, chatMsg, 0)
	log.Printf("[Chat] Message %d broadcast to room %d", msg.ID, payload.RoomID)
}

// KickUserFromRoom 将用户踢出房间
func (h *Hub) KickUserFromRoom(roomID, userID uint64, reason string) {
	// 发送踢出事件给被踢用户
	h.SendToUser(userID, EventRoomKicked, RoomKickedPayload{
		Reason: reason,
	})

	// 广播成员离开事件
	h.BroadcastToRoom(roomID, EventRoomMemberLeave, RoomMemberLeavePayload{
		UserID: userID,
	}, userID)

	// 如果用户在线，将其从房间中移除
	h.mu.RLock()
	client, ok := h.Clients[userID]
	h.mu.RUnlock()

	if ok {
		client.LeaveRoom(roomID)
	}
}
