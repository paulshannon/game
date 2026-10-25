class_name InputSetup
extends RefCounted
## Registers input actions in code. The [input] section of project.godot is
## serialized InputEvent objects that are easy to corrupt by hand-editing;
## defining them here keeps them reviewable and diff-friendly.
##
## Each action has binding slots: KEY_SLOTS keyboard keys, then PAD_SLOTS
## controller inputs. Players can remap them (InputBindings); these are the
## defaults.

const LEFT: StringName = &"move_left"
const RIGHT: StringName = &"move_right"
const UP: StringName = &"move_up"
const DOWN: StringName = &"move_down"
const JUMP: StringName = &"jump"
const FIRE: StringName = &"fire"

const ACTIONS: Array[StringName] = [LEFT, RIGHT, UP, DOWN, JUMP, FIRE]
const MOVES: Array[StringName] = [LEFT, RIGHT, UP, DOWN]

const KEY_SLOTS: int = 2
const PAD_SLOTS: int = 2
const SLOT_COUNT: int = KEY_SLOTS + PAD_SLOTS

## Analog dead zone for the move actions. Keys always press at full
## strength, so this only matters for analog input (TouchControls' stick, a
## controller's stick). The engine default (0.5) would ignore half the
## stick's travel.
const STICK_DEADZONE: float = 0.2


static func ensure_actions() -> void:
	for action: StringName in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, STICK_DEADZONE if action in MOVES else 0.5)
		InputBindings.apply(action, default_bindings(action))


## The default slots for an action (null = empty): two keys, then two
## controller inputs. Fire and jump share Space and the A button: no game
## uses both, and each reads only its own action.
static func default_bindings(action: StringName) -> Array[InputEvent]:
	match action:
		LEFT:
			return [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0), _button(JOY_BUTTON_DPAD_LEFT)]
		RIGHT:
			return [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0), _button(JOY_BUTTON_DPAD_RIGHT)]
		UP:
			return [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0), _button(JOY_BUTTON_DPAD_UP)]
		DOWN:
			return [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0), _button(JOY_BUTTON_DPAD_DOWN)]
		JUMP:
			return [_key(KEY_SPACE), null, _button(JOY_BUTTON_A), null]
		FIRE:
			return [_key(KEY_SPACE), null, _button(JOY_BUTTON_A), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]
	return [null, null, null, null]


## Button text for an action: "jump" -> "Jump".
static func label(action: StringName) -> String:
	return String(action).capitalize()


static func _key(key: Key) -> InputEvent:
	var ev := InputEventKey.new()
	ev.physical_keycode = key  # layout-independent: WASD stays WASD on AZERTY
	return ev


static func _button(button: JoyButton) -> InputEvent:
	var ev := InputEventJoypadButton.new()
	ev.device = -1  # any controller
	ev.button_index = button
	return ev


static func _axis(axis: JoyAxis, direction: float) -> InputEvent:
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis
	ev.axis_value = direction
	return ev
