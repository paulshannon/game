class_name SpaceFx
extends Node2D
## Client-only effects for the space game: entity ghosts (see SpaceEntity),
## explosions made of Kenney smoke puffs, and sounds. Purely cosmetic and
## never networked: everything here is triggered by state the server already
## replicated. Not under the replicated Entities node, so the spawner never
## sees ghosts.

const PUFFS: String = "res://assets/kenney/space-shooter-extension/PNG/Sprites/Effects/spaceEffects_%03d.png"
const PUFF_FIRST: int = 8    # spaceEffects_008..016: round smoke puffs, small to large
const PUFF_LAST: int = 16

## Effects farther than this from the camera are skipped: off screen, and in
## unbounded space possibly thousands of pixels away. That includes rocks the
## server drops for being far from every ship (SpaceField.STRAY_DISTANCE is
## larger), which would otherwise "explode" when their ghost ends.
const EFFECT_DISTANCE: float = 1200.0

const SOUNDS: Dictionary = {
	"shot": "res://assets/kenney/sci-fi-sounds/Audio/laserSmall_001.ogg",
	"rock": "res://assets/kenney/sci-fi-sounds/Audio/explosionCrunch_000.ogg",
	"ship": "res://assets/kenney/sci-fi-sounds/Audio/lowFrequency_explosion_000.ogg",
	"pickup": "res://assets/kenney/digital-audio/Audio/powerUp2.ogg",
	"shield": "res://assets/kenney/sci-fi-sounds/Audio/forceField_000.ogg",
}

var clock: SnapshotClock

## Smoke-test bookkeeping: what this client actually drew.
var own_shots_seen: int = 0
var explosions_seen: int = 0

var _players: Dictionary = {}   # sound name -> AudioStreamPlayer
var _puffs: Array[Texture2D] = []
## Held so they stay loaded: the first spawns then don't stall the client
## loading art (which also throws its server clock off).
var _preloaded: Array[Resource] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 5   # explosions over ships and rocks
	for key: String in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx_" + key
		p.stream = load(str(SOUNDS[key])) as AudioStream
		p.max_polyphony = 4
		add_child(p)
		_players[key] = p
	for i: int in range(PUFF_FIRST, PUFF_LAST + 1):
		_puffs.append(load(PUFFS % i) as Texture2D)
	for path: String in SpaceEntity.texture_paths() + SpaceShip.texture_paths():
		_preloaded.append(load(path))


func play(sound: String, volume_db: float = 0.0) -> void:
	# Nobody hears a headless client (smoke-test bots), and Godot's dummy
	# audio driver never releases a playback that is cut off (stopped, or
	# replaced when max_polyphony is reached): they'd be leaked at exit.
	if DisplayServer.get_name() == "headless":
		return
	var p: AudioStreamPlayer = _players.get(sound) as AudioStreamPlayer
	if p != null:
		p.volume_db = volume_db
		p.play()


## A despawned entity keeps being drawn until render time reaches its removal.
func leave_ghost(data: Dictionary, removed_at: float, shown: bool) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return   # the whole game is being torn down
	var ghost := SpaceEntity.new()
	ghost.setup(data)
	ghost.setup_client(clock, self, removed_at, shown)
	add_child(ghost)


## An entity became visible on this client.
func on_appeared(e: SpaceEntity) -> void:
	if e.kind != SpaceEntity.Kind.SHOT:
		return
	var own: bool = Net.is_online() and e.owner_peer == multiplayer.get_unique_id()
	if own:
		own_shots_seen += 1
	if own or near_camera(e.global_position):
		play("shot", -6.0 if own else -14.0)


func near_camera(at: Vector2) -> bool:
	var cam: Camera2D = get_viewport().get_camera_2d()
	return cam == null or cam.global_position.distance_to(at) <= EFFECT_DISTANCE


func explode(at: Vector2, radius: float) -> void:
	if not near_camera(at):
		return
	explosions_seen += 1
	play("rock", -4.0)
	_puff_burst(at, radius, Color(1.0, 0.75, 0.45))


func ship_destroyed(at: Vector2) -> void:
	if not near_camera(at):
		return
	play("ship")
	_puff_burst(at, 34.0, Color(1.0, 0.55, 0.3))


func _puff_burst(at: Vector2, radius: float, tint: Color) -> void:
	var count: int = 3 + int(radius / 10.0)
	for i: int in count:
		var s := Sprite2D.new()
		s.texture = _puffs[_rng.randi() % _puffs.size()]
		s.position = at + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * radius * 0.6
		s.rotation = _rng.randf() * TAU
		s.modulate = tint.lerp(Color(0.8, 0.8, 0.85), _rng.randf() * 0.5)
		var start: float = radius / 40.0
		s.scale = Vector2.ONE * start
		add_child(s)
		var life: float = _rng.randf_range(0.35, 0.6)
		var tw: Tween = s.create_tween().set_parallel()
		tw.tween_property(s, "scale", Vector2.ONE * start * 2.2, life)
		tw.tween_property(s, "modulate:a", 0.0, life)
		tw.tween_property(s, "position", s.position + (s.position - at) * 0.8, life)
		tw.chain().tween_callback(s.queue_free)
