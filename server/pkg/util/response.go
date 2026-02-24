package util

import (
	"net/http"

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
	c.JSON(http.StatusOK, Response{
		Code:    20000,
		Message: "ok",
		Data:    data,
	})
}

// mapCodeToHTTPStatus 根据业务错误码映射 HTTP 状态码
func mapCodeToHTTPStatus(code int) int {
	switch {
	case code == 20000:
		return http.StatusOK
	case code >= 40001 && code < 40100:
		return http.StatusBadRequest // 400 参数校验失败
	case code >= 40101 && code < 40300:
		return http.StatusUnauthorized // 401 未登录或 Token 过期
	case code >= 40301 && code < 40400:
		return http.StatusForbidden // 403 权限不足
	case code >= 40401 && code < 40900:
		return http.StatusNotFound // 404 资源不存在
	case code >= 40901 && code < 50000:
		return http.StatusConflict // 409 资源冲突
	case code >= 50001:
		return http.StatusInternalServerError // 500 服务内部错误
	default:
		return http.StatusInternalServerError
	}
}

// Error 错误响应，自动根据错误码映射 HTTP 状态码
func Error(c *gin.Context, code int, message string) {
	c.JSON(mapCodeToHTTPStatus(code), Response{
		Code:    code,
		Message: message,
		Data:    nil,
	})
}

// ErrorWithStatus 带 HTTP 状态码的错误响应（用于需要显式指定 HTTP 状态码的场景）
func ErrorWithStatus(c *gin.Context, httpStatus, code int, message string) {
	c.JSON(httpStatus, Response{
		Code:    code,
		Message: message,
		Data:    nil,
	})
}
