class_name InputBindings
extends RefCounted
## Player remapping of the InputSetup actions: read and change an action's
## binding slots, describe them for the UI, and save them to user:// (on the
## web that's the browser's IndexedDB, so it survives a reload).
##
## The InputMap itself holds the current bindings; this only rewrites it.
## Slots 0..KEY_SLOTS-1 take keys, the rest controller buttons or stick and
## trigger directions. An action's empty slots are compacted when read back.
##
## Saved format: one string per slot ("key:<physical keycode>",
## "button:<index>", "axis:<axis>:<+1|-1>", "" for empty), so a hand-edited
## or stale file can only ever produce plain key and joypad events.

const PATH: String = "user://controls.cfg"
const SECTION: String = "bindings"

## Stick or trigger travel that counts as choosing that direction.
const AXIS_PICK: float = 0.5

const _BUTTON_NAMES: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}


static func is_key_slot(slot: int) -> bool:
	return slot < InputSetup.KEY_SLOTS


## The action's slots (null = empty), read from the InputMap.
static func get_bindings(action: StringName) -> Array[InputEvent]:
	var keys: Array[InputEvent] = []
	var pads: Array[InputEvent] = []
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			keys.append(ev)
		elif ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			pads.append(ev)
	var out: Array[InputEvent] = []
	for i: int in InputSetup.KEY_SLOTS:
		out.append(keys[i] if i < keys.size() else null)
	for i: int in InputSetup.PAD_SLOTS:
		out.append(pads[i] if i < pads.size() else null)
	return out


## Replaces all of the action's events with `slots` (nulls skipped).
static func apply(action: StringName, slots: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for ev: InputEvent in slots:
		if ev != null:
			InputMap.action_add_event(action, ev)


## Binds `event` (raw, as captured) to one slot of `action`. The same input
## is first removed from every action in `group` (the actions one menu shows),
## so it can't do two things at once. A null event clears the slot. Returns
## false when the event can't go in that slot (a key in a controller slot, a
## mouse click, a stick barely moved).
static func assign(action: StringName, slot: int, event: InputEvent, group: Array[StringName]) -> bool:
	if slot < 0 or slot >= InputSetup.SLOT_COUNT:
		return false
	var ev: InputEvent = null
	if event != null:
		ev = normalize(event)
		if ev == null or (ev is InputEventKey) != is_key_slot(slot):
			return false
		var code: String = encode(ev)
		for other: StringName in group:
			var others: Array[InputEvent] = get_bindings(other)
			for i: int in others.size():
				if others[i] != null and encode(others[i]) == code:
					others[i] = null
			apply(other, others)
	var slots: Array[InputEvent] = get_bindings(action)
	slots[slot] = ev
	apply(action, slots)
	return true


## A clean, bindable copy of a captured press (any controller, full
## strength), or null if it isn't one.
static func normalize(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var k: InputEventKey = event
		var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if not k.pressed or k.echo or code == KEY_NONE:
			return null
		return decode("key:%d" % code)
	if event is InputEventJoypadButton:
		var b: InputEventJoypadButton = event
		return decode("button:%d" % b.button_index) if b.pressed else null
	if event is InputEventJoypadMotion:
		var m: InputEventJoypadMotion = event
		if absf(m.axis_value) < AXIS_PICK:
			return null
		return decode("axis:%d:%d" % [m.axis, 1 if m.axis_value > 0.0 else -1])
	return null


static func encode(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return "key:%d" % (ev as InputEventKey).physical_keycode
	if ev is InputEventJoypadButton:
		return "button:%d" % (ev as InputEventJoypadButton).button_index
	if ev is InputEventJoypadMotion:
		var m: InputEventJoypadMotion = ev
		return "axis:%d:%d" % [m.axis, 1 if m.axis_value > 0.0 else -1]
	return ""


## Parses one saved slot. Anything malformed or out of range is null.
static func decode(text: String) -> InputEvent:
	var parts: PackedStringArray = text.split(":")
	for p: String in parts.slice(1):
		if not p.is_valid_int():
			return null
	if parts[0] == "key" and parts.size() == 2:
		var code: int = parts[1].to_int()
		if code <= 0 or code >= KEY_SPECIAL * 2:
			return null
		var k := InputEventKey.new()
		k.physical_keycode = code as Key
		return k
	if parts[0] == "button" and parts.size() == 2:
		var index: int = parts[1].to_int()
		if index < 0 or index >= JOY_BUTTON_SDL_MAX:
			return null
		var b := InputEventJoypadButton.new()
		b.device = -1
		b.button_index = index as JoyButton
		return b
	if parts[0] == "axis" and parts.size() == 3:
		var axis: int = parts[1].to_int()
		var dir: int = parts[2].to_int()
		if axis < 0 or axis >= JOY_AXIS_SDL_MAX or absi(dir) != 1:
			return null
		var m := InputEventJoypadMotion.new()
		m.device = -1
		m.axis = axis as JoyAxis
		m.axis_value = float(dir)
		return m
	return null


## Short UI text for a binding: "W", "Space", "A", "L stick left", "RT".
static func describe(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	if ev is InputEventJoypadButton:
		var index: int = (ev as InputEventJoypadButton).button_index
		return _BUTTON_NAMES.get(index, "Button %d" % index)
	if ev is InputEventJoypadMotion:
		var m: InputEventJoypadMotion = ev
		var pos: bool = m.axis_value > 0.0
		match m.axis:
			JOY_AXIS_LEFT_X:
				return "L stick " + ("right" if pos else "left")
			JOY_AXIS_LEFT_Y:
				return "L stick " + ("down" if pos else "up")
			JOY_AXIS_RIGHT_X:
				return "R stick " + ("right" if pos else "left")
			JOY_AXIS_RIGHT_Y:
				return "R stick " + ("down" if pos else "up")
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
		return "Axis %d %s" % [m.axis, "+" if pos else "-"]
	return ""


static func reset(actions: Array[StringName]) -> void:
	for action: StringName in actions:
		apply(action, InputSetup.default_bindings(action))


static func save(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	for action: StringName in InputSetup.ACTIONS:
		var codes := PackedStringArray()
		for ev: InputEvent in get_bindings(action):
			codes.append(encode(ev) if ev != null else "")
		cfg.set_value(SECTION, String(action), codes)
	return cfg.save(path)


## Applies saved bindings over the defaults. A missing file is normal (never
## remapped); a missing, malformed or wrong-kind entry keeps that action's or
## slot's current binding empty or unchanged rather than failing.
static func load_saved(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for action: StringName in InputSetup.ACTIONS:
		if not cfg.has_section_key(SECTION, String(action)):
			continue
		var codes: Variant = cfg.get_value(SECTION, String(action))
		if not (codes is PackedStringArray) or (codes as PackedStringArray).size() != InputSetup.SLOT_COUNT:
			continue
		var slots: Array[InputEvent] = []
		for i: int in InputSetup.SLOT_COUNT:
			var ev: InputEvent = decode((codes as PackedStringArray)[i])
			slots.append(ev if ev != null and (ev is InputEventKey) == is_key_slot(i) else null)
		apply(action, slots)
