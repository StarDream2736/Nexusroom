package service

import (
	"time"

	"github.com/livekit/protocol/auth"
	lksdk "github.com/livekit/server-sdk-go"

	"nexusroom-server/internal/config"
)

type LiveKitService struct {
	client *lksdk.RoomServiceClient
}

func NewLiveKitService() *LiveKitService {
	cfg := config.GlobalConfig.LiveKit

	roomClient := lksdk.NewRoomServiceClient(cfg.URL, cfg.APIKey, cfg.APISecret)

	return &LiveKitService{
		client: roomClient,
	}
}

// GenerateToken 生成 LiveKit Access Token（语音房间）
func (s *LiveKitService) GenerateToken(roomName, userID, nickname string) (string, error) {
	cfg := config.GlobalConfig.LiveKit

	at := auth.NewAccessToken(cfg.APIKey, cfg.APISecret)
	grant := &auth.VideoGrant{
		RoomJoin:     true,
		Room:         roomName,
		CanPublish:   boolPtr(true),
		CanSubscribe: boolPtr(true),
	}

	at.AddGrant(grant)
	at.SetIdentity(userID)
	at.SetName(nickname)
	at.SetValidFor(24 * time.Hour) // 24小时有效期

	token, err := at.ToJWT()

	return token, err
}

func boolPtr(b bool) *bool {
	return &b
}
