class_name SpaceBelts
extends RefCounted
## Pure rules for the asteroid belts: rings of rocks orbiting the star
## (SpaceOrbit). Most go round on circles; some start a little slow or fast
## and sweep in and out across their ring; broken rocks' pieces fly apart onto
## all sorts of orbits, some diving into the star, some escaping. SpaceDirector
## fills the rings at the start and tops them up. No nodes: tests call these.
##
## The first ring sits just outside where ships spawn (SpaceStar.SAFE_RADIUS),
## so there's something to shoot at once; the outer ones are bigger and
## slower. Between and beyond the rings, space is empty.

## Each ring: Vector3(radius, half width, rocks to keep in it).
const RINGS: Array[Vector3] = [
	Vector3(1500.0, 160.0, 28),
	Vector3(2500.0, 220.0, 40),
	Vector3(3600.0, 280.0, 54),
]
## A new rock never appears closer than this to a ship (off its screen).
const CLEARANCE: float = 900.0
## Some new rocks start off circular speed (by OFF_SPEED times it), so their
## orbits are ellipses that sweep in and out across the ring.
const OFF_SPEED_SHARE: float = 0.4
const OFF_SPEED := Vector2(0.88, 1.12)
## A broken rock's two pieces fly apart: equal and opposite kicks of this
## many px/s in a random direction (momentum kept), starting SPLIT_GAP px
## apart along it. Circular speed in ring 1 is ~220 px/s and escape ~310, so
## the bigger kicks fling pieces out of the system or drop them into the star.
const SPLIT_KICK := Vector2(30.0, 140.0)
const SPLIT_GAP: float = 10.0
## Further out than this, a rock has escaped: the server removes it.
const ESCAPE_RADIUS: float = 6000.0
## Never more rocks than this many times the rings' total (rocks on wild
## orbits between the rings don't count towards any ring's refill).
const MAX_OVERFILL: float = 1.3
## Sizes of new rocks, by weight: mostly large.
const SIZE_WEIGHTS: Array[float] = [0.1, 0.3, 0.6]   # SpaceSim.SMALL, MEDIUM, LARGE


static func target_total() -> int:
	var n: int = 0
	for ring: Vector3 in RINGS:
		n += int(ring.z)
	return n


## Which ring a point at `at` belongs to (the band, a little widened), or -1.
static func ring_of(at: Vector2) -> int:
	var r: float = SpaceStar.distance(at)
	for i: int in RINGS.size():
		if absf(r - RINGS[i].x) <= RINGS[i].y * 1.5:
			return i
	return -1


## Rocks in each ring, from their positions.
static func counts(rocks: PackedVector2Array) -> Array[int]:
	var out: Array[int] = []
	out.resize(RINGS.size())
	for at: Vector2 in rocks:
		var i: int = ring_of(at)
		if i != -1:
			out[i] += 1
	return out


## The ring furthest below its count, or -1 when all are full.
static func neediest(rock_counts: Array[int]) -> int:
	var best: int = -1
	var best_gap: int = 0
	for i: int in RINGS.size():
		var gap: int = int(RINGS[i].z) - rock_counts[i]
		if gap > best_gap:
			best_gap = gap
			best = i
	return best


## A point in ring `ring`: random radius within its band, random angle
## (u, v in 0..1 from the caller's RNG).
static func point_in(ring: int, u: float, v: float) -> Vector2:
	var band: Vector3 = RINGS[ring]
	var r: float = band.x + (u * 2.0 - 1.0) * band.y
	return SpaceStar.CENTER + Vector2.from_angle(v * TAU) * r


## Whether a new rock may appear at `at`: not on anyone's screen.
static func is_clear(at: Vector2, ships: PackedVector2Array) -> bool:
	for s: Vector2 in ships:
		if at.distance_to(s) < CLEARANCE:
			return false
	return true


## A new rock's size from a 0..1 roll, weighted by SIZE_WEIGHTS.
static func size_for(roll: float) -> int:
	var acc: float = 0.0
	for size: int in SIZE_WEIGHTS.size():
		acc += SIZE_WEIGHTS[size]
		if roll < acc:
			return size
	return SIZE_WEIGHTS.size() - 1


## A new rock's velocity at `at`: circular, or (for OFF_SPEED_SHARE of them,
## by `roll`) that times a factor in OFF_SPEED (by `factor_roll`).
static func spawn_velocity(at: Vector2, roll: float, factor_roll: float) -> Vector2:
	var v: Vector2 = SpaceStar.circular_velocity(at)
	if roll >= OFF_SPEED_SHARE:
		return v
	return v * lerpf(OFF_SPEED.x, OFF_SPEED.y, factor_roll)


## The pieces of a rock of `size` broken at `at` while moving at `velocity`:
## [position, velocity] pairs, empty for the smallest (it just goes). The
## kick's direction is `angle`; its strength, `kick_roll` (0..1) across
## SPLIT_KICK.
static func split(size: int, at: Vector2, velocity: Vector2, angle: float, kick_roll: float) -> Array:
	if size <= SpaceSim.SMALL:
		return []
	var dir := Vector2.from_angle(angle)
	var kick: Vector2 = dir * lerpf(SPLIT_KICK.x, SPLIT_KICK.y, kick_roll)
	return [[at + dir * SPLIT_GAP, velocity + kick], [at - dir * SPLIT_GAP, velocity - kick]]


static func escaped(at: Vector2) -> bool:
	return SpaceStar.distance(at) > ESCAPE_RADIUS
