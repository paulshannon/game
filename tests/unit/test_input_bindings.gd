extends TestCase
## Remapping (InputBindings) and the Controls page (ControlsEditor). Both
## change the global InputMap, so every test puts the defaults back.

const PATH: String = "user://test_controls.cfg"
const GROUP: Array[StringName] = [InputSetup.LEFT, InputSetup.RIGHT, InputSetup.UP, InputSetup.DOWN, InputSetup.FIRE]


func _fresh() -> void:
	InputSetup.ensure_actions()
	InputBindings.reset(InputSetup.ACTIONS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _codes(action: StringName) -> Array[String]:
	var out: Array[String] = []
	for ev: InputEvent in InputBindings.get_bindings(action):
		out.append(InputBindings.encode(ev) if ev != null else "")
	return out


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = pressed
	return k


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.device = 3
	b.button_index = button
	b.pressed = true
	return b


func test_defaults_have_keys_and_controller() -> void:
	_fresh()
	assert_eq(_codes(InputSetup.LEFT), ["key:%d" % KEY_A, "key:%d" % KEY_LEFT, "axis:0:-1", "button:%d" % JOY_BUTTON_DPAD_LEFT])
	assert_eq(_codes(InputSetup.FIRE), ["key:%d" % KEY_SPACE, "", "button:%d" % JOY_BUTTON_A, "axis:%d:1" % JOY_AXIS_TRIGGER_RIGHT])
	assert_near(InputMap.action_get_deadzone(InputSetup.LEFT), InputSetup.STICK_DEADZONE)


func test_controller_drives_the_move_vector() -> void:
	_fresh()
	var m := InputEventJoypadMotion.new()
	m.device = 0
	m.axis = JOY_AXIS_LEFT_X
	m.axis_value = -0.6
	Input.parse_input_event(m)
	Input.flush_buffered_events()
	assert_near(Input.get_vector(InputSetup.LEFT, InputSetup.RIGHT, InputSetup.UP, InputSetup.DOWN).x, -0.5, 0.1)
	m.axis_value = 0.0
	Input.parse_input_event(m)
	Input.flush_buffered_events()


func test_assign_key_and_move_conflicts() -> void:
	_fresh()
	assert_true(InputBindings.assign(InputSetup.FIRE, 0, _key(KEY_D), GROUP))
	assert_eq(_codes(InputSetup.FIRE)[0], "key:%d" % KEY_D)
	assert_eq(_codes(InputSetup.RIGHT)[0], "key:%d" % KEY_RIGHT, "D taken from Turn right; its other key moves up")
	assert_eq(_codes(InputSetup.JUMP)[0], "key:%d" % KEY_SPACE, "actions outside the group keep their keys")


func test_assign_rejects_wrong_kind_and_non_presses() -> void:
	_fresh()
	assert_false(InputBindings.assign(InputSetup.FIRE, 2, _key(KEY_X), GROUP), "key in a controller slot")
	assert_false(InputBindings.assign(InputSetup.FIRE, 0, _pad(JOY_BUTTON_B), GROUP), "button in a key slot")
	assert_false(InputBindings.assign(InputSetup.FIRE, 0, _key(KEY_X, false), GROUP), "a release")
	var weak := InputEventJoypadMotion.new()
	weak.axis = JOY_AXIS_RIGHT_X
	weak.axis_value = 0.2
	assert_false(InputBindings.assign(InputSetup.FIRE, 2, weak, GROUP), "a stick barely moved")
	assert_false(InputBindings.assign(InputSetup.FIRE, 4, _key(KEY_X), GROUP), "no such slot")
	assert_eq(_codes(InputSetup.FIRE)[0], "key:%d" % KEY_SPACE)


func test_assign_controller_any_device() -> void:
	_fresh()
	assert_true(InputBindings.assign(InputSetup.FIRE, 2, _pad(JOY_BUTTON_RIGHT_SHOULDER), GROUP))
	var bound: InputEvent = InputBindings.get_bindings(InputSetup.FIRE)[2]
	assert_eq(bound.device, -1, "works on every controller")
	assert_eq(InputBindings.describe(bound), "RB")


func test_decode_rejects_garbage() -> void:
	for bad: String in ["", "key", "key:0", "key:x", "key:-5", "button:99", "axis:1:0", "axis:1:2", "axis:99:1", "mouse:1", "key:1:2", "button:1.5"]:
		assert_eq(InputBindings.decode(bad), null, bad)
	assert_eq(InputBindings.encode(InputBindings.decode("axis:3:-1")), "axis:3:-1")


func test_describe() -> void:
	assert_eq(InputBindings.describe(InputBindings.decode("key:%d" % KEY_W)), "W")
	assert_eq(InputBindings.describe(InputBindings.decode("key:%d" % KEY_SPACE)), "Space")
	assert_eq(InputBindings.describe(InputBindings.decode("axis:0:-1")), "L stick left")
	assert_eq(InputBindings.describe(InputBindings.decode("axis:%d:1" % JOY_AXIS_TRIGGER_RIGHT)), "RT")
	assert_eq(InputBindings.describe(InputBindings.decode("button:%d" % JOY_BUTTON_A)), "A")


func test_save_and_load_round_trip() -> void:
	_fresh()
	InputBindings.assign(InputSetup.UP, 1, _key(KEY_I), GROUP)
	InputBindings.assign(InputSetup.FIRE, 3, null, GROUP)
	assert_eq(InputBindings.save(PATH), OK)
	var saved: Array[String] = _codes(InputSetup.UP)
	InputBindings.reset(InputSetup.ACTIONS)
	assert_eq(_codes(InputSetup.UP)[1], "key:%d" % KEY_UP)
	InputBindings.load_saved(PATH)
	assert_eq(_codes(InputSetup.UP), saved)
	assert_eq(_codes(InputSetup.FIRE)[3], "", "a cleared slot stays cleared")
	_fresh()


func test_load_ignores_bad_entries() -> void:
	_fresh()
	var cfg := ConfigFile.new()
	cfg.set_value(InputBindings.SECTION, String(InputSetup.LEFT), "not a list")
	cfg.set_value(InputBindings.SECTION, String(InputSetup.FIRE),
			PackedStringArray(["button:0", "key:%d" % KEY_K, "key:%d" % KEY_J, "axis:9:9"]))
	cfg.save(PATH)
	InputBindings.load_saved(PATH)
	assert_eq(_codes(InputSetup.LEFT)[0], "key:%d" % KEY_A, "malformed entry keeps the defaults")
	assert_eq(_codes(InputSetup.FIRE), ["key:%d" % KEY_K, "", "", ""], "wrong-kind and bad slots dropped")
	InputBindings.load_saved("user://does_not_exist.cfg")  # never remapped: no error
	_fresh()


func test_editor_captures_saves_and_cancels() -> void:
	_fresh()
	var e := ControlsEditor.new({InputSetup.FIRE: "Fire", InputSetup.RIGHT: "Turn right"}, "", PATH)
	var fire_key: Button = e.get_node("Grid/fire_0")
	assert_eq(fire_key.text, "Space")
	fire_key.pressed.emit()
	assert_eq(fire_key.text, ControlsEditor.KEY_PROMPT)
	assert_true(e.handle_capture(_pad(JOY_BUTTON_X)), "wrong kind is swallowed while waiting")
	assert_true(e.is_capturing())
	assert_true(e.handle_capture(_key(KEY_D)))
	assert_false(e.is_capturing())
	assert_eq(fire_key.text, "D")
	assert_eq((e.get_node("Grid/move_right_0") as Button).text, "Right", "conflict moved")
	assert_true(FileAccess.file_exists(PATH), "saved straight away")

	(e.get_node("Grid/fire_2") as Button).pressed.emit()
	assert_eq((e.get_node("Grid/fire_2") as Button).text, ControlsEditor.PAD_PROMPT)
	assert_true(e.handle_capture(_key(KEY_ESCAPE)))
	assert_false(e.is_capturing())
	assert_eq((e.get_node("Grid/fire_2") as Button).text, "A")

	(e.get_node("Bar/Reset") as Button).pressed.emit()
	assert_eq(fire_key.text, "Space")
	var closed: Array[bool] = [false]
	e.closed.connect(func() -> void: closed[0] = true)
	(e.get_node("Bar/Back") as Button).pressed.emit()
	assert_true(closed[0])
	e.free()
	_fresh()


func test_menu_defaults_to_escape_and_start() -> void:
	var slots: Array[InputEvent] = InputSetup.default_bindings(InputSetup.MENU)
	assert_eq((slots[0] as InputEventKey).physical_keycode, KEY_ESCAPE)
	assert_eq((slots[2] as InputEventJoypadButton).button_index, JOY_BUTTON_START)


func test_strafe_defaults_to_q_e_and_shoulders() -> void:
	var left: Array[InputEvent] = InputSetup.default_bindings(InputSetup.STRAFE_LEFT)
	var right: Array[InputEvent] = InputSetup.default_bindings(InputSetup.STRAFE_RIGHT)
	assert_eq((left[0] as InputEventKey).physical_keycode, KEY_Q)
	assert_eq((right[0] as InputEventKey).physical_keycode, KEY_E)
	assert_eq((left[2] as InputEventJoypadButton).button_index, JOY_BUTTON_LEFT_SHOULDER)
	assert_eq((right[3] as InputEventJoypadMotion).axis, JOY_AXIS_RIGHT_X)
