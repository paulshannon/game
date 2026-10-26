class_name SpaceShip
extends Node2D
## One player's ship. Turn with left/right, thrust with up (down brakes), fire
## with Space / the touch Fire button. Momentum, shots, hits and score are
## SpaceSim rules run on the server (SpaceDirector handles collisions).
##
## Server: steps SpaceSim from InputRelay, writes the net_* props.
## Client: PlayerNet buffers and interpolates them; this draws the Kenney
## ship, its flame, RCS puffs (braking, turning, strafing) and shield, and plays the
## explosion when it dies.

const PACK: String = "res://assets/kenney/space-shooter-remastered/PNG/"
const COLORS: Array[String] = ["blue", "green", "orange", "red"]
## A colour pick meaning "my seat's colour" (player index), the default.
const COLOR_AUTO: int = -1
const SHIP_SCALE: float = 0.5

## flags bits. Sent with every snapshot (an int), so each change is stamped
## with the server time it happened at and drawn at that moment.
const ALIVE: int = 1
const THRUST: int = 2
const SHIELD: int = 4
const RAPID: int = 8
const PROTECTED: int = 16
const BRAKE: int = 32
const TURN_LEFT: int = 64
const TURN_RIGHT: int = 128
const STRAFE_LEFT: int = 256
const STRAFE_RIGHT: int = 512

## RCS puffs. Where each hull's nozzles and flames are: SpaceHullArt.
const RCS_TEXTURE: String = PACK + "Effects/fire14.png"
const RCS_SCALE: float = 0.41
## Clear air between an RCS nozzle and its puff (px). Main flames have none.
const RCS_GAP: float = 3.0
## Main flames overlap the hull this much (sprite px), so no seam shows.
const FLAME_OVERLAP: float = 1.0
const FLAME_TEXTURE: String = PACK + "Effects/fire08.png"

## Server: total distance flown. Client: total distance drawn. Smoke tests read these.
var traveled: float = 0.0
var rendered_distance: float = 0.0
## Client: frames drawn with an RCS thruster firing (smoke test).
var rcs_frames: int = 0
## Server: seconds spent strafing. Client: frames drawn strafing. Smoke tests.
var strafe_time: float = 0.0
var strafe_frames: int = 0

## Server-side rules state. SpaceDirector reads and changes it too.
var state := SpaceSim.Ship.new()

var _net := PlayerNet.new(true)
var _color: int = 0   # index into COLORS
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

# Replicated with every snapshot, after net_time (stamped, see StateTimeline).
var flags: int = ALIVE:
	set(v):
		flags = v
		if not _net.server_side:
			_flag_timeline.push(net_time, v)
## Pickups collected so far: lets clients notice each one (sound).
var pickups: int = 0:
	set(v):
		pickups = v
		if not _net.server_side:
			_pickup_timeline.push(net_time, v)

# Replicated on change: the scoreboard and energy bar read them, timing
# doesn't matter.
var score: int = 0
## Energy, whole units (0..SpaceStar.ENERGY_MAX): the owner's energy bar.
var energy: int = int(SpaceStar.ENERGY_MAX)

# Client: flags and pickups as of the render time being drawn.
var _flag_timeline := StateTimeline.new(ALIVE)
var _pickup_timeline := StateTimeline.new()

var _body: Node2D
var _flames: Array[Sprite2D] = []
var _shield: Sprite2D
# Client: RCS puffs by flag bit (BRAKE, TURN_*, STRAFE_*).
var _rcs: Dictionary = {}   # int -> Array[Sprite2D]
var _label: Label


## Called by the spawn function on every peer, before the node enters the tree.
func setup(data: Dictionary, server_side: bool, use_bot: bool, arena: SpaceArena) -> void:
	_arena = arena
	if not server_side:
		_net.use_clock(arena.clock)   # same timeline as shots and asteroids
	_net.setup(self, data, server_side, use_bot, PackedStringArray(["flags", "pickups"]),
			PackedStringArray(["score", "energy"]))
	if use_bot and not server_side:
		_net.relay.make_bot = func() -> BotInput: return SpaceBot.new(self, arena)
	SpaceSim.set_hull(state, int(data.get("hull", SpaceSim.FALCON)))
	_color = int(data.get("color", _net.player_index)) % COLORS.size()
	state.team = _color
	SpaceSim.respawn(state, data["pos"])   # by its base (SpaceArena._spawn_position)
	net_position = state.position
	net_rotation = state.rotation
	position = state.position
	if not server_side:
		_build_visuals()


func peer_id() -> int:
	return _net.peer_id


func player_index() -> int:
	return _net.player_index


## Flown by the server (ServerBots).
func is_bot() -> bool:
	return _net.is_bot


## Which of SpaceSim.HULLS this ship is (from the spawn data).
func hull() -> int:
	return state.hull


## Which of COLORS the player picked (or their seat's, for COLOR_AUTO).
func color_index() -> int:
	return _color


func color_name() -> String:
	return COLORS[_color]


## Client: as drawn now. Server: as simulated.
func is_alive() -> bool:
	return _shown_flags() & ALIVE != 0


func _shown_flags() -> int:
	return flags if _net.server_side else _flag_timeline.current()


## Spawn protection (blinking): shots fly through. As drawn on a client.
func is_protected() -> bool:
	return _shown_flags() & PROTECTED != 0


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
	var used: float = state.energy_used
	var gained: float = state.energy_gained
	if SpaceSim.step_ship(state, _net.relay.move, _net.relay.fire, delta, _net.relay.strafe):
		_arena.director.fire(self)
	_arena.energy_used += state.energy_used - used
	_arena.energy_gained += state.energy_gained - gained
	if state.strafing != 0:
		strafe_time += delta
		_arena.strafers[peer_id()] = true
	if was_alive and state.alive:
		traveled += state.velocity.length() * delta
	# Back at its team's starbase, wherever it was destroyed.
	if SpaceSim.can_respawn(state):
		SpaceSim.respawn(state, SpaceBases.spawn_point(_arena.base_of(state.team), _net.player_index, PlayerNet.now()))
	publish()


## Server: copy the rules state into the replicated properties.
func publish() -> void:
	net_time = PlayerNet.now()
	net_position = state.position
	net_rotation = state.rotation
	position = state.position
	score = state.score
	energy = ceili(state.energy)
	var f: int = 0
	if state.alive:
		f |= ALIVE
	if state.thrusting:
		f |= THRUST
	if state.braking:
		f |= BRAKE
	if state.turning < 0:
		f |= TURN_LEFT
	elif state.turning > 0:
		f |= TURN_RIGHT
	if state.strafing < 0:
		f |= STRAFE_LEFT
	elif state.strafing > 0:
		f |= STRAFE_RIGHT
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
	_flag_timeline.advance(t, _on_flags_changed)
	_pickup_timeline.advance(t, _on_pickup)
	var p: Vector2 = _net.position_at(t)
	if is_alive():
		rendered_distance += position.distance_to(p)
	position = p
	var r: Variant = _net.rotation_at(t)
	if r != null:
		_body.rotation = float(r)
	visible = is_alive()
	var shown: int = _shown_flags()
	for flame: Sprite2D in _flames:
		flame.visible = shown & THRUST != 0
		var size: float = float(flame.get_meta("size"))
		flame.scale = Vector2(size, size * randf_range(0.8, 1.15))
	var rcs: bool = false
	for bit: int in _rcs:
		var on: bool = shown & bit != 0
		rcs = rcs or on
		for puff: Sprite2D in _rcs[bit]:
			puff.visible = on
			puff.scale = Vector2.ONE * RCS_SCALE * randf_range(0.75, 1.1)
	if rcs and visible:
		rcs_frames += 1
	if shown & (STRAFE_LEFT | STRAFE_RIGHT) != 0 and visible:
		strafe_frames += 1
	_shield.visible = shown & SHIELD != 0
	# Blink while invulnerable after (re)spawning.
	_body.modulate.a = 0.45 if shown & PROTECTED != 0 and int(t * 8.0) % 2 == 0 else 1.0


func _on_flags_changed(before: int, after: int, at: float) -> void:
	if before & ALIVE != 0 and after & ALIVE == 0:
		# Where it was at that server time: the hit (it stays parked there,
		# hidden, until it respawns).
		_arena.fx.ship_destroyed(_net.position_at(at))
	elif before & SHIELD != 0 and after & SHIELD == 0 and after & ALIVE != 0:
		_arena.fx.play("shield")


func _on_pickup(before: int, after: int, _at: float) -> void:
	if after > before:
		_arena.fx.play("pickup", -4.0)


## Every texture a ship can use, to load them before play starts.
static func texture_paths() -> Array[String]:
	var out: Array[String] = [FLAME_TEXTURE, PACK + "Effects/shield1.png", RCS_TEXTURE]
	for h: int in SpaceSim.HULLS.size():
		for c: String in COLORS:
			out.append(SpaceHullArt.texture(h, c))
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

	var flame_tex: Texture2D = load(FLAME_TEXTURE) as Texture2D
	for jet: Vector3 in SpaceHullArt.flames(state.hull):
		var flame := Sprite2D.new()
		flame.name = "Flame%d" % _flames.size()
		flame.texture = flame_tex
		# Hang it from its top (the wide end): flicker stretches it away
		# from the hull, never off it.
		flame.offset = Vector2(0, flame_tex.get_height() * 0.5)
		flame.position = Vector2(jet.x, jet.y - FLAME_OVERLAP)
		flame.set_meta("size", jet.z)
		flame.visible = false
		art.add_child(flame)
		_flames.append(flame)

	var ship := Sprite2D.new()
	ship.name = "Ship"
	ship.texture = load(SpaceHullArt.texture(state.hull, color_name())) as Texture2D
	if SpaceHullArt.points_down(state.hull):
		ship.rotation = PI
	art.add_child(ship)

	_shield = Sprite2D.new()
	_shield.name = "Shield"
	_shield.texture = load(PACK + "Effects/shield1.png") as Texture2D
	_shield.position = Vector2(0, -8)
	_shield.visible = false
	art.add_child(_shield)

	# RCS: braking fires both nose thrusters forward. Turning fires a nose and
	# a tail thruster on opposite sides, pushing the nose round: turning right
	# (clockwise) blows the nose's left side and the tail's right side.
	var rcs_tex: Texture2D = load(RCS_TEXTURE) as Texture2D
	var h: int = state.hull
	var nose_l: Vector2 = SpaceHullArt.nozzle(h, true, false)
	var nose_r: Vector2 = SpaceHullArt.nozzle(h, true, true)
	var tail_l: Vector2 = SpaceHullArt.nozzle(h, false, false)
	var tail_r: Vector2 = SpaceHullArt.nozzle(h, false, true)
	_rcs[BRAKE] = [
		_add_rcs(rcs_tex, nose_l, Vector2(1, -0.35)),
		_add_rcs(rcs_tex, nose_r, Vector2(1, 0.35)),
	]
	_rcs[TURN_RIGHT] = [
		_add_rcs(rcs_tex, nose_l, Vector2.UP),
		_add_rcs(rcs_tex, tail_r, Vector2.DOWN),
	]
	_rcs[TURN_LEFT] = [
		_add_rcs(rcs_tex, nose_r, Vector2.DOWN),
		_add_rcs(rcs_tex, tail_l, Vector2.UP),
	]
	# Strafing fires a nose and a tail thruster on the same side, away from
	# where it's going: strafing right blows out of the left side.
	_rcs[STRAFE_RIGHT] = [
		_add_rcs(rcs_tex, nose_l, Vector2.UP),
		_add_rcs(rcs_tex, tail_l, Vector2.UP),
	]
	_rcs[STRAFE_LEFT] = [
		_add_rcs(rcs_tex, nose_r, Vector2.DOWN),
		_add_rcs(rcs_tex, tail_r, Vector2.DOWN),
	]

	_label = Label.new()
	_label.text = "P%d" % (_net.player_index + 1)
	_label.position = Vector2(-40, -48)
	_label.custom_minimum_size = Vector2(80, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(SpaceUi.STAR_WHITE, 0.8))
	add_child(_label)


## A puff whose nozzle sits at `at` and whose exhaust points along `exhaust`
## (body frame). Kenney's fire14 is wide at the top and narrows downwards;
## flipped, it starts narrow and spreads out along +y, RCS_GAP from the
## nozzle (the offset is in texture pixels, so divided by the scale).
func _add_rcs(texture: Texture2D, at: Vector2, exhaust: Vector2) -> Sprite2D:
	var puff := Sprite2D.new()
	puff.name = "Rcs%d" % _body.get_child_count()
	puff.texture = texture
	puff.flip_v = true
	puff.offset = Vector2(0, texture.get_height() * 0.5 + RCS_GAP / RCS_SCALE)
	puff.position = at
	puff.rotation = exhaust.angle() - PI / 2.0
	puff.scale = Vector2.ONE * RCS_SCALE
	puff.z_index = -1   # under the hull
	puff.visible = false
	_body.add_child(puff)
	return puff
