class_name SpaceBaseView
extends Node2D
## Client: the teams' starbases (SpaceBases), drawn where they are at the
## time this client draws (the arena's shared server clock, like the rocks):
## a Kenney station in a slowly turning ring of its team's colour, named
## underneath. Purely visual: nothing touches or shoots them.

const STATION: String = "res://assets/kenney/space-shooter-extension/PNG/Sprites/Station/spaceStation_021.png"
const STATION_SCALE: float = 1.2
const RING_RADIUS: float = 190.0
const DASHES: int = 24
## World pixels: about 22 on screen at SpaceArena.ZOOM.
const LABEL_SIZE: int = 36

var clock: SnapshotClock
var arena: SpaceArena
## Closest your ship has been drawn to a base (smoke test: it spawns by one).
var own_closest: float = INF

var _stations: Array[Sprite2D] = []
var _time: float = 0.0


func _ready() -> void:
	z_index = -3   # over the star and dust, under rocks, ships and shots
	var tex: Texture2D = load(STATION) as Texture2D
	for team: int in SpaceBases.COUNT:
		var sprite := Sprite2D.new()
		sprite.name = "Base%d" % team
		sprite.texture = tex
		sprite.scale = Vector2.ONE * STATION_SCALE
		sprite.visible = false
		add_child(sprite)
		_stations.append(sprite)


func _process(delta: float) -> void:
	_time += delta
	var synced: bool = clock != null and clock.is_synced()
	var t: float = clock.render_time(PlayerNet.now()) if synced else 0.0
	var own: Node2D = arena.local_player() as Node2D if arena != null else null
	for team: int in _stations.size():
		var sprite: Sprite2D = _stations[team]
		sprite.visible = synced
		sprite.position = SpaceBases.position(team, t)
		if synced and own != null:
			own_closest = minf(own_closest, own.position.distance_to(sprite.position))
		# Long side along the orbit, solar panels out to the sides.
		sprite.rotation = SpaceBases.angle(team, t)
	queue_redraw()


func _draw() -> void:
	for team: int in _stations.size():
		var sprite: Sprite2D = _stations[team]
		if not sprite.visible:
			continue
		var color: Color = team_color(team)
		var at: Vector2 = sprite.position
		draw_circle(at, RING_RADIUS, Color(color, 0.07))
		var spin: float = _time * 0.15
		for i: int in DASHES:
			var a: float = spin + TAU * i / DASHES
			draw_arc(at, RING_RADIUS, a, a + TAU / DASHES * 0.55, 6, Color(color, 0.7), 3.0)
		var label: String = "%s base" % SpaceShip.COLORS[team].to_upper()
		var font: Font = SpaceUi.font()
		var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		draw_string(font, at + Vector2(-width * 0.5, RING_RADIUS + LABEL_SIZE * 1.4), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color(color, 0.85))


static func team_color(team: int) -> Color:
	return SpaceScoreboard.SHIP_COLORS.get(SpaceShip.COLORS[team], Color.WHITE)
