class_name InputRelay
extends Node
## Carries one player's input from their client to the server.
##
## This node exists on every peer (it is a child of the spawned player), so
## its node path is identical everywhere — which is what makes the RPC
## resolve. Only the owning client sends; only the server accepts.

## Peer that owns this player. Set by the spawner from spawn data.
var owner_peer: int = 0
## Drive input from a wandering bot instead of the keyboard (smoke tests).
var use_bot: bool = false

## Latest accepted input, read by the server-side player each physics tick.
var move: Vector2 = Vector2.ZERO
var jump: bool = false
var last_seq: int = -1

var _seq: int = 0
var _send_accum: float = 0.0
var _bot: BotInput = null


func _ready() -> void:
	if use_bot:
		_bot = BotInput.new(owner_peer)


func is_local_owner() -> bool:
	return Net.is_online() \
			and not multiplayer.is_server() \
			and multiplayer.get_unique_id() == owner_peer


func _physics_process(delta: float) -> void:
	if not is_local_owner():
		return
	_send_accum += delta
	var interval: float = 1.0 / Protocol.INPUT_HZ
	if _send_accum < interval:
		return
	_send_accum = fmod(_send_accum, interval)

	var m: Vector2
	var j: bool
	if _bot != null:
		_bot.update(interval)
		m = _bot.move
		j = _bot.jump
	else:
		m = Input.get_vector(InputSetup.LEFT, InputSetup.RIGHT, InputSetup.UP, InputSetup.DOWN)
		j = Input.is_action_pressed(InputSetup.JUMP)
	_seq += 1
	submit_input.rpc_id(1, m, j, _seq)


# "unreliable_ordered" is the correct intent: stale input is useless and newer
# input supersedes it. Over WebSocket (TCP) it is delivered reliably anyway;
# the annotation becomes real if the transport changes to WebRTC.
@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func submit_input(m: Vector2, j: bool, seq: int) -> void:
	if not multiplayer.is_server():
		return
	# Never trust the caller: the sender must be the peer this player belongs to.
	if multiplayer.get_remote_sender_id() != owner_peer:
		return
	# Drop out-of-order or replayed packets.
	if seq <= last_seq:
		return
	last_seq = seq
	move = ArenaSim.sanitize_move(m)
	jump = j
