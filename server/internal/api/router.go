package api

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"

	"nexusroom-server/internal/api/handler"
	"nexusroom-server/internal/api/middleware"
	"nexusroom-server/internal/config"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/service"
	"nexusroom-server/internal/wg"
	"nexusroom-server/internal/ws"
	"nexusroom-server/pkg/jwt"
	"nexusroom-server/pkg/util"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // 允许所有来源
	},
}

func SetupRouter(
	cfg *config.Config,
	userRepo *repository.UserRepository,
	roomRepo *repository.RoomRepository,
	msgRepo *repository.MessageRepository,
	ingressRepo *repository.IngressRepository,
	friendRepo *repository.FriendshipRepository,
	wgCoordinator *wg.Coordinator,
	hub *ws.Hub,
) *gin.Engine {
	router := gin.Default()

	// 中间件
	router.Use(middleware.CORSMiddleware())

	// 服务初始化
	livekitSvc := service.NewLiveKitService()

	// Handler 初始化
	authHandler := handler.NewAuthHandler(userRepo)
	userHandler := handler.NewUserHandler(userRepo, cfg)
	roomHandler := handler.NewRoomHandler(roomRepo, userRepo, ingressRepo, hub, cfg)
	msgHandler := handler.NewMessageHandler(msgRepo, roomRepo)
	livekitHandler := handler.NewLiveKitHandler(roomRepo, userRepo, livekitSvc, cfg)
	ingressHandler := handler.NewIngressHandler(roomRepo, ingressRepo, cfg, hub)
	fileHandler := handler.NewFileHandler(cfg, roomRepo)
	adminHandler := handler.NewAdminHandler(userRepo, roomRepo, msgRepo, hub, cfg)
	friendHandler := handler.NewFriendHandler(friendRepo, userRepo, roomRepo, hub)
	webhookHandler := handler.NewWebhookHandler(msgRepo, roomRepo, ingressRepo, hub, cfg)
	vlanHandler := handler.NewVLANHandler(roomRepo, userRepo, wgCoordinator, hub)
	webPublicHandler := handler.NewWebPublicHandler(ingressRepo, cfg)

	// 健康检查
	router.GET("/ping", func(c *gin.Context) {
		util.Success(c, gin.H{"status": "ok", "version": "1.4.0"})
	})

	// 静态文件（头像等公开资源）
	router.Use(func(c *gin.Context) {
		path := c.Request.URL.Path
		if path == "/" || path == "/index.html" || path == "/player.html" || path == "/srs.sdk.js" || path == "/mpegts.min.js" {
			c.Header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
			c.Header("Pragma", "no-cache")
			c.Header("Expires", "0")
		}
		c.Next()
	})

	router.Static("/uploads", cfg.Storage.Path)
	router.GET("/", func(c *gin.Context) {
		c.File("./web/index.html")
	})
	router.StaticFile("/index.html", "./web/index.html")
	router.StaticFile("/player.html", "./web/player.html")
	router.StaticFile("/srs.sdk.js", "./web/srs.sdk.js")
	router.StaticFile("/mpegts.min.js", "./web/mpegts.min.js")

	// API v1 路由组
	apiV1 := router.Group("/api/v1")
	{
		// 文件下载（handler 内部自行校验 token + 房间成员）
		apiV1.GET("/files/:fileId", fileHandler.GetByID)

		// 认证模块（公开）
		auth := apiV1.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
		}

		// 需要认证的接口
		authorized := apiV1.Group("")
		authorized.Use(middleware.AuthMiddleware())
		{
			// 用户模块
			users := authorized.Group("/users")
			{
				users.GET("/me", userHandler.GetMe)
				users.PATCH("/me", userHandler.UpdateProfile)
				users.POST("/me/avatar", userHandler.UploadAvatar)
				users.GET("/search", userHandler.SearchByDisplayID)
			}

			// 房间模块
			rooms := authorized.Group("/rooms")
			{
				rooms.POST("", roomHandler.Create)
				rooms.POST("/join", roomHandler.Join)
				rooms.GET("", roomHandler.List)
				rooms.GET("/:roomId", roomHandler.GetDetail)
				rooms.PATCH("/:roomId", roomHandler.UpdateRoom)
				rooms.DELETE("/:roomId", roomHandler.Delete)
				rooms.DELETE("/:roomId/leave", roomHandler.Leave)
				rooms.DELETE("/:roomId/members/:userId", roomHandler.KickMember)

				// 在线用户
				rooms.GET("/:roomId/online-users", roomHandler.OnlineUsers)

				// 消息
				rooms.GET("/:roomId/messages", msgHandler.GetMessages)

				// LiveKit Token
				rooms.POST("/:roomId/livekit-token", livekitHandler.GenerateToken)

				// Ingress 管理
				rooms.POST("/:roomId/ingresses", ingressHandler.Create)
				rooms.GET("/:roomId/ingresses", ingressHandler.List)
				rooms.DELETE("/:roomId/ingresses/:ingressId", ingressHandler.Delete)

				// VLAN
				rooms.POST("/:roomId/vlan/join", vlanHandler.Join)
				rooms.DELETE("/:roomId/vlan/leave", vlanHandler.Leave)
				rooms.GET("/:roomId/vlan/peers", vlanHandler.Peers)
			}

			// 好友模块
			friends := authorized.Group("/friends")
			{
				friends.GET("", friendHandler.ListFriends)
				friends.GET("/pending", friendHandler.ListPendingRequests)
				friends.POST("/request", friendHandler.SendRequest)
				friends.PATCH("/request/:requestId", friendHandler.HandleRequest)
			}

			// 文件模块
			files := authorized.Group("/files")
			{
				files.POST("/upload", fileHandler.Upload)
			}
		}

		// 超管接口
		admin := apiV1.Group("/admin")
		admin.Use(middleware.AuthMiddleware(), middleware.AdminMiddleware())
		{
			admin.GET("/users", adminHandler.ListUsers)
			admin.PATCH("/users/:userId", adminHandler.ToggleUser)
			admin.GET("/rooms", adminHandler.ListRooms)
			admin.DELETE("/rooms/:roomId", adminHandler.DeleteRoom)
			admin.GET("/config", adminHandler.GetConfig)
			admin.PATCH("/config", adminHandler.UpdateConfig)
			admin.GET("/stats", adminHandler.GetStats)
		}

		// QQ 机器人 Webhook
		apiV1.POST("/webhook/qq", webhookHandler.QQWebhook)

		// SRS 推流状态回调（SRS HTTP Hooks）
		apiV1.POST("/webhook/srs", webhookHandler.SRSWebhook)

		// HTTP-FLV 直播流代理（公开，无需认证）
		apiV1.GET("/stream/:streamKey", ingressHandler.ProxyStream)

		// 网页直播（独立于客户端业务流程）
		apiV1.GET("/web/rooms/live", webPublicHandler.ListLiveRooms)
		apiV1.POST("/web/rtc/play", webPublicHandler.RTCPlayProxy)
	}

	// WebSocket 路由
	router.GET("/ws", func(c *gin.Context) {
		// 从 query 参数获取 token
		tokenString := c.Query("token")
		if tokenString == "" {
			util.Error(c, 40101, "缺少认证 Token")
			return
		}

		claims, err := jwt.ParseToken(tokenString)
		if err != nil {
			util.Error(c, 40101, "Token 无效或已过期")
			return
		}

		conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
		if err != nil {
			return
		}

		client := ws.NewClient(hub, conn, claims.UserID, claims.Username, claims.Role)
		hub.Register <- client

		go client.WritePump()
		go client.ReadPump()
	})

	return router
}
