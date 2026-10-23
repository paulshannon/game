class_name SnapshotClock
extends RefCounted
## Maps server snapshot timestamps onto the local clock, so snapshots are
## drawn at the pace the server produced them, not the pace they arrived.
##
## Why: WebSocket is TCP. After a stall, several queued snapshots arrive in
## the same frame. Stamped with arrival time they would sit ~0 s apart and the
## player would jump across all of them at once. Stamped with server time they
## keep their real spacing, and playback simply continues through them.
##
## offset = local arrival time - server send time. Its minimum over the last
## WINDOW snapshots is the least-delayed packet, i.e. latency without the
## jitter; late (stalled) packets have a larger offset and don't move it. The
## offset used for playback chases that minimum at a limited rate, so a
## latency change speeds playback up or slows it down slightly instead of
## jumping. Both clocks are monotonic; drift between them is tiny.
##
## One exception: when playback is more than SNAP_BEHIND further in the past
## than the best latency seen, it jumps forward instead. That happens when the
## first snapshots were held up (a client stalling while it loads art when the
## first players spawn): slewing out of a 2 s backlog would take 20 s, all of
## it drawn 2 s late. A stall can't trigger the jump: late packets only add
## larger offsets, never smaller ones.

const WINDOW: int = 40           # ~2 s of snapshots at 20 Hz
const MAX_SLEW: float = 0.1      # offset may change by at most 0.1 s per second
const SNAP_BEHIND: float = 0.5   # further behind than this: jump, don't slew

var _offsets: PackedFloat64Array = PackedFloat64Array()
var _offset: float = 0.0
var _last_local: float = 0.0
var _synced: bool = false


## Call once per received snapshot.
func observe(server_time: float, local_time: float) -> void:
	_offsets.append(local_time - server_time)
	if _offsets.size() > WINDOW:
		_offsets.remove_at(0)
	var target: float = _offsets[0]
	for o: float in _offsets:
		target = minf(target, o)
	if not _synced or _offset - target > SNAP_BEHIND:
		_offset = target
		_synced = true
	else:
		var max_step: float = maxf(local_time - _last_local, 0.0) * MAX_SLEW
		_offset = move_toward(_offset, target, max_step)
	_last_local = local_time


func is_synced() -> bool:
	return _synced


## Server time to draw at `local_time`: INTERP_DELAY behind the newest
## snapshot that arrived with the least delay.
func render_time(local_time: float) -> float:
	return local_time - _offset - Protocol.INTERP_DELAY
