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
	rooms map[uint64]bool
	mu    sync.RWMutex
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
	
	// 路由到对应的处理器
	switch envelope.Event {
	case EventHeartbeat:
		c.handleHeartbeat()
	case EventRoomJoin:
		c.handleRoomJoin(envelope.Payload)
	case EventRoomLeave:
		c.handleRoomLeave(envelope.Payload)
	case EventChatSend:
		c.handleChatSend(envelope.Payload)
	case EventVoiceMute:
		c.handleVoiceMute(envelope.Payload)
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

func (c *Client) handleRoomJoin(payload json.RawMessage) {
	var p RoomJoinPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return
	}
	
	c.JoinRoom(p.RoomID)
	
	// 广播成员加入事件
	c.Hub.BroadcastToRoom(p.RoomID, EventRoomMemberJoin, RoomMemberJoinPayload{
		UserID:   c.UserID,
		Nickname: c.Username,
	}, c.UserID)
}

func (c *Client) handleRoomLeave(payload json.RawMessage) {
	var p RoomLeavePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return
	}
	
	c.LeaveRoom(p.RoomID)
	
	// 广播成员离开事件
	c.Hub.BroadcastToRoom(p.RoomID, EventRoomMemberLeave, RoomMemberLeavePayload{
		UserID: c.UserID,
	}, c.UserID)
}

func (c *Client) handleChatSend(payload json.RawMessage) {
	var p ChatSendPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return
	}
	
	// 调用 Hub 处理消息发送
	c.Hub.HandleChatSend(c, p)
}

func (c *Client) handleVoiceMute(payload json.RawMessage) {
	var p VoiceMutePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return
	}
	
	// 广播语音状态变更
	c.Hub.BroadcastToRoom(p.RoomID, EventVoiceStateUpdate, VoiceStateUpdatePayload{
		UserID: c.UserID,
		Muted:  p.Muted,
	}, 0) // 0 表示广播给所有人，包括自己
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
		// 发送缓冲区满，关闭连接
		close(c.Send)
	}
}

func mustMarshal(v interface{}) json.RawMessage {
	data, _ := json.Marshal(v)
	return data
}
