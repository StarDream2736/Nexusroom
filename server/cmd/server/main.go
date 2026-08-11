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
	"nexusroom-server/internal/network/publicip"
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
	publicIPv4, err := publicip.New(publicip.Options{
		ManualIP:        cfg.Media.PublicIP,
		Enabled:         cfg.Media.PublicIPDiscovery.Enabled,
		RefreshInterval: time.Duration(cfg.Media.PublicIPDiscovery.RefreshIntervalSeconds) * time.Second,
		STUNServers:     cfg.Media.PublicIPDiscovery.STUNServers,
		OnChange: func(previous, current string) {
			if previous == "" {
				log.Printf("[Network] Public IPv4 discovered: %s", current)
				return
			}
			log.Printf("[Network] Public IPv4 changed: %s -> %s; new RTC sessions will use the new address", previous, current)
		},
	})
	if err != nil {
		log.Fatalf("Failed to configure public IPv4: %v", err)
	}
	discoveryCtx, cancelDiscovery := context.WithTimeout(appCtx, 8*time.Second)
	if err := publicIPv4.Refresh(discoveryCtx); err != nil && publicIPv4.Automatic() {
		log.Printf("[Network] Public IPv4 is not available yet: %v", err)
	}
	cancelDiscovery()
	go publicIPv4.Run(appCtx, func(err error) {
		log.Printf("[Network] Public IPv4 refresh failed; keeping %q: %v", publicIPv4.Current(), err)
	})

	wgCoordinator := wg.NewCoordinator(&cfg.WireGuard, wgPeerRepo)
	if err := wgCoordinator.InitInterface(); err != nil {
		log.Printf("WireGuard initialization failed; VLAN will use database-only mode: %v", err)
	}

	hub := ws.NewHub(msgRepo, roomRepo, userRepo)
	hub.SetWGCoordinator(wgCoordinator)
	turnServer, turnErr := turnserver.Start(turnserver.Options{
		Enabled: cfg.Media.TURN.Enabled, PublicIPProvider: publicIPv4.Current, Port: cfg.Media.TURN.Port,
		Realm: cfg.Media.TURN.Realm, Username: cfg.Media.TURN.Username, Password: cfg.Media.TURN.Password,
		RelayPortMin: cfg.Media.TURN.RelayPortMin, RelayPortMax: cfg.Media.TURN.RelayPortMax,
	})
	if turnErr != nil {
		log.Printf("TURN is unavailable: %v", turnErr)
	} else if turnServer != nil {
		defer turnServer.Close()
	}
	hub.SetRTCClientConfigProvider(func() ws.RTCClientConfig {
		return buildRTCClientConfig(publicIPv4.Current(), cfg, turnServer != nil)
	})
	voiceEngine, err := voice.New(voice.Options{
		PublicIPProvider: publicIPv4.Current, UDPMin: cfg.Media.RTC.UDPPortMin,
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
		PublicIPProvider: publicIPv4.Current, UDPMin: cfg.Media.RTC.UDPPortMin, UDPMax: cfg.Media.RTC.UDPPortMax,
	}, streamRegistry)
	if err != nil {
		log.Fatalf("Failed to initialize WebRTC playback: %v", err)
	}
	rtmpServer := rtmp.New(fmt.Sprintf(":%d", cfg.Media.RTMP.Port), streamRegistry, cfg.Media.RTC.FFmpegPath,
		newRTMPAuthorizer(cfg.Media.RTMP.AllowTemporaryStreams, streamRegistry, ingressRepo),
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

func buildRTCClientConfig(publicIPv4 string, cfg *config.Config, turnAvailable bool) ws.RTCClientConfig {
	if publicIPv4 == "" {
		return ws.RTCClientConfig{}
	}
	iceServers := []ws.RTCICEServer{{URLs: []string{fmt.Sprintf("stun:%s:%d", publicIPv4, cfg.Media.TURN.Port)}}}
	if turnAvailable {
		iceServers = append(iceServers, ws.RTCICEServer{
			URLs:       []string{fmt.Sprintf("turn:%s:%d?transport=udp", publicIPv4, cfg.Media.TURN.Port)},
			Username:   cfg.Media.TURN.Username,
			Credential: cfg.Media.TURN.Password,
		})
	}
	return ws.RTCClientConfig{ICEServers: iceServers}
}

type streamKeyLookup interface {
	ExistsByStreamKey(streamKey string) (bool, error)
}

func newRTMPAuthorizer(allowTemporary bool, streams *mediastream.Registry, lookup streamKeyLookup) rtmp.AuthorizeFunc {
	return func(streamKey string) bool {
		if _, active := streams.Get(streamKey); active {
			return false
		}
		exists, err := lookup.ExistsByStreamKey(streamKey)
		if err != nil {
			log.Printf("Failed to authorize RTMP stream key: %v", err)
			return false
		}
		return exists || allowTemporary
	}
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
