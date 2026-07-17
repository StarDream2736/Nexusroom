FROM golang:1.25-alpine AS builder

ARG GOPROXY=https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY}
WORKDIR /src
RUN apk add --no-cache gcc git musl-dev
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=1 \
    CGO_CFLAGS="-D_LARGEFILE64_SOURCE -D_GNU_SOURCE" \
    GOOS=linux \
    go build -trimpath -ldflags="-s -w" -o /out/nexusroom ./cmd/server

FROM alpine:3.22
WORKDIR /app
RUN apk add --no-cache ca-certificates iproute2 iptables wireguard-go wireguard-tools \
    && mkdir -p /app/data/uploads
COPY --from=builder /out/nexusroom /app/nexusroom
EXPOSE 8080 1935 3478/udp 50000-50050/udp 51000-51100/udp 51820/udp
ENTRYPOINT ["/app/nexusroom"]
