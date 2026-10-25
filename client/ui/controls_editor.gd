class_name ControlsEditor
extends VBoxContainer
## Settings page for remapping controls: one row per action, two keyboard
## slots and two controller slots each, plus Reset and Back. Click (or
## Enter / gamepad A on) a slot, then press the new key or button, or push a
## stick or trigger; Escape or a click cancels. Every change is saved
## straight away (InputBindings).
##
## Generic: a game's menu puts it in its own panel and theme, with the game's
## names for the actions (GameBase.control_names()).

signal closed()

const EMPTY: String = "-"
const KEY_PROMPT: String = "Press a key..."
const PAD_PROMPT: String = "Press a button..."
const HINT: String = "Pick a slot, then press the new key or button. Esc cancels."
const SLOT_HEADERS: Array[String] = ["Key", "Alt key", "Controller", "Alt"]

## action -> label, in display order.
var names: Dictionary
## Extra line under the table (e.g. how the touch controls work).
var note: String
var save_path: String

## Button per slot: _slots[row][slot].
var _slots: Array[Array] = []
var _actions: Array[StringName] = []
var _capture_row: int = -1
var _capture_slot: int = -1


func _init(action_names: Dictionary, note_text: String = "", path: String = InputBindings.PATH) -> void:
	names = action_names
	note = note_text
	save_path = path
	for a: StringName in names:
		_actions.append(a)
	_build()


## Built on construction (not in _ready) so the parent menu can lay it out,
## and tests can use it, before it's in a tree.
func _build() -> void:
	add_theme_constant_override("separation", 16)
	var hint := _label(HINT)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 1 + InputSetup.SLOT_COUNT
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	grid.add_child(_label(""))
	for h: String in SLOT_HEADERS:
		var l := _label(h)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(l)
	for row: int in _actions.size():
		grid.add_child(_label(String(names[_actions[row]])))
		var buttons: Array[Button] = []
		for slot: int in InputSetup.SLOT_COUNT:
			var b := Button.new()
			b.name = "%s_%d" % [_actions[row], slot]
			b.custom_minimum_size = Vector2(200, 44)
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(start_capture.bind(row, slot))
			grid.add_child(b)
			buttons.append(b)
		_slots.append(buttons)

	if not note.is_empty():
		var n := _label(note)
		n.name = "Note"
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(n)

	var bar := HBoxContainer.new()
	bar.name = "Bar"
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	add_child(bar)
	bar.add_child(_bar_button("Reset", reset_defaults))
	bar.add_child(_bar_button("Back", close))
	refresh()


## Focus the first slot, so keyboard and controller users can start at once.
func focus_first() -> void:
	if not _slots.is_empty() and is_inside_tree():
		(_slots[0][0] as Button).grab_focus.call_deferred()


func refresh() -> void:
	for row: int in _actions.size():
		var bound: Array[InputEvent] = InputBindings.get_bindings(_actions[row])
		for slot: int in InputSetup.SLOT_COUNT:
			var b: Button = _slots[row][slot]
			if row == _capture_row and slot == _capture_slot:
				b.text = KEY_PROMPT if InputBindings.is_key_slot(slot) else PAD_PROMPT
			else:
				b.text = InputBindings.describe(bound[slot]) if bound[slot] != null else EMPTY


func is_capturing() -> bool:
	return _capture_row != -1


func start_capture(row: int, slot: int) -> void:
	_capture_row = row
	_capture_slot = slot
	refresh()


func cancel_capture() -> void:
	_capture_row = -1
	_capture_slot = -1
	refresh()


## Feeds one event to a running capture. Returns true if it was consumed.
## Separate from _input so tests can drive it without a viewport.
func handle_capture(event: InputEvent) -> bool:
	if not is_capturing():
		return false
	if event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			cancel_capture()
		return true
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		cancel_capture()
		return true
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return false
	if InputBindings.assign(_actions[_capture_row], _capture_slot, event, _actions):
		InputBindings.save(save_path)
		cancel_capture()
	return true  # swallow releases and stray input while waiting


func reset_defaults() -> void:
	InputBindings.reset(_actions)
	InputBindings.save(save_path)
	cancel_capture()


func close() -> void:
	cancel_capture()
	closed.emit()


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and handle_capture(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _bar_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = text
	b.text = text
	b.custom_minimum_size = Vector2(200, 56)
	b.pressed.connect(on_press)
	return b
