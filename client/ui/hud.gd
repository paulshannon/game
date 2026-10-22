class_name Hud
extends CanvasLayer
## Connection status + the join button: the web "click to join" gate, and
## "Rejoin" / "Try again" after the connection is lost or fails.
##
## Browsers only allow audio after a user gesture, so web builds wait for a
## click before connecting. That same click is a natural "ready" moment.

var _status: Label
var _start: Button
var _on_press: Callable


func _ready() -> void:
	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.add_theme_font_size_override("font_size", 18)
	add_child(_status)

	# A full-rect CenterContainer keeps the button centred at any window size
	# (anchoring the button itself centres its top-left corner, not the button).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_start = Button.new()
	_start.text = "Click to join"
	_start.add_theme_font_size_override("font_size", 28)
	_start.custom_minimum_size = Vector2(320, 80)
	_start.visible = false
	_start.pressed.connect(_pressed)
	center.add_child(_start)


func set_status(text: String) -> void:
	_status.text = text


## Shows the button; one press hides it and calls `on_press`. Can be shown
## again any number of times (each call replaces the callback).
func show_start(on_press: Callable, text: String = "Click to join") -> void:
	_on_press = on_press
	_start.text = text
	_start.visible = true


func _pressed() -> void:
	_start.visible = false
	if _on_press.is_valid():
		_on_press.call()
