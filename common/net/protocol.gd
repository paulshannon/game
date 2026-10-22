class_name Protocol
extends RefCounted
## Shared network constants. Client and server MUST agree on these, so they
## live in one place. Change them here, never inline in game scripts.

## One port per game so a single VPS can run both prototypes side by side.
const PORTS: Dictionary = {
	"2d": 9080,
	"3d": 9081,
}

## Server simulation runs on the physics tick (project setting: 60 Hz).
## Snapshots go out less often than that: at 20 Hz a client needs ~2
## snapshots inside its interpolation window, which hides WebSocket (TCP)
## jitter without sending 3x the bandwidth.
const SNAPSHOT_HZ: float = 20.0

## Clients send input at 30 Hz. Higher buys little on TCP; lower makes
## movement feel sticky.
const INPUT_HZ: float = 30.0

## Remote entities are drawn this far in the past so there are always two
## snapshots to interpolate between. Rule of thumb: 2 x snapshot interval.
const INTERP_DELAY: float = 0.1

## Server: input older than this counts as released (all keys up). Covers a
## backgrounded browser tab (it stops sending) and network stalls, so a held
## key can't keep a player running into a wall. Longer than a normal TCP
## hitch, so ordinary jitter never stops a moving player.
const INPUT_TIMEOUT: float = 0.25

## Server-side cap. WebSocket has no built-in connection limit.
const MAX_PLAYERS: int = 8


static func port_for(game: String) -> int:
	return int(PORTS.get(game, PORTS["2d"]))
