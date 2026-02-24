package ws

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 512 * 1024 // 512KB
)

// Client 表示一个 WebSocket 连接
type Client struct {
	Hub      *Hub
	Conn     *websocket.Conn
	Send     chan []byte
	UserID   uint64
	Username string
	Role     string

	// 用户加入的房间
	rooms     map[uint64]bool
	mu        sync.RWMutex
	closeOnce sync.Once
}

func NewClient(hub *Hub, conn *websocket.Conn, userID uint64, username, role string) *Client {
	return &Client{
		Hub:      hub,
		Conn:     conn,
		Send:     make(chan []byte, 256),
		UserID:   userID,
		Username: username,
		Role:     role,
		rooms:    make(map[uint64]bool),
	}
}

// JoinRoom 加入房间
func (c *Client) JoinRoom(roomID uint64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.rooms[roomID] = true
}

// LeaveRoom 离开房间
func (c *Client) LeaveRoom(roomID uint64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.rooms, roomID)
}

// IsInRoom 检查是否在房间中
func (c *Client) IsInRoom(roomID uint64) bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.rooms[roomID]
}

// GetRooms 获取用户加入的所有房间
func (c *Client) GetRooms() []uint64 {
	c.mu.RLock()
	defer c.mu.RUnlock()

	rooms := make([]uint64, 0, len(c.rooms))
	for roomID := range c.rooms {
		rooms = append(rooms, roomID)
	}
	return rooms
}

// ReadPump 从 WebSocket 读取消息
func (c *Client) ReadPump() {
	defer func() {
		c.Hub.Unregister <- c
		c.Conn.Close()
	}()

	c.Conn.SetReadLimit(maxMessageSize)
	c.Conn.SetReadDeadline(time.Now().Add(pongWait))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			break
		}

		c.HandleMessage(message)
	}
}

// WritePump 向 WebSocket 写入消息
func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			c.Conn.WriteMessage(websocket.TextMessage, message)

		case <-ticker.C:
			c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// HandleMessage 处理收到的消息
func (c *Client) HandleMessage(data []byte) {
	var envelope Envelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		log.Printf("Failed to unmarshal message: %v", err)
		return
	}

	log.Printf("[WS] User %d event=%s room_id=%d", c.UserID, envelope.Event, envelope.RoomID)

	// 路由到对应的处理器
	switch envelope.Event {
	case EventHeartbeat:
		c.handleHeartbeat()
	case EventRoomJoin:
		c.handleRoomJoin(envelope)
	case EventRoomLeave:
		c.handleRoomLeave(envelope)
	case EventChatSend:
		c.handleChatSend(envelope)
	case EventVoiceMute:
		c.handleVoiceMute(envelope)
	default:
		log.Printf("Unknown event type: %s", envelope.Event)
	}
}

func (c *Client) handleHeartbeat() {
	response := Envelope{
		Event:     EventPong,
		Payload:   json.RawMessage("{}"),
		Timestamp: time.Now(),
	}
	data, _ := json.Marshal(response)
	c.Send <- data
}

func (c *Client) handleRoomJoin(env Envelope) {
	var p RoomJoinPayload
	if err := json.Unmarshal(env.Payload, &p); err != nil {
		log.Printf("[WS] User %d room.join unmarshal error: %v", c.UserID, err)
		return
	}

	// 优先从信封顶层读 room_id，兼容 payload 内的 room_id
	roomID := env.RoomID
	if roomID == 0 {
		roomID = p.RoomID
	}

	// 校验用户是否是房间成员
	if !c.Hub.roomRepo.IsMember(roomID, c.UserID) {
		log.Printf("[WS] User %d room.join(%d) REJECTED — not a member", c.UserID, roomID)
		return
	}

	c.JoinRoom(roomID)
	log.Printf("[WS] User %d joined room %d, rooms=%v", c.UserID, roomID, c.GetRooms())

	// 获取用户真实昵称和头像
	nickname := c.Username
	avatarURL := ""
	if user, err := c.Hub.userRepo.FindByID(c.UserID); err == nil {
		nickname = user.Nickname
		avatarURL = user.AvatarURL
	}

	// 广播成员加入事件
	c.Hub.BroadcastToRoom(roomID, EventRoomMemberJoin, RoomMemberJoinPayload{
		UserID:    c.UserID,
		Nickname:  nickname,
		AvatarURL: avatarURL,
	}, c.UserID)
}

func (c *Client) handleRoomLeave(env Envelope) {
	var p RoomLeavePayload
	if err := json.Unmarshal(env.Payload, &p); err != nil {
		return
	}

	roomID := env.RoomID
	if roomID == 0 {
		roomID = p.RoomID
	}

	c.LeaveRoom(roomID)

	// 广播成员离开事件
	c.Hub.BroadcastToRoom(roomID, EventRoomMemberLeave, RoomMemberLeavePayload{
		UserID: c.UserID,
	}, c.UserID)
}

func (c *Client) handleChatSend(env Envelope) {
	var p ChatSendPayload
	if err := json.Unmarshal(env.Payload, &p); err != nil {
		log.Printf("[WS] User %d chat.send unmarshal error: %v", c.UserID, err)
		return
	}

	// 优先从信封顶层读 room_id
	if env.RoomID != 0 {
		p.RoomID = env.RoomID
	}
	log.Printf("[WS] User %d chat.send -> room %d, content=%q", c.UserID, p.RoomID, p.Content)

	// 调用 Hub 处理消息发送
	c.Hub.HandleChatSend(c, p)
}

func (c *Client) handleVoiceMute(env Envelope) {
	var p VoiceMutePayload
	if err := json.Unmarshal(env.Payload, &p); err != nil {
		return
	}

	roomID := env.RoomID
	if roomID == 0 {
		roomID = p.RoomID
	}

	// 广播语音状态变更
	c.Hub.BroadcastToRoom(roomID, EventVoiceStateUpdate, VoiceStateUpdatePayload{
		UserID: c.UserID,
		Muted:  p.Muted,
	}, 0) // 0 表示广播给所有人，包括自己
}

// closeSend 安全关闭 Send channel，防止 double-close panic
func (c *Client) closeSend() {
	c.closeOnce.Do(func() {
		close(c.Send)
	})
}

// SendEvent 发送事件给客户端
func (c *Client) SendEvent(event MessageType, payload interface{}) {
	envelope := Envelope{
		Event:     event,
		Payload:   mustMarshal(payload),
		Timestamp: time.Now(),
	}
	data, _ := json.Marshal(envelope)

	select {
	case c.Send <- data:
	default:
		// 发送缓冲区满，安全关闭连接
		c.closeSend()
	}
}

func mustMarshal(v interface{}) json.RawMessage {
	data, _ := json.Marshal(v)
	return data
}
