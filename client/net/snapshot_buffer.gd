class_name SnapshotBuffer
extends RefCounted
## Stores timestamped snapshots of one value and samples between them.
##
## Why: snapshots arrive ~20 times a second and, over WebSocket/TCP, with
## uneven gaps. Drawing the newest value directly looks jerky. Instead we
## draw at (now - Protocol.INTERP_DELAY), which is almost always bracketed
## by two received snapshots, and blend between them.
##
## Supports Vector2, Vector3, Quaternion (slerp) and float (optionally as an
## angle, so 359° -> 1° turns 2°, not 358°).

const CAPACITY: int = 32

var _angular: bool = false
var _times: PackedFloat64Array = PackedFloat64Array()
var _values: Array = []


func _init(angular: bool = false) -> void:
	_angular = angular


func push(time: float, value: Variant) -> void:
	# Keep times monotonic; a snapshot can't arrive "before" the last one.
	if not _times.is_empty() and time <= _times[_times.size() - 1]:
		time = _times[_times.size() - 1] + 0.0001
	_times.append(time)
	_values.append(value)
	if _times.size() > CAPACITY:
		_times.remove_at(0)
		_values.remove_at(0)


func size() -> int:
	return _times.size()


func is_empty() -> bool:
	return _times.is_empty()


func clear() -> void:
	_times.clear()
	_values.clear()


## Returns null when empty. Before the first / after the last snapshot it
## holds the end value rather than extrapolating (extrapolation overshoots
## badly when a player stops).
func sample(time: float) -> Variant:
	var n: int = _times.size()
	if n == 0:
		return null
	if n == 1 or time <= _times[0]:
		return _values[0]
	if time >= _times[n - 1]:
		return _values[n - 1]
	var i: int = _times.bsearch(time, true) - 1
	i = clampi(i, 0, n - 2)
	var t0: float = _times[i]
	var t1: float = _times[i + 1]
	var w: float = (time - t0) / (t1 - t0)
	return _blend(_values[i], _values[i + 1], w)


func _blend(a: Variant, b: Variant, w: float) -> Variant:
	match typeof(a):
		TYPE_VECTOR2:
			return (a as Vector2).lerp(b as Vector2, w)
		TYPE_VECTOR3:
			return (a as Vector3).lerp(b as Vector3, w)
		TYPE_QUATERNION:
			return (a as Quaternion).slerp(b as Quaternion, w)
		TYPE_FLOAT:
			if _angular:
				return lerp_angle(float(a), float(b), w)
			return lerpf(float(a), float(b), w)
	return b
