package handler

import (
	"os"
	"path/filepath"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"nexusroom-server/internal/config"
	"nexusroom-server/pkg/util"
)

type FileHandler struct {
	storagePath string
	maxSize     int64
}

func NewFileHandler(cfg *config.Config) *FileHandler {
	return &FileHandler{
		storagePath: cfg.Storage.Path,
		maxSize:     int64(cfg.Storage.MaxFileSizeMB) * 1024 * 1024,
	}
}

func (h *FileHandler) Upload(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		util.Error(c, 40001, "文件不能为空")
		return
	}

	if h.maxSize > 0 && file.Size > h.maxSize {
		util.Error(c, 40001, "文件大小超出限制")
		return
	}

	if err := os.MkdirAll(h.storagePath, 0755); err != nil {
		util.Error(c, 50001, "创建存储目录失败")
		return
	}

	mimeType := file.Header.Get("Content-Type")
	ext := filepath.Ext(file.Filename)
	fileName := uuid.NewString() + ext

	fileDir := filepath.Join(h.storagePath, "files")
	if err := os.MkdirAll(fileDir, 0755); err != nil {
		util.Error(c, 50001, "创建文件目录失败")
		return
	}

	destPath := filepath.Join(fileDir, fileName)
	if err := c.SaveUploadedFile(file, destPath); err != nil {
		util.Error(c, 50001, "保存文件失败")
		return
	}

	util.Success(c, gin.H{
		"file_id":    fileName,
		"url":        "/uploads/files/" + fileName,
		"mime_type":  mimeType,
		"size_bytes": file.Size,
	})
}
