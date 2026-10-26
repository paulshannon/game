class_name TouchControls
extends CanvasLayer
## On-screen controls for touch screens (iPad, phones): a floating joystick on
## the left half of the screen and, in games that have one, an action button
## (Jump, Fire: GameBase.action_button()) bottom-right, and a small Menu button
## top-left (InputSetup.MENU, which is Esc on a keyboard: back to select).
##
## They press the same input actions as the keyboard (InputSetup), with analog
## strength, so InputRelay's Input.get_vector() picks them up unchanged and the
## network protocol and server don't know touch exists. The server still
## sanitizes every move it receives.
##
## Multi-touch: each control tracks the finger (touch index) that started it,
## so moving and jumping (or firing) work at the same time.

const BUTTON_RADIUS: float = 64.0
## Action button centre, measured from the bottom-right corner of the screen.
const BUTTON_INSET := Vector2(120, 120)
## Menu button: below the HUD's status line, top-left.
const MENU_RADIUS: float = 34.0
const MENU_CENTER := Vector2(56, 96)

## Input action the button presses; empty for no button.
var action: StringName = &""

var _stick := TouchStick.new()
var _stick_index: int = -1
var _button_index: int = -1
var _menu_index: int = -1
## Draw the controls once we know the screen is touch (or after a first touch).
var _shown: bool = false
var _canvas: Control


func _init(button_action: StringName = &"") -> void:
	action = button_action
	layer = 5  # above the game, below nothing in particular; HUD buttons still get taps


func _ready() -> void:
	_shown = DisplayServer.is_touchscreen_available()
	_canvas = Control.new()
	_canvas.name = "TouchOverlay"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)


## Unhandled, so the HUD's join button (a Control) gets its tap first.
func _unhandled_input(event: InputEvent) -> void:
	if handle_event(event, get_viewport().get_visible_rect().size):
		get_viewport().set_input_as_handled()


## Applies one touch event to the controls. Returns true if it was ours.
## Separate from _unhandled_input so tests can drive it without a viewport.
func handle_event(event: InputEvent, view: Vector2) -> bool:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			return _touch_down(t.index, t.position, view)
		return _touch_up(t.index)  # also covers touches the OS cancelled
	if event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _stick_index:
			_stick.drag(d.position)
			_apply_stick()
			return true
	return false


func button_center(view: Vector2) -> Vector2:
	return view - BUTTON_INSET


## Lets go of everything: on focus loss / backgrounding the OS may never send
## the matching touch-up events, and a stuck action would keep the player
## moving. (The server's input timeout covers the time the tab is hidden; this
## covers coming back.)
func release_all() -> void:
	_stick_index = -1
	_stick.release()
	_apply_stick()
	if _button_index != -1:
		_button_index = -1
		Input.action_release(action)
	if _menu_index != -1:
		_menu_index = -1
		Input.action_release(InputSetup.MENU)
	_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, \
				NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_EXIT_TREE:
			release_all()


func _touch_down(index: int, pos: Vector2, view: Vector2) -> bool:
	_shown = true
	if _menu_index == -1 and pos.distance_to(MENU_CENTER) <= MENU_RADIUS:
		_menu_index = index
		Input.action_press(InputSetup.MENU)
		_redraw()
		return true
	if not action.is_empty() and _button_index == -1 \
			and pos.distance_to(button_center(view)) <= BUTTON_RADIUS:
		_button_index = index
		Input.action_press(action)
		_redraw()
		return true
	if _stick_index == -1 and pos.x < view.x * 0.5:
		_stick_index = index
		_stick.press(pos)
		_apply_stick()
		return true
	_redraw()  # first touch may have just revealed the controls
	return false


func _touch_up(index: int) -> bool:
	if index == _menu_index:
		_menu_index = -1
		Input.action_release(InputSetup.MENU)
		_redraw()
		return true
	if index == _button_index:
		_button_index = -1
		Input.action_release(action)
		_redraw()
		return true
	if index == _stick_index:
		_stick_index = -1
		_stick.release()
		_apply_stick()
		return true
	return false


func _apply_stick() -> void:
	var v: Vector2 = _stick.value()
	_set_action(InputSetup.LEFT, -v.x)
	_set_action(InputSetup.RIGHT, v.x)
	_set_action(InputSetup.UP, -v.y)
	_set_action(InputSetup.DOWN, v.y)
	_redraw()


static func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, minf(strength, 1.0))
	else:
		Input.action_release(action)


func _redraw() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _draw_controls() -> void:
	if not _shown:
		return
	var view: Vector2 = _canvas.size
	var base := Color(1, 1, 1, 0.12)
	var edge := Color(1, 1, 1, 0.35)
	if _stick.active:
		_canvas.draw_circle(_stick.center, TouchStick.RADIUS, base)
		_canvas.draw_arc(_stick.center, TouchStick.RADIUS, 0.0, TAU, 48, edge, 2.0)
		_canvas.draw_circle(_stick.knob, TouchStick.RADIUS * 0.4, Color(1, 1, 1, 0.45))
	else:
		# Resting hint where a left thumb naturally lands.
		var hint := Vector2(BUTTON_INSET.x, view.y - BUTTON_INSET.y)
		_canvas.draw_arc(hint, TouchStick.RADIUS, 0.0, TAU, 48, edge, 2.0)
	if not action.is_empty():
		_draw_button(button_center(view), BUTTON_RADIUS, InputSetup.label(action), 22, _button_index != -1)
	_draw_button(MENU_CENTER, MENU_RADIUS, "Menu", 15, _menu_index != -1)


func _draw_button(c: Vector2, radius: float, text: String, size: int, held: bool) -> void:
	_canvas.draw_circle(c, radius, Color(1, 1, 1, 0.35 if held else 0.15))
	_canvas.draw_arc(c, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
	var font: Font = ThemeDB.fallback_font
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_canvas.draw_string(font, c + Vector2(-w * 0.5, size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.8))
