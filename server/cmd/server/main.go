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

	"nexusroom-server/internal/api"
	"nexusroom-server/internal/config"
	"nexusroom-server/internal/database"
	"nexusroom-server/internal/media/rtcplay"
	"nexusroom-server/internal/media/rtmp"
	mediastream "nexusroom-server/internal/media/stream"
	"nexusroom-server/internal/media/turnserver"
	"nexusroom-server/internal/media/voice"
	"nexusroom-server/internal/repository"
	"nexusroom-server/internal/wg"
	"nexusroom-server/internal/ws"
)

func main() {
	appCtx, cancelApp := context.WithCancel(context.Background())
	defer cancelApp()

	cfg, err := config.Load("config.yaml")
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}
	db, err := database.Open(cfg)
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}
	if sqlDB, sqlErr := db.DB(); sqlErr == nil {
		defer sqlDB.Close()
	}
	if err := database.Migrate(db); err != nil {
		log.Fatalf("Failed to migrate database: %v", err)
	}
	if err := database.Check(db); err != nil {
		log.Fatalf("Failed to validate database: %v", err)
	}

	userRepo := repository.NewUserRepository(db)
	roomRepo := repository.NewRoomRepository(db)
	msgRepo := repository.NewMessageRepository(db)
	ingressRepo := repository.NewIngressRepository(db)
	friendRepo := repository.NewFriendshipRepository(db)
	wgPeerRepo := repository.NewWGPeerRepository(db)

	wgCoordinator := wg.NewCoordinator(&cfg.WireGuard, wgPeerRepo)
	if err := wgCoordinator.InitInterface(); err != nil {
		log.Printf("WireGuard initialization failed; VLAN will use database-only mode: %v", err)
	}

	hub := ws.NewHub(msgRepo, roomRepo, userRepo)
	hub.SetWGCoordinator(wgCoordinator)
	iceServers := make([]ws.RTCICEServer, 0, 2)
	if cfg.Media.PublicIP != "" {
		iceServers = append(iceServers, ws.RTCICEServer{URLs: []string{fmt.Sprintf("stun:%s:%d", cfg.Media.PublicIP, cfg.Media.TURN.Port)}})
	}
	turnServer, turnErr := turnserver.Start(turnserver.Options{
		Enabled: cfg.Media.TURN.Enabled, PublicIP: cfg.Media.PublicIP, Port: cfg.Media.TURN.Port,
		Realm: cfg.Media.TURN.Realm, Username: cfg.Media.TURN.Username, Password: cfg.Media.TURN.Password,
		RelayPortMin: cfg.Media.TURN.RelayPortMin, RelayPortMax: cfg.Media.TURN.RelayPortMax,
	})
	if turnErr != nil {
		log.Printf("TURN is unavailable: %v", turnErr)
	} else if turnServer != nil {
		defer turnServer.Close()
		iceServers = append(iceServers, ws.RTCICEServer{
			URLs:     []string{fmt.Sprintf("turn:%s:%d?transport=udp", cfg.Media.PublicIP, cfg.Media.TURN.Port)},
			Username: cfg.Media.TURN.Username, Credential: cfg.Media.TURN.Password,
		})
	}
	hub.SetRTCClientConfig(ws.RTCClientConfig{ICEServers: iceServers})
	voiceEngine, err := voice.New(voice.Options{
		PublicIP: cfg.Media.PublicIP, UDPMin: cfg.Media.RTC.UDPPortMin,
		UDPMax: cfg.Media.RTC.UDPPortMax, Signal: hub.SendMediaSignal,
	})
	if err != nil {
		log.Fatalf("Failed to initialize voice SFU: %v", err)
	}
	hub.SetVoiceEngine(voiceEngine)
	defer voiceEngine.Close()
	go hub.Run()

	streamRegistry := mediastream.NewRegistry()
	playbackEngine, err := rtcplay.New(rtcplay.Options{
		PublicIP: cfg.Media.PublicIP, UDPMin: cfg.Media.RTC.UDPPortMin, UDPMax: cfg.Media.RTC.UDPPortMax,
	}, streamRegistry)
	if err != nil {
		log.Fatalf("Failed to initialize WebRTC playback: %v", err)
	}
	rtmpServer := rtmp.New(fmt.Sprintf(":%d", cfg.Media.RTMP.Port), streamRegistry,
		func(streamKey string) bool {
			if _, active := streamRegistry.Get(streamKey); active {
				return false
			}
			_, findErr := ingressRepo.FindByStreamKey(streamKey)
			return findErr == nil
		},
		func(streamKey string, active bool) {
			ingress, findErr := ingressRepo.FindByStreamKey(streamKey)
			if findErr != nil {
				return
			}
			if updateErr := ingressRepo.SetActive(ingress.ID, active); updateErr != nil {
				log.Printf("Failed to update ingress state: %v", updateErr)
			}
			hub.BroadcastToRoom(ingress.RoomID, ws.EventIngressUpdate, ws.IngressUpdatePayload{
				RoomID: ingress.RoomID, Action: "status_changed",
			}, 0)
		},
	)

	router := api.SetupRouter(
		cfg, userRepo, roomRepo, msgRepo, ingressRepo, friendRepo,
		wgCoordinator, hub, streamRegistry, playbackEngine,
	)
	httpServer := &http.Server{Addr: fmt.Sprintf(":%d", cfg.Server.Port), Handler: router}
	errors := make(chan error, 2)
	go func() {
		if runErr := rtmpServer.Run(appCtx); runErr != nil {
			errors <- fmt.Errorf("RTMP server: %w", runErr)
		}
	}()
	go func() {
		if runErr := httpServer.ListenAndServe(); runErr != nil && runErr != http.ErrServerClosed {
			errors <- fmt.Errorf("HTTP server: %w", runErr)
		}
	}()
	go startMessageCleanupJob(appCtx, msgRepo, cfg.Message.RetentionDays)

	log.Printf("NexusRoom started: HTTP=%d RTMP=%d RTC/UDP=%d-%d", cfg.Server.Port, cfg.Media.RTMP.Port, cfg.Media.RTC.UDPPortMin, cfg.Media.RTC.UDPPortMax)
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	select {
	case <-quit:
	case runErr := <-errors:
		log.Printf("Server stopped unexpectedly: %v", runErr)
	}

	log.Println("Shutting down NexusRoom...")
	cancelApp()
	_ = rtmpServer.Close()
	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelShutdown()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		log.Printf("HTTP shutdown failed: %v", err)
	}
	log.Println("NexusRoom exited")
}

func startMessageCleanupJob(ctx context.Context, msgRepo *repository.MessageRepository, retentionDays int) {
	if retentionDays <= 0 {
		return
	}
	if err := msgRepo.CleanupOldMessages(retentionDays); err != nil {
		log.Printf("Failed to clean old messages: %v", err)
	}
	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := msgRepo.CleanupOldMessages(retentionDays); err != nil {
				log.Printf("Failed to clean old messages: %v", err)
			}
		}
	}
}
