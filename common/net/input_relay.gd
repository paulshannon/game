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
## Optional `func() -> BotInput` for a game's own bot (a BotInput subclass).
## Called once, only on the client that owns this player; otherwise a
## wandering BotInput is used.
var make_bot: Callable
## Server: the pilot of a bot the server flies itself (ServerBots). Its input
## is accepted directly, as if it had arrived from a client.
var server_bot: BotInput
## The game's one button action (GameBase.action_button(), set by the
## spawner). Only it is sent: in a game without fire, Space (also bound to
## jump) must not send fire, and the other way round.
var action: StringName = &""

## Latest accepted input, read by the server-side player each physics tick.
var move: Vector2 = Vector2.ZERO
var jump: bool = false
var fire: bool = false
## Sideways: -1 left .. 1 right (strafe actions; games that don't strafe ignore it).
var strafe: float = 0.0
var last_seq: int = -1

var _seq: int = 0
## Server: seconds since the last accepted input (see Protocol.INPUT_TIMEOUT).
var _since_input: float = 0.0
var _send_accum: float = 0.0
var _bot: BotInput = null
## The key that pressed the menu's Play button (Space is ui_accept too) may
## still be down when the player spawns: ignore it until it's released.
var _wait_for_release: bool = true


func _ready() -> void:
	if use_bot and is_local_owner():
		_bot = make_bot.call() as BotInput if make_bot.is_valid() else BotInput.new(owner_peer)


func is_local_owner() -> bool:
	return Net.is_online() \
			and not multiplayer.is_server() \
			and multiplayer.get_unique_id() == owner_peer


func _physics_process(delta: float) -> void:
	if Net.is_online() and multiplayer.is_server():
		if server_bot != null:
			_fly_server_bot(delta)
		age_input(delta)
		return
	if not is_local_owner():
		return
	_send_accum += delta
	var interval: float = 1.0 / Protocol.INPUT_HZ
	if _send_accum < interval:
		return
	_send_accum = fmod(_send_accum, interval)

	var m: Vector2
	var pressed: bool
	var side: float
	if _bot != null:
		_bot.update(interval)
		m = _bot.move
		side = _bot.strafe
		pressed = (action == InputSetup.JUMP and _bot.jump) or (action == InputSetup.FIRE and _bot.fire)
	else:
		m = Input.get_vector(InputSetup.LEFT, InputSetup.RIGHT, InputSetup.UP, InputSetup.DOWN)
		side = Input.get_axis(InputSetup.STRAFE_LEFT, InputSetup.STRAFE_RIGHT)
		pressed = gate_button(not action.is_empty() and Input.is_action_pressed(action))
	_seq += 1
	submit_input.rpc_id(1, m, pressed and action == InputSetup.JUMP, pressed and action == InputSetup.FIRE,
			side, _seq)


## Server: the bot's input at INPUT_HZ, like a client would send it.
func _fly_server_bot(delta: float) -> void:
	_send_accum += delta
	var interval: float = 1.0 / Protocol.INPUT_HZ
	if _send_accum < interval:
		return
	_send_accum = fmod(_send_accum, interval)
	server_bot.update(interval)
	accept_input(server_bot.move, action == InputSetup.JUMP and server_bot.jump,
			action == InputSetup.FIRE and server_bot.fire, server_bot.strafe)


## Client: the button as sent. Held since before this player spawned counts
## as up until it's released once.
func gate_button(pressed: bool) -> bool:
	if _wait_for_release:
		if pressed:
			return false
		_wait_for_release = false
	return pressed


# "unreliable_ordered" is the correct intent: stale input is useless and newer
# input supersedes it. Over WebSocket (TCP) it is delivered reliably anyway;
# the annotation becomes real if the transport changes to WebRTC.
@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func submit_input(m: Vector2, j: bool, f: bool, s: float, seq: int) -> void:
	# A player sent back to select leaves the tree at once (GameBase), but
	# input already on its way can still be delivered to it: drop it.
	if not is_inside_tree() or not multiplayer.is_server():
		return
	# Never trust the caller: the sender must be the peer this player belongs to.
	if multiplayer.get_remote_sender_id() != owner_peer:
		return
	# Drop out-of-order or replayed packets.
	if seq <= last_seq:
		return
	last_seq = seq
	accept_input(m, j, f, s)


## Server: store a validated input and restart the staleness timer.
func accept_input(m: Vector2, j: bool, f: bool = false, s: float = 0.0) -> void:
	move = ArenaSim.sanitize_move(m)
	jump = j
	fire = f
	strafe = clampf(s, -1.0, 1.0) if is_finite(s) else 0.0
	_since_input = 0.0


## Server, every physics tick. A client that stops sending (backgrounded tab,
## stalled network) must not keep its last keys held forever: once input is
## older than INPUT_TIMEOUT, treat it as released.
func age_input(delta: float) -> void:
	_since_input += delta
	if _since_input >= Protocol.INPUT_TIMEOUT:
		move = Vector2.ZERO
		jump = false
		fire = false
		strafe = 0.0
