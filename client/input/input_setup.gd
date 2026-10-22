class_name InputSetup
extends RefCounted
## Registers input actions in code. The [input] section of project.godot is
## serialized InputEvent objects that are easy to corrupt by hand-editing;
## defining them here keeps them reviewable and diff-friendly.

const LEFT: StringName = &"move_left"
const RIGHT: StringName = &"move_right"
const UP: StringName = &"move_up"
const DOWN: StringName = &"move_down"
const JUMP: StringName = &"jump"

## Analog dead zone for the move actions. Keys always press at full
## strength, so this only matters for analog input (TouchControls' stick).
## The engine default (0.5) would ignore half the stick's travel.
const STICK_DEADZONE: float = 0.2


static func ensure_actions() -> void:
	_bind(LEFT, [KEY_A, KEY_LEFT], STICK_DEADZONE)
	_bind(RIGHT, [KEY_D, KEY_RIGHT], STICK_DEADZONE)
	_bind(UP, [KEY_W, KEY_UP], STICK_DEADZONE)
	_bind(DOWN, [KEY_S, KEY_DOWN], STICK_DEADZONE)
	_bind(JUMP, [KEY_SPACE])


static func _bind(action: StringName, keys: Array[Key], deadzone: float = 0.5) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, deadzone)
	for key: Key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key  # layout-independent: WASD stays WASD on AZERTY
		InputMap.action_add_event(action, ev)
