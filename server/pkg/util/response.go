package util

import (
	"github.com/gin-gonic/gin"
)

// Response 统一响应格式
type Response struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data"`
}

// Success 成功响应
func Success(c *gin.Context, data interface{}) {
	c.JSON(200, Response{
		Code:    20000,
		Message: "ok",
		Data:    data,
	})
}

// Error 错误响应
func Error(c *gin.Context, code int, message string) {
	c.JSON(200, Response{
		Code:    code,
		Message: message,
		Data:    nil,
	})
}

// ErrorWithStatus 带 HTTP 状态码的错误响应
func ErrorWithStatus(c *gin.Context, httpStatus, code int, message string) {
	c.JSON(httpStatus, Response{
		Code:    code,
		Message: message,
		Data:    nil,
	})
}
