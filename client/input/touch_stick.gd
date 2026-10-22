class_name TouchStick
extends RefCounted
## Floating virtual joystick: the stick's centre is wherever the finger first
## touched, and the knob follows the finger up to RADIUS away. value() is the
## offset scaled to length <= 1, so a half push is half speed. There is no
## dead zone here: the move actions apply InputSetup.STICK_DEADZONE, the same
## as for any analog input.

const RADIUS: float = 90.0  # canvas units (the viewport is 1280x720 before stretch)

var active: bool = false
var center: Vector2 = Vector2.ZERO
var knob: Vector2 = Vector2.ZERO


func press(pos: Vector2) -> void:
	active = true
	center = pos
	knob = pos


func drag(pos: Vector2) -> void:
	if active:
		knob = center + (pos - center).limit_length(RADIUS)


func release() -> void:
	active = false
	knob = center


## x: -1 left .. 1 right, y: -1 up .. 1 down (screen axes, like Input.get_vector).
func value() -> Vector2:
	if not active:
		return Vector2.ZERO
	return (knob - center) / RADIUS
