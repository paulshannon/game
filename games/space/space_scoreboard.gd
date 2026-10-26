class_name SpaceScoreboard
extends CanvasLayer
## Client: scores top-right, by team (colours are teams): each team's total,
## best team first, then its ships, highest first, in the team's colour.
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
	var teams: Dictionary = {}   # colour index -> Array[SpaceShip]
	for p: Node in players_root.get_children():
		var ship: SpaceShip = p as SpaceShip
		if ship != null and not ship.is_queued_for_deletion():
			if not teams.has(ship.color_index()):
				teams[ship.color_index()] = [] as Array[SpaceShip]
			(teams[ship.color_index()] as Array[SpaceShip]).append(ship)
	var order: Array = teams.keys()
	order.sort_custom(func(a: int, b: int) -> bool:
		var ta: int = team_total(teams[a])
		var tb: int = team_total(teams[b])
		return ta > tb or (ta == tb and a < b))
	var me: int = multiplayer.get_unique_id() if Net.is_online() else 0
	var key: String = ""
	for t: int in order:
		for ship: SpaceShip in teams[t]:
			key += "%d:%d:%d:%d;" % [t, ship.player_index(), ship.score, int(ship.peer_id() == me)]
	if key == _shown:
		return
	_shown = key
	for c: Node in _list.get_children():
		c.queue_free()
	for t: int in order:
		var members: Array[SpaceShip] = teams[t]
		members.sort_custom(func(a: SpaceShip, b: SpaceShip) -> bool:
			return a.score > b.score or (a.score == b.score and a.player_index() < b.player_index()))
		var color: Color = SHIP_COLORS.get(SpaceShip.COLORS[t], Color.WHITE)
		_add_row("%s team   %d" % [SpaceShip.COLORS[t], team_total(members)], color, 20)
		for ship: SpaceShip in members:
			var mine: bool = ship.peer_id() == me
			var tag: String = "  (you)" if mine else ("  bot" if ship.is_bot() else "")
			_add_row("P%d%s   %d" % [ship.player_index() + 1, tag, ship.score], Color(color, 0.85),
					18 if mine else 15)


static func team_total(members: Array) -> int:
	var total: int = 0
	for ship: SpaceShip in members:
		total += ship.score
	return total


func _add_row(text: String, color: Color, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_override("font", SpaceUi.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(l)
