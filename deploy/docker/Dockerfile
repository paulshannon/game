# Dedicated game server image: just the exported server binary (pck embedded)
# on a slim base. Built from the binary CI already exported and smoke-tested,
# never re-exported here, so the image holds exactly the tested artifact.
#
#   tools/export.sh server
#   docker build -f deploy/docker/Dockerfile -t game-server .
#   docker run --rm -p 9080:9080 -e GAME=2d game-server
#
# The build context is the repo root, but .dockerignore admits only the
# server binary and this folder.
FROM debian:bookworm-slim

# Non-root, fixed UID, and a writable HOME: Godot creates user:// (logs,
# future saves) under $HOME/.local/share at startup, and 4.7.1 segfaults if
# it can't (see #3).
RUN useradd --system --uid 10001 --user-group --home-dir /data --create-home \
	--shell /usr/sbin/nologin game
ENV HOME=/data \
	GAME=2d \
	PORT=9080
VOLUME /data

COPY --chmod=755 build/server/server.x86_64 /app/server.x86_64
COPY --chmod=755 deploy/docker/entrypoint.sh /app/entrypoint.sh

USER 10001:10001
WORKDIR /data
EXPOSE 9080

# A TCP connect is enough to prove the server is listening; no WebSocket
# client needed.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
	CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/"$PORT"' || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]

ARG VERSION=dev
ARG REVISION=unknown
LABEL org.opencontainers.image.title="game-server" \
	org.opencontainers.image.description="Headless Godot 4.7 dedicated server for the Kenney multiplayer prototypes (GAME=2d|3d|space)" \
	org.opencontainers.image.source="https://github.com/paulshannon/game" \
	org.opencontainers.image.version="$VERSION" \
	org.opencontainers.image.revision="$REVISION"
