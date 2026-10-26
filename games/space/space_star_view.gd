class_name SpaceStarView
extends Node2D
## Client: the star at the centre of the map, drawn in code (no Kenney sun):
## a white-hot core inside layers of yellow-orange glow that breathe slowly.
## Purely visual: its rules are SpaceStar.

const GLOW := Color(1.0, 0.62, 0.18)
const CORE := Color(1.0, 0.96, 0.78)
const LAYERS: int = 16   # many faint layers: a smooth falloff, no bands
const GLOW_REACH: float = 3.2   # outermost glow, in star radii

var _time: float = 0.0


func _ready() -> void:
	position = SpaceStar.CENTER
	z_index = -5   # under rocks, ships and shots


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var r: float = SpaceStar.RADIUS
	var breathe: float = 1.0 + 0.04 * sin(_time * 1.7)
	for i: int in LAYERS:
		var f: float = 1.0 - float(i) / LAYERS          # 1 outermost .. small
		var radius: float = r * lerpf(1.0, GLOW_REACH, f) * breathe
		draw_circle(Vector2.ZERO, radius, Color(GLOW, 0.025 + 0.035 * (1.0 - f)))
	draw_circle(Vector2.ZERO, r * 1.05, Color(GLOW, 0.9))
	draw_circle(Vector2.ZERO, r * 0.9, CORE)
