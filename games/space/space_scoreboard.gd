class_name SpaceScoreboard
extends CanvasLayer
## Client: every ship's score, top-right, highest first, in the ship's colour.
## Reads the replicated SpaceShip.score; never computes a score itself.

const SHIP_COLORS: Dictionary = {
	"blue": Color(0.45, 0.75, 1.0),
	"green": Color(0.5, 0.95, 0.55),
	"orange": Color(1.0, 0.72, 0.35),
	"red": Color(1.0, 0.45, 0.45),
}

var players_root: Node

var _list: VBoxContainer
var _shown: String = ""


func _ready() -> void:
	layer = 4   # over the world, under the touch controls and menu
	var box := MarginContainer.new()
	box.name = "Scores"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("margin_right", 16)
	box.add_theme_constant_override("margin_top", 12)
	add_child(box)
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_list)


func _process(_delta: float) -> void:
	if players_root == null:
		return
	var rows: Array[SpaceShip] = []
	for p: Node in players_root.get_children():
		var ship: SpaceShip = p as SpaceShip
		if ship != null and not ship.is_queued_for_deletion():
			rows.append(ship)
	rows.sort_custom(func(a: SpaceShip, b: SpaceShip) -> bool:
		return a.score > b.score or (a.score == b.score and a.player_index() < b.player_index()))
	var me: int = multiplayer.get_unique_id() if Net.is_online() else 0
	var key: String = ""
	for ship: SpaceShip in rows:
		key += "%d:%d:%d;" % [ship.player_index(), ship.score, int(ship.peer_id() == me)]
	if key == _shown:
		return
	_shown = key
	for c: Node in _list.get_children():
		c.queue_free()
	for ship: SpaceShip in rows:
		var l := Label.new()
		var you: String = "  (you)" if ship.peer_id() == me else ""
		l.text = "P%d%s   %d" % [ship.player_index() + 1, you, ship.score]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_font_override("font", SpaceUi.font())
		l.add_theme_font_size_override("font_size", 22 if ship.peer_id() == me else 18)
		l.add_theme_color_override("font_color", SHIP_COLORS.get(ship.color_name(), Color.WHITE))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 4)
		_list.add_child(l)
