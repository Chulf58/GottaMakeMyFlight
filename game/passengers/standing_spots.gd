class_name StandingSpots
extends RefCounted
## Where passengers stand at the gate when every gate seat is taken (decision
## passenger-spacing-fixed-per-cause-standing-spots-staggered-unloading-
## ordered-files, part 1).
##
## Spots are points on a fixed 0.6 m lattice in grid-local millimetres, so a
## spot's id (its lattice index) stays the same across edits. They are derived
## from the grid and layout after an edit: a breadth-first walk over routable
## steps (BuildGrid.can_route, which never crosses a scanner, so it stays
## airside) starts at the gate seats' access cells. The sim has one gate and
## no per-gate seat grouping, so every gate seat counts; with no seats the walk
## starts at the exit doors. Cells up to NEAR_STEPS steps out are the gate
## area, and cells up to OVERFLOW_STEPS out are the overflow. A cell holds
## no spot when it is a queue lane, a scanner passage or exit, a security
## lane's kept-clear cell, a staff spot, an object's interaction cell, a seat
## access cell, a door cell or inside a room.
##
## Passenger claims are separate from the spots: one spot per passenger and
## one passenger per spot. They are saved (to_list()) and restored as saved,
## never allocated again on load. A claim whose spot an edit removed is
## dropped (drop_invalid()) and the passenger plans again.

const NO_SPOT := -1
const PITCH_MM := 600
const CELL_MM := 1000
## The first lattice point sits half a pitch in from the grid's edge.
const OFFSET_MM := 300
const HALF_CELL_MM := 500
## Steps from a seat access cell that still count as the gate area.
const NEAR_STEPS := 2
## How far the overflow reaches, in steps from a seat access cell.
const OVERFLOW_STEPS := 12
const NEAR := 0
const OVERFLOW := 1
## The nearest free spots a claim tries a path to before it gives up.
const TRIES := 4
const STEPS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(1, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

## Spot id -> {"cell": Vector2i, "mm": Vector2i (grid-local), "tier": NEAR or
## OVERFLOW}.
var spots: Dictionary = {}
## Set by an edit; the sim rebuilds on its next tick.
var stale := true
## Spot id -> passenger id.
var _claims: Dictionary = {}
## Passenger id -> spot id.
var _spot_of: Dictionary = {}
var _ids: Array[int] = []


## Lattice points per grid row.
static func columns(grid_size: Vector2i) -> int:
	@warning_ignore("integer_division")
	return (grid_size.x * CELL_MM - OFFSET_MM + PITCH_MM - 1) / PITCH_MM


## The lattice indices whose points fall inside cell coordinate `c`.
static func lattice_in(c: int) -> Array[int]:
	var out: Array[int] = []
	@warning_ignore("integer_division")
	var first := (c * CELL_MM - OFFSET_MM + PITCH_MM - 1) / PITCH_MM
	@warning_ignore("integer_division")
	var last := (c * CELL_MM + CELL_MM - 1 - OFFSET_MM) / PITCH_MM
	for i in range(first, last + 1):
		out.append(i)
	return out


## Derives the spots from the sim's grid and layout. Claims are kept; the sim
## drops the ones whose spot is gone (drop_invalid()).
func rebuild(sim: PassengerSim) -> void:
	var grid := sim.grid
	var layout := sim.layout
	spots.clear()
	stale = false
	var excluded := _excluded_cells(sim)
	var frontier: Array[Vector2i] = []
	for seat in layout.seats:
		if not frontier.has(seat["front"]):
			frontier.append(seat["front"])
	if frontier.is_empty():
		for door in layout.exits:
			frontier.append(layout.door_cell(grid, door))
	var depth := {}
	for cell in frontier:
		depth[cell] = 0
	var head := 0
	while head < frontier.size():
		var cell := frontier[head]
		head += 1
		if depth[cell] >= OVERFLOW_STEPS:
			continue
		for step in STEPS:
			var next := cell + step
			if not depth.has(next) and grid.can_route(cell, next):
				depth[next] = depth[cell] + 1
				frontier.append(next)
	var per_row := columns(grid.size)
	for cell in frontier:
		if excluded.has(cell) or not grid.is_walkable(cell) or grid.room_at(cell) != 0:
			continue
		var tier := NEAR if depth[cell] <= NEAR_STEPS else OVERFLOW
		for j in lattice_in(cell.y):
			for i in lattice_in(cell.x):
				var mm := Vector2i(OFFSET_MM + PITCH_MM * i, OFFSET_MM + PITCH_MM * j)
				spots[j * per_row + i] = {"cell": cell, "mm": mm, "tier": tier}
	_ids.assign(spots.keys())
	_ids.sort()


## The spot a passenger holds, or NO_SPOT.
func spot_of(passenger: int) -> int:
	return _spot_of.get(passenger, NO_SPOT)


## The passenger holding a spot, or 0.
func holder_of(spot: int) -> int:
	return _claims.get(spot, 0)


func cell_of(spot: int) -> Vector2i:
	return spots[spot]["cell"]


func tier_of(spot: int) -> int:
	return spots[spot]["tier"]


func world_of(grid: BuildGrid, spot: int) -> Vector3:
	var mm: Vector2i = spots[spot]["mm"]
	return grid.origin + Vector3(mm.x / float(CELL_MM), 0.0, mm.y / float(CELL_MM))


func claim_count() -> int:
	return _claims.size()


## Whether `p` is held: on its way to the gate with no seat and no spot, and
## not walking, so it waits where it stands until one frees up.
func is_held(p: Passenger) -> bool:
	return (
		p.stage == Passenger.Stage.TO_GATE
		and p.seat_object == 0
		and not _spot_of.has(p.id)
		and not p.is_moving()
	)


## How many of the sim's passengers are held for want of a seat or spot: the
## shortage the HUD can show.
func shortage(sim: PassengerSim) -> int:
	var count := 0
	for id in sim.passenger_ids():
		count += int(is_held(sim.get_passenger(id)))
	return count


## The free spots in claim order: the gate area before the overflow, then the
## nearest to the centre of cell `from` (squared mm), then the lower id.
func free_nearest(from: Vector2i) -> Array[int]:
	var centre := from * CELL_MM + Vector2i(HALF_CELL_MM, HALF_CELL_MM)
	var keyed := []
	for id in _ids:
		if _claims.has(id):
			continue
		var d: Vector2i = spots[id]["mm"] - centre
		keyed.append([spots[id]["tier"], d.x * d.x + d.y * d.y, id])
	keyed.sort()
	var out: Array[int] = []
	for entry in keyed:
		out.append(entry[2])
	return out


func claim(passenger: int, spot: int) -> void:
	release(passenger)
	_claims[spot] = passenger
	_spot_of[passenger] = spot


func release(passenger: int) -> void:
	if _spot_of.has(passenger):
		_claims.erase(_spot_of[passenger])
		_spot_of.erase(passenger)


## Releases every claim whose spot the last rebuild removed and returns those
## passengers' ids in order.
func drop_invalid() -> Array[int]:
	var out: Array[int] = []
	for passenger: int in _spot_of:
		if not spots.has(_spot_of[passenger]):
			out.append(passenger)
	out.sort()
	for passenger in out:
		release(passenger)
	return out


## The claims for a save, in passenger id order.
func to_list() -> Array:
	var ids: Array = _spot_of.keys()
	ids.sort()
	var out := []
	for passenger in ids:
		out.append({"passenger": passenger, "spot": _spot_of[passenger]})
	return out


## Saved claims checked against the spots (rebuild() first) and the loaded
## passengers by id: {"claims": {passenger: spot}}, or {"error": text}. A
## claim must name a known passenger at most once, a spot that exists at most
## once, and a cleared passenger with no seat on its way to the gate or
## standing on that spot's cell.
func checked(list: Variant, by_id: Dictionary) -> Dictionary:
	if typeof(list) != TYPE_ARRAY:
		return {"error": "standing must be a list"}
	var claims := {}
	var taken := {}
	for entry: Variant in list:
		if (
			typeof(entry) != TYPE_DICTIONARY
			or (entry as Dictionary).size() != 2
			or not WholeNumber.is_whole(entry.get("passenger"))
			or not WholeNumber.is_whole(entry.get("spot"))
		):
			return {"error": "standing claim %s is malformed" % str(entry).left(80)}
		var id := int(entry["passenger"])
		var spot := int(entry["spot"])
		var p: Passenger = by_id.get(id)
		if p == null or claims.has(id) or taken.has(spot) or not spots.has(spot):
			return {"error": "standing claim %d -> %d is unknown or repeated" % [id, spot]}
		var on_way := p.stage == Passenger.Stage.TO_GATE
		var standing := p.stage == Passenger.Stage.STANDING and p.at == cell_of(spot)
		if not p.cleared or p.seat_object != 0 or not (on_way or standing):
			return {"error": "passenger %d cannot hold standing spot %d" % [id, spot]}
		claims[id] = spot
		taken[spot] = true
	return {"claims": claims}


## Replaces every claim with checked()'s claims.
func restore(claims: Dictionary) -> void:
	_claims.clear()
	_spot_of.clear()
	for passenger: int in claims:
		_spot_of[passenger] = claims[passenger]
		_claims[claims[passenger]] = passenger


static func _excluded_cells(sim: PassengerSim) -> Dictionary:
	var grid := sim.grid
	var layout := sim.layout
	var out := {}
	for id in grid.object_ids():
		out[grid.interaction_cell(id)] = true
		out[StaffSpots.spot_of(grid, id)] = true
	for cells: Array in layout.lanes.values():
		for cell: Vector2i in cells:
			out[cell] = true
	for cells: Array in layout.passages.values():
		for cell: Vector2i in cells:
			out[cell] = true
	for scanner in layout.scanners:
		out[sim.security.exit_cell(scanner)] = true
	for arch in layout.security_lanes.complete_arches():
		for cell in SecurityLanes.kept_clear_cells(layout.security_lanes.lane(arch)):
			out[cell] = true
	for seat in layout.seats:
		out[seat["front"]] = true
	for door in layout.entrances + layout.exits:
		out[layout.door_cell(grid, door)] = true
	return out
