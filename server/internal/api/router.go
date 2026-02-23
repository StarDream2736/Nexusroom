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
	roomHandler := handler.NewRoomHandler(roomRepo, userRepo, ingressRepo, livekitSvc)
	msgHandler := handler.NewMessageHandler(msgRepo, roomRepo)
	livekitHandler := handler.NewLiveKitHandler(roomRepo, livekitSvc)
	ingressHandler := handler.NewIngressHandler(roomRepo, ingressRepo, livekitSvc)
	fileHandler := handler.NewFileHandler(cfg)
	
	// 健康检查
	router.GET("/ping", func(c *gin.Context) {
		util.Success(c, gin.H{"status": "ok", "version": "1.3.1"})
	})

	// 静态文件
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
				rooms.POST("/:roomId/vlan/join", func(c *gin.Context) {
					// TODO: 实现 VLAN join
					util.Success(c, nil)
				})
				rooms.DELETE("/:roomId/vlan/leave", func(c *gin.Context) {
					// TODO: 实现 VLAN leave
					util.Success(c, nil)
				})
				rooms.GET("/:roomId/vlan/peers", func(c *gin.Context) {
					// TODO: 实现 VLAN peers
					util.Success(c, []gin.H{})
				})
			}
			
			// 好友模块
			friends := authorized.Group("/friends")
			{
				friends.GET("", func(c *gin.Context) {
					// TODO: 实现好友列表
					util.Success(c, []gin.H{})
				})
				friends.POST("/request", func(c *gin.Context) {
					// TODO: 实现发送好友申请
					util.Success(c, nil)
				})
				friends.PATCH("/request/:requestId", func(c *gin.Context) {
					// TODO: 实现接受/拒绝好友申请
					util.Success(c, nil)
				})
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
			admin.GET("/users", func(c *gin.Context) {
				// TODO: 实现用户列表
				util.Success(c, gin.H{
					"users": []gin.H{},
					"total": 0,
				})
			})
			admin.PATCH("/users/:userId", func(c *gin.Context) {
				// TODO: 实现禁用/启用用户
				util.Success(c, nil)
			})
			admin.GET("/rooms", func(c *gin.Context) {
				// TODO: 实现房间列表
				util.Success(c, gin.H{
					"rooms": []gin.H{},
					"total": 0,
				})
			})
			admin.DELETE("/rooms/:roomId", func(c *gin.Context) {
				// TODO: 实现强制解散房间
				util.Success(c, nil)
			})
			admin.GET("/config", func(c *gin.Context) {
				// TODO: 实现获取配置
				util.Success(c, gin.H{})
			})
			admin.PATCH("/config", func(c *gin.Context) {
				// TODO: 实现修改配置
				util.Success(c, nil)
			})
			admin.GET("/stats", func(c *gin.Context) {
				// TODO: 实现统计信息
				util.Success(c, gin.H{
					"online_users": 0,
					"total_rooms":  0,
					"total_messages": 0,
				})
			})
		}
		
		// QQ 机器人 Webhook
		apiV1.POST("/webhook/qq", func(c *gin.Context) {
			// TODO: 实现 QQ 机器人 Webhook
			util.Success(c, nil)
		})
	}
	
	// WebSocket 路由
	router.GET("/ws", func(c *gin.Context) {
		// 从 query 参数获取 token
		tokenString := c.Query("token")
		if tokenString == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
			return
		}
		
		claims, err := jwt.ParseToken(tokenString)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
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
