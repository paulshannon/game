#!/bin/sh
# Container entrypoint: one game server per container.
#   GAME  space | 2d | 3d   (default space)
#   PORT  listen port inside the container (default 9080, whatever the game;
#         map it to anything on the host)
# Extra arguments are passed to the server after its own, e.g.
#   docker run ... game-server --run-seconds=20 --expect-peers=2
#
# This shell stays PID 1 and forwards SIGTERM/SIGINT to the server: as PID 1
# the server itself would ignore SIGTERM, so `docker stop` would wait out its
# timeout and SIGKILL it. (Same job as tini, without installing anything.)
set -eu
/app/server.x86_64 --headless -- --server \
	--game="${GAME:-space}" --port="${PORT:-9080}" --bind=0.0.0.0 "$@" &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null' TERM INT
# The first wait returns early when a trapped signal arrives; wait again for
# the server to actually exit, and exit with its status.
set +e
wait "$pid"
status=$?
if kill -0 "$pid" 2>/dev/null; then
	wait "$pid"
	status=$?
fi
exit "$status"
