# 构建阶段
FROM golang:1.22-alpine3.20 AS builder

# Go module download settings for restricted networks
ARG GOPROXY=https://goproxy.cn,direct
ARG GOSUMDB=sum.golang.google.cn
ENV GOPROXY=${GOPROXY}
ENV GOSUMDB=${GOSUMDB}

WORKDIR /app

# 安装依赖
RUN apk add --no-cache git

# 复制依赖文件
COPY go.mod go.sum ./
RUN go mod download

# 复制源代码
COPY . .

# 构建
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o server cmd/server/main.go

# 运行阶段
FROM alpine:3.23.2

WORKDIR /app

# 安装 ca-certificates 用于 HTTPS
RUN apk --no-cache add ca-certificates

# 从构建阶段复制二进制文件
COPY --from=builder /app/server .

# 创建数据目录
RUN mkdir -p /app/data

# 暴露端口
EXPOSE 8080 51820/udp

# 运行
CMD ["./server"]
