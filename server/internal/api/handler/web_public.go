package handler

import (
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"nexusroom-server/internal/media/rtcplay"
	mediastream "nexusroom-server/internal/media/stream"
	"nexusroom-server/internal/repository"
	"nexusroom-server/pkg/util"
)

type WebPublicHandler struct {
	ingressRepo *repository.IngressRepository
	streams     *mediastream.Registry
	rtc         *rtcplay.Engine
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

func NewWebPublicHandler(ingressRepo *repository.IngressRepository, streams *mediastream.Registry, rtc *rtcplay.Engine) *WebPublicHandler {
	return &WebPublicHandler{ingressRepo: ingressRepo, streams: streams, rtc: rtc}
}

func (h *WebPublicHandler) ListLiveRooms(c *gin.Context) {
	liveStreams := h.streams.Snapshot()
	streamKeys := make([]string, 0, len(liveStreams))
	for _, live := range liveStreams {
		streamKeys = append(streamKeys, live.Key)
	}
	refs, err := h.ingressRepo.ListRoomRefsByStreamKeys(streamKeys)
	if err != nil {
		util.Error(c, 50001, "查询房间映射失败: "+err.Error())
		return
	}
	rooms := buildWebLiveRooms(liveStreams, refs)
	util.Success(c, gin.H{"rooms": rooms, "total": len(rooms), "generated_at": time.Now().UTC()})
}

func buildWebLiveRooms(liveStreams []mediastream.Info, refs []repository.StreamRoomRef) []webLiveRoom {
	refByKey := make(map[string]repository.StreamRoomRef, len(refs))
	for _, ref := range refs {
		refByKey[ref.StreamKey] = ref
	}
	rooms := make([]webLiveRoom, 0)
	knownIndex := make(map[uint64]int)
	for _, live := range liveStreams {
		if ref, ok := refByKey[live.Key]; ok {
			index, exists := knownIndex[ref.RoomID]
			if !exists {
				rooms = append(rooms, webLiveRoom{ID: fmt.Sprintf("room-%d", ref.RoomID), Name: ref.RoomName, Type: "known", RoomID: ref.RoomID, Streams: []webLiveStream{}})
				index = len(rooms) - 1
				knownIndex[ref.RoomID] = index
			}
			label := strings.TrimSpace(ref.Label)
			if label == "" {
				label = live.Key
			}
			rooms[index].Streams = append(rooms[index].Streams, toWebStream(live, label))
			continue
		}
		prefix := live.Key
		if len(prefix) > 8 {
			prefix = prefix[:8]
		}
		rooms = append(rooms, webLiveRoom{
			ID: "virtual-" + live.Key, Name: "临时直播-" + prefix, Type: "virtual",
			Streams: []webLiveStream{toWebStream(live, "未知流")},
		})
	}
	for i := range rooms {
		rooms[i].StreamCnt = len(rooms[i].Streams)
		sort.Slice(rooms[i].Streams, func(a, b int) bool { return rooms[i].Streams[a].StreamKey < rooms[i].Streams[b].StreamKey })
	}
	sort.Slice(rooms, func(i, j int) bool {
		if rooms[i].Type != rooms[j].Type {
			return rooms[i].Type < rooms[j].Type
		}
		return rooms[i].Name < rooms[j].Name
	})
	return rooms
}

func toWebStream(info mediastream.Info, label string) webLiveStream {
	return webLiveStream{
		App: "live", StreamKey: info.Key, Label: label, Clients: info.Viewers,
		Bitrate: info.BitrateKbps, PlayURL: fmt.Sprintf("/api/v1/stream/%s", info.Key),
	}
}

type rtcPlayRequest struct {
	SDP       string `json:"sdp"`
	StreamURL string `json:"streamurl"`
}

func (h *WebPublicHandler) RTCPlay(c *gin.Context) {
	var request rtcPlayRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		util.Error(c, 40001, "WebRTC 播放请求格式错误")
		return
	}
	streamKey, err := streamKeyFromURL(request.StreamURL)
	if err != nil {
		util.Error(c, 40001, err.Error())
		return
	}
	streamInfo, ok := h.streams.Get(streamKey)
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"code": 40001, "message": mediastream.ErrNotFound.Error()})
		return
	}
	answer, err := h.rtc.Answer(c.Request.Context(), streamKey, request.SDP)
	if err != nil {
		status := http.StatusBadRequest
		if err == mediastream.ErrNotFound {
			status = http.StatusNotFound
		}
		c.JSON(status, gin.H{"code": 40001, "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"code": 0, "server": "nexusroom", "sdp": answer, "sessionid": streamKey,
		"source_has_audio": streamInfo.HasAudio,
	})
}

func streamKeyFromURL(raw string) (string, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return "", fmt.Errorf("无效的播放地址")
	}
	parts := strings.Split(strings.Trim(u.Path, "/"), "/")
	if len(parts) != 2 || parts[0] != "live" || strings.TrimSpace(parts[1]) == "" {
		return "", fmt.Errorf("播放地址必须为 /live/{streamKey}")
	}
	return parts[1], nil
}
