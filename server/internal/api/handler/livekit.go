package handler

import (
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/service"
	"nexusroom-server/pkg/util"
)

type LiveKitHandler struct {
	roomRepo    *repository.RoomRepository
	userRepo    *repository.UserRepository
	ingressRepo *repository.IngressRepository
	livekitSvc  *service.LiveKitService
	cfg         *config.Config
}

func NewLiveKitHandler(roomRepo *repository.RoomRepository, userRepo *repository.UserRepository, ingressRepo *repository.IngressRepository, livekitSvc *service.LiveKitService, cfg *config.Config) *LiveKitHandler {
	return &LiveKitHandler{
		roomRepo:    roomRepo,
		userRepo:    userRepo,
		ingressRepo: ingressRepo,
		livekitSvc:  livekitSvc,
		cfg:         cfg,
	}
}

func (h *LiveKitHandler) GenerateToken(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.Param("roomId"), 10, 64)
	if err != nil {
		util.Error(c, 40001, "房间ID格式错误")
		return
	}

	userID := c.GetUint64("userID")

	// 检查是否是成员
	if !h.roomRepo.IsMember(roomID, userID) {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权访问该房间")
		return
	}

	room, err := h.roomRepo.FindByID(roomID)
	if err != nil {
		util.Error(c, 40401, "房间不存在")
		return
	}

	// 获取用户昵称
	user, err := h.userRepo.FindByID(userID)
	if err != nil {
		util.Error(c, 50001, "获取用户信息失败")
		return
	}

	// 根据 type 参数选择语音房间或直播房间
	roomType := c.DefaultQuery("type", "voice")
	livekitRoom := room.LiveKitRoomName
	if roomType == "stream" {
		// 每个 Ingress 有独立的 LiveKit 房间，通过 ingress_id 查找
		ingressIDStr := c.Query("ingress_id")
		if ingressIDStr == "" {
			util.Error(c, 40001, "直播观看需提供 ingress_id 参数")
			return
		}
		ingressDBID, err := strconv.ParseUint(ingressIDStr, 10, 64)
		if err != nil {
			util.Error(c, 40001, "ingress_id 格式错误")
			return
		}
		ingress, err := h.ingressRepo.FindByID(ingressDBID)
		if err != nil {
			util.Error(c, 40401, "推流入口不存在")
			return
		}
		// 优先使用 Ingress 记录中的独立房间名（新创建的 Ingress 才有）
		if ingress.LiveKitRoomName != "" {
			livekitRoom = ingress.LiveKitRoomName
		} else {
			// 兼容旧数据：回退到共享房间
			livekitRoom = room.LiveKitRoomName + "_stream"
		}
	}

	var token string
	if roomType == "stream" {
		// 直播观看者只需订阅权限，不需要发布权限
		token, err = h.livekitSvc.GenerateViewerToken(livekitRoom, strconv.FormatUint(userID, 10), user.Nickname)
	} else {
		token, err = h.livekitSvc.GenerateToken(livekitRoom, strconv.FormatUint(userID, 10), user.Nickname)
	}
	if err != nil {
		util.Error(c, 50001, "生成 Token 失败")
		return
	}

	publicURL := h.cfg.LiveKit.PublicURL
	secure := isSecureRequest(c)
	if publicURL == "" {
		publicURL = derivePublicLiveKitURL(c, h.cfg.LiveKit.URL)
	}
	publicURL = normalizeWsURL(publicURL, secure)
	if publicURL == "" {
		publicURL = h.cfg.LiveKit.URL
	}

	util.Success(c, gin.H{
		"token":     token,
		"url":       publicURL,
		"room_name": livekitRoom,
	})
}

func isSecureRequest(c *gin.Context) bool {
	proto := strings.TrimSpace(strings.Split(c.GetHeader("X-Forwarded-Proto"), ",")[0])
	if proto != "" {
		proto = strings.ToLower(proto)
		return proto == "https" || proto == "wss"
	}

	return c.Request.TLS != nil
}

func normalizeWsURL(raw string, preferSecure bool) string {
	if raw == "" {
		return ""
	}

	u, err := url.Parse(raw)
	if err != nil || u.Scheme == "" {
		scheme := "ws"
		if preferSecure {
			scheme = "wss"
		}
		return scheme + "://" + strings.TrimPrefix(raw, "//")
	}

	switch strings.ToLower(u.Scheme) {
	case "http":
		u.Scheme = "ws"
	case "https":
		u.Scheme = "wss"
	}

	return u.String()
}

func derivePublicLiveKitURL(c *gin.Context, livekitURL string) string {
	host := strings.TrimSpace(strings.Split(c.GetHeader("X-Forwarded-Host"), ",")[0])
	if host == "" {
		host = c.Request.Host
	}
	if isLoopbackHost(host) {
		originHost := hostFromHeaderURL(c.GetHeader("Origin"))
		if originHost == "" {
			originHost = hostFromHeaderURL(c.GetHeader("Referer"))
		}
		if originHost != "" {
			host = originHost
		}
	}
	if host == "" {
		return ""
	}

	port := livekitPortFromURL(livekitURL)
	baseHost := stripPort(host)
	baseHost = strings.TrimPrefix(baseHost, "[")
	baseHost = strings.TrimSuffix(baseHost, "]")
	if port != "" {
		baseHost = net.JoinHostPort(baseHost, port)
	}

	scheme := "ws"
	if isSecureRequest(c) {
		scheme = "wss"
	}

	return scheme + "://" + baseHost
}

func livekitPortFromURL(raw string) string {
	u, err := url.Parse(raw)
	if err == nil {
		if port := u.Port(); port != "" {
			return port
		}
	}

	return "7880"
}

func stripPort(host string) string {
	if h, _, err := net.SplitHostPort(host); err == nil {
		return h
	}
	return host
}

func hostFromHeaderURL(raw string) string {
	if raw == "" {
		return ""
	}

	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return ""
	}

	return u.Host
}

func isLoopbackHost(host string) bool {
	host = stripPort(host)
	host = strings.TrimPrefix(host, "[")
	host = strings.TrimSuffix(host, "]")
	if host == "" {
		return true
	}
	if strings.EqualFold(host, "localhost") {
		return true
	}
	if ip := net.ParseIP(host); ip != nil {
		return ip.IsLoopback()
	}
	return false
}
