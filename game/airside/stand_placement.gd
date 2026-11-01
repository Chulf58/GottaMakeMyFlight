class_name StandPlacement
extends RefCounted
## Where the one plane stand goes on the airport site (decision plane-stand-
## design-airside-moves-110-m-north-stand-snaps-to, point 2). Pure: nothing
## here changes the grid.
##
## A stand is {"exit": exit door id (0 for none), "x": the door's x, "wall_z":
## the wall line's z}. The plane parks nose-in, straight out from a north-
## facing exit: its port door on the exit cell's centre x, its nose NOSE_GAP_M
## north of the wall line the exit stands in. It is pushed back PUSHBACK_M,
## turned to face north, and taxis north to the taxi lane at TAXI_LANE_Z.
##
## A candidate exit needs its parked plane clear of the shared lane zone
## (clears_lane()), a clear aircraft route (swept_rects(): the parked
## plane, the pushback and its swing, the way north to the taxi lane, with no
## floor, wall, object or site obstacle under any of it) and a passenger walk
## from the exit over open ground to the plane door (walk_of()). Candidates
## rank by that walk's length, then the live stand's exit, then the northmost
## wall line, then the lowest door id. With none the result is UNAVAILABLE and
## the live stand stays.
##
## Not guaranteed: the swing area is a rectangle around the pushback, a little
## wider than the plane really sweeps, so it can refuse a building the plane
## would just miss.

const OK := "ok"
const UNAVAILABLE := "unavailable"
## The plane's shape about its stand point (tp_plane_05a.glb with PlaneView's
## model_offset): nose 14.7 m ahead, tail 14.85 m behind, wings 14.2 m out.
const NOSE_M := 14.7
const TAIL_M := 14.85
const HALF_SPAN_M := 14.2
## Farthest any part of the plane reaches from its stand point.
const SWING_RADIUS_M := 20.6
## The gap between the wall line and the nose.
const NOSE_GAP_M := 2.3
## The port door: this far to the plane's left (+x, nose to +z) and behind the
## nose.
const DOOR_SIDE_M := 3.5
const DOOR_AFT_M := 4.2
const PUSHBACK_M := 29.0
const TAXI_LANE_Z := -256.0
## The runway's centreline (main.tscn's Airside runway markers).
const RUNWAY_Z := -310.0
## How far east and west the shared zones reach: past every waypoint and stand.
const ZONE_HALF_LENGTH_M := 1000.0
## A walk from an exit to the plane door longer than this is warned about.
const WALK_WARNING_M := 30.0


static func make(exit_id: int, door_x: float, wall_z: float) -> Dictionary:
	return {"exit": exit_id, "x": door_x, "wall_z": wall_z}


## Whether `data` has a stand's shape (a loaded save's, for example).
static func is_stand(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in ["exit", "x", "wall_z"]:
		if not (data as Dictionary).has(key) or not typeof(data[key]) in [TYPE_INT, TYPE_FLOAT]:
			return false
	return true


## Where the plane's origin stands, nose to +z.
static func stand_point(stand: Dictionary) -> Vector3:
	return Vector3(
		float(stand["x"]) - DOOR_SIDE_M, 0.0, float(stand["wall_z"]) - NOSE_GAP_M - NOSE_M
	)


static func door_point(stand: Dictionary) -> Vector3:
	return Vector3(float(stand["x"]), 0.0, float(stand["wall_z"]) - NOSE_GAP_M - DOOR_AFT_M)


static func pushback_end(stand: Dictionary) -> Vector3:
	return stand_point(stand) + Vector3(0.0, 0.0, -PUSHBACK_M)


## Where the way north from the stand meets the taxi lane.
static func lane_join(stand: Dictionary) -> Vector3:
	return Vector3(stand_point(stand).x, 0.0, TAXI_LANE_Z)


## The shared RUNWAY ground as a world xz rectangle (x, z): the band a plane on
## the runway sweeps, wingtips HALF_SPAN_M either side of the centreline. The
## approach and takeoff fly along it. FlightTimetable reserves it (decision
## gates-technical-design-gate-desks-link-to-north-exits-one-st, point 4).
static func runway_zone() -> Rect2:
	var north := RUNWAY_Z - HALF_SPAN_M
	return Rect2(-ZONE_HALF_LENGTH_M, north, 2.0 * ZONE_HALF_LENGTH_M, 2.0 * HALF_SPAN_M)


## The shared LANE ground: from the runway zone's south edge to the south edge
## of the band a plane on the taxi lane sweeps, so the links between runway and
## lane are in it. South of it each stand's own column and stand are private.
static func lane_zone() -> Rect2:
	var north := runway_zone().end.y
	var south := TAXI_LANE_Z + HALF_SPAN_M
	return Rect2(-ZONE_HALF_LENGTH_M, north, 2.0 * ZONE_HALF_LENGTH_M, south - north)


## Whether the plane parked at `stand` stays out of the lane zone. One whose
## tail reaches it would hold the shared lane for its whole turnaround, so it
## is not a legal stand (the grid's north row misses by 5 cm).
static func clears_lane(stand: Dictionary) -> bool:
	return stand_point(stand).z - TAIL_M >= lane_zone().end.y


## The one source of the plane door for passengers: the points a walk outside
## ends with after its last grid cell (door_seed()).
static func apron_route(stand: Dictionary) -> PackedVector3Array:
	return PackedVector3Array([door_point(stand)])


## The grid cell a walk to the plane door ends in: the cell under the door,
## or the north edge cell in its column when the door stands beyond the grid.
static func door_seed(grid: BuildGrid, stand: Dictionary) -> Vector2i:
	var cell := grid.world_to_cell(door_point(stand))
	return Vector2i(cell.x, maxi(cell.y, 0))


## The stand straight out from the exit door at grid cell `cell` facing north.
static func for_cell(grid: BuildGrid, cell: Vector2i, exit_id := 0) -> Dictionary:
	var centre := grid.cell_to_world(cell)
	return make(exit_id, centre.x, centre.z - 0.5)


## The stand of exit door `exit_id`, or {} when it is not an exit door whose
## outside faces north.
static func for_exit(grid: BuildGrid, exit_id: int) -> Dictionary:
	var record := grid.get_object(exit_id)
	if record.is_empty() or StringName(record["def"]) != &"exit_door":
		return {}
	if DoorPlacement.back_step(record["facing"]) != SiteDefinition.PLANE_STEP:
		return {}
	return for_cell(grid, record["anchor"], exit_id)


## The starter shell's stand: straight out from ReferenceTerminal's exit
## cell, moved by the site's starter offset. The stand a new game starts with.
static func starter_stand(grid: BuildGrid, site: SiteDefinition) -> Dictionary:
	return for_cell(grid, ReferenceTerminal.EXIT_CELL + site.starter_offset)


## The ground the plane sweeps from the stand through its departure, as world
## xz rectangles (x, z): the parked plane, pushback and swing, then the way
## north to the taxi lane. With `north_of`, only what lies north of that z: the
## part still ahead of a plane already on its way out.
static func swept_rects(stand: Dictionary, north_of := INF) -> Array[Rect2]:
	var at := stand_point(stand)
	var back := pushback_end(stand)
	var swing_south := at.z + NOSE_M
	var swing_north := back.z - SWING_RADIUS_M
	var rects: Array[Rect2] = [
		Rect2(at.x - SWING_RADIUS_M, swing_north, 2.0 * SWING_RADIUS_M, swing_south - swing_north),
		Rect2(at.x - HALF_SPAN_M, TAXI_LANE_Z, 2.0 * HALF_SPAN_M, back.z - TAXI_LANE_Z),
	]
	var out: Array[Rect2] = []
	for rect in rects:
		var south := minf(rect.end.y, north_of)
		if south > rect.position.y:
			out.append(
				Rect2(rect.position.x, rect.position.y, rect.size.x, south - rect.position.y)
			)
	return out


## The in-bounds grid cells any of `rects` covers by more than a sliver, each
## once, as a set (cell -> true).
static func cells_under(grid: BuildGrid, rects: Array[Rect2]) -> Dictionary:
	var out := {}
	for rect in rects:
		var low := grid.world_to_cell(
			Vector3(rect.position.x, 0.0, rect.position.y) + Vector3(0.01, 0.0, 0.01)
		)
		var high := grid.world_to_cell(
			Vector3(rect.end.x, 0.0, rect.end.y) - Vector3(0.01, 0.0, 0.01)
		)
		for y in range(maxi(low.y, 0), mini(high.y, grid.size.y - 1) + 1):
			for x in range(maxi(low.x, 0), mini(high.x, grid.size.x - 1) + 1):
				out[Vector2i(x, y)] = true
	return out


## Whether nothing built stands under the plane's sweep from `stand`.
static func aircraft_clear(grid: BuildGrid, site: SiteDefinition, stand: Dictionary) -> bool:
	for cell: Vector2i in cells_under(grid, swept_rects(stand)):
		if not _apron_clear(grid, site, cell):
			return false
	return true


## The walk out of exit door `exit_id` to the plane door at `stand`
## (SiteRoutes.departure()), or empty when there is none.
static func walk_of(
	grid: BuildGrid,
	site: SiteDefinition,
	exit_id: int,
	stand: Dictionary,
	dist := PackedInt32Array()
) -> Array[Vector3]:
	var record := grid.get_object(exit_id)
	if record.is_empty():
		return [] as Array[Vector3]
	if dist.is_empty():
		dist = to_door(grid, site, stand)
	var out := DoorPlacement.back_step(record["facing"])
	var cells := SiteRoutes.door_cells(
		grid, site, record["anchor"], out, SiteDefinition.PLANE_STEP, dist
	)
	if cells.is_empty():
		return [] as Array[Vector3]
	return SiteRoutes.departure(grid, site, cells, stand)


## SiteRoutes.distances() to the plane door's cell at `stand`.
static func to_door(grid: BuildGrid, site: SiteDefinition, stand: Dictionary) -> PackedInt32Array:
	var seeds: Array[Vector2i] = [door_seed(grid, stand)]
	return SiteRoutes.distances(grid, site, seeds)


static func walk_length(points: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## The best stand for the grid as it stands, given the `live` one:
## {"status": OK or UNAVAILABLE, "stand": the chosen stand (the live one when
## UNAVAILABLE), "walk_m": its exit's walk to the door (-1 when UNAVAILABLE),
## "longest_walk_m": the longest walk from any exit with a walk to that door,
## "warning": whether that longest walk is over WALK_WARNING_M}.
static func place(grid: BuildGrid, site: SiteDefinition, live: Dictionary) -> Dictionary:
	var best := {}
	var best_key: Array = []
	var live_exit: int = live.get("exit", 0)
	var ids := grid.object_ids()
	ids.sort()
	for id in ids:
		var stand := for_exit(grid, id)
		if stand.is_empty() or not grid.is_passenger_cell(grid.get_object(id)["anchor"]):
			continue
		if not clears_lane(stand):
			continue
		if not aircraft_clear(grid, site, stand):
			continue
		var walk := walk_of(grid, site, id, stand)
		if walk.is_empty():
			continue
		var key := [
			roundi(walk_length(walk) * 1000.0),
			0 if id == live_exit else 1,
			float(stand["wall_z"]),
			id
		]
		if best.is_empty() or key < best_key:
			best = stand
			best_key = key
	if best.is_empty():
		return {
			"status": UNAVAILABLE,
			"stand": live,
			"walk_m": -1.0,
			"longest_walk_m": -1.0,
			"warning": false
		}
	var longest := longest_walk(grid, site, best)
	return {
		"status": OK,
		"stand": best,
		"walk_m": best_key[0] / 1000.0,
		"longest_walk_m": longest,
		"warning": longest > WALK_WARNING_M
	}


## The longest walk from any exit door that has one to the plane door at
## `stand`, in metres; 0 with none.
static func longest_walk(grid: BuildGrid, site: SiteDefinition, stand: Dictionary) -> float:
	var dist := to_door(grid, site, stand)
	var longest := 0.0
	for id in grid.object_ids():
		if StringName(grid.get_object(id)["def"]) != &"exit_door":
			continue
		var walk := walk_of(grid, site, id, stand, dist)
		if not walk.is_empty():
			longest = maxf(longest, walk_length(walk))
	return longest


## Whether a plane may pass over `cell`: no floor, object, site obstacle or
## wall on any of its edges.
static func _apron_clear(grid: BuildGrid, site: SiteDefinition, cell: Vector2i) -> bool:
	if grid.floor_at(cell) != BuildGrid.FLOOR_NONE or grid.object_at(cell) != 0:
		return false
	if site != null and site.is_obstacle(cell):
		return false
	for side in 4:
		if grid.has_wall(cell, side):
			return false
	return true
