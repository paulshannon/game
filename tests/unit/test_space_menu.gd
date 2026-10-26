extends TestCase
## The space game's registration and menu, without a network. Building the
## menu also loads every Kenney sprite and the font it uses: a wrong path logs
## an error, which fails the test.


func test_space_is_a_known_game_with_its_own_port() -> void:
	var c: LaunchConfig = LaunchConfig.from_args(PackedStringArray(["--game=space"]))
	assert_eq(c.game, "space")
	assert_eq(c.port, 9082)
	assert_eq(LaunchConfig.from_web_location("http:", "localhost:8000", "localhost", "?game=space").url,
			"ws://localhost:9082")


func test_space_names_its_controls() -> void:
	var space := SpaceArena.new()
	var names: Dictionary = space.control_names()
	assert_eq(names[InputSetup.UP], "Thrust")
	assert_eq(names.keys(), [InputSetup.LEFT, InputSetup.RIGHT, InputSetup.UP, InputSetup.DOWN,
			InputSetup.STRAFE_LEFT, InputSetup.STRAFE_RIGHT, InputSetup.FIRE, InputSetup.MENU])
	assert_eq(names[InputSetup.MENU], "Ship select")
	space.free()


func test_only_space_has_a_menu() -> void:
	var space := SpaceArena.new()
	var menu: GameMenu = space.make_menu()
	assert_true(menu is SpaceMenu)
	var plain := Arena2D.new()
	assert_eq(plain.make_menu(), null)
	assert_eq(space.action_button(), InputSetup.FIRE)
	assert_eq(plain.action_button(), &"")
	menu.free()
	space.free()
	plain.free()


func test_theme_loads_pack_assets() -> void:
	var t: Theme = SpaceUi.make_theme()
	assert_true(t.default_font != null)
	var normal: StyleBoxTexture = t.get_stylebox("normal", "Button")
	assert_true(normal.texture != null, "button sprite loaded")
	var panel: StyleBoxTexture = t.get_stylebox("panel", "PanelContainer")
	assert_eq(panel.texture.get_height(), 64)
	assert_near(panel.texture_margin_top, SpaceUi.HEADER_HEIGHT + 2.0)


func test_menu_shows_status_and_rejoin() -> void:
	var m := SpaceMenu.new()
	m._ready()  # builds the UI; not in a tree, so no focus grab
	var play: Button = m.get_node("Root/Center/Column/Panel/Items/Play")
	var status: Label = m.get_node("Root/Center/Column/Panel/Items/Status")
	m.show_menu()
	assert_eq(play.text, "Play")
	assert_false(status.visible, "no status at startup")
	m.show_menu("Disconnected from server", "Rejoin")
	assert_eq(play.text, "Rejoin")
	assert_true(status.visible)
	assert_eq(status.text, "Disconnected from server")
	assert_true(m.visible)
	m.free()


func test_play_hides_menu_and_requests_join() -> void:
	var m := SpaceMenu.new()
	m._ready()
	var fired: Array[bool] = [false]
	m.play_requested.connect(func() -> void: fired[0] = true)
	m.show_menu()
	(m.get_node("Root/Center/Column/Panel/Items/Play") as Button).pressed.emit()
	assert_true(fired[0])
	assert_false(m.visible)
	m.free()


func test_controls_page_opens_and_closes() -> void:
	var space := SpaceArena.new()
	var m: SpaceMenu = space.make_menu()
	m._ready()
	var main: Control = m.get_node("Root/Center/Column/Panel")
	var page: Control = m.get_node("Root/Center/Column/ControlsPanel")
	assert_false(page.visible)
	(m.get_node("Root/Center/Column/Panel/Items/Controls") as Button).pressed.emit()
	assert_true(page.visible)
	assert_false(main.visible)
	assert_eq((m.get_node("Root/Center/Column/ControlsPanel/Items/Editor/Grid/move_up_0") as Button).text, "W")
	(m.get_node("Root/Center/Column/ControlsPanel/Items/Editor/Bar/Back") as Button).pressed.emit()
	assert_true(main.visible)
	assert_false(page.visible)
	m.show_controls()
	m.show_menu("Disconnected from server", "Rejoin")
	assert_true(main.visible, "the menu comes back on its main page")
	m.free()
	space.free()


const PICKS: String = "user://test_space_picks.cfg"


func test_picker_cycles_ship_and_colour_and_remembers() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PICKS))
	var p := SpaceShipPicker.new(PICKS)
	assert_eq(p.choice(), {"hull": SpaceSim.FALCON, "color": SpaceShip.COLOR_AUTO, "bots": 0}, "defaults")
	p.pick_bots(-1)
	assert_eq(p.bots, ServerBots.MAX_BOTS, "bots wrap round too")
	assert_eq((p.get_node("Bots/Cycle") as Button).text, "Bots: %d" % ServerBots.MAX_BOTS)
	p.pick_hull(-1)
	assert_eq(p.hull, SpaceSim.HULLS.size() - 1, "wraps round backwards")
	p.pick_color(1)
	assert_eq(p.color, 0, "after auto comes the first colour")
	for i: int in SpaceShip.COLORS.size():
		p.pick_color(1)
	assert_eq(p.color, SpaceShip.COLOR_AUTO, "and back round to auto")
	p.pick_color(-1)
	assert_eq((p.get_node("Colour/Cycle") as Button).text, "Colour: red")
	var again := SpaceShipPicker.new(PICKS)
	assert_eq(again.choice(), p.choice(), "restored from the save")
	p.free()
	again.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PICKS))


func test_ship_select_keeps_the_score() -> void:
	var space := SpaceArena.new()
	space.config = LaunchConfig.new()
	space.config.is_server = true
	var data: Dictionary = {"id": 5, "index": 0, "hue": 0.0, "pos": Vector2.ZERO, "hull": 0, "color": 0}
	var first: SpaceShip = space._create_player(data)
	first.state.score = 320
	space._player_leaving(5, first)
	first.free()
	data["hull"] = SpaceSim.COMET
	var second: SpaceShip = space._create_player(data)
	assert_eq(second.state.score, 320, "the new ship starts with the old score")
	assert_eq(second.hull(), SpaceSim.COMET)
	second.free()
	var third: SpaceShip = space._create_player(data)
	assert_eq(third.state.score, 0, "banked once, restored once")
	third.free()
	space.free()
