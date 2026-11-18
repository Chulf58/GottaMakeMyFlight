class_name GroundPlannerKit
extends RefCounted
## Shared set-up for the GroundPlanner tests: main.tscn's Airside waypoints read
## from the saved scene (no node built), each phase's path for one gate's stand
## as Airside.phase_path() gives it (test_ground_planner.gd checks that), the
## legal stands of each class on the empty site, and the drawn plane's pose and
## footprint polygon, posed by FlightPose.

const SITE := preload("res://build/terminal_site.tres")
const MAIN_SCENE := "res://main/main.tscn"
## A departure at 10:00 on day 1.
const DEPARTURE_DAY := 1
const DEPARTURE_MINUTE := 600
## The parked states, drawn at the end of TAXI_IN.
const PARKED_STATES: Array[int] = [
	FlightSim.State.AT_STAND, FlightSim.State.BOARDING, FlightSim.State.DOORS_CLOSED
]
## An overlap smaller than this (m²) is two shapes sharing an edge: 0.01 m² is
## 0.3 mm along a 30 m plane (test_shared_ground_holds.gd uses the same).
const TOUCH_M2 := 0.01

## Waypoint name -> its position.
var points := {}
var grid: BuildGrid


func _init() -> void:
	grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	for i in state.get_node_count():
		if String(state.get_node_path(i, true)) != "./Airside":
			continue
		if state.get_node_type(i) != &"Marker3D":
			continue
		for k in state.get_node_property_count(i):
			if state.get_node_property_name(i, k) == &"transform":
				var at: Transform3D = state.get_node_property_value(i, k)
				points[state.get_node_name(i)] = at.origin


func planner() -> GroundPlanner:
	return GroundPlanner.new(points[&"HoldIn"], points[&"HoldRunway"])


## The stand straight out from grid `cell`, its exit facing out to `side`
## (north unless given): a west or east one is a synthetic side stand, its way
## out on the spur at x -124 or +124 (board airside-all-around-s4).
func stand(cell: Vector2i, side := StandPlacement.NORTH) -> Dictionary:
	return StandPlacement.for_cell(grid, cell, 0, side)


## Each phase's path for a plane of `plane_class` at `at` (the only gate),
## written out here as the reference for TaxiRoutes. A north stand taxis in
## along the lane to its join and out along it to TaxiWest. A west stand taxis
## in along the whole lane and south down the west spur, and out north up the
## spur straight on to the west stub. An east stand taxis in straight on from
## the east stub down the east spur, and out north up it and along the lane.
func routes(at: Dictionary, plane_class: String) -> Dictionary:
	var suffix: String = Airside.CLASS_SUFFIX[plane_class]
	var spot := StandPlacement.stand_point(at)
	var back := StandPlacement.pushback_end(at)
	var join := StandPlacement.lane_join(at)
	var p := points
	var taxi_in := PackedVector3Array([p[&"RunwayExit"], p[&"TaxiEast"], join, back, spot])
	var taxi_out := PackedVector3Array([back, join, p[&"TaxiWest"], p[&"RunwayEntry"]])
	match StandPlacement.side_of(at):
		StandPlacement.WEST:
			taxi_in = PackedVector3Array(
				[p[&"RunwayExit"], p[&"TaxiEast"], p[&"TaxiWest"], join, back, spot]
			)
		StandPlacement.EAST:
			taxi_out = PackedVector3Array(
				[back, join, p[&"TaxiEast"], p[&"TaxiWest"], p[&"RunwayEntry"]]
			)
	return {
		FlightSim.State.APPROACH:
		PackedVector3Array([p[&"ApproachStart" + suffix], p[&"Touchdown" + suffix]]),
		FlightSim.State.LANDING: PackedVector3Array([p[&"Touchdown" + suffix], p[&"RunwayExit"]]),
		FlightSim.State.TAXI_IN: taxi_in,
		FlightSim.State.PUSHBACK: PackedVector3Array([spot, back]),
		FlightSim.State.TAXI_OUT: taxi_out,
		FlightSim.State.TAKEOFF:
		PackedVector3Array([p[&"RunwayEntry"], p[&"Liftoff" + suffix], p[&"ClimbEnd"]]),
	}


## FlightSim's starts for a flight departing `minute` on `day` with the taxi
## pair `taxi`.
static func starts_at(day: int, minute: int, taxi: Array = TaxiTimes.BASE) -> Array[int]:
	var departure := GameCalendar.tick_at(day, minute, 0)
	return FlightSim.schedule_starts(departure - FlightTimetable.departure_offset(taxi), taxi)


## A request at `at` on the base taxi pair, as the north stands' pinned tests
## were written; a west or east stand's runs on its own pair (TaxiTimes.
## for_stand()), as its contract would, since its spur route is too long for
## the base pair's TAXI_IN under the speed cap.
func request(
	id: String,
	plane_class: String,
	at: Dictionary,
	day := DEPARTURE_DAY,
	minute := DEPARTURE_MINUTE
) -> Dictionary:
	var taxi: Array = TaxiTimes.BASE
	if StandPlacement.side_of(at) != StandPlacement.NORTH:
		taxi = TaxiTimes.for_stand(at)
	return GroundPlanner.request(
		id, plane_class, at, starts_at(day, minute, taxi), routes(at, plane_class), 0
	)


## Whether a plane of `plane_class` may stand at `at` on the empty site: its
## envelope (StandEnvelope) clears the lane band and covers no site obstacle,
## as StandEnvelope.blocked_part() finds on an empty grid, and none of it
## reaches over the road (StandPlacement.reaches_road(), which only a side
## stand's envelope can).
func is_legal(at: Dictionary, plane_class: String) -> bool:
	if not StandEnvelope.clears_lane(at, plane_class):
		return false
	if StandPlacement.reaches_road(grid, StandEnvelope.rects(at, plane_class)):
		return false
	for rect in StandEnvelope.rects(at, plane_class):
		var inner := rect.grow(-0.01)
		for obstacle in SITE.obstacles:
			var centre := grid.cell_to_world(obstacle)
			var cell := Rect2(centre.x - 0.5, centre.z - 0.5, 1.0, 1.0)
			if inner.intersects(cell):
				return false
	return true


## Every grid cell whose stand facing out to `side` is legal for `plane_class`.
func legal_cells(plane_class: String, side := StandPlacement.NORTH) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in SITE.grid_size.y:
		for column in SITE.grid_size.x:
			var cell := Vector2i(column, row)
			if is_legal(stand(cell, side), plane_class):
				out.append(cell)
	return out


## The state at tick `time`: the last one started.
static func state_at(starts: Array, time: float) -> int:
	var state := FlightSim.State.SCHEDULED
	while state < FlightSim.State.DEPARTED and time >= starts[state + 1]:
		state += 1
	return state


## The drawn plane's pose at `time` (APPROACH to TAKEOFF), with taxi `pauses`
## (state -> MovementPlan pause), as PlaneView poses it: parked states at the
## end of TAXI_IN.
static func pose(req: Dictionary, time: float, pauses: Dictionary) -> Transform3D:
	var starts: Array = req["starts"]
	var routes_by: Dictionary = req["routes"]
	var state := state_at(starts, time)
	var progress: float = (time - starts[state]) / float(starts[state + 1] - starts[state])
	if PARKED_STATES.has(state):
		state = FlightSim.State.TAXI_IN
		progress = 1.0
	var path: PackedVector3Array = routes_by[state]
	var entry := (path[1] - path[0]).slide(Vector3.UP).normalized()
	if GroundPlanner.PREVIOUS_MOVE.has(state):
		entry = MovementPlan.exit_dir(routes_by[GroundPlanner.PREVIOUS_MOVE[state]])
	elif state == FlightSim.State.LANDING:
		entry = MovementPlan.exit_dir(routes_by[FlightSim.State.APPROACH])
	var budget := float(starts[state + 1] - starts[state])
	return FlightPose.pose(state, progress, path, entry, pauses.get(state, {}), budget)


## For each taxi phase, the longest pause it may take at its gate hold line
## (when `gate` and it has one) or else at its stub's hold line.
static func longest_pauses(planner: GroundPlanner, req: Dictionary, gate: bool) -> Dictionary:
	var out := {}
	for state in GroundPlanner.TAXI_STATES:
		var lines := planner.holds(req, state)
		var hold: String = lines[0]["hold"]
		for line in lines:
			if gate == (line["hold"] == GroundPlanner.HOLD_GATE):
				hold = line["hold"]
		# Options run from the shortest pause up, so the last one at the hold
		# is the longest.
		for option in planner.phase_options(req, state):
			if not option.is_empty() and option["hold"] == hold:
				out[state] = option
	return out


## For each hold of each taxi phase in turn, the longest pause there: one
## pauses dictionary per index into the longer of the two phases' hold lists
## (a phase with fewer holds keeps its last), so every hold is sampled.
static func every_hold_pauses(planner: GroundPlanner, req: Dictionary) -> Array[Dictionary]:
	var lines := {}
	var count := 0
	for state in GroundPlanner.TAXI_STATES:
		lines[state] = planner.holds(req, state)
		count = maxi(count, lines[state].size())
	var out: Array[Dictionary] = []
	for i in count:
		var pauses := {}
		for state in GroundPlanner.TAXI_STATES:
			var hold: String = lines[state][mini(i, lines[state].size() - 1)]["hold"]
			for option in planner.phase_options(req, state):
				if not option.is_empty() and option["hold"] == hold:
					pauses[state] = option
		out.append(pauses)
	return out


## Half-tick footprint sampling of one flight's bookings with taxi `pauses`:
## every half tick from APPROACH to DEPARTED, PUSHBACK left out (board
## 13e98b04 owns the drawn swing) and each parked state at its first and last
## half tick only. A sample whose footprint polygon has more than TOUCH_M2
## outside the union of the flight's bookings active then is uncovered.
## Returns {"samples", "uncovered": the count, "first": the first few}. With
## `cut`, every slice, corner and runway window is shortened by that many
## ticks at each end (the negative control).
static func sample(req: Dictionary, pauses: Dictionary, cut := 0.0) -> Dictionary:
	var list: Array[Dictionary] = GroundPlanner.fixed_bookings(req)
	for state in GroundPlanner.TAXI_STATES:
		list.append_array(GroundPlanner.phase_bookings(req, state, pauses.get(state, {})))
	if cut > 0.0:
		for booking in list:
			if booking["kind"] in [GroundPlanner.SLICE, GroundPlanner.CORNER, GroundPlanner.RUNWAY]:
				booking["from"] += cut
				booking["to"] -= cut
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["from"] < b["from"])
	var fp := GroundPlanner.footprint(req["class"])
	var starts: Array = req["starts"]
	var next := 0
	var active: Array[Dictionary] = []
	var out := {"samples": 0, "uncovered": 0, "first": []}
	var first: int = 2 * starts[FlightSim.State.APPROACH]
	for half in range(first, 2 * starts[FlightSim.State.DEPARTED]):
		var time := half / 2.0
		var state := state_at(starts, time)
		if state == FlightSim.State.PUSHBACK:
			continue
		var parked_middle: bool = half != 2 * starts[state] and half != 2 * starts[state + 1] - 1
		if PARKED_STATES.has(state) and parked_middle:
			continue
		while next < list.size() and list[next]["from"] <= time:
			active.append(list[next])
			next += 1
		active = active.filter(func(b: Dictionary) -> bool: return b["to"] > time)
		var shape := polygon(pose(req, time, pauses), fp)
		var box := Rect2(shape[0], Vector2.ZERO)
		for point in shape:
			box = box.expand(point)
		var rects: Array[Rect2] = []
		for booking in active:
			if (booking["rect"] as Rect2).intersects(box):
				rects.append(booking["rect"])
		out["samples"] += 1
		var area := uncovered_area(shape, rects)
		if area > TOUCH_M2:
			out["uncovered"] += 1
			if out["first"].size() < 4:
				out["first"].append("t %.1f state %d: %.3f m2" % [time, state, area])
	return out


## The plan-view rectangle of footprint `fp` (GroundPlanner.footprint()) at `at`.
static func polygon(at: Transform3D, fp: Dictionary) -> PackedVector2Array:
	var nose := Vector2(at.basis.z.x, at.basis.z.z).normalized()
	var side := Vector2(nose.y, -nose.x) * float(fp["half_width"])
	var origin := Vector2(at.origin.x, at.origin.z)
	var ahead := origin + nose * float(fp["ahead"])
	var behind := origin - nose * float(fp["behind"])
	return PackedVector2Array([ahead + side, ahead - side, behind - side, behind + side])


## Area (m²) of `shape` outside every one of `rects`: the shape is clipped by
## each rectangle in turn, keeping holes as negative pieces, so the sum is exact.
static func uncovered_area(shape: PackedVector2Array, rects: Array[Rect2]) -> float:
	var pieces: Array = [[shape, 1.0]]
	for rect in rects:
		var square := PackedVector2Array(
			[
				rect.position,
				Vector2(rect.end.x, rect.position.y),
				rect.end,
				Vector2(rect.position.x, rect.end.y)
			]
		)
		var next: Array = []
		for piece: Array in pieces:
			var rests := Geometry2D.clip_polygons(piece[0], square)
			# Outer boundaries share one winding and holes have the other; the
			# largest piece is always an outer one.
			var largest := 0.0
			var outer_winding := false
			for rest in rests:
				if absf(_area(rest)) > largest:
					largest = absf(_area(rest))
					outer_winding = Geometry2D.is_polygon_clockwise(rest)
			for rest in rests:
				var hole := Geometry2D.is_polygon_clockwise(rest) != outer_winding
				next.append([rest, -float(piece[1]) if hole else float(piece[1])])
		pieces = next
		if pieces.is_empty():
			return 0.0
	var area := 0.0
	for piece: Array in pieces:
		area += float(piece[1]) * absf(_area(piece[0]))
	return area


static func _area(points_of: PackedVector2Array) -> float:
	var twice := 0.0
	for i in points_of.size():
		twice += points_of[i].cross(points_of[(i + 1) % points_of.size()])
	return twice / 2.0
