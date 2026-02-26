package handler

import (
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"

	"nexusroom-server/internal/config"
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
}

func NewIngressHandler(roomRepo *repository.RoomRepository, ingressRepo *repository.IngressRepository,
	cfg *config.Config, hub *ws.Hub) *IngressHandler {
	return &IngressHandler{
		roomRepo:    roomRepo,
		ingressRepo: ingressRepo,
		cfg:         cfg,
		hub:         hub,
	}
}

type CreateIngressRequest struct {
	Label string `json:"label" validate:"required,min=1,max=64"`
}

func (h *IngressHandler) Create(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	var req CreateIngressRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		util.Error(c, 40001, "参数校验失败")
		return
	}

	validate := validator.New()
	if err := validate.Struct(req); err != nil {
		util.Error(c, 40001, err.Error())
		return
	}

	userID := c.GetUint64("userID")

	// 检查房间存在
	if _, err := h.roomRepo.FindByID(roomID); err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 检查权限（房间成员即可创建推流入口）
	if !h.roomRepo.IsMember(roomID, userID) && c.GetString("role") != "super_admin" {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权创建推流入口")
		return
	}

	// 生成本地 stream key（SRS 模式，不调用外部 API）
	streamKey := uuid.New().String()[:12]
	ingressID := uuid.New().String() // 本地唯一标识

	// 构造 RTMP 推流地址（指向 SRS）
	rtmpURL := h.deriveRTMPURL(c)

	// 保存到数据库
	rmIngress := &model.RoomIngress{
		RoomID:    roomID,
		IngressID: ingressID,
		StreamKey: streamKey,
		RTMPURL:   rtmpURL,
		Label:     req.Label,
		CreatedBy: userID,
	}

	if err := h.ingressRepo.Create(rmIngress); err != nil {
		util.Error(c, 50001, "保存推流入口失败: "+err.Error())
		return
	}

	util.Success(c, gin.H{
		"id":         rmIngress.ID,
		"ingress_id": rmIngress.IngressID,
		"rtmp_url":   rmIngress.RTMPURL,
		"stream_key": rmIngress.StreamKey,
		"label":      rmIngress.Label,
	})

	// 广播 ingress 更新事件给房间成员
	h.hub.BroadcastToRoom(roomID, ws.EventIngressUpdate, ws.IngressUpdatePayload{
		RoomID: roomID,
		Action: "created",
	}, 0)
}

func (h *IngressHandler) List(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	// 检查房间是否存在
	if _, err := h.roomRepo.FindByID(roomID); err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 检查权限（房间成员即可查看推流列表）
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
	for _, ing := range ingresses {
		result = append(result, gin.H{
			"id":         ing.ID,
			"ingress_id": ing.IngressID,
			"rtmp_url":   ing.RTMPURL,
			"stream_key": ing.StreamKey,
			"label":      ing.Label,
			"is_active":  ing.IsActive,
		})
	}

	util.Success(c, result)
}

func (h *IngressHandler) Delete(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	ingressID, err := strconv.ParseUint(c.Param("ingressId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "Ingress ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	// 检查房间是否存在
	if _, err := h.roomRepo.FindByID(roomID); err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 检查权限（房间成员即可删除推流入口）
	if !h.roomRepo.IsMember(roomID, userID) && c.GetString("role") != "super_admin" {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权删除推流入口")
		return
	}

	// 获取 Ingress 信息（确认存在）
	if _, err := h.ingressRepo.FindByID(ingressID); err != nil {
		util.Error(c, 40401, "推流入口不存在")
		return
	}

	// 删除数据库记录
	if err := h.ingressRepo.Delete(ingressID); err != nil {
		util.Error(c, 50001, "删除推流入口失败")
		return
	}

	// 广播 ingress 更新事件给房间成员
	h.hub.BroadcastToRoom(roomID, ws.EventIngressUpdate, ws.IngressUpdatePayload{
		RoomID: roomID,
		Action: "deleted",
	}, 0)

	util.Success(c, nil)
}

// deriveRTMPURL 根据请求来源+配置构造 RTMP 推流地址（指向 SRS）
func (h *IngressHandler) deriveRTMPURL(c *gin.Context) string {
	// 优先使用配置中的服务器公网 IP / 域名
	host := h.cfg.Server.Domain
	if host == "" {
		host = h.cfg.WireGuard.ServerIP
	}
	if host == "" || host == "your-server-public-ip" {
		// 回退: 从请求头提取客户端访问的 Host
		host = strings.TrimSpace(strings.Split(c.GetHeader("X-Forwarded-Host"), ",")[0])
		if host == "" {
			host = c.Request.Host
		}
		host = stripHostPort(host)
	}

	port := h.cfg.SRS.RTMPPort
	if port == 0 {
		port = 1935
	}

	return fmt.Sprintf("rtmp://%s:%d/live", host, port)
}

func stripHostPort(host string) string {
	if h, _, err := net.SplitHostPort(host); err == nil {
		return h
	}
	return host
}

// ProxyStream GET /stream/:streamKey — 反向代理 SRS HTTP-FLV 直播流
// 客户端通过 8080 端口拉流，无需直连 SRS 8085 端口
func (h *IngressHandler) ProxyStream(c *gin.Context) {
	streamKey := c.Param("streamKey")
	if streamKey == "" {
		c.Status(http.StatusBadRequest)
		return
	}

	// 构造 SRS 内网 FLV 地址
	srsHost := h.cfg.SRS.Host
	if srsHost == "" {
		srsHost = "srs"
	}
	srsPort := h.cfg.SRS.HTTPPort
	if srsPort == 0 {
		srsPort = 8085
	}
	target := fmt.Sprintf("http://%s:%d/live/%s.flv", srsHost, srsPort, streamKey)

	// 发起内部请求到 SRS
	req, err := http.NewRequestWithContext(c.Request.Context(), "GET", target, nil)
	if err != nil {
		log.Printf("[StreamProxy] create request error: %v", err)
		c.Status(http.StatusBadGateway)
		return
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("[StreamProxy] SRS unreachable: %v", err)
		c.Status(http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		c.Status(resp.StatusCode)
		return
	}

	// 设置响应头 — HTTP-FLV 流式传输
	c.Header("Content-Type", "video/x-flv")
	c.Header("Cache-Control", "no-cache, no-store")
	c.Header("Connection", "close")
	c.Header("Access-Control-Allow-Origin", "*")
	c.Status(http.StatusOK)

	// 流式转发：逐块读取 SRS 响应并刷新到客户端
	flusher, _ := c.Writer.(http.Flusher)
	buf := make([]byte, 32*1024)
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			if _, writeErr := c.Writer.Write(buf[:n]); writeErr != nil {
				return // 客户端断开
			}
			if flusher != nil {
				flusher.Flush()
			}
		}
		if readErr != nil {
			if readErr != io.EOF {
				log.Printf("[StreamProxy] read error: %v", readErr)
			}
			return
		}
	}
}
