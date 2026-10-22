class_name Starfield
extends Control
## Screen-space star field: three depth layers of stars that drift slowly and
## twinkle. Procedural (no art needed) and seeded, so it looks the same every
## run. Fills its rect; used behind the menu and as the arena backdrop.

const COUNT: int = 220
const DRIFT := Vector2(-6.0, 1.5)   # pixels per second for the nearest layer

var _stars: Array[Vector4] = []     # x, y (0..1), depth (0.25..1), twinkle phase
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Already in the tree here, so offsets must be reset too: plain
	# set_anchors_preset() would keep the current (zero) size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	for i: int in COUNT:
		var depth: float = [0.25, 0.5, 1.0][rng.randi() % 3]
		_stars.append(Vector4(rng.randf(), rng.randf(), depth, rng.randf() * TAU))


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var r: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, r), Color(0.03, 0.04, 0.09))
	for s: Vector4 in _stars:
		var p := Vector2(s.x * r.x, s.y * r.y) + DRIFT * s.z * _time
		p = Vector2(fposmod(p.x, r.x), fposmod(p.y, r.y))
		var twinkle: float = 0.65 + 0.35 * sin(_time * (1.0 + s.z * 2.0) + s.w)
		var c := Color(SpaceUi.STAR_WHITE, twinkle * (0.35 + 0.65 * s.z))
		draw_circle(p, 0.6 + 1.4 * s.z, c)
