extends TestCase


func test_defaults_to_space_client_localhost() -> void:
	var c: LaunchConfig = LaunchConfig.from_args(PackedStringArray())
	assert_false(c.is_server)
	assert_eq(c.game, "space")
	assert_eq(c.port, Protocol.port_for("space"))
	assert_eq(c.url, "ws://127.0.0.1:%d" % Protocol.port_for("space"))


func test_server_args() -> void:
	var c: LaunchConfig = LaunchConfig.from_args(PackedStringArray(["--server", "--game=3d", "--port=7000", "--run-seconds=5", "--expect-peers=2"]))
	assert_true(c.is_server)
	assert_eq(c.game, "3d")
	assert_eq(c.port, 7000)
	assert_near(c.run_seconds, 5.0)
	assert_eq(c.expect_peers, 2)
	assert_eq(c.bind_address, "*", "default binds all interfaces")


func test_bind_address() -> void:
	var c: LaunchConfig = LaunchConfig.from_args(PackedStringArray(["--server", "--bind=127.0.0.1"]))
	assert_eq(c.bind_address, "127.0.0.1")


func test_unknown_game_falls_back() -> void:
	assert_eq(LaunchConfig.from_args(PackedStringArray(["--game=pong"])).game, "space")


func test_web_https_uses_wss_proxy_path() -> void:
	var c: LaunchConfig = LaunchConfig.from_web_location("https:", "play.example.com", "play.example.com", "?game=3d")
	assert_eq(c.url, "wss://play.example.com/ws/3d")


func test_web_http_uses_direct_port() -> void:
	var c: LaunchConfig = LaunchConfig.from_web_location("http:", "localhost:8000", "localhost", "")
	assert_eq(c.game, "space", "no ?game= opens the default game")
	assert_eq(c.url, "ws://localhost:%d" % Protocol.port_for("space"))


func test_web_explicit_server_wins() -> void:
	var c: LaunchConfig = LaunchConfig.from_web_location("https:", "a.com", "a.com", "?server=wss%3A%2F%2Fb.com%2Fx")
	assert_eq(c.url, "wss://b.com/x")


func test_parse_query() -> void:
	var q: Dictionary = LaunchConfig.parse_query("?a=1&b=two%20words&flag")
	assert_eq(q["a"], "1")
	assert_eq(q["b"], "two words")
	assert_true(q.has("flag"))
