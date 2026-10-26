class_name SpaceField
extends RefCounted
## Pure rules for the unbounded asteroid field: keeping rocks around every
## ship and forgetting the ones left far behind. No nodes: SpaceDirector
## (server) calls these with plain positions, and tests call them directly.
##
## "Anchors" are the points the field is kept around: every ship (a destroyed
## one is parked where it was hit, so it still counts), or the origin when
## nobody is playing.

const ROCKS_PER_ANCHOR: int = 6       # keep at least this many rocks near each ship
const NEAR_DISTANCE: float = 1000.0   # "near" for that count
## New rocks come in this far from a ship: just outside a 1280x720 view
## (half-diagonal ~734 px, plus a large rock's radius).
const ENTRY_DISTANCE: float = 800.0
## Rocks farther than this from every anchor are removed. Well beyond
## ENTRY_DISTANCE, so a rock never disappears from anyone's screen.
const STRAY_DISTANCE: float = 1800.0
## Entering rocks head for the ship, give or take this much (rad), so they
## cross its view instead of drifting off unseen.
const ENTRY_SPREAD: float = 0.7
const SAFE_DISTANCE: float = 260.0    # new rocks appear at least this far from every ship


static func count_near(anchor: Vector2, rocks: PackedVector2Array) -> int:
	var n: int = 0
	for r: Vector2 in rocks:
		if anchor.distance_squared_to(r) <= NEAR_DISTANCE * NEAR_DISTANCE:
			n += 1
	return n


## The anchor with the fewest rocks near it, if that's fewer than
## ROCKS_PER_ANCHOR; -1 when every anchor has enough.
static func neediest(anchors: PackedVector2Array, rocks: PackedVector2Array) -> int:
	var best: int = -1
	var best_n: int = ROCKS_PER_ANCHOR
	for i: int in anchors.size():
		var n: int = count_near(anchors[i], rocks)
		if n < best_n:
			best_n = n
			best = i
	return best


## Left far behind by everyone: nobody will see it again.
static func is_stray(p: Vector2, anchors: PackedVector2Array) -> bool:
	for a: Vector2 in anchors:
		if a.distance_squared_to(p) <= STRAY_DISTANCE * STRAY_DISTANCE:
			return false
	return true


## Whether a new rock at `p` keeps clear of every anchor.
static func is_clear(p: Vector2, anchors: PackedVector2Array) -> bool:
	for a: Vector2 in anchors:
		if a.distance_squared_to(p) < SAFE_DISTANCE * SAFE_DISTANCE:
			return false
	return true


## Where a rock enters for `anchor`: `angle` picks the side, `distance` how far.
static func entry_point(anchor: Vector2, angle: float, distance: float = ENTRY_DISTANCE) -> Vector2:
	return anchor + Vector2.from_angle(angle) * distance


## Its velocity: towards the anchor, turned by `turn` (-1..1 of ENTRY_SPREAD).
static func entry_velocity(at: Vector2, anchor: Vector2, turn: float, speed: float) -> Vector2:
	var dir: Vector2 = (anchor - at).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	return dir.rotated(clampf(turn, -1.0, 1.0) * ENTRY_SPREAD) * speed
