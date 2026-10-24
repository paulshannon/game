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
## WINDOW seconds of server time is the least-delayed packet, i.e. latency without the
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
##
## The window is server time, not a packet count, so several players can share
## one clock (PlayerNet.use_clock): eight ships feeding it still filter jitter
## over the same 2 s, not 2 s / 8.

const WINDOW: float = 2.0        # seconds of server time
const MAX_SAMPLES: int = 1024    # memory bound, whatever the snapshot rate
const MAX_SLEW: float = 0.1      # offset may change by at most 0.1 s per second
const SNAP_BEHIND: float = 0.5   # further behind than this: jump, don't slew

var _times: PackedFloat64Array = PackedFloat64Array()     # server time of each sample
var _offsets: PackedFloat64Array = PackedFloat64Array()
var _newest: float = -INF
var _offset: float = 0.0
var _last_local: float = 0.0
var _synced: bool = false


## Call once per received snapshot.
func observe(server_time: float, local_time: float) -> void:
	_times.append(server_time)
	_offsets.append(local_time - server_time)
	_newest = maxf(_newest, server_time)
	while _offsets.size() > MAX_SAMPLES or (_offsets.size() > 1 and _times[0] < _newest - WINDOW):
		_times.remove_at(0)
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
