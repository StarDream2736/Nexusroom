package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/repository"
	"nexusroom-server/pkg/util"
)

type WebPublicHandler struct {
	ingressRepo *repository.IngressRepository
	cfg         *config.Config
	httpClient  *http.Client
}

type srsStreamListResponse struct {
	Code    int             `json:"code"`
	Streams []srsStreamItem `json:"streams"`
}

type srsStreamItem struct {
	App     string          `json:"app"`
	Name    string          `json:"name"`
	Stream  string          `json:"stream"`
	Clients int             `json:"clients"`
	Publish srsPublishState `json:"publish"`
	Kbps    srsKbpsState    `json:"kbps"`
}

type srsPublishState struct {
	Active bool `json:"active"`
}

type srsKbpsState struct {
	Recv30s float64 `json:"recv_30s"`
}

type webLiveStream struct {
	App       string  `json:"app"`
	StreamKey string  `json:"stream_key"`
	Label     string  `json:"label"`
	Clients   int     `json:"clients"`
	Bitrate   float64 `json:"bitrate_kbps"`
	PlayURL   string  `json:"play_url"`
}

type webLiveRoom struct {
	ID        string          `json:"id"`
	Name      string          `json:"name"`
	Type      string          `json:"type"`
	RoomID    uint64          `json:"room_id,omitempty"`
	Streams   []webLiveStream `json:"streams"`
	StreamCnt int             `json:"stream_count"`
}

func NewWebPublicHandler(ingressRepo *repository.IngressRepository, cfg *config.Config) *WebPublicHandler {
	return &WebPublicHandler{
		ingressRepo: ingressRepo,
		cfg:         cfg,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

func (h *WebPublicHandler) ListLiveRooms(c *gin.Context) {
	liveStreams, err := h.fetchSRSLiveStreams(c.Request.Context())
	if err != nil {
		util.Error(c, 50001, "获取 SRS 直播流失败: "+err.Error())
		return
	}

	streamKeys := make([]string, 0, len(liveStreams))
	for _, s := range liveStreams {
		streamKeys = append(streamKeys, s.Stream)
	}

	refs, err := h.ingressRepo.ListRoomRefsByStreamKeys(streamKeys)
	if err != nil {
		util.Error(c, 50001, "查询房间映射失败: "+err.Error())
		return
	}

	refByKey := make(map[string]repository.StreamRoomRef, len(refs))
	for _, ref := range refs {
		refByKey[ref.StreamKey] = ref
	}

	rooms := make([]webLiveRoom, 0)
	knownIdx := make(map[uint64]int)

	for _, stream := range liveStreams {
		if ref, ok := refByKey[stream.Stream]; ok {
			idx, exists := knownIdx[ref.RoomID]
			if !exists {
				rooms = append(rooms, webLiveRoom{
					ID:      fmt.Sprintf("room-%d", ref.RoomID),
					Name:    ref.RoomName,
					Type:    "known",
					RoomID:  ref.RoomID,
					Streams: []webLiveStream{},
				})
				idx = len(rooms) - 1
				knownIdx[ref.RoomID] = idx
			}

			label := strings.TrimSpace(ref.Label)
			if label == "" {
				label = stream.Stream
			}

			rooms[idx].Streams = append(rooms[idx].Streams, webLiveStream{
				App:       stream.App,
				StreamKey: stream.Stream,
				Label:     label,
				Clients:   stream.Clients,
				Bitrate:   stream.Kbps.Recv30s,
				PlayURL:   fmt.Sprintf("/api/v1/stream/%s", stream.Stream),
			})
			continue
		}

		prefix := stream.Stream
		if len(prefix) > 8 {
			prefix = prefix[:8]
		}

		rooms = append(rooms, webLiveRoom{
			ID:   "virtual-" + stream.Stream,
			Name: "临时直播-" + prefix,
			Type: "virtual",
			Streams: []webLiveStream{{
				App:       stream.App,
				StreamKey: stream.Stream,
				Label:     "未知流",
				Clients:   stream.Clients,
				Bitrate:   stream.Kbps.Recv30s,
				PlayURL:   fmt.Sprintf("/api/v1/stream/%s", stream.Stream),
			}},
		})
	}

	for i := range rooms {
		rooms[i].StreamCnt = len(rooms[i].Streams)
		sort.Slice(rooms[i].Streams, func(a, b int) bool {
			return rooms[i].Streams[a].StreamKey < rooms[i].Streams[b].StreamKey
		})
	}

	sort.Slice(rooms, func(i, j int) bool {
		if rooms[i].Type != rooms[j].Type {
			return rooms[i].Type < rooms[j].Type
		}
		return rooms[i].Name < rooms[j].Name
	})

	util.Success(c, gin.H{
		"rooms":        rooms,
		"total":        len(rooms),
		"generated_at": time.Now().UTC(),
	})
}

func (h *WebPublicHandler) RTCPlayProxy(c *gin.Context) {
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		util.Error(c, 40001, "读取请求失败")
		return
	}

	target := fmt.Sprintf("http://%s:%d/rtc/v1/play/", h.srsHost(), h.srsAPIPort())
	req, err := http.NewRequestWithContext(c.Request.Context(), http.MethodPost, target, bytes.NewReader(body))
	if err != nil {
		util.Error(c, 50001, "创建代理请求失败")
		return
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := h.httpClient.Do(req)
	if err != nil {
		util.Error(c, 50001, "SRS RTC 播放接口不可用")
		return
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		util.Error(c, 50001, "读取 SRS 返回失败")
		return
	}

	c.Data(resp.StatusCode, "application/json", respBody)
}

func (h *WebPublicHandler) fetchSRSLiveStreams(reqCtx context.Context) ([]srsStreamItem, error) {
	target := fmt.Sprintf("http://%s:%d/api/v1/streams", h.srsHost(), h.srsAPIPort())
	req, err := http.NewRequest(http.MethodGet, target, nil)
	if err != nil {
		return nil, err
	}
	req = req.WithContext(reqCtx)

	resp, err := h.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		msg, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(msg)))
	}

	var payload srsStreamListResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, err
	}
	if payload.Code != 0 {
		return nil, fmt.Errorf("srs code=%d", payload.Code)
	}

	result := make([]srsStreamItem, 0, len(payload.Streams))
	for _, s := range payload.Streams {
		streamKey := strings.TrimSpace(s.Name)
		if streamKey == "" {
			streamKey = strings.TrimSpace(s.Stream)
		}
		if streamKey == "" {
			continue
		}
		if !s.Publish.Active {
			continue
		}
		if strings.TrimSpace(s.App) == "" {
			s.App = "live"
		}
		s.Stream = streamKey
		result = append(result, s)
	}

	return result, nil
}

func (h *WebPublicHandler) srsHost() string {
	host := strings.TrimSpace(h.cfg.SRS.Host)
	if host == "" {
		return "srs"
	}
	return host
}

func (h *WebPublicHandler) srsAPIPort() int {
	if h.cfg.SRS.APIPort == 0 {
		return 1985
	}
	return h.cfg.SRS.APIPort
}
