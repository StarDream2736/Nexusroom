package handler

import (
	"fmt"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"nexusroom-server/internal/config"
	"nexusroom-server/internal/repository"
	"nexusroom-server/pkg/util"
)

// allowedExtensions 文件扩展名白名单
var allowedExtensions = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true,
	".mp4": true, ".webm": true, ".mp3": true, ".ogg": true, ".wav": true,
	".pdf": true, ".doc": true, ".docx": true, ".txt": true, ".zip": true,
}

type FileHandler struct {
	storagePath string
	maxSize     int64
	roomRepo    *repository.RoomRepository
}

func NewFileHandler(cfg *config.Config, roomRepo *repository.RoomRepository) *FileHandler {
	return &FileHandler{
		storagePath: cfg.Storage.Path,
		maxSize:     int64(cfg.Storage.MaxFileSizeMB) * 1024 * 1024,
		roomRepo:    roomRepo,
	}
}

func (h *FileHandler) Upload(c *gin.Context) {
	roomID, err := strconv.ParseUint(c.PostForm("room_id"), 10, 64)
	if err != nil || roomID == 0 {
		util.Error(c, 40001, "room_id 参数错误")
		return
	}

	userID := c.GetUint64("userID")
	if !h.roomRepo.IsMember(roomID, userID) {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "不是房间成员，无法上传文件")
		return
	}

	file, err := c.FormFile("file")
	if err != nil {
		util.Error(c, 40001, "文件不能为空")
		return
	}

	if h.maxSize > 0 && file.Size > h.maxSize {
		util.Error(c, 40001, "文件大小超出限制")
		return
	}

	// 检查扩展名白名单
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if !allowedExtensions[ext] {
		util.Error(c, 40001, "不支持的文件类型: "+ext)
		return
	}

	// 检查 MIME magic bytes
	f, err := file.Open()
	if err != nil {
		util.Error(c, 50001, "读取文件失败")
		return
	}
	defer f.Close()

	buf := make([]byte, 512)
	n, _ := f.Read(buf)
	detectedType := http.DetectContentType(buf[:n])
	// 拒绝可执行文件或脚本
	if strings.Contains(detectedType, "octet-stream") && !allowedExtensions[ext] {
		util.Error(c, 40001, "不支持的文件类型")
		return
	}

	if err := os.MkdirAll(h.storagePath, 0755); err != nil {
		util.Error(c, 50001, "创建存储目录失败")
		return
	}

	fileID := fmt.Sprintf("r%d_%s%s", roomID, uuid.NewString(), ext)

	fileDir := filepath.Join(h.storagePath, "private_files")
	if err := os.MkdirAll(fileDir, 0755); err != nil {
		util.Error(c, 50001, "创建文件目录失败")
		return
	}

	destPath := filepath.Join(fileDir, fileID)
	if err := c.SaveUploadedFile(file, destPath); err != nil {
		util.Error(c, 50001, "保存文件失败")
		return
	}

	util.Success(c, gin.H{
		"file_id":    fileID,
		"url":        "/api/v1/files/" + fileID,
		"mime_type":  detectedType,
		"size_bytes": file.Size,
		"file_name":  file.Filename,
	})
}

// GetByID GET /api/v1/files/:fileId
// 从 fileId 中解析 room_id，校验用户是房间成员后返回文件内容
func (h *FileHandler) GetByID(c *gin.Context) {
	fileID := c.Param("fileId")
	if fileID == "" {
		util.Error(c, 40001, "file_id 不能为空")
		return
	}

	parts := strings.SplitN(fileID, "_", 2)
	if len(parts) != 2 || !strings.HasPrefix(parts[0], "r") {
		util.Error(c, 40001, "file_id 格式错误")
		return
	}

	roomID, err := strconv.ParseUint(strings.TrimPrefix(parts[0], "r"), 10, 64)
	if err != nil || roomID == 0 {
		util.Error(c, 40001, "file_id 格式错误")
		return
	}

	userID := c.GetUint64("userID")
	if !h.roomRepo.IsMember(roomID, userID) {
		util.ErrorWithStatus(c, http.StatusForbidden, 40301, "无权访问该文件")
		return
	}

	fullPath := filepath.Join(h.storagePath, "private_files", fileID)
	if _, err := os.Stat(fullPath); err != nil {
		util.Error(c, 40401, "文件不存在")
		return
	}

	contentType := mime.TypeByExtension(strings.ToLower(filepath.Ext(fileID)))
	if contentType != "" {
		c.Header("Content-Type", contentType)
	}
	c.File(fullPath)
}
