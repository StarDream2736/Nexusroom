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

FROM alpine:3.22 AS ffmpeg-builder

ARG FFMPEG_VERSION=6.1.2
ARG FFMPEG_SHA256=3b624649725ecdc565c903ca6643d41f33bd49239922e45c9b1442c63dca4e38
RUN apk add --no-cache build-base curl nasm opus-dev pkgconf xz \
    && curl --retry 4 --retry-all-errors --retry-delay 2 -fsSLo /tmp/ffmpeg.tar.xz "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
    && echo "${FFMPEG_SHA256}  /tmp/ffmpeg.tar.xz" | sha256sum -c - \
    && mkdir /tmp/ffmpeg-src \
    && tar -xJf /tmp/ffmpeg.tar.xz -C /tmp/ffmpeg-src --strip-components=1
WORKDIR /tmp/ffmpeg-src
RUN ./configure \
      --prefix=/opt/ffmpeg \
      --disable-autodetect \
      --disable-doc \
      --disable-debug \
      --disable-avdevice \
      --disable-swscale \
      --disable-ffprobe \
      --disable-static \
      --enable-shared \
      --enable-small \
      --disable-everything \
      --enable-ffmpeg \
      --enable-avcodec \
      --enable-avformat \
      --enable-avfilter \
      --enable-avutil \
      --enable-swresample \
      --enable-network \
      --enable-libopus \
      --enable-decoder=aac \
      --enable-encoder=libopus \
      --enable-demuxer=aac \
      --enable-muxer=rtp \
      --enable-parser=aac \
      --enable-filter=aformat,anull,aresample \
      --enable-protocol=pipe,rtp,udp \
      --extra-cflags="-Os" \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make install \
    && strip /opt/ffmpeg/bin/ffmpeg /opt/ffmpeg/lib/*.so.* \
    && rm -rf /opt/ffmpeg/include /opt/ffmpeg/lib/pkgconfig /opt/ffmpeg/share \
    && find /opt/ffmpeg/lib -type l -name '*.so' -delete \
    && cp COPYING.LGPLv2.1 /opt/ffmpeg/LICENSE

FROM alpine:3.22
WORKDIR /app
ENV LD_LIBRARY_PATH=/opt/ffmpeg/lib
RUN apk add --no-cache ca-certificates iproute2 iptables opus wireguard-go wireguard-tools \
    && mkdir -p /app/data/uploads
COPY --from=builder /out/nexusroom /app/nexusroom
COPY --from=ffmpeg-builder /opt/ffmpeg /opt/ffmpeg
RUN ln -s /opt/ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
EXPOSE 8080 1935 3478/udp 50000-50050/udp 51000-51100/udp 51820/udp
ENTRYPOINT ["/app/nexusroom"]
