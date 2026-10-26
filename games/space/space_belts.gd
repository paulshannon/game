class_name SpaceBelts
extends RefCounted
## Pure rules for the asteroid belts: rings of rocks on circular orbits round
## the star (SpaceStar.orbit_position). SpaceDirector fills them at the start
## and tops them up as rocks are shot. No nodes: tests call these directly.
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
## A broken rock's two pieces go onto orbits this far inside and outside its
## own, so they part as they go round (inner orbits are faster).
const SPLIT_SPREAD: float = 30.0
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


## Where a rock broken at `at` puts its two pieces: on the orbits just inside
## and outside its own (empty for the smallest size, which just goes).
static func split_points(size: int, at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if size <= SpaceSim.SMALL:
		return out
	var out_dir: Vector2 = (at - SpaceStar.CENTER).normalized()
	out.append(at - out_dir * SPLIT_SPREAD)
	out.append(at + out_dir * SPLIT_SPREAD)
	return out
