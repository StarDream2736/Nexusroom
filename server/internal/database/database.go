package database

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/model"
)

// Open initializes the embedded SQLite database used by NexusRoom.
// WAL keeps readers independent from the single SQLite writer while
// busy_timeout gives short concurrent writes time to complete.
func Open(cfg *config.Config) (*gorm.DB, error) {
	path := filepath.Clean(cfg.GetDatabasePath())
	dir := filepath.Dir(path)
	if dir != "." {
		if err := os.MkdirAll(dir, 0o750); err != nil {
			return nil, fmt.Errorf("create database directory: %w", err)
		}
	}

	logLevel := logger.Silent
	if cfg.Server.Mode == "debug" {
		logLevel = logger.Info
	}

	separator := "?"
	if strings.Contains(path, "?") {
		separator = "&"
	}
	dsn := path + separator + "_journal_mode=WAL&_busy_timeout=5000&_foreign_keys=on&_synchronous=NORMAL"
	db, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
	})
	if err != nil {
		return nil, fmt.Errorf("open sqlite database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("get sqlite connection: %w", err)
	}
	sqlDB.SetMaxOpenConns(4)
	sqlDB.SetMaxIdleConns(4)

	return db, nil
}

func Migrate(db *gorm.DB) error {
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

func Check(db *gorm.DB) error {
	var integrity string
	if err := db.Raw("PRAGMA integrity_check").Scan(&integrity).Error; err != nil {
		return fmt.Errorf("run sqlite integrity check: %w", err)
	}
	if integrity != "ok" {
		return fmt.Errorf("sqlite integrity check failed: %s", integrity)
	}

	var violations int64
	if err := db.Raw("SELECT COUNT(*) FROM pragma_foreign_key_check").Scan(&violations).Error; err != nil {
		return fmt.Errorf("run sqlite foreign key check: %w", err)
	}
	if violations != 0 {
		return fmt.Errorf("sqlite foreign key check found %d violation(s)", violations)
	}
	return nil
}
