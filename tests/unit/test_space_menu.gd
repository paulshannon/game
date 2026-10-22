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


func test_only_space_has_a_menu() -> void:
	var space := SpaceArena.new()
	var menu: GameMenu = space.make_menu()
	assert_true(menu is SpaceMenu)
	var plain := Arena2D.new()
	assert_eq(plain.make_menu(), null)
	assert_false(space.uses_jump())
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
