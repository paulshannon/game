class_name SpaceEnergyBar
extends CanvasLayer
## Client: your ship's energy (SpaceShip.energy, replicated by the server) as
## a bar, bottom-centre. Turns red below one shot's worth. Hidden while your
## ship isn't in the match.

const SIZE := Vector2(260, 14)
const BOTTOM: float = 26.0
const FULL := Color(0.35, 0.85, 1.0)
const LOW := Color(1.0, 0.35, 0.3)

var arena: SpaceArena
## Lowest energy shown so far (smoke test: proves it's replicated).
var lowest_shown: int = int(SpaceStar.ENERGY_MAX)

var _canvas: Control


func _ready() -> void:
	layer = 4   # with the scoreboard and radar
	_canvas = Control.new()
	_canvas.name = "EnergyBar"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_bar)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _draw_bar() -> void:
	var own: SpaceShip = arena.local_player() as SpaceShip if arena != null else null
	if own == null:
		return
	lowest_shown = mini(lowest_shown, own.energy)
	var at := Vector2((_canvas.size.x - SIZE.x) * 0.5, _canvas.size.y - BOTTOM - SIZE.y)
	var frac: float = clampf(own.energy / SpaceStar.ENERGY_MAX, 0.0, 1.0)
	var color: Color = LOW if own.energy < SpaceStar.SHOT_COST else FULL
	_canvas.draw_rect(Rect2(at - Vector2(2, 2), SIZE + Vector2(4, 4)), Color(0.02, 0.05, 0.12, 0.7))
	_canvas.draw_rect(Rect2(at, Vector2(SIZE.x * frac, SIZE.y)), color)
	_canvas.draw_rect(Rect2(at, SIZE), Color(SpaceUi.STAR_WHITE, 0.4), false, 1.0)
	_canvas.draw_string(SpaceUi.font(), at + Vector2(0, -6), "ENERGY", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 13, Color(SpaceUi.STAR_WHITE, 0.6))
