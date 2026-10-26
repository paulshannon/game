class_name BotInput
extends RefCounted
## Deterministic wandering input. Lets headless clients exercise the full
## input -> server sim -> snapshot -> interpolation loop in smoke tests.
## A game can give its players a smarter bot by subclassing this and setting
## InputRelay.bot (see SpaceBot).

var move: Vector2 = Vector2.ZERO
var jump: bool = false
var fire: bool = false
## -1 left .. 1 right (InputRelay.strafe).
var strafe: float = 0.0

var _rng := RandomNumberGenerator.new()
var _until_change: float = 0.0


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


func update(delta: float) -> void:
	_until_change -= delta
	jump = false
	if _until_change <= 0.0:
		_until_change = _rng.randf_range(0.6, 1.6)
		move = Vector2.from_angle(_rng.randf() * TAU)
		jump = _rng.randf() < 0.3
		fire = _rng.randf() < 0.5
