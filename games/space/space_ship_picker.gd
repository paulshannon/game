class_name SpaceShipPicker
extends VBoxContainer
## The ship, colour and bots picker on the space menu (SpaceMenu), above
## Play. The ship row has arrows and a preview; the colour and bots rows have
## arrows round a button that also cycles. Left/Right (keys, D-pad, stick)
## change the colour or bots while that button has the focus, and the ship
## otherwise, so Play can keep the focus. Picks are remembered in SAVE_PATH.
##
## Bots: how many the server flies (ServerBots). Only the first person into
## an empty match decides; everyone else's pick is ignored.

const SAVE_PATH: String = "user://space.cfg"
const AUTO_LABEL: String = "Colour: auto"
const MIDDLE_WIDTH: float = 290.0   # both rows, so their arrows line up

var hull: int = SpaceSim.FALCON
## An index into SpaceShip.COLORS, or SpaceShip.COLOR_AUTO (the seat's).
var color: int = SpaceShip.COLOR_AUTO
var bots: int = 0

var _save_path: String
var _art: TextureRect
var _name: Label
var _blurb: Label
var _color_button: Button
var _bots_button: Button


## `save_path`: where picks are remembered (tests use their own).
func _init(save_path: String = SAVE_PATH) -> void:
	_save_path = save_path
	name = "Picker"
	add_theme_constant_override("separation", 6)
	_load()

	var ship_row := _row("Ship", pick_hull)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(MIDDLE_WIDTH, 0)
	middle.add_theme_constant_override("separation", 4)
	ship_row.add_child(middle)
	ship_row.move_child(middle, 1)
	_art = TextureRect.new()
	_art.name = "Art"
	_art.custom_minimum_size = Vector2(0, 76)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	middle.add_child(_art)
	_name = Label.new()
	_name.name = "Name"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_name)
	_blurb = Label.new()
	_blurb.name = "Blurb"
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb.add_theme_font_size_override("font_size", 14)
	_blurb.add_theme_color_override("font_color", Color(SpaceUi.INK, 0.75))
	middle.add_child(_blurb)

	var color_row := _row("Colour", pick_color)
	_color_button = Button.new()
	_color_button.name = "Cycle"
	_color_button.custom_minimum_size = Vector2(MIDDLE_WIDTH, 56)
	_color_button.pressed.connect(pick_color.bind(1))
	color_row.add_child(_color_button)
	color_row.move_child(_color_button, 1)

	var bots_row := _row("Bots", pick_bots)
	_bots_button = Button.new()
	_bots_button.name = "Cycle"
	_bots_button.custom_minimum_size = Vector2(MIDDLE_WIDTH, 56)
	_bots_button.pressed.connect(pick_bots.bind(1))
	bots_row.add_child(_bots_button)
	bots_row.move_child(_bots_button, 1)
	var note := Label.new()
	note.name = "BotsNote"
	note.text = "Bots: set by the first player in"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(SpaceUi.INK, 0.75))
	add_child(note)
	_show()


## The join choice for GameBase.join_choice.
func choice() -> Dictionary:
	return {"hull": hull, "color": color, "bots": bots}


## Step through the hulls (wrapping round) and remember the pick.
func pick_hull(step: int) -> void:
	hull = posmod(hull + step, SpaceSim.HULLS.size())
	_changed()


## Step through auto and the colours (wrapping round).
func pick_color(step: int) -> void:
	var n: int = SpaceShip.COLORS.size() + 1   # + auto
	color = posmod(color - SpaceShip.COLOR_AUTO + step, n) + SpaceShip.COLOR_AUTO
	_changed()


## Step through 0..ServerBots.MAX_BOTS bots (wrapping round).
func pick_bots(step: int) -> void:
	bots = posmod(bots + step, ServerBots.MAX_BOTS + 1)
	_changed()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var step: int = 0
	if event.is_action_pressed("ui_left"):
		step = -1
	elif event.is_action_pressed("ui_right"):
		step = 1
	if step == 0:
		return
	if _color_button.has_focus():
		pick_color(step)
	elif _bots_button.has_focus():
		pick_bots(step)
	else:
		pick_hull(step)
	get_viewport().set_input_as_handled()


func _changed() -> void:
	_show()
	var cfg := ConfigFile.new()
	cfg.set_value("ship", "hull", hull)
	cfg.set_value("ship", "color", color)
	cfg.set_value("ship", "bots", bots)
	cfg.save(_save_path)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) != OK:
		return
	hull = SpaceSim.sanitize_hull(int(cfg.get_value("ship", "hull", SpaceSim.FALCON)))
	color = clampi(int(cfg.get_value("ship", "color", SpaceShip.COLOR_AUTO)),
			SpaceShip.COLOR_AUTO, SpaceShip.COLORS.size() - 1)
	bots = clampi(int(cfg.get_value("ship", "bots", 0)), 0, ServerBots.MAX_BOTS)


func _show() -> void:
	var h: Dictionary = SpaceSim.HULLS[hull]
	# Auto previews blue: the seat (and so the colour) is only known on joining.
	var shown: String = SpaceShip.COLORS[maxi(color, 0)]
	_art.texture = load(SpaceShip.hull_texture(hull, shown)) as Texture2D
	_art.flip_v = SpaceShip.hull_points_down(hull)
	_name.text = "%s  (%d/%d)" % [h["name"], hull + 1, SpaceSim.HULLS.size()]
	_blurb.text = str(h["blurb"])
	_color_button.text = AUTO_LABEL if color == SpaceShip.COLOR_AUTO else "Colour: " + shown
	_bots_button.text = "Bots: %d" % bots


## An HBox with arrows either side; the caller puts its middle in between.
func _row(row_name: String, on_step: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_arrow("<", on_step.bind(-1)))
	row.add_child(_arrow(">", on_step.bind(1)))
	add_child(row)
	return row


func _arrow(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = "Prev" if text == "<" else "Next"
	b.text = text
	b.custom_minimum_size = Vector2(56, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Kenney Future has no < or >: the engine's default font does.
	b.add_theme_font_override("font", ThemeDB.fallback_font)
	b.add_theme_font_size_override("font_size", 30)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b
