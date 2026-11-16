class_name StandPlacement
extends RefCounted
## Where the one plane stand goes on the airport site (decision plane-stand-
## design-airside-moves-110-m-north-stand-snaps-to, point 2). Pure: nothing
## here changes the grid.
##
## A stand is {"exit": exit door id (0 for none), "x" and "wall_z": the world x
## and z of its sill, where the exit door meets the wall line, and, for a stand
## that is not on a north wall, "side"}. The plane parks nose-in, straight out
## from a north-facing exit: its port door on the exit cell's centre x, its
## nose NOSE_GAP_M north of the wall line the exit stands in. It is pushed back
## PUSHBACK_M, turned to face north, and taxis north to the taxi lane at
## TAXI_LANE_Z.
##
## A stand's side (decision airside-all-around-technical-design-one-route-
## source-per-con, slice S3) is the way its exit faces out: NORTH, WEST or EAST.
## A west or east stand is the north stand turned a quarter turn about its sill,
## never mirrored, so the port door stays on the plane's left: every point and
## rectangle of it is its north twin's (north_twin()) moved by to_world(). Its
## way out ends on the side lane, SIDE_LANE_X out west or east. A north stand
## has no "side" key, so its dictionary and every value worked out from it are
## the ones they were before sides. Only north stands are made in play
## (for_exit()); side exits come with later slices.
##
## A candidate exit needs a clear aircraft route (swept_rects(): the parked
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
## Whole cells (1 m each) two gates' exits need between them so their small-
## plane swing squares do not meet: StandEnvelope.spacing_cells(SMALL), which
## test_stand_envelope.gd checks. Neighbouring gates share the larger envelopes
## (decision runway-and-taxi-technical-design-movement-plan-analytic-bookings-
## planned-pauses, section 3).
const EXIT_SPACING_CELLS := 19
## The gap between the wall line and the nose. 2.2 m (2.3 m in decision
## plane-stand-design-airside-moves-110-m-north-stand-snaps-to): with the lane
## at z -256 it kept a north-row tail 0.05 m clear of the shared lane zone
## (clears_lane()). With the lane at TAXI_LANE_Z the clearance is 28.05 m.
const NOSE_GAP_M := 2.2
## The port door: this far to the plane's left (+x, nose to +z) and behind the
## nose.
const DOOR_SIDE_M := 3.5
const DOOR_AFT_M := 4.2
const PUSHBACK_M := 29.0
## The taxi lane's and the runway's centrelines (main.tscn's Airside markers),
## 28 m north of the -256 and -310 they were, so a north-row large plane's tail
## stays clear of the large-plane lane band (decision runway-and-taxi-
## technical-design-movement-plan-analytic-bookings-planned-pauses).
const TAXI_LANE_Z := -284.0
const RUNWAY_Z := -338.0
## How far east and west the shared zones reach: past every waypoint and stand.
const ZONE_HALF_LENGTH_M := 1000.0
## A walk from an exit to the plane door longer than this is warned about.
const WALK_WARNING_M := 30.0
## The sides a stand's exit can face out to.
const NORTH := "N"
const WEST := "W"
const EAST := "E"
const SIDES: Array[String] = [NORTH, WEST, EAST]
## Side -> the grid step out of its exit door.
const OUT_STEP := {NORTH: Vector2i(0, -1), WEST: Vector2i(-1, 0), EAST: Vector2i(1, 0)}
## Side -> the turn about +y from a north stand to it, in radians.
const SIDE_YAW := {NORTH: 0.0, WEST: PI / 2.0, EAST: -PI / 2.0}
## How far west and east of x 0 the side lanes run: the TaxiWest and TaxiEast
## waypoints' x in main.tscn, where board airside-all-around-s4 puts the spurs.
## A west or east stand's way out ends on its side's lane.
const SIDE_LANE_X := 124.0


## A stand whose sill is at (`door_x`, `wall_z`) and whose exit faces out to
## `side`. {} (with an error) for an unknown side.
static func make(exit_id: int, door_x: float, wall_z: float, side := NORTH) -> Dictionary:
	if not SIDES.has(side):
		push_error("StandPlacement.make: '%s' is not a side" % side)
		return {}
	var stand := {"exit": exit_id, "x": door_x, "wall_z": wall_z}
	if side != NORTH:
		stand["side"] = side
	return stand


## Whether `data` has a stand's shape (a loaded save's, for example).
static func is_stand(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in ["exit", "x", "wall_z"]:
		if not (data as Dictionary).has(key) or not typeof(data[key]) in [TYPE_INT, TYPE_FLOAT]:
			return false
	if (data as Dictionary).has("side"):
		return typeof(data["side"]) == TYPE_STRING and SIDES.has(data["side"])
	return true


## The stand `data` (is_stand()) rebuilt with make(), its side kept: what a
## loaded save's stand becomes.
static func from_saved(data: Dictionary) -> Dictionary:
	return make(int(data["exit"]), float(data["x"]), float(data["wall_z"]), side_of(data))


## The side `stand`'s exit faces out to: NORTH for a stand with no "side".
static func side_of(stand: Dictionary) -> String:
	return String(stand.get("side", NORTH))


## The grid step out of `stand`'s exit door.
static func out_step(stand: Dictionary) -> Vector2i:
	return OUT_STEP[side_of(stand)]


## The north stand a west or east `stand` is turned from: its sill as far from
## the taxi lane as `stand`'s is from its side lane, at x 0. A north stand is
## its own twin.
static func north_twin(stand: Dictionary) -> Dictionary:
	match side_of(stand):
		WEST:
			return make(int(stand["exit"]), 0.0, TAXI_LANE_Z + float(stand["x"]) + SIDE_LANE_X)
		EAST:
			return make(int(stand["exit"]), 0.0, TAXI_LANE_Z + SIDE_LANE_X - float(stand["x"]))
	return stand


## The flat direction `v`, given in a north stand's frame, turned to `stand`'s
## side. A quarter turn, never a mirror: +x (the plane's port side) turns to
## -z on a west stand and to +z on an east one.
static func turn(stand: Dictionary, v: Vector3) -> Vector3:
	match side_of(stand):
		WEST:
			return Vector3(v.z, v.y, -v.x)
		EAST:
			return Vector3(-v.z, v.y, v.x)
	return v


## turn() undone: a direction at `stand` in its north twin's frame.
static func turn_back(stand: Dictionary, v: Vector3) -> Vector3:
	match side_of(stand):
		WEST:
			return Vector3(-v.z, v.y, v.x)
		EAST:
			return Vector3(v.z, v.y, -v.x)
	return v


## The world point at `stand` that is `point` at its north twin: turned about
## the twin's sill onto the stand's sill. A north stand's points are its own.
static func to_world(stand: Dictionary, point: Vector3) -> Vector3:
	if side_of(stand) == NORTH:
		return point
	var twin := north_twin(stand)
	var from := Vector3(float(twin["x"]), point.y, float(twin["wall_z"]))
	return Vector3(float(stand["x"]), point.y, float(stand["wall_z"])) + turn(stand, point - from)


## to_world() undone: where world `point` at `stand` lies at its north twin.
static func to_frame(stand: Dictionary, point: Vector3) -> Vector3:
	if side_of(stand) == NORTH:
		return point
	var twin := north_twin(stand)
	var sill := Vector3(float(stand["x"]), point.y, float(stand["wall_z"]))
	return (
		Vector3(float(twin["x"]), point.y, float(twin["wall_z"])) + turn_back(stand, point - sill)
	)


## The world xz rectangles at `stand` that `rects` are at its north twin.
static func rects_to_world(stand: Dictionary, rects: Array[Rect2]) -> Array[Rect2]:
	if side_of(stand) == NORTH:
		return rects
	var out: Array[Rect2] = []
	for rect in rects:
		var a := to_world(stand, Vector3(rect.position.x, 0.0, rect.position.y))
		var b := to_world(stand, Vector3(rect.end.x, 0.0, rect.end.y))
		out.append(Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)))
	return out


## Where the plane's origin stands, nose to +z (at a side stand, nose to its
## wall).
static func stand_point(stand: Dictionary) -> Vector3:
	if side_of(stand) != NORTH:
		return to_world(stand, stand_point(north_twin(stand)))
	return Vector3(
		float(stand["x"]) - DOOR_SIDE_M, 0.0, float(stand["wall_z"]) - NOSE_GAP_M - NOSE_M
	)


## Where the passengers' walk ends beside the plane door, on the apron. With
## `model` it is beside that model's own parked door, moved by its
## PlaneClasses.door_shift() (model 04 parks further out); with "" it is the
## stand's door, where model 05's stands.
static func door_point(stand: Dictionary, model := "") -> Vector3:
	if side_of(stand) != NORTH:
		return to_world(stand, door_point(north_twin(stand), model))
	var at := Vector3(float(stand["x"]), 0.0, float(stand["wall_z"]) - NOSE_GAP_M - DOOR_AFT_M)
	return at + PlaneClasses.door_shift(model)


static func pushback_end(stand: Dictionary) -> Vector3:
	if side_of(stand) != NORTH:
		return to_world(stand, pushback_end(north_twin(stand)))
	return stand_point(stand) + Vector3(0.0, 0.0, -PUSHBACK_M)


## Where the way out from the stand meets the taxi lane (at a side stand, its
## side lane).
static func lane_join(stand: Dictionary) -> Vector3:
	if side_of(stand) != NORTH:
		return to_world(stand, lane_join(north_twin(stand)))
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
## tail reached it would hold the shared lane for its whole turnaround. Every
## stand on the site does, the north row with 28.05 m to spare (NOSE_GAP_M);
## test_shared_ground_holds.gd checks it. A side stand is checked as its north
## twin, against its own side lane.
static func clears_lane(stand: Dictionary) -> bool:
	if side_of(stand) != NORTH:
		return clears_lane(north_twin(stand))
	return stand_point(stand).z - TAIL_M >= lane_zone().end.y


## The one source of the plane door for passengers: the points a walk outside
## ends with after its last grid cell (door_seed()), to the door of a plane
## drawn with `model` ("" for the stand's door).
static func apron_route(stand: Dictionary, model := "") -> PackedVector3Array:
	return PackedVector3Array([door_point(stand, model)])


## The grid cell a walk to the plane door ends in: the cell under the door,
## or, when the door stands beyond the grid, the edge cell straight back from
## it toward the exit (the north edge cell in its column at a north stand, the
## west or east edge cell in its row at a side one).
static func door_seed(grid: BuildGrid, stand: Dictionary) -> Vector2i:
	var cell := grid.world_to_cell(door_point(stand))
	match side_of(stand):
		WEST:
			return Vector2i(maxi(cell.x, 0), cell.y)
		EAST:
			return Vector2i(mini(cell.x, grid.size.x - 1), cell.y)
	return Vector2i(cell.x, maxi(cell.y, 0))


## The stand straight out from the exit door at grid cell `cell` facing out to
## `side` (north unless given): its sill on the cell's outer edge.
static func for_cell(grid: BuildGrid, cell: Vector2i, exit_id := 0, side := NORTH) -> Dictionary:
	var centre := grid.cell_to_world(cell)
	if side == NORTH:
		return make(exit_id, centre.x, centre.z - 0.5)
	if not OUT_STEP.has(side):
		push_error("StandPlacement.for_cell: '%s' is not a side" % side)
		return {}
	var step: Vector2i = OUT_STEP[side]
	return make(exit_id, centre.x + 0.5 * step.x, centre.z + 0.5 * step.y, side)


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
## part still ahead of a plane already on its way out. A side stand's are its
## north twin's turned onto it, and its `north_of` is a z at that twin
## (to_frame()).
static func swept_rects(stand: Dictionary, north_of := INF) -> Array[Rect2]:
	if side_of(stand) != NORTH:
		return rects_to_world(stand, swept_rects(north_twin(stand), north_of))
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


## Whether any of `rects` reaches past the grid's south edge, over the road
## (SiteDefinition.ROAD_STEP). cells_under() keeps only the cells on the grid,
## so a side stand's wing over the road would otherwise count as clear. Ground
## past the other edges is open airside.
static func reaches_road(grid: BuildGrid, rects: Array[Rect2]) -> bool:
	var road_edge := grid.origin.z + grid.size.y
	for rect in rects:
		if rect.end.y - 0.01 > road_edge:
			return true
	return false


## Whether nothing built stands under the plane's sweep from `stand`, and none
## of it reaches over the road.
static func aircraft_clear(grid: BuildGrid, site: SiteDefinition, stand: Dictionary) -> bool:
	var rects := swept_rects(stand)
	if reaches_road(grid, rects):
		return false
	for cell: Vector2i in cells_under(grid, rects):
		if not apron_clear(grid, site, cell):
			return false
	return true


## The walk out of exit door `exit_id` to the plane door at `stand`
## (SiteRoutes.departure()), or empty when there is none. A door on the grid
## edge walks straight out over the edge the stand's side faces.
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
	var cells := SiteRoutes.door_cells(grid, site, record["anchor"], out, out_step(stand), dist)
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


## One gate's stand checked as place() checks a candidate (gates-technical-
## design-gate-desks-link-to-north-exits-one-st, point 2): {"status": OK when
## the plane's sweep is clear and exit `exit_id` has a walk to its door, else
## UNAVAILABLE; "walk_m": that walk (-1 when UNAVAILABLE); "warning": whether
## it is over WALK_WARNING_M}.
static func check(
	grid: BuildGrid, site: SiteDefinition, exit_id: int, stand: Dictionary
) -> Dictionary:
	var walk: Array[Vector3] = []
	if aircraft_clear(grid, site, stand):
		walk = walk_of(grid, site, exit_id, stand)
	if walk.is_empty():
		return {"status": UNAVAILABLE, "walk_m": -1.0, "warning": false}
	var metres := walk_length(walk)
	return {"status": OK, "walk_m": metres, "warning": metres > WALK_WARNING_M}


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
## wall on any of its edges. StandEnvelope asks it for each class's envelope.
static func apron_clear(grid: BuildGrid, site: SiteDefinition, cell: Vector2i) -> bool:
	if grid.floor_at(cell) != BuildGrid.FLOOR_NONE or grid.object_at(cell) != 0:
		return false
	if site != null and site.is_obstacle(cell):
		return false
	for side in 4:
		if grid.has_wall(cell, side):
			return false
	return true
