package jwt

import (
	"fmt"
	"time"
	
	"github.com/golang-jwt/jwt/v5"
	"nexusroom-server/internal/config"
)

type Claims struct {
	UserID    uint64 `json:"user_id"`
	Username  string `json:"username"`
	Role      string `json:"role"`
	jwt.RegisteredClaims
}

func GenerateToken(userID uint64, username, role string) (string, error) {
	cfg := config.GlobalConfig.Auth
	
	claims := Claims{
		UserID:   userID,
		Username: username,
		Role:     role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Duration(cfg.JWTExpireHours) * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(cfg.JWTSecret))
}

func ParseToken(tokenString string) (*Claims, error) {
	cfg := config.GlobalConfig.Auth
	
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return []byte(cfg.JWTSecret), nil
	})
	
	if err != nil {
		return nil, err
	}
	
	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}
	
	return nil, fmt.Errorf("invalid token")
}
