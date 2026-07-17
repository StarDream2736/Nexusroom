package handler

import (
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/media/flv"
	mediastream "nexusroom-server/internal/media/stream"
	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/ws"
	"nexusroom-server/pkg/util"
)

type IngressHandler struct {
	roomRepo    *repository.RoomRepository
	ingressRepo *repository.IngressRepository
	cfg         *config.Config
	hub         *ws.Hub
	streams     *mediastream.Registry
}

func NewIngressHandler(roomRepo *repository.RoomRepository, ingressRepo *repository.IngressRepository,
	cfg *config.Config, hub *ws.Hub, streams *mediastream.Registry) *IngressHandler {
	return &IngressHandler{roomRepo: roomRepo, ingressRepo: ingressRepo, cfg: cfg, hub: hub, streams: streams}
}

type CreateIngressRequest struct {
	Label string `json:"label" validate:"required,min=1,max=64"`
}

func (h *IngressHandler) Create(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间 ID 格式错误")
		return
	}
	var req CreateIngressRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}
	if err := validator.New().Struct(req); err != nil {
		util.Error(c, 40001, err.Error())
		return
	}
	userID := c.GetUint64("userID")
	if _, err := h.roomRepo.FindByID(roomID); err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}
	if !h.roomRepo.IsMember(roomID, userID) && c.GetString("role") != "super_admin" {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权创建推流入口")
		return
	}

	ingress := &model.RoomIngress{
		RoomID: roomID, IngressID: uuid.NewString(), StreamKey: uuid.NewString()[:12],
		RTMPURL: h.deriveRTMPURL(c), Label: req.Label, CreatedBy: userID,
	}
	if err := h.ingressRepo.Create(ingress); err != nil {
		util.Error(c, 50001, "保存推流入口失败: "+err.Error())
		return
	}
	util.Success(c, gin.H{
		"id": ingress.ID, "ingress_id": ingress.IngressID, "rtmp_url": ingress.RTMPURL,
		"stream_key": ingress.StreamKey, "publish_url": joinRTMPPublishURL(ingress.RTMPURL, ingress.StreamKey),
		"label": ingress.Label,
	})
	h.hub.BroadcastToRoom(roomID, ws.EventIngressUpdate, ws.IngressUpdatePayload{RoomID: roomID, Action: "created"}, 0)
}

func (h *IngressHandler) List(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间 ID 格式错误")
		return
	}
	userID := c.GetUint64("userID")
	if _, err := h.roomRepo.FindByID(roomID); err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}
	if !h.roomRepo.IsMember(roomID, userID) && c.GetString("role") != "super_admin" {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权访问推流入口")
		return
	}
	ingresses, err := h.ingressRepo.ListByRoom(roomID)
	if err != nil {
		util.Error(c, 50001, "获取推流入口失败")
		return
	}
	result := make([]gin.H, 0, len(ingresses))
	rtmpURL := h.deriveRTMPURL(c)
	for _, ingress := range ingresses {
		_, active := h.streams.Get(ingress.StreamKey)
		result = append(result, gin.H{
			"id": ingress.ID, "ingress_id": ingress.IngressID, "rtmp_url": rtmpURL,
			"stream_key": ingress.StreamKey, "publish_url": joinRTMPPublishURL(rtmpURL, ingress.StreamKey),
			"label": ingress.Label, "is_active": active,
		})
	}
	util.Success(c, result)
}

func (h *IngressHandler) Delete(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间 ID 格式错误")
		return
	}
	ingressID, err := strconv.ParseUint(c.Param("ingressId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "Ingress ID 格式错误")
		return
	}
	userID := c.GetUint64("userID")
	if _, err := h.roomRepo.FindByID(roomID); err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}
	if !h.roomRepo.IsMember(roomID, userID) && c.GetString("role") != "super_admin" {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权删除推流入口")
		return
	}
	ingress, err := h.ingressRepo.FindByID(ingressID)
	if err != nil || ingress.RoomID != roomID {
		util.Error(c, 40401, "推流入口不存在")
		return
	}
	if _, active := h.streams.Get(ingress.StreamKey); active {
		util.Error(c, 40901, "推流仍在进行，请停止推流后删除")
		return
	}
	if err := h.ingressRepo.Delete(ingressID); err != nil {
		util.Error(c, 50001, "删除推流入口失败")
		return
	}
	h.hub.BroadcastToRoom(roomID, ws.EventIngressUpdate, ws.IngressUpdatePayload{RoomID: roomID, Action: "deleted"}, 0)
	util.Success(c, nil)
}

func (h *IngressHandler) deriveRTMPURL(c *gin.Context) string {
	host := strings.TrimSpace(h.cfg.Server.Domain)
	if host == "" {
		host = strings.TrimSpace(h.cfg.Media.PublicIP)
	}
	if host == "" || host == "your-server-public-ip" {
		host = strings.TrimSpace(strings.Split(c.GetHeader("X-Forwarded-Host"), ",")[0])
		if host == "" {
			host = c.Request.Host
		}
	}
	port := h.cfg.Media.RTMP.Port
	if port == 0 {
		port = 1935
	}
	return buildRTMPURL(host, port)
}

func buildRTMPURL(value string, port int) string {
	host := strings.TrimSpace(strings.Split(value, ",")[0])
	if parsed, err := url.Parse(host); err == nil && parsed.Hostname() != "" {
		host = parsed.Hostname()
	} else if parsed, err := url.Parse("//" + host); err == nil && parsed.Hostname() != "" {
		host = parsed.Hostname()
	} else {
		host = stripHostPort(strings.Trim(host, "[]/"))
	}
	if host == "" {
		host = "127.0.0.1"
	}
	return fmt.Sprintf("rtmp://%s/live", net.JoinHostPort(host, strconv.Itoa(port)))
}

func stripHostPort(host string) string {
	if parsed, _, err := net.SplitHostPort(host); err == nil {
		return parsed
	}
	return strings.Trim(host, "[]")
}

func joinRTMPPublishURL(baseURL, streamKey string) string {
	return strings.TrimRight(baseURL, "/") + "/" + strings.TrimLeft(streamKey, "/")
}

// ProxyStream serves a live HTTP-FLV stream directly from the embedded registry.
func (h *IngressHandler) ProxyStream(c *gin.Context) {
	streamKey := strings.TrimSpace(c.Param("streamKey"))
	subscription, err := h.streams.Subscribe(streamKey)
	if err != nil {
		c.Status(http.StatusNotFound)
		return
	}
	defer subscription.Close()

	c.Header("Content-Type", "video/x-flv")
	c.Header("Cache-Control", "no-cache, no-store")
	c.Header("Access-Control-Allow-Origin", "*")
	c.Header("X-Accel-Buffering", "no")
	c.Status(http.StatusOK)
	muxer := flv.New(c.Writer)
	if err := muxer.WriteHeader(subscription.SPS, subscription.PPS, subscription.AAC); err != nil {
		return
	}
	c.Writer.Flush()

	started := false
	for {
		select {
		case <-c.Request.Context().Done():
			return
		case frame, ok := <-subscription.Frames:
			if !ok {
				return
			}
			if !started {
				if !frame.KeyFrame {
					continue
				}
				started = true
			}
			if err := muxer.WriteFrame(frame); err != nil {
				return
			}
			c.Writer.Flush()
		case audio, ok := <-subscription.Audio:
			if !ok {
				return
			}
			if started && len(subscription.AAC) != 0 {
				if err := muxer.WriteAudio(audio); err != nil {
					return
				}
				c.Writer.Flush()
			}
		}
	}
}
