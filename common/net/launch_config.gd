class_name LaunchConfig
extends RefCounted
## Decides role, game and server address from the command line (native) or
## the page URL (web). Parsing is pure so it can be unit-tested.
##
## Native:  godot --path . -- --server --game=3d --port=9081 [--bind=127.0.0.1]
##          godot --path . -- --client --game=space --url=ws://127.0.0.1:9082 --bot
## Web:     index.html?game=3d&server=wss://example.com/ws/3d

var is_server: bool = false
var game: String = Protocol.DEFAULT_GAME
var port: int = 0
## Server listen address. "*" = all interfaces (dev). Use 127.0.0.1 behind a
## reverse proxy so the raw, unencrypted port is not exposed to the internet.
var bind_address: String = "*"
var url: String = ""
var bot: bool = false
## > 0: run this long, print a SMOKE_RESULT line, then quit. Used by tools/smoke.sh.
var run_seconds: float = 0.0
## Smoke test pass condition: how many players must have been seen.
var expect_peers: int = 0


static func from_environment() -> LaunchConfig:
	var cfg: LaunchConfig
	if OS.has_feature("web"):
		cfg = from_web_location(_js_string("window.location.protocol"),
				_js_string("window.location.host"),
				_js_string("window.location.hostname"),
				_js_string("window.location.search"))
	else:
		cfg = from_args(OS.get_cmdline_user_args())
	if OS.has_feature("dedicated_server"):
		cfg.is_server = true
	return cfg


static func from_args(args: PackedStringArray) -> LaunchConfig:
	var cfg := LaunchConfig.new()
	for arg: String in args:
		var key: String = arg
		var value: String = ""
		var eq: int = arg.find("=")
		if eq != -1:
			key = arg.substr(0, eq)
			value = arg.substr(eq + 1)
		match key:
			"--server": cfg.is_server = true
			"--client": cfg.is_server = false
			"--game": cfg.game = _normalize_game(value)
			"--port": cfg.port = value.to_int()
			"--bind": cfg.bind_address = value
			"--url": cfg.url = value
			"--bot": cfg.bot = true
			"--run-seconds": cfg.run_seconds = value.to_float()
			"--expect-peers": cfg.expect_peers = value.to_int()
	if cfg.port <= 0:
		cfg.port = Protocol.port_for(cfg.game)
	if cfg.url.is_empty():
		cfg.url = "ws://127.0.0.1:%d" % cfg.port
	return cfg


## protocol: "https:"   host: "game.example.com:8443"   hostname: "game.example.com"
## search: "?game=3d&server=wss://..."
static func from_web_location(protocol: String, host: String, hostname: String, search: String) -> LaunchConfig:
	var cfg := LaunchConfig.new()
	var query: Dictionary = parse_query(search)
	cfg.game = _normalize_game(str(query.get("game", Protocol.DEFAULT_GAME)))
	cfg.port = Protocol.port_for(cfg.game)
	cfg.bot = query.has("bot")
	if query.has("server"):
		cfg.url = str(query["server"])
	elif protocol == "https:":
		# HTTPS pages may only open wss://. Production puts a TLS reverse proxy
		# (deploy/Caddyfile) in front of the game server on the same host.
		cfg.url = "wss://%s/ws/%s" % [host, cfg.game]
	else:
		# Local dev: page from `tools/serve_web.sh`, server on the same machine.
		cfg.url = "ws://%s:%d" % [hostname if not hostname.is_empty() else "127.0.0.1", cfg.port]
	return cfg


static func parse_query(search: String) -> Dictionary:
	var out: Dictionary = {}
	var q: String = search.trim_prefix("?")
	if q.is_empty():
		return out
	for pair: String in q.split("&", false):
		var eq: int = pair.find("=")
		if eq == -1:
			out[pair.uri_decode()] = ""
		else:
			out[pair.substr(0, eq).uri_decode()] = pair.substr(eq + 1).uri_decode()
	return out


static func _normalize_game(value: String) -> String:
	var v: String = value.to_lower()
	return v if Protocol.PORTS.has(v) else Protocol.DEFAULT_GAME


static func _js_string(expr: String) -> String:
	var v: Variant = JavaScriptBridge.eval(expr, true)
	return "" if v == null else str(v)
