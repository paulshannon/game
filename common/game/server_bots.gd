class_name ServerBots
extends RefCounted
## Server: players the server flies itself, with no client behind them.
## The first person in a match picks how many (join_choice "bots"); they
## spawn like anyone else (same spawner, so every client draws them), and the
## server feeds their InputRelay from a BotInput (GameBase._make_server_bot)
## instead of the network.
##
## Bots never keep a person out: one gives up its seat when the match is full
## and someone connects, and all of them leave with the last person.

## Bot ids are negative (-1, -2, ...): real peer ids are always positive.
const MAX_BOTS: int = Protocol.MAX_PLAYERS - 1

var _game: GameBase
var _ids: Array[int] = []
## Most bots flying at once (smoke test).
var peak: int = 0


func _init(game: GameBase) -> void:
	_game = game


func count() -> int:
	return _ids.size()


static func is_bot(id: int) -> bool:
	return id < 0


## Flies `n` bots (0..MAX_BOTS), as far as free seats allow.
func set_count(n: int) -> void:
	n = clampi(n, 0, MAX_BOTS)
	while _ids.size() > n:
		remove(_ids.back())
	while _ids.size() < n and _add():
		pass
	peak = maxi(peak, _ids.size())
	print("[server] %d bot(s) flying" % _ids.size())


## Frees a seat for a person: removes the newest bot. False when there is none.
func give_up_seat() -> bool:
	if _ids.is_empty():
		return false
	remove(_ids.back())
	return true


func remove(id: int) -> void:
	_ids.erase(id)
	_game.release_seat(id)
	var p: Node = _game.players_root.get_node_or_null(str(id))
	if p != null:
		_game.players_root.remove_child(p)   # despawns on clients
		p.queue_free()


func _add() -> bool:
	var id: int = -1
	while _ids.has(id):
		id -= 1
	var index: int = _game.claim_seat(id)
	if index == -1:
		return false
	_ids.append(id)
	var choice: Dictionary = _game.bot_choice()
	choice.erase("bots")
	_game.spawn_player(id, index, choice, {"bot": true})
	return true
