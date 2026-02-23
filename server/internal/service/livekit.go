package service

import (
	"context"
	"fmt"
	"math/rand"
	"time"
	
	"github.com/livekit/protocol/auth"
	"github.com/livekit/protocol/livekit"
	lksdk "github.com/livekit/server-sdk-go"
	
	"nexusroom-server/internal/config"
)

type LiveKitService struct {
	client  *lksdk.RoomServiceClient
	ingress *lksdk.IngressClient
}

func NewLiveKitService() *LiveKitService {
	cfg := config.GlobalConfig.LiveKit
	
	roomClient := lksdk.NewRoomServiceClient(cfg.URL, cfg.APIKey, cfg.APISecret)
	ingressClient := lksdk.NewIngressClient(cfg.URL, cfg.APIKey, cfg.APISecret)
	
	return &LiveKitService{
		client:  roomClient,
		ingress: ingressClient,
	}
}

// GenerateToken 生成 LiveKit Access Token
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
	at.SetValidFor(24 * 60 * 60) // 24小时有效期
	
	token, err := at.ToJWT()
	
	return token, err
}

// CreateIngress 创建 RTMP Ingress
func (s *LiveKitService) CreateIngress(roomName, label string) (*livekit.IngressInfo, error) {
	req := &livekit.CreateIngressRequest{
		InputType:           livekit.IngressInput_RTMP_INPUT,
		Name:                label,
		RoomName:            roomName,
		ParticipantIdentity: fmt.Sprintf("ingress_%s", generateRandomID()),
		ParticipantName:     label,
	}
	
	return s.ingress.CreateIngress(context.Background(), req)
}

// DeleteIngress 删除 Ingress
func (s *LiveKitService) DeleteIngress(ingressID string) error {
	_, err := s.ingress.DeleteIngress(context.Background(), &livekit.DeleteIngressRequest{
		IngressId: ingressID,
	})
	return err
}

// ListIngresses 列出房间的 Ingress
func (s *LiveKitService) ListIngresses(roomName string) ([]*livekit.IngressInfo, error) {
	res, err := s.ingress.ListIngress(context.Background(), &livekit.ListIngressRequest{
		RoomName: roomName,
	})
	if err != nil {
		return nil, err
	}
	return res.Items, nil
}

func generateRandomID() string {
	rand.Seed(time.Now().UnixNano())
	const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	result := make([]byte, 8)
	for i := range result {
		result[i] = chars[rand.Intn(len(chars))]
	}
	return string(result)
}

func boolPtr(b bool) *bool {
	return &b
}
