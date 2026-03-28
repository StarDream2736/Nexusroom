FROM golang:1.22-alpine3.20 AS builder

ARG GOPROXY=https://goproxy.cn,direct
ARG GOSUMDB=sum.golang.google.cn
ENV GOPROXY=${GOPROXY}
ENV GOSUMDB=${GOSUMDB}

WORKDIR /app

RUN apk add --no-cache git

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o server cmd/server/main.go

FROM alpine:3.23.2

WORKDIR /app

RUN apk --no-cache add ca-certificates wireguard-tools wireguard-go iproute2 iptables

COPY --from=builder /app/server /app/server
COPY --from=builder /app/web /app/web

RUN mkdir -p /app/data

EXPOSE 8080 51820/udp

CMD ["./server"]
