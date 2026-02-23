package ws

import (
	"encoding/json"
	"time"
)

// MessageType WebSocket 消息类型
type MessageType string

const (
	// 客户端 -> 服务端
	EventHeartbeat       MessageType = "heartbeat"
	EventRoomJoin        MessageType = "room.join"
	EventRoomLeave       MessageType = "room.leave"
	EventChatSend        MessageType = "chat.send"
	EventVoiceMute       MessageType = "voice.mute"
	EventVlanPeerUpdate  MessageType = "vlan.peer_update"
	
	// 服务端 -> 客户端
	EventConnected       MessageType = "connected"
	EventPong            MessageType = "pong"
	EventChatMessage     MessageType = "chat.message"
	EventRoomMemberJoin  MessageType = "room.member_join"
	EventRoomMemberLeave MessageType = "room.member_leave"
	EventRoomKicked      MessageType = "room.kicked"
	EventVoiceStateUpdate MessageType = "voice.state_update"
	EventFriendRequest   MessageType = "friend.request"
	EventFriendAccepted  MessageType = "friend.accepted"
)

// Envelope WebSocket 消息信封
type Envelope struct {
	Event     MessageType     `json:"event"`
	RoomID    uint64          `json:"room_id,omitempty"`
	Payload   json.RawMessage `json:"payload"`
	Timestamp time.Time       `json:"timestamp"`
}

// Payload 定义
type HeartbeatPayload struct{}

type RoomJoinPayload struct {
	RoomID uint64 `json:"room_id"`
}

type RoomLeavePayload struct {
	RoomID uint64 `json:"room_id"`
}

type ChatSendPayload struct {
	RoomID  uint64          `json:"room_id"`
	Type    string          `json:"type"`    // text / image / file
	Content string          `json:"content"`
	Meta    *map[string]interface{} `json:"meta,omitempty"`
}

type VoiceMutePayload struct {
	RoomID uint64 `json:"room_id"`
	Muted  bool   `json:"muted"`
}

type VlanPeerUpdatePayload struct {
	RoomID   uint64 `json:"room_id"`
	Action   string `json:"action"`   // join / leave
	PeerInfo PeerInfo `json:"peer_info"`
}

type PeerInfo struct {
	UserID    uint64 `json:"user_id"`
	Nickname  string `json:"nickname"`
	PublicKey string `json:"public_key"`
	AssignedIP string `json:"assigned_ip"`
}

// 服务端发送的消息
type ConnectedPayload struct {
	UserID        uint64 `json:"user_id"`
	ServerVersion string `json:"server_version"`
}

type ChatMessagePayload struct {
	ID        uint64    `json:"id"`
	RoomID    uint64    `json:"room_id"`
	SenderID  uint64    `json:"sender_id"`
	Type      string    `json:"type"`
	Content   string    `json:"content"`
	Meta      *map[string]interface{} `json:"meta,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	Sender    SenderInfo `json:"sender"`
}

type SenderInfo struct {
	ID       uint64 `json:"id"`
	Nickname string `json:"nickname"`
	AvatarURL string `json:"avatar_url"`
}

type RoomMemberJoinPayload struct {
	UserID    uint64 `json:"user_id"`
	Nickname  string `json:"nickname"`
	AvatarURL string `json:"avatar_url"`
}

type RoomMemberLeavePayload struct {
	UserID uint64 `json:"user_id"`
}

type RoomKickedPayload struct {
	Reason string `json:"reason"`
}

type VoiceStateUpdatePayload struct {
	UserID   uint64 `json:"user_id"`
	Muted    bool   `json:"muted"`
	Speaking bool   `json:"speaking"`
}

type FriendRequestPayload struct {
	FromUserID uint64 `json:"from_user_id"`
	Nickname   string `json:"nickname"`
}

type FriendAcceptedPayload struct {
	UserID   uint64 `json:"user_id"`
	Nickname string `json:"nickname"`
}
