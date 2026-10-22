class_name PlayerSlots
extends RefCounted
## Server-side seat assignment: which peer sits in which of MAX_PLAYERS slots.
##
## Why not count the Players node's children: a leaving player is only
## queue_free'd, so it still counts until the end of the frame. A peer that
## joins in that same frame (common when a browser tab reloads) would be told
## the match is full. And a join counter that only grows would hand out slot
## indexes past MAX_PLAYERS, spawning the newcomer on top of someone else.
## Slots are the source of truth instead: claimed on join, released on leave,
## and the lowest free one is reused.

var _capacity: int
var _slot_of: Dictionary = {}   # peer id -> slot index


func _init(capacity: int = Protocol.MAX_PLAYERS) -> void:
	_capacity = capacity


## Returns the slot for `peer` (the lowest free one), or -1 when full.
## Claiming twice returns the same slot.
func claim(peer: int) -> int:
	if _slot_of.has(peer):
		return int(_slot_of[peer])
	if _slot_of.size() >= _capacity:
		return -1
	var taken: Array = _slot_of.values()
	for i: int in _capacity:
		if not taken.has(i):
			_slot_of[peer] = i
			return i
	return -1


func release(peer: int) -> void:
	_slot_of.erase(peer)


func count() -> int:
	return _slot_of.size()
