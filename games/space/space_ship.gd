class_name SpaceShip
extends Node2D
## One player's ship. Turn with left/right, thrust with up (down brakes), fire
## with Space / the touch Fire button. Momentum, shots, hits and score are
## SpaceSim rules run on the server (SpaceDirector handles collisions).
##
## Server: steps SpaceSim from InputRelay, writes the net_* props.
## Client: PlayerNet buffers and interpolates them; this draws the Kenney
## ship, its flame and shield, and plays the explosion when it dies.

const PACK: String = "res://assets/kenney/space-shooter-remastered/PNG/"
const COLORS: Array[String] = ["blue", "green", "orange", "red"]
const SHIP_SCALE: float = 0.5

## flags bits: rarely changing state, sent on change (not every snapshot).
const ALIVE: int = 1
const THRUST: int = 2
const SHIELD: int = 4
const RAPID: int = 8
const PROTECTED: int = 16

## Server: total distance flown. Client: total distance drawn. Smoke tests read these.
var traveled: float = 0.0
var rendered_distance: float = 0.0

## Server-side rules state. SpaceDirector reads and changes it too.
var state := SpaceSim.Ship.new()
var spawn_point: Vector2 = Vector2.ZERO

var _net := PlayerNet.new(true)
var _arena: SpaceArena

# Replicated every snapshot (PlayerNet.SYNCED).
var net_time: float = 0.0:
	set(v):
		net_time = v
		_net.on_time(v)
var net_position: Vector2 = Vector2.ZERO:
	set(v):
		net_position = v
		_net.on_position(net_time, v)
var net_rotation: float = 0.0:
	set(v):
		net_rotation = v
		_net.on_rotation(net_time, v)

# Replicated on change.
var score: int = 0
var flags: int = ALIVE:
	set(v):
		flags = v
		_queue_flags(v)
## Pickups collected so far: lets clients notice each one (sound).
var pickups: int = 0:
	set(v):
		if v > pickups and _arena != null and _arena.fx != null:
			_arena.fx.play("pickup", -4.0)
		pickups = v

# Client: flags arrive as soon as they change, but the ship is drawn
# INTERP_DELAY in the past, so each change waits until render time reaches
# it (else a ship would vanish before it visibly touches the rock).
var _shown_flags: int = ALIVE
var _flag_times: PackedFloat64Array = PackedFloat64Array()
var _flag_values: PackedInt32Array = PackedInt32Array()
var _flags_drawn_once: bool = false

var _body: Node2D
var _flame: Sprite2D
var _shield: Sprite2D
var _label: Label


## Called by the spawn function on every peer, before the node enters the tree.
func setup(data: Dictionary, server_side: bool, use_bot: bool, arena: SpaceArena) -> void:
	_arena = arena
	if not server_side:
		_net.use_clock(arena.clock)   # same timeline as shots and asteroids
	_net.setup(self, data, server_side, use_bot, PackedStringArray(["score", "flags", "pickups"]))
	if use_bot and not server_side:
		_net.relay.bot = SpaceBot.new(self, arena)
	spawn_point = data["pos"]
	SpaceSim.respawn(state, spawn_point)
	net_position = state.position
	net_rotation = state.rotation
	position = state.position
	if not server_side:
		_build_visuals()


func peer_id() -> int:
	return _net.peer_id


func player_index() -> int:
	return _net.player_index


func color_name() -> String:
	return COLORS[_net.player_index % COLORS.size()]


## Client: as drawn now. Server: as simulated.
func is_alive() -> bool:
	return (_shown_flags if not _net.server_side else flags) & ALIVE != 0


## Client: the facing being drawn (what the player sees).
func rendered_rotation() -> float:
	return _body.rotation if _body != null else net_rotation


func _ready() -> void:
	if _label != null:
		_label.text = _net.label_text(self)


func _physics_process(delta: float) -> void:
	if not _net.server_side:
		return
	var was_alive: bool = state.alive
	if SpaceSim.step_ship(state, _net.relay.move, _net.relay.fire, delta):
		_arena.director.fire(self)
	if was_alive and state.alive:
		traveled += state.velocity.length() * delta
	if SpaceSim.can_respawn(state):
		SpaceSim.respawn(state, spawn_point)
	publish()


## Server: copy the rules state into the replicated properties.
func publish() -> void:
	net_time = PlayerNet.now()
	net_position = state.position
	net_rotation = state.rotation
	position = state.position
	score = state.score
	var f: int = 0
	if state.alive:
		f |= ALIVE
	if state.thrusting:
		f |= THRUST
	if state.shield:
		f |= SHIELD
	if state.rapid_for > 0.0:
		f |= RAPID
	if state.protected_for > 0.0:
		f |= PROTECTED
	flags = f


func _process(_delta: float) -> void:
	if not _net.can_render():
		return
	var t: float = _net.render_time()
	_apply_flags_until(t)
	var p: Vector2 = _net.position_at(t)
	if is_alive():
		rendered_distance += position.distance_to(p)
	position = p
	var r: Variant = _net.rotation_at(t)
	if r != null:
		_body.rotation = float(r)
	visible = is_alive()
	_flame.visible = _shown_flags & THRUST != 0
	_flame.scale = Vector2(0.9, randf_range(0.8, 1.15))
	_shield.visible = _shown_flags & SHIELD != 0
	# Blink while invulnerable after (re)spawning.
	_body.modulate.a = 0.45 if _shown_flags & PROTECTED != 0 and int(t * 8.0) % 2 == 0 else 1.0


func _queue_flags(v: int) -> void:
	if _net.server_side or _arena == null:
		return
	# Changed at about the server's "now": the newest server time the shared
	# clock maps to (0 = before the clock syncs: apply at once).
	var at: float = 0.0
	if _arena.clock.is_synced():
		at = _arena.clock.render_time(PlayerNet.now()) + Protocol.INTERP_DELAY
	_flag_times.append(at)
	_flag_values.append(v)


func _apply_flags_until(t: float) -> void:
	while not _flag_times.is_empty() and _flag_times[0] <= t:
		var after: int = _flag_values[0]
		_flag_times.remove_at(0)
		_flag_values.remove_at(0)
		var before: int = _shown_flags
		_shown_flags = after
		if not _flags_drawn_once:   # a late joiner's first look: no effects
			_flags_drawn_once = true
			continue
		if before & ALIVE != 0 and after & ALIVE == 0:
			_arena.fx.ship_destroyed(position)
		elif before & SHIELD != 0 and after & SHIELD == 0 and after & ALIVE != 0:
			_arena.fx.play("shield")


## Every texture a ship can use, to load them before play starts.
static func texture_paths() -> Array[String]:
	var out: Array[String] = [PACK + "Effects/fire08.png", PACK + "Effects/shield1.png"]
	for shape: int in range(1, 4):
		for c: String in COLORS:
			out.append(PACK + "playerShip%d_%s.png" % [shape, c])
	return out


func _build_visuals() -> void:
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)

	# Kenney ships point up; the body's rotation 0 points along +x.
	var art := Node2D.new()
	art.name = "Art"
	art.rotation = PI / 2.0
	art.scale = Vector2.ONE * SHIP_SCALE
	_body.add_child(art)

	_flame = Sprite2D.new()
	_flame.name = "Flame"
	_flame.texture = load(PACK + "Effects/fire08.png") as Texture2D
	_flame.position = Vector2(0, 52)
	_flame.visible = false
	art.add_child(_flame)

	var ship := Sprite2D.new()
	ship.name = "Ship"
	var shape: int = 1 + (_net.player_index / COLORS.size()) % 3
	ship.texture = load(PACK + "playerShip%d_%s.png" % [shape, color_name()]) as Texture2D
	art.add_child(ship)

	_shield = Sprite2D.new()
	_shield.name = "Shield"
	_shield.texture = load(PACK + "Effects/shield1.png") as Texture2D
	_shield.position = Vector2(0, -8)
	_shield.visible = false
	art.add_child(_shield)

	_label = Label.new()
	_label.text = "P%d" % (_net.player_index + 1)
	_label.position = Vector2(-40, -48)
	_label.custom_minimum_size = Vector2(80, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(SpaceUi.STAR_WHITE, 0.8))
	add_child(_label)
