class_name BirdPerches
extends RefCounted
## Where the ambient crows perch, and the two choices a group makes: whether
## something is close enough to scatter it, and which perch it flies to.
##
## User-ruled 2026-10-31 through the question form, "Outdoors, a bit larger":
## flocks perch where cars and passengers pass (road edge, curb bays, car
## parks, forecourt) and are seen when the player looks at the landside, not
## from the default view over the terminal.
##
## Each perch is a patch of one flat outdoor surface with only open sky, or
## the high entrance canopy, above it (test_bird_perches.gd measures every
## patch against the shell and the car park models):
## - the forecourt between the entrance porches (Porch_7, Porch_8: cut away
##   at the default zoom but shown from far out, so no patch is under one);
## - the road edge at the curb in front of the west gap (y 0.1; the curb bay
##   kerb, TP_Curb_Bay_01A at 0.127, is uneven and has none);
## - the road's far sidewalk, west and east of the multi-storey;
## - the surface lot's aisle while that lot is built (LOTS).
## The multi-storey has none: its 10.3 m deck has the next slab at 20.3 m over
## it and the lower decks the one at 10 m, so every deck is under a slab.
##
## A group only flies within its zone, where every flight clears the shell,
## the curb bays and the car parks (test_bird_flight_clearance.gd):
## UNDER_CANOPY (forecourt and curb, arches over the porch roofs and under the
## canopy), WEST and EAST (the sidewalk and lot either side of the 20 m tall
## multi-storey, which no arch clears).

enum Zone { UNDER_CANOPY, WEST, EAST }

## Patch centres, on the surface top.
const SPOTS: Array[Vector3] = [
	Vector3(-30.1, 0.2, -62.8),
	Vector3(-30.1, 0.2, -61.5),
	Vector3(-21.2, 0.2, -62.8),
	Vector3(-21.2, 0.2, -61.5),
	Vector3(-30.3, 0.1, -57.6),
	Vector3(-38.0, 0.2, -40.6),
	Vector3(-27.0, 0.2, -40.6),
	Vector3(-17.0, 0.2, -40.6),
	Vector3(16.0, 0.2, -40.6),
	Vector3(40.0, 0.2, -40.6),
	Vector3(31.7, 0.1, -27.0),
	Vector3(31.7, 0.1, -17.0),
	Vector3(-32.5, 0.2, -40.6),
	Vector3(-22.0, 0.2, -40.6),
	Vector3(22.0, 0.2, -40.6),
]
## How far each patch reaches from its centre along x and z.
const HALVES: Array[Vector2] = [
	Vector2(0.75, 0.35),
	Vector2(0.75, 0.35),
	Vector2(0.75, 0.35),
	Vector2(0.75, 0.35),
	Vector2(0.8, 0.4),
	Vector2(1.5, 0.35),
	Vector2(1.5, 0.35),
	Vector2(1.5, 0.35),
	Vector2(1.5, 0.35),
	Vector2(1.5, 0.35),
	Vector2(1.2, 1.2),
	Vector2(1.2, 1.2),
	Vector2(1.5, 0.35),
	Vector2(1.5, 0.35),
	Vector2(1.5, 0.35),
]
const ZONES: Array[int] = [
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.WEST,
	Zone.WEST,
	Zone.WEST,
	Zone.EAST,
	Zone.EAST,
	Zone.EAST,
	Zone.EAST,
	Zone.WEST,
	Zone.WEST,
	Zone.EAST,
]
## The lot spot (LandsideSim.lots_built) a perch needs built, or -1.
const LOTS: Array[int] = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, -1, -1, -1]
## Birds in one patch stand at least this far apart at bird scale 1, so two
## perched crows (0.23 m wide, 0.56 m long) never overlap whatever their heading.
const MIN_SPACING := 0.55
## A moving car or a passenger this close to a perched group scatters it. A
## car at a curb berth straight in front of a forecourt patch is 4.4 m from
## the front row and 5.8 m from the back row, and scatters both; a car passing
## in the near lane (z -55) is 6.6 m or more from the forecourt and does not.
const SCATTER_RADIUS := 6.3
## A scattered group prefers a perch with nothing this close.
const LAND_CLEAR := 9.0


## Whether anything in `threats` is within `radius` of `centre`, measured flat
## (on the ground plane), so a car's origin height does not matter.
static func scatter_due(
	centre: Vector3, threats: PackedVector3Array, radius := SCATTER_RADIUS
) -> bool:
	for t in threats:
		if Vector2(t.x - centre.x, t.z - centre.z).length() <= radius:
			return true
	return false


## The flat distance from `centre` to the nearest of `threats` (INF for none).
static func nearest(centre: Vector3, threats: PackedVector3Array) -> float:
	var best := INF
	for t in threats:
		best = minf(best, Vector2(t.x - centre.x, t.z - centre.z).length())
	return best


## The perches there are now: every perch whose lot (LOTS) is built.
static func available(lots_built: Array[bool]) -> Array[int]:
	var out: Array[int] = []
	for i in SPOTS.size():
		if LOTS[i] < 0 or (LOTS[i] < lots_built.size() and lots_built[LOTS[i]]):
			out.append(i)
	return out


## The perch a group on `from_spot` flies to: one in the same zone, not in
## `busy` (the perches other groups hold or fly to, and the ones not there
## now) and not `from_spot`, picked at random among those with nothing within
## LAND_CLEAR; when none is clear, the one whose nearest threat is farthest.
## -1 when no other perch in the zone is free.
static func pick(
	rng: RandomNumberGenerator, from_spot: int, busy: Array[int], threats: PackedVector3Array
) -> int:
	var clear: Array[int] = []
	var best := -1
	var best_gap := -1.0
	for i in SPOTS.size():
		if i == from_spot or busy.has(i) or ZONES[i] != ZONES[from_spot]:
			continue
		var gap := nearest(SPOTS[i], threats)
		if gap >= LAND_CLEAR:
			clear.append(i)
		if gap > best_gap:
			best_gap = gap
			best = i
	if not clear.is_empty():
		return clear[rng.randi_range(0, clear.size() - 1)]
	return best


## Up to `count` places inside patch `spot`, as offsets from its centre on the
## ground plane (y 0), each at least MIN_SPACING * `scale` from the others;
## fewer when the patch has no more room. Random placement can box itself in,
## so it starts over up to 20 times and keeps the fullest try.
static func offsets(
	rng: RandomNumberGenerator, count: int, spot: int, scale := 1.0
) -> Array[Vector3]:
	var best: Array[Vector3] = []
	for attempt in 20:
		var got := _place_once(rng, count, HALVES[spot], MIN_SPACING * scale)
		if got.size() > best.size():
			best = got
		if best.size() == count:
			break
	return best


static func _place_once(
	rng: RandomNumberGenerator, count: int, half: Vector2, spacing: float
) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for tries in 200:
		if out.size() == count:
			break
		var p := Vector3(rng.randf_range(-half.x, half.x), 0.0, rng.randf_range(-half.y, half.y))
		var ok := true
		for q in out:
			if p.distance_to(q) < spacing:
				ok = false
				break
		if ok:
			out.append(p)
	return out
