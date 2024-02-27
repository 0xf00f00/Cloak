FROM golang:1.21 AS builder

RUN go version

WORKDIR /app

COPY ./ ./

RUN set -eux; \
	arch="$(dpkg --print-architecture)"; arch="${arch##*-}"; \
	case "$arch" in \
		'amd64') \
			export GOARCH='amd64' GOOS='linux'; \
			;; \
		'armhf') \
			export GOARCH='arm' GOARM='7' GOOS='linux'; \
			;; \
		'armel') \
			export GOARCH='arm' GOARM='5' GOOS='linux'; \
			;; \
		'arm64') \
			export GOARCH='arm64' GOOS='linux'; \
			;; \
		'i386') \
			export GOARCH='386' GOOS='linux'; \
			;; \
		'mips64el') \
			export GOARCH='mips64el' GOOS='linux'; \
			;; \
		'mips64') \
			export GOARCH='mips64' GOOS='linux'; \
			;; \
		'mips') \
			export GOARCH='mips' GOOS='linux'; \
			;; \
		'mips_softfloat') \
			export GOARCH='mips' GOMIPS='softfloat' GOOS='linux'; \
			;; \
		'mipsle') \
			export GOARCH='mipsle' GOOS='linux'; \
			;; \
		'mipsle_softfloat') \
			export GOARCH='mipsle' GOMIPS='softfloat' GOOS='linux'; \
			;; \
		*) echo >&2 "error: unsupported architecture '$arch' (likely packaging update needed)"; exit 1 ;; \
	esac; \
    \
    export GOCACHE='/tmp/gocache'; \
    \
    go get ./...; \
    \
    make; \
	\
	./build/ck-server -v; \
	./build/ck-client -v;

FROM debian:stable-slim

VOLUME [ "/data" ]

WORKDIR /usr/local/bin

COPY --from=builder /app/build/ck-server ./
COPY --from=builder /app/build/ck-client ./

COPY ./docker-entrypoint.sh ./
RUN chmod +x ./docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["ck-server"]