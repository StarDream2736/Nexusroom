package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"nexusroom-server/internal/api"
	"nexusroom-server/internal/config"
	"nexusroom-server/internal/model"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/ws"
)

func main() {
	// 加载配置
	cfg, err := config.Load("config.yaml")
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// 连接数据库
	db, err := initDatabase(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// 自动迁移
	if err := autoMigrate(db); err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}

	// 连接 Redis
	redisClient := initRedis(cfg)
	defer redisClient.Close()

	// 初始化 Repository
	userRepo := repository.NewUserRepository(db)
	roomRepo := repository.NewRoomRepository(db)
	msgRepo := repository.NewMessageRepository(db)
	ingressRepo := repository.NewIngressRepository(db)
	friendRepo := repository.NewFriendshipRepository(db)
	wgPeerRepo := repository.NewWGPeerRepository(db)

	// 初始化 WebSocket Hub
	hub := ws.NewHub(msgRepo, roomRepo, userRepo)
	go hub.Run()

	// 设置路由
	ginRouter := api.SetupRouter(cfg, userRepo, roomRepo, msgRepo, ingressRepo, friendRepo, wgPeerRepo, hub)

	// 创建 HTTP 服务器
	srv := &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.Server.Port),
		Handler: ginRouter,
	}

	// 启动消息清理定时任务
	go startMessageCleanupJob(msgRepo, cfg.Message.RetentionDays)

	// 优雅关闭
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	log.Printf("Server started on port %d", cfg.Server.Port)

	// 等待中断信号
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}

func initDatabase(cfg *config.Config) (*gorm.DB, error) {
	logLevel := logger.Silent
	if cfg.Server.Mode == "debug" {
		logLevel = logger.Info
	}

	return gorm.Open(postgres.Open(cfg.GetDSN()), &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
	})
}

func initRedis(cfg *config.Config) *redis.Client {
	client := redis.NewClient(&redis.Options{
		Addr:     cfg.GetRedisAddr(),
		Password: cfg.Redis.Password,
		DB:       0,
	})

	// 测试连接
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		log.Printf("Warning: Failed to connect to Redis: %v", err)
	}

	return client
}

func autoMigrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&model.User{},
		&model.Room{},
		&model.RoomMember{},
		&model.Message{},
		&model.RoomIngress{},
		&model.Friendship{},
		&model.WGPeer{},
	)
}

func startMessageCleanupJob(msgRepo *repository.MessageRepository, retentionDays int) {
	if retentionDays <= 0 {
		return
	}

	// 每天执行一次
	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()

	// 首次执行
	if err := msgRepo.CleanupOldMessages(retentionDays); err != nil {
		log.Printf("Failed to cleanup old messages: %v", err)
	}

	for range ticker.C {
		if err := msgRepo.CleanupOldMessages(retentionDays); err != nil {
			log.Printf("Failed to cleanup old messages: %v", err)
		}
	}
}
