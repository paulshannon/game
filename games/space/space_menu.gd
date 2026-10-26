class_name SpaceMenu
extends GameMenu
## Main menu for the space game: star field, title, and a Kenney sci-fi panel
## with the ship picker, Play, Controls (remapping, ControlsEditor) and Quit
## (outside the browser, where quitting means nothing). After a lost connection main.gd
## shows it again with the reason and "Rejoin" / "Try again" on Play.

var _play: Button
var _status: Label
var _main_panel: PanelContainer
var _controls_panel: PanelContainer
var _controls: ControlsEditor
var _title: Label
var _credit: Label
var _control_names: Dictionary
var _touch_help: String
var _hull: int = SpaceSim.FALCON
var _ship_art: TextureRect
var _ship_name: Label
var _ship_blurb: Label

## The picked hull is remembered here between sessions.
const SAVE_PATH: String = "user://space.cfg"


## `control_names`: action -> label for the Controls page
## (GameBase.control_names()); `touch_help` is shown under it.
func _init(control_names: Dictionary = {}, touch_help: String = "") -> void:
	super._init()
	_control_names = control_names
	_touch_help = touch_help


func _ready() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = SpaceUi.make_theme()
	add_child(root)

	var stars := Starfield.new()
	stars.name = "Starfield"
	root.add_child(stars)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 28)
	center.add_child(column)

	var title := Label.new()
	_title = title
	title.name = "Title"
	title.text = "SPACE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 104)
	title.add_theme_color_override("font_color", SpaceUi.STAR_WHITE)
	title.add_theme_color_override("font_outline_color", SpaceUi.ACCENT)
	title.add_theme_constant_override("outline_size", 10)
	column.add_child(title)

	_main_panel = _build_panel()
	column.add_child(_main_panel)
	_controls_panel = _build_controls()
	column.add_child(_controls_panel)

	var credit := Label.new()
	_credit = credit
	credit.text = "v%s  ·  UI art: Kenney (kenney.nl), CC0" % ProjectSettings.get_setting("application/config/version", "dev")
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.add_theme_font_size_override("font_size", 14)
	credit.add_theme_color_override("font_color", Color(SpaceUi.STAR_WHITE, 0.45))
	column.add_child(credit)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _build_panel() -> PanelContainer:
	var panel := _panel("Panel", "Main menu")
	var box: VBoxContainer = panel.get_node("Items")

	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	_status.visible = false
	box.add_child(_status)

	box.add_child(_build_ship_picker())
	_play = _button("Play", request_play)
	box.add_child(_play)
	box.add_child(_button("Controls", show_controls))
	if not OS.has_feature("web"):  # a browser tab can't quit itself
		box.add_child(_button("Quit", func() -> void: get_tree().quit()))
	return panel


## Arrows either side of the ship. Left/Right (keys, D-pad, stick) also pick,
## so Play can keep the focus.
func _build_ship_picker() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Ship"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_arrow("<", -1))

	var middle := VBoxContainer.new()
	middle.custom_minimum_size = Vector2(220, 0)
	middle.add_theme_constant_override("separation", 4)
	row.add_child(middle)
	_ship_art = TextureRect.new()
	_ship_art.name = "Art"
	_ship_art.custom_minimum_size = Vector2(0, 90)
	_ship_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ship_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	middle.add_child(_ship_art)
	_ship_name = Label.new()
	_ship_name.name = "Name"
	_ship_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_ship_name)
	_ship_blurb = Label.new()
	_ship_blurb.name = "Blurb"
	_ship_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ship_blurb.add_theme_font_size_override("font_size", 14)
	_ship_blurb.add_theme_color_override("font_color", Color(SpaceUi.INK, 0.75))
	middle.add_child(_ship_blurb)

	row.add_child(_arrow(">", 1))
	_load_hull()
	_show_hull()
	return row


func _arrow(text: String, step: int) -> Button:
	var b := Button.new()
	b.name = "Prev" if step < 0 else "Next"
	b.text = text
	b.custom_minimum_size = Vector2(56, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Kenney Future has no < or >: the engine's default font does.
	b.add_theme_font_override("font", ThemeDB.fallback_font)
	b.add_theme_font_size_override("font_size", 30)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(pick_hull.bind(step))
	return b


## Step through the hulls (wrapping round) and remember the pick.
func pick_hull(step: int) -> void:
	_hull = posmod(_hull + step, SpaceSim.HULLS.size())
	_show_hull()
	var cfg := ConfigFile.new()
	cfg.set_value("ship", "hull", _hull)
	cfg.save(SAVE_PATH)


func choice() -> int:
	return _hull


func _load_hull() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_hull = SpaceSim.sanitize_hull(int(cfg.get_value("ship", "hull", SpaceSim.FALCON)))


func _show_hull() -> void:
	var h: Dictionary = SpaceSim.HULLS[_hull]
	_ship_art.texture = load(SpaceShip.hull_texture(_hull, "blue")) as Texture2D
	_ship_art.flip_v = SpaceShip.hull_points_down(_hull)
	_ship_name.text = "%s  (%d/%d)" % [h["name"], _hull + 1, SpaceSim.HULLS.size()]
	_ship_blurb.text = str(h["blurb"])


func _input(event: InputEvent) -> void:
	if not visible or _main_panel == null or not _main_panel.visible:
		return
	if event.is_action_pressed("ui_left"):
		pick_hull(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		pick_hull(1)
		get_viewport().set_input_as_handled()


## The Controls page: a second panel in place of the main one, so the title
## and credit hide to leave room for the table.
func _build_controls() -> PanelContainer:
	var panel := _panel("ControlsPanel", "Controls")
	_controls = ControlsEditor.new(_control_names, _touch_help)
	_controls.name = "Editor"
	_controls.closed.connect(show_main)
	panel.get_node("Items").add_child(_controls)
	panel.visible = false
	return panel


## A sci-fi panel whose first child (in "Items") sits on the blue header strip.
func _panel(panel_name: String, header_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	box.name = "Items"
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	var header := Label.new()
	header.name = "Header"
	header.text = header_text
	header.custom_minimum_size = Vector2(0, SpaceUi.HEADER_HEIGHT)
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color.WHITE)
	header.add_theme_font_size_override("font_size", 16)
	box.add_child(header)
	return panel


func show_controls() -> void:
	_set_page(true)
	_controls.focus_first()


func show_main() -> void:
	_set_page(false)
	_on_visibility_changed()


func _set_page(controls: bool) -> void:
	_main_panel.visible = not controls
	_controls_panel.visible = controls
	_title.visible = not controls
	_credit.visible = not controls


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = text
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(on_press)
	return b


func _apply(status: String, play_text: String) -> void:
	_set_page(false)
	_status.text = status
	_status.visible = not status.is_empty()
	_play.text = play_text


func _on_visibility_changed() -> void:
	# Enter / Space / gamepad A starts the game without touching the mouse.
	if visible and _play != null and _play.is_inside_tree():
		_play.grab_focus.call_deferred()
