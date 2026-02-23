package middleware

import (
	"net/http"
	"strings"
	
	"github.com/gin-gonic/gin"
	"nexusroom-server/pkg/jwt"
)

func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"code":    40101,
				"message": "未登录或 Token 过期",
				"data":    nil,
			})
			c.Abort()
			return
		}
		
		parts := strings.SplitN(authHeader, " ", 2)
		if !(len(parts) == 2 && parts[0] == "Bearer") {
			c.JSON(http.StatusUnauthorized, gin.H{
				"code":    40101,
				"message": "Token 格式错误",
				"data":    nil,
			})
			c.Abort()
			return
		}
		
		claims, err := jwt.ParseToken(parts[1])
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{
				"code":    40101,
				"message": "Token 无效或已过期",
				"data":    nil,
			})
			c.Abort()
			return
		}
		
		// 将用户信息存入上下文
		c.Set("userID", claims.UserID)
		c.Set("username", claims.Username)
		c.Set("role", claims.Role)
		
		c.Next()
	}
}

func AdminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists || role != "super_admin" {
			c.JSON(http.StatusForbidden, gin.H{
				"code":    40302,
				"message": "超管权限不足",
				"data":    nil,
			})
			c.Abort()
			return
		}
		c.Next()
	}
}
