class_name ArenaSim
extends RefCounted
## Pure movement rules. No nodes, no rendering, no networking — so the server
## can run them, tests can call them directly, and a future client-side
## prediction step can reuse exactly the same code.


class State2D:
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO


class State3D:
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var on_floor: bool = true


const SPEED_2D: float = 320.0
const ACCEL_2D: float = 2400.0
const BOUNDS_2D := Rect2(-600.0, -320.0, 1200.0, 640.0)

const SPEED_3D: float = 6.0
const ACCEL_3D: float = 40.0
const GRAVITY_3D: float = 24.0
const JUMP_SPEED_3D: float = 9.0
const HALF_EXTENT_3D: float = 14.0


## Clients can send anything: NaN, infinities, huge vectors. Clamp before use.
static func sanitize_move(m: Vector2) -> Vector2:
	if not m.is_finite():
		return Vector2.ZERO
	return m.limit_length(1.0)


static func step_2d(s: State2D, move: Vector2, delta: float) -> void:
	var target: Vector2 = sanitize_move(move) * SPEED_2D
	s.velocity = s.velocity.move_toward(target, ACCEL_2D * delta)
	s.position += s.velocity * delta
	var clamped := Vector2(
			clampf(s.position.x, BOUNDS_2D.position.x, BOUNDS_2D.end.x),
			clampf(s.position.y, BOUNDS_2D.position.y, BOUNDS_2D.end.y))
	# Kill velocity into a wall so players don't "stick" accelerating into it.
	if clamped.x != s.position.x:
		s.velocity.x = 0.0
	if clamped.y != s.position.y:
		s.velocity.y = 0.0
	s.position = clamped


## move.x -> world X, move.y -> world Z (screen "down" is toward the camera).
static func step_3d(s: State3D, move: Vector2, jump: bool, delta: float) -> void:
	var m: Vector2 = sanitize_move(move)
	var target := Vector3(m.x, 0.0, m.y) * SPEED_3D
	var horizontal := Vector3(s.velocity.x, 0.0, s.velocity.z).move_toward(target, ACCEL_3D * delta)
	s.velocity.x = horizontal.x
	s.velocity.z = horizontal.z

	if s.on_floor and jump:
		s.velocity.y = JUMP_SPEED_3D
		s.on_floor = false
	if not s.on_floor:
		s.velocity.y -= GRAVITY_3D * delta

	s.position += s.velocity * delta
	if s.position.y <= 0.0:
		s.position.y = 0.0
		s.velocity.y = 0.0
		s.on_floor = true

	s.position.x = clampf(s.position.x, -HALF_EXTENT_3D, HALF_EXTENT_3D)
	s.position.z = clampf(s.position.z, -HALF_EXTENT_3D, HALF_EXTENT_3D)


## Facing derived from horizontal velocity; keeps previous facing when still.
static func facing_from_velocity(v: Vector3, previous: Quaternion) -> Quaternion:
	var flat := Vector2(v.x, v.z)
	if flat.length_squared() < 0.01:
		return previous
	return Quaternion(Vector3.UP, atan2(v.x, v.z))
