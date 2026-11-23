class_name BirdPerches
extends RefCounted
## Where the ambient crows perch, and the choices a group makes: whether
## something is close enough to scatter it, and which perch it flies to.
##
## Ground perches (SPOTS / HALVES / ZONES / LOTS) sit on flat open-sky patches
## off the buildable terminal plot (SiteDefinition, x -43..43, z -100..-60) and
## clear of LandsideStreetDressing props:
## - the forecourt road edge (west and east curb);
## - the south sidewalk and extended north/south highway sidewalks;
## - boulevard & car-park grass verges (y -0.10);
## - the surface lot's aisle while that lot is built (LOTS).
##
## Elevated perches are derived directly from LandsideStreetDressing.prop_specs()
## (streetlights, benches, and tree crowns) with exact local contact offsets and
## zero stroll radius so elevated birds never walk off a lamppost or rail.
##
## Cross-zone flights are allowed wherever the flight curve stays clear of the
## 28 m tall multi-storey car park (Parking_2A) and remains within local range.

enum Zone { UNDER_CANOPY, WEST, EAST }

## Ground patch centres, on the surface top (must stay clear of street props).
const SPOTS: Array[Vector3] = [
	Vector3(-31.3, 0.1, -57.6),
	Vector3(-24.8, 0.1, -57.6),
	Vector3(-40.0, 0.2, -40.6),
	Vector3(-28.7, 0.2, -40.6),
	Vector3(-17.8, 0.2, -40.6),
	Vector3(15.7, 0.2, -40.6),
	Vector3(39.8, 0.2, -40.6),
	Vector3(31.7, 0.1, -27.0),
	Vector3(31.7, 0.1, -17.0),
	Vector3(-34.4, 0.2, -40.6),
	Vector3(-23.2, 0.2, -40.6),
	Vector3(21.5, 0.2, -40.6),
	Vector3(33.5, 0.1, -57.2),
	Vector3(-62.0, 0.2, -51.4),
	Vector3(-80.0, 0.2, -51.4),
	Vector3(62.0, 0.2, -51.4),
	Vector3(80.0, 0.2, -51.4),
	Vector3(-59.0, -0.1, -55.5),
	Vector3(59.0, -0.1, -55.5),
	Vector3(-70.0, 0.2, -40.6),
	Vector3(-32.0, -0.1, -36.5),
	Vector3(-22.0, -0.1, -36.5),
	Vector3(-68.0, -0.1, -35.8),
	Vector3(70.0, 0.2, -40.6),
	Vector3(52.0, -0.1, -29.0),
	Vector3(68.0, -0.1, -35.8),
]
## How far each ground patch reaches from its centre along x and z.
const HALVES: Array[Vector2] = [
	Vector2(2.0, 0.45),
	Vector2(2.0, 0.45),
	Vector2(2.3, 0.22),
	Vector2(2.6, 0.22),
	Vector2(2.3, 0.22),
	Vector2(2.2, 0.22),
	Vector2(2.4, 0.22),
	Vector2(2.0, 2.0),
	Vector2(2.0, 2.0),
	Vector2(2.3, 0.22),
	Vector2(2.3, 0.22),
	Vector2(2.0, 0.22),
	Vector2(1.8, 0.35),
	Vector2(2.3, 0.22),
	Vector2(2.3, 0.22),
	Vector2(2.3, 0.22),
	Vector2(2.3, 0.22),
	Vector2(2.2, 1.5),
	Vector2(2.2, 1.5),
	Vector2(2.3, 0.22),
	Vector2(2.2, 1.2),
	Vector2(2.2, 1.2),
	Vector2(2.2, 1.4),
	Vector2(2.3, 0.22),
	Vector2(2.2, 1.5),
	Vector2(2.2, 1.4),
]
const ZONES: Array[int] = [
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
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.UNDER_CANOPY,
	Zone.WEST,
	Zone.WEST,
	Zone.WEST,
	Zone.WEST,
	Zone.EAST,
	Zone.EAST,
	Zone.EAST,
]
## The lot spot (LandsideSim.lots_built) a ground perch needs built, or -1.
const LOTS: Array[int] = [
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	0,
	0,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
	-1,
]
## Birds in one patch stand at least this far apart at bird scale 1, so two
## perched crows (0.23 m wide, 0.66 m long) keep clear air in any heading.
const MIN_SPACING := 0.95
## A moving car or a passenger this close to a low perch scatters it.
const SCATTER_RADIUS := 6.3
## Elevated perches >= HIGH_PERCH_Y (lamps, trees) use 3D scatter distance so
## traffic 6 m below does not flush them continuously.
const HIGH_PERCH_Y := 2.5
const HIGH_SCATTER_RADIUS := 5.0
## A scattered group prefers a perch with nothing this close.
const LAND_CLEAR := 9.0
## Maximum flat distance for a single scatter flight across the landside.
const MAX_FLIGHT_SPAN := 68.0
## Multi-storey footprint (Parking_2A: x -12..12, z -40..18) grown by wingspan margin.
const MULTI_CLEAR := Rect2(-13.4, -41.4, 26.8, 60.8)
## Local prop bounding boxes (x/z half-extents + top y) used for flight clearance.
const PROP_BOXES := {
	"lamp_ped": [Vector2(-0.36, -0.36), Vector2(0.36, 0.36), 4.24],
	"lamp_hwy": [Vector2(-2.06, -0.40), Vector2(0.40, 0.40), 5.97],
	"signpost": [Vector2(-0.80, -0.21), Vector2(0.80, 0.21), 4.83],
	"tree_planter": [Vector2(-1.44, -1.44), Vector2(1.44, 1.44), 4.90],
	"tree_leaf": [Vector2(-1.94, -2.36), Vector2(1.95, 1.94), 5.92],
	"pine": [Vector2(-1.34, -1.34), Vector2(1.34, 1.33), 6.24],
	"bush_pot": [Vector2(-0.56, -0.56), Vector2(0.58, 0.56), 1.67],
	"bush_hedge": [Vector2(-0.89, -0.92), Vector2(0.84, 0.90), 1.93],
	"bench": [Vector2(-0.29, -0.97), Vector2(0.39, 0.99), 0.96],
	"trash": [Vector2(-0.35, -0.35), Vector2(0.35, 0.35), 0.91],
	"bollard": [Vector2(-0.15, -0.15), Vector2(0.15, 0.15), 0.90],
}
const CLEARANCE_PAD := 0.12
const BODY_RADIUS := 0.85
const BODY_UP := 0.375
## Curb / grass / sidewalk capacity for group offsets.
const GROUND_CAPACITY := 6
## Measured local contact offsets on LandsideStreetDressing props.
const LAMP_PED_LOCAL := Vector3(0.0, 4.2342, 0.0)
const LAMP_HWY_LOCAL := Vector3(-1.80, 5.9674, 0.0)
const BENCH_LOCAL := Vector3(0.32, 0.9523, 0.0)
const BENCH_SLOTS_LOCAL: Array[Vector3] = [
	Vector3(0.32, 0.9523, -0.60),
	Vector3(0.32, 0.9523, 0.60),
]
const TREE_PLANTER_LOCAL := Vector3(0.0, 4.7026, 0.0)
const PINE_LOCAL := Vector3(0.0, 6.0269, 0.0)
const TREE_LEAF_LOCAL := Vector3(0.0, 5.8337, 0.0)
const MAX_ELEVATED_X := 85.0
const MAX_HWY_LAMP_X := 75.0

static var _all_cache: Array[Dictionary] = []
static var _obstacle_cache: Array[Dictionary] = []
static var _fly_cache: Dictionary = {}


static func _perches() -> Array[Dictionary]:
	if not _all_cache.is_empty():
		return _all_cache
	var out: Array[Dictionary] = []
	for i in SPOTS.size():
		var p := SPOTS[i]
		var kind := "grass" if is_equal_approx(p.y, -0.1) else "ground"
		(
			out
			. append(
				{
					"pos": p,
					"half": HALVES[i],
					"zone": ZONES[i],
					"lot": LOTS[i],
					"elevated": false,
					"kind": kind,
					"capacity": GROUND_CAPACITY,
					"slots": [],
				}
			)
		)
	for spec in LandsideStreetDressing.prop_specs():
		var kind: String = spec["kind"]
		var pos: Vector3 = spec["pos"]
		var rot_y: float = spec["rot_y"]
		var entry := _elevated_from_prop(kind, pos, rot_y)
		if not entry.is_empty():
			out.append(entry)
	_all_cache = out
	return _all_cache


static func _elevated_from_prop(kind: String, pos: Vector3, rot_y: float) -> Dictionary:
	var local := Vector3.ZERO
	var slots: Array[Vector3] = []
	var cap := 1
	if kind == "lamp_ped":
		local = LAMP_PED_LOCAL
	elif kind == "lamp_hwy":
		if absf(pos.x) > MAX_HWY_LAMP_X:
			return {}
		local = LAMP_HWY_LOCAL
	elif kind == "bench":
		local = BENCH_LOCAL
		cap = BENCH_SLOTS_LOCAL.size()
		var center_world := pos + local.rotated(Vector3.UP, rot_y)
		for s in BENCH_SLOTS_LOCAL:
			slots.append((pos + s.rotated(Vector3.UP, rot_y)) - center_world)
	elif kind == "tree_planter":
		local = TREE_PLANTER_LOCAL
	elif kind == "pine":
		if absf(pos.x) > MAX_ELEVATED_X:
			return {}
		local = PINE_LOCAL
	elif kind == "tree_leaf":
		if absf(pos.x) > MAX_ELEVATED_X:
			return {}
		local = TREE_LEAF_LOCAL
	else:
		return {}
	var world_pos := pos + local.rotated(Vector3.UP, rot_y)
	var zone := _zone_of(world_pos)
	return {
		"pos": world_pos,
		"half": Vector2.ZERO,
		"zone": zone,
		"lot": -1,
		"elevated": true,
		"kind": kind,
		"capacity": cap,
		"slots": slots,
	}


static func _zone_of(world_pos: Vector3) -> int:
	if world_pos.z <= -48.5:
		return Zone.UNDER_CANOPY
	if world_pos.x < 0.0:
		return Zone.WEST
	return Zone.EAST


static func perch_count() -> int:
	return _perches().size()


static func spot_pos(i: int) -> Vector3:
	return _perches()[i]["pos"]


static func spot_half(i: int) -> Vector2:
	return _perches()[i]["half"]


static func spot_zone(i: int) -> int:
	return _perches()[i]["zone"]


static func spot_lot(i: int) -> int:
	return _perches()[i]["lot"]


static func is_elevated(i: int) -> bool:
	return _perches()[i]["elevated"]


static func spot_kind(i: int) -> String:
	return _perches()[i]["kind"]


static func spot_capacity(i: int) -> int:
	return _perches()[i]["capacity"]


static func can_stroll(i: int) -> bool:
	var p := _perches()[i]
	return not bool(p["elevated"]) and (p["half"] as Vector2).length_squared() > 0.01


## Whether anything in `threats` is within `radius` of `centre`, measured flat
## (on the ground plane), so a car's origin height does not matter.
static func scatter_due(
	centre: Vector3, threats: PackedVector3Array, radius := SCATTER_RADIUS
) -> bool:
	for t in threats:
		if Vector2(t.x - centre.x, t.z - centre.z).length() <= radius:
			return true
	return false


## 3D distance check used for high perches (>= HIGH_PERCH_Y) above traffic.
static func scatter_due_3d(
	centre: Vector3, threats: PackedVector3Array, radius := HIGH_SCATTER_RADIUS
) -> bool:
	for t in threats:
		if centre.distance_to(t) <= radius:
			return true
	return false


## The ground-plane box (x, z) holding every patch grown by SCATTER_RADIUS:
## a car or passenger outside it cannot scatter any group.
static func reach() -> Rect2:
	var list := _perches()
	var first_pos: Vector3 = list[0]["pos"]
	var box := Rect2(Vector2(first_pos.x, first_pos.z), Vector2.ZERO)
	for entry in list:
		var pos: Vector3 = entry["pos"]
		var half: Vector2 = (entry["half"] as Vector2) + Vector2.ONE * SCATTER_RADIUS
		var c := Vector2(pos.x, pos.z)
		box = box.merge(Rect2(c - half, half * 2.0))
	return box


## The flat distance from `centre` to the nearest of `threats` (INF for none).
static func nearest(centre: Vector3, threats: PackedVector3Array) -> float:
	var best := INF
	for t in threats:
		best = minf(best, Vector2(t.x - centre.x, t.z - centre.z).length())
	return best


## The perches there are now: every perch whose lot (spot_lot) is built.
static func available(lots_built: Array[bool]) -> Array[int]:
	var out: Array[int] = []
	var list := _perches()
	for i in list.size():
		var lot: int = list[i]["lot"]
		if lot < 0 or (lot < lots_built.size() and lots_built[lot]):
			out.append(i)
	return out


## Whether a group can fly smoothly from `from_spot` to `to_spot` without
## crossing the multi-storey, surface car park roof, or street props.
static func can_fly(from_spot: int, to_spot: int) -> bool:
	if from_spot == to_spot:
		return false
	var key := (from_spot << 16) | to_spot
	if _fly_cache.has(key):
		return _fly_cache[key]
	var a := spot_pos(from_spot)
	var b := spot_pos(to_spot)
	var ok := Vector2(a.x - b.x, a.z - b.z).length() <= MAX_FLIGHT_SPAN
	if ok:
		var hi := spot_half(from_spot)
		var hj := spot_half(to_spot)
		var lifts := BirdFlock.lift_bounds(a, b, spot_zone(to_spot))
		var from_offs := _endpoints_of(from_spot, a, hi)
		var to_offs := _endpoints_of(to_spot, b, hj)
		for pa in from_offs:
			if not ok:
				break
			for pb in to_offs:
				if not ok:
					break
				for lift: float in [lifts.x, (lifts.x + lifts.y) * 0.5, lifts.y]:
					if not _curve_clear(pa, pb, lift):
						ok = false
						break
	_fly_cache[key] = ok
	return ok


static func _endpoints_of(spot: int, centre: Vector3, half: Vector2) -> Array[Vector3]:
	var slots: Array = _perches()[spot]["slots"]
	if not slots.is_empty():
		var out: Array[Vector3] = [centre]
		for s: Vector3 in slots:
			out.append(centre + s)
		return out
	if half == Vector2.ZERO:
		return [centre]
	return [
		centre,
		centre + Vector3(-half.x, 0, -half.y),
		centre + Vector3(half.x, 0, half.y),
		centre + Vector3(-half.x, 0, half.y),
		centre + Vector3(half.x, 0, -half.y),
	]


static func _obstacles() -> Array[Dictionary]:
	if not _obstacle_cache.is_empty():
		return _obstacle_cache
	var out: Array[Dictionary] = [
		{"rect": MULTI_CLEAR, "min_y": -0.2, "max_y": 29.0},
		{
			"rect": Rect2(19.7 - CLEARANCE_PAD, -40.2 - CLEARANCE_PAD, 24.1, 34.8),
			"min_y": 0.25,
			"max_y": 3.2,
		},
	]
	for spec in LandsideStreetDressing.prop_specs():
		var kind: String = spec["kind"]
		if not PROP_BOXES.has(kind):
			continue
		var entry: Array = PROP_BOXES[kind]
		var lo: Vector2 = entry[0]
		var hi: Vector2 = entry[1]
		var pos: Vector3 = spec["pos"]
		var rot_y: float = spec["rot_y"]
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		for cx in [lo.x, hi.x]:
			for cz in [lo.y, hi.y]:
				var w := pos + Vector3(cx, 0.0, cz).rotated(Vector3.UP, rot_y)
				min_p = min_p.min(Vector2(w.x, w.z))
				max_p = max_p.max(Vector2(w.x, w.z))
		var r := Rect2(min_p, max_p - min_p).grow(CLEARANCE_PAD)
		out.append({"rect": r, "min_y": pos.y - 0.1, "max_y": pos.y + float(entry[2]) + 0.05})
	_obstacle_cache = out
	return _obstacle_cache


static func _curve_clear(from: Vector3, to: Vector3, lift: float) -> bool:
	var obs := _obstacles()
	var sides := [
		Vector2.ZERO,
		Vector2(BODY_RADIUS, 0.0),
		Vector2(-BODY_RADIUS, 0.0),
		Vector2(0.0, BODY_RADIUS),
		Vector2(0.0, -BODY_RADIUS),
	]
	for k in 65:
		var u := float(k) / 64.0
		var body := BirdFlock.flight_point(from, to, lift, u) + Vector3.UP * BODY_UP
		var base_pt := Vector2(body.x, body.z)
		for o in obs:
			if body.y > float(o["max_y"]) or body.y < float(o["min_y"]):
				continue
			var r := o["rect"] as Rect2
			for s: Vector2 in sides:
				if r.has_point(base_pt + s):
					return false
	return true


## The perch a group of `count` birds on `from_spot` flies to: any reachable
## perch (including cross-zone and elevated perches) with enough capacity, not
## in `busy`, picked at random among those with nothing within LAND_CLEAR; when
## none is clear, the one whose nearest threat is farthest. -1 if none free.
static func pick(
	rng: RandomNumberGenerator,
	from_spot: int,
	busy: Array[int],
	threats: PackedVector3Array,
	count := 1
) -> int:
	var clear: Array[int] = []
	var best := -1
	var best_gap := -1.0
	var list := _perches()
	for i in list.size():
		if busy.has(i) or not can_fly(from_spot, i):
			continue
		if int(list[i]["capacity"]) < count:
			continue
		var gap := nearest(list[i]["pos"], threats)
		if gap >= LAND_CLEAR:
			clear.append(i)
		if gap > best_gap:
			best_gap = gap
			best = i
	if not clear.is_empty():
		return clear[rng.randi_range(0, clear.size() - 1)]
	return best


## Up to `count` places at perch `spot`, as offsets from its centre, each at
## least MIN_SPACING * `scale` from the others; elevated point perches hold 1
## bird at the anchor, benches hold up to 2 along their rail, ground patches
## pack randomly inside HALVES[spot].
static func offsets(
	rng: RandomNumberGenerator, count: int, spot: int, scale := 1.0
) -> Array[Vector3]:
	var entry := _perches()[spot]
	var slots: Array = entry["slots"]
	if not slots.is_empty():
		var pick_slots: Array[Vector3] = []
		for s: Vector3 in slots:
			pick_slots.append(s)
		if count == 1:
			return [pick_slots[rng.randi_range(0, pick_slots.size() - 1)]]
		var sliced: Array[Vector3] = []
		for idx in mini(count, pick_slots.size()):
			sliced.append(pick_slots[idx])
		return sliced
	if bool(entry["elevated"]):
		var single: Array[Vector3] = []
		if count >= 1:
			single.append(Vector3.ZERO)
		return single
	var half: Vector2 = entry["half"]
	var best: Array[Vector3] = []
	for attempt in 20:
		var got := _place_once(rng, count, half, MIN_SPACING * scale)
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
