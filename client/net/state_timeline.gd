class_name StateTimeline
extends RefCounted
## Discrete replicated state (flag bits, counters) put on the server timeline,
## so its changes play out when the client's render time reaches them, in
## step with the interpolated position. A ship that dies then disappears where
## it is drawn touching the rock, not when the packet arrived.
##
## push() each value with the net_time of the snapshot that carried it (send
## it with every snapshot, after net_time: PlayerNet's extra_synced). Repeats
## are dropped. advance() reports each change once render time passes it. The
## first value is a baseline, not a change: a late joiner seeing a ship that
## is already dead, or has already collected pickups, gets no effects for it.

var _times: PackedFloat64Array = PackedFloat64Array()
var _values: PackedInt64Array = PackedInt64Array()
var _last_pushed: int = 0
var _pushed_any: bool = false
var _current: int = 0
var _has_current: bool = false


func _init(initial: int = 0) -> void:
	_current = initial


func push(server_time: float, value: int) -> void:
	if _pushed_any and value == _last_pushed:
		return
	_pushed_any = true
	_last_pushed = value
	if not _times.is_empty():
		server_time = maxf(server_time, _times[_times.size() - 1])
	_times.append(server_time)
	_values.append(value)


## Releases every value stamped at or before `render_time`, calling
## `on_change(before: int, after: int, at: float)` for each real change.
func advance(render_time: float, on_change: Callable) -> void:
	while not _times.is_empty() and _times[0] <= render_time:
		var at: float = _times[0]
		var v: int = _values[0]
		_times.remove_at(0)
		_values.remove_at(0)
		if not _has_current:
			_has_current = true
			_current = v
			continue
		if v != _current:
			var before: int = _current
			_current = v
			on_change.call(before, v, at)


## The value as of the last advance() (the initial value until then).
func current() -> int:
	return _current
