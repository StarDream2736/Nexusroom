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
	wgPeerRepo *repository.WGPeerRepository,
	hub *ws.Hub,
) *gin.Engine {
	router := gin.Default()

	// 中间件
	router.Use(middleware.CORSMiddleware())

	// 服务初始化
	livekitSvc := service.NewLiveKitService()
	wgCoordinator := wg.NewCoordinator(&cfg.WireGuard, wgPeerRepo)

	// Handler 初始化
	authHandler := handler.NewAuthHandler(userRepo)
	userHandler := handler.NewUserHandler(userRepo, cfg)
	roomHandler := handler.NewRoomHandler(roomRepo, userRepo, ingressRepo, livekitSvc, hub)
	msgHandler := handler.NewMessageHandler(msgRepo, roomRepo)
	livekitHandler := handler.NewLiveKitHandler(roomRepo, userRepo, livekitSvc, cfg)
	ingressHandler := handler.NewIngressHandler(roomRepo, ingressRepo, livekitSvc, cfg)
	fileHandler := handler.NewFileHandler(cfg, roomRepo)
	adminHandler := handler.NewAdminHandler(userRepo, roomRepo, msgRepo, hub, cfg)
	friendHandler := handler.NewFriendHandler(friendRepo, userRepo, roomRepo, hub)
	webhookHandler := handler.NewWebhookHandler(msgRepo, roomRepo, hub, cfg)
	vlanHandler := handler.NewVLANHandler(roomRepo, userRepo, wgCoordinator, hub)

	// 健康检查
	router.GET("/ping", func(c *gin.Context) {
		util.Success(c, gin.H{"status": "ok", "version": "1.3.1"})
	})

	// 静态文件（头像等公开资源）
	router.Static("/uploads", cfg.Storage.Path)

	// API v1 路由组
	apiV1 := router.Group("/api/v1")
	{
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
			// 文件访问（鉴权 + 房间成员校验）
			authorized.GET("/files/:fileId", fileHandler.GetByID)

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
