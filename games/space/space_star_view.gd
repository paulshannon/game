class_name SpaceStarView
extends Node2D
## Client: the star at the centre of the map, drawn in code (no Kenney sun):
## a white-hot core inside layers of yellow-orange glow that breathe slowly,
## and a faint band of dust along each asteroid belt (SpaceBelts), so you can
## see where the rings are. Purely visual: the rules are SpaceStar's.

const GLOW := Color(1.0, 0.62, 0.18)
const CORE := Color(1.0, 0.96, 0.78)
const LAYERS: int = 32   # many faint layers: a smooth falloff, no bands
const GLOW_REACH: float = 1.8   # outermost glow, in star radii
const DUST := Color(0.78, 0.66, 0.55, 0.035)
const ARC_POINTS: int = 256

var _time: float = 0.0


func _ready() -> void:
	position = SpaceStar.CENTER
	z_index = -5   # under rocks, ships and shots
	var dust := MeshInstance2D.new()
	dust.name = "Belts"
	dust.mesh = belt_mesh()
	dust.show_behind_parent = true
	add_child(dust)


## The belts' dust as one mesh, built once (they never change): each ring a
## closed band of quads. A thick draw_arc leaves a seam where its ends meet.
static func belt_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	for ring: Vector3 in SpaceBelts.RINGS:
		var inner: float = ring.x - ring.y
		var outer: float = ring.x + ring.y
		for i: int in ARC_POINTS:
			var a := Vector2.from_angle(TAU * i / ARC_POINTS)
			var b := Vector2.from_angle(TAU * (i + 1) / ARC_POINTS)
			verts.append_array([a * inner, a * outer, b * outer, a * inner, b * outer, b * inner])
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(DUST)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
