class_name TestSharedGroundHolds
extends GdUnitTestSuite
## The shared RUNWAY and LANE reservations (decision gates-technical-design-
## gate-desks-link-to-north-exits-one-st, point 4) cover every tick any part of
## an aircraft is on them. The plane's footprint (StandPlacement's rectangle:
## nose, tail and wingtips about its origin) is posed exactly as PlaneView
## draws it and compared with StandPlacement.runway_zone() and lane_zone().
## Every occupied sample must fall inside one of the flight's holds on that
## zone (FlightTimetable.flight_holds).
##
## Every legal stand is checked: each grid cell StandPlacement can stand a
## plane at for a north-facing exit (legal_cells()). The boundary stands (the
## north-most and south-most legal rows, the west-most and east-most legal
## columns) are sampled every tick from APPROACH to DEPARTED. Every legal
## stand, those included, is also sampled around each bound of each hold
## (WINDOW_TICKS either side: every half tick within NEAR_TICKS of the bound,
## every FAR_STEP-th tick beyond). A stand that is not on the boundary is
## posed only at the window samples that no hold of some zone covers, the
## samples a bound can fail on; a sample inside every hold cannot fail. The
## measured first and last ticks are printed beside the holds, and the
## phase-boundary cuts the design rejected are shown to be short.

const MAIN_SCENE := "res://main/main.tscn"
const SITE := preload("res://build/terminal_site.tres")
const FIRST := 3000
## Ticks either side of each hold bound that every legal stand is sampled over.
const WINDOW_TICKS := 60
## Within this many ticks of a bound the window is sampled every half tick.
const NEAR_TICKS := 3
## Beyond NEAR_TICKS the window is sampled every this-many ticks.
const FAR_STEP := 15
## The negative control shortens each bound of each hold by this many ticks,
## more than the 16 the widest measured cut margin leaves.
const CONTROL_CUT_TICKS := 30
## [hold index, at its end] of the bounds that stay at a phase edge with room to
## spare since the lane moved to z -284: the arrival's lane hold ends at
## AT_STAND although a north-row plane is off the lane about 170 ticks before,
## and the departure's lane hold starts at PUSHBACK although it reaches the lane
## about 87 ticks after. Holding the lane longer than needed is safe.
const LOOSE_BOUNDS := [[1, true], [2, false]]
## An overlap smaller than this (m²) is two shapes sharing an edge, not a plane
## on the zone: a plane on the runway has its wingtips on the lane zone's edge,
## and single-precision poses put them up to a few hundredths of a millimetre
## over it. 0.01 m² is 0.3 mm along the plane's whole length.
const TOUCH_M2 := 0.01

var _airside: Airside
var _view: PlaneView
var _grid: BuildGrid
## The measurement of the stand being run, reset per test.
var _seen := {}
## The same for the legal stands alone, without the extra door lines.
var _site_seen := {}
var _on_site := true
var _occupied := 0
var _samples := 0
var _uncovered: Array[String] = []


func before() -> void:
	_airside = scene_airside()
	add_child(_airside)
	_view = PlaneView.new()
	_view.airside = _airside
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)


func after() -> void:
	_view.free()
	_airside.free()


## main.tscn's Airside markers and links, built from the saved scene state
## without instantiating the scene.
static func scene_airside() -> Airside:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	var airside := Airside.new()
	for i in state.get_node_count():
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		var parent := String(state.get_node_path(i, true))
		if parent == "./Airside" and state.get_node_type(i) == &"Marker3D":
			var marker := Marker3D.new()
			marker.name = state.get_node_name(i)
			marker.transform = props.get(&"transform", Transform3D.IDENTITY)
			airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			airside.links = props[&"links"]
	return airside


## The plane's plan-view rectangle at `pose`: nose NOSE_M ahead, tail TAIL_M
## behind, wingtips HALF_SPAN_M out, turned to its heading.
static func footprint(pose: Transform3D) -> PackedVector2Array:
	var nose := Vector2(pose.basis.z.x, pose.basis.z.z).normalized()
	var side := Vector2(nose.y, -nose.x)
	var at := Vector2(pose.origin.x, pose.origin.z)
	var ahead := nose * StandPlacement.NOSE_M
	var behind := -nose * StandPlacement.TAIL_M
	var out := side * StandPlacement.HALF_SPAN_M
	return PackedVector2Array(
		[at + ahead + out, at + ahead - out, at + behind - out, at + behind + out]
	)


static func on_zone(shape: PackedVector2Array, zone: Rect2) -> bool:
	var box := Rect2(shape[0], Vector2.ZERO)
	for point in shape:
		box = box.expand(point)
	if not box.intersects(zone):
		return false
	var low := zone.position
	var high := zone.end
	var square := PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])
	var area := 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(shape, square):
		area += absf(_area(piece))
	return area > TOUCH_M2


static func _area(points: PackedVector2Array) -> float:
	var twice := 0.0
	for i in points.size():
		twice += points[i].cross(points[(i + 1) % points.size()])
	return twice / 2.0


static func held(holds: Array, zone: String, tick: int) -> bool:
	for hold in holds:
		if hold[0] == zone and hold[1] <= tick and tick < hold[2]:
			return true
	return false


## Whether a plane may stand at grid `cell` for a north-facing exit on an
## empty grid: StandPlacement.clears_lane() and aircraft_clear(). aircraft_clear
## is the real check but costs about 6 ms a stand (85 s over the site), so it
## runs for the stands whose sweep comes within a metre of a site obstacle; on
## the empty grid nothing else can block a sweep. A grid with buildings only
## removes stands from this set, and place() needs an exit and a walk on top.
static func is_legal(grid: BuildGrid, site: SiteDefinition, cell: Vector2i) -> bool:
	var stand := StandPlacement.for_cell(grid, cell)
	if not StandPlacement.clears_lane(stand):
		return false
	for rect in StandPlacement.swept_rects(stand):
		for obstacle in site.obstacles:
			var at := grid.cell_to_world(obstacle)
			if rect.grow(1.0).has_point(Vector2(at.x, at.z)):
				return StandPlacement.aircraft_clear(grid, site, stand)
	return true


## Every grid cell of the site with a legal stand.
func legal_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in SITE.grid_size.y:
		for column in SITE.grid_size.x:
			if is_legal(_grid, SITE, Vector2i(column, row)):
				cells.append(Vector2i(column, row))
	return cells


## The legal cells in the north-most or south-most legal row, or in the
## west-most or east-most legal column.
static func boundary_cells(legal: Array[Vector2i]) -> Array[Vector2i]:
	var low := legal[0]
	var high := legal[0]
	for cell in legal:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	var out: Array[Vector2i] = []
	for cell in legal:
		if cell.x in [low.x, high.x] or cell.y in [low.y, high.y]:
			out.append(cell)
	return out


## Sample times, in ticks. The three parked states hold one pose, so each is
## sampled at its first and last half tick only. With `every_tick`, every other
## state is sampled every tick from APPROACH to DEPARTED, and the window around
## each bound of each hold (see the file comment) in full. Without it, only the
## window samples some zone has no hold on.
static func sample_times(starts: Array[int], holds: Array, every_tick: bool) -> Array[float]:
	var parked := [FlightSim.State.AT_STAND, FlightSim.State.BOARDING, FlightSim.State.DOORS_CLOSED]
	var halves := {}
	for state in range(FlightSim.State.APPROACH, FlightSim.State.DEPARTED):
		var start := starts[state]
		var end := starts[state + 1]
		if parked.has(state):
			halves[2 * start] = true
			halves[2 * end - 1] = true
		elif every_tick:
			for tick in range(start, end):
				halves[2 * tick] = true
	var first := starts[FlightSim.State.APPROACH]
	var last := starts[FlightSim.State.DEPARTED]
	for hold: Array in holds:
		for bound: int in [hold[1], hold[2]]:
			for tick in range(maxi(bound - WINDOW_TICKS, first), mini(bound + WINDOW_TICKS, last)):
				if not every_tick and _all_held(holds, tick):
					continue
				if tick >= bound - NEAR_TICKS and tick < bound + NEAR_TICKS:
					halves[2 * tick] = true
					halves[2 * tick + 1] = true
				elif (tick - bound) % FAR_STEP == 0:
					halves[2 * tick] = true
	var keys := halves.keys()
	keys.sort()
	var times: Array[float] = []
	for half: int in keys:
		times.append(half / 2.0)
	return times


## Whether a hold covers `tick` on both zones.
static func _all_held(holds: Array, tick: int) -> bool:
	return held(holds, FlightTimetable.RUNWAY, tick) and held(holds, FlightTimetable.LANE, tick)


func test_the_shared_zones_sit_on_the_scene_runway_and_taxi_lane() -> void:
	var runway := StandPlacement.runway_zone()
	var lane := StandPlacement.lane_zone()
	print("runway zone %s, lane zone %s" % [runway, lane])
	for waypoint in [&"Touchdown", &"RunwayExit", &"RunwayEntry", &"Liftoff"]:
		var at := _airside.graph.position_of(waypoint)
		assert_float(at.z).is_equal(StandPlacement.RUNWAY_Z)
		assert_bool(runway.has_point(Vector2(at.x, at.z))).is_true()
	for waypoint in [&"TaxiEast", &"TaxiWest"]:
		var at := _airside.graph.position_of(waypoint)
		assert_bool(lane.has_point(Vector2(at.x, at.z))).is_true()
	# The lane reaches from the runway band to the band lane traffic sweeps.
	assert_float(lane.position.y).is_equal_approx(runway.end.y, 0.001)
	assert_float(lane.end.y).is_equal_approx(
		StandPlacement.TAXI_LANE_Z + StandPlacement.HALF_SPAN_M, 0.001
	)


## A plane parked on the site's north row keeps its tail clear of the lane
## traffic's band (StandPlacement.NOSE_GAP_M 2.2 m), so it does not hold the
## lane for its turnaround: 28.05 m since the lane moved from z -256 to -284.
## Control: on the old lane the same tail was 0.05 m clear.
func test_the_north_row_parked_tail_clears_the_lane() -> void:
	var north := StandPlacement.make(1, 0.5, SITE.grid_origin.z)
	var at := StandPlacement.stand_point(north)
	var edge := StandPlacement.lane_zone().end.y
	var old_edge := -256.0 + StandPlacement.HALF_SPAN_M
	var tail := at.z - StandPlacement.TAIL_M
	print(
		(
			"north row tail z %.3f, lane band edge z %.3f, clearance %.3f m (old lane %.3f m)"
			% [tail, edge, tail - edge, tail - old_edge]
		)
	)
	var lane := StandPlacement.lane_zone()
	assert_bool(on_zone(footprint(Transform3D(Basis.IDENTITY, at)), lane)).is_false()
	assert_bool(StandPlacement.clears_lane(north)).is_true()
	assert_float(tail - edge).is_equal_approx(28.05, 0.001)
	assert_float(tail - old_edge).is_equal_approx(0.05, 0.001)


## The decision's reason for the move: a large plane parked door-aligned on a
## north-row stand (PlaneClasses.stand_offset) keeps its tail at least 0.5 m
## clear of the band a large plane on the taxi lane sweeps (the lane's z plus
## the widest large half span). Control: on the old lane at z -256 the same
## tail reached far into that band.
func test_a_north_row_large_tail_clears_the_large_lane_band() -> void:
	var at := StandPlacement.stand_point(StandPlacement.make(1, 0.5, SITE.grid_origin.z))
	var half_span := 0.0
	for model: String in PlaneClasses.CLASSES[PlaneClasses.LARGE]["models"]:
		half_span = maxf(half_span, PlaneModels.PLANES[model]["half_span"])
	var edge := StandPlacement.TAXI_LANE_Z + half_span
	var old_edge := -256.0 + half_span
	var worst := INF
	for model: String in PlaneClasses.CLASSES[PlaneClasses.LARGE]["models"]:
		var tail: float = (
			at.z + PlaneClasses.stand_offset(model).z - PlaneModels.PLANES[model]["tail"]
		)
		print(
			(
				"%s north row tail z %.2f, large lane band edge z %.2f: clearance %.2f m (old lane %.2f m)"
				% [model, tail, edge, tail - edge, tail - old_edge]
			)
		)
		worst = minf(worst, tail - edge)
		assert_float(tail - old_edge).is_less(0.0)
	assert_float(worst).is_greater_equal(0.5)


func test_the_legal_stand_filter_agrees_with_aircraft_clear() -> void:
	# The corners of the site and the stands around its obstacle.
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(SITE.grid_size.x - 1, 0),
		Vector2i(0, SITE.grid_size.y - 1),
		Vector2i(SITE.grid_size.x - 1, SITE.grid_size.y - 1),
	]
	for obstacle in SITE.obstacles:
		for dx in range(-24, 25, 8):
			for dy in range(-3, 4):
				cells.append(obstacle + Vector2i(dx, dy))
	var checked := 0
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= SITE.grid_size.x or cell.y >= SITE.grid_size.y:
			continue
		var stand := StandPlacement.for_cell(_grid, cell)
		var real := (
			StandPlacement.clears_lane(stand) and StandPlacement.aircraft_clear(_grid, SITE, stand)
		)
		(
			assert_bool(is_legal(_grid, SITE, cell))
			. override_failure_message("filter and real check disagree at %s" % [cell])
			. is_equal(real)
		)
		checked += 1
	assert_int(checked).is_greater(10)
	# Control: a stand with an obstacle under its way north is not legal.
	var blocked: SiteDefinition = SITE.duplicate()
	blocked.obstacles = [Vector2i(10, 20)] as Array[Vector2i]
	assert_bool(is_legal(_grid, blocked, Vector2i(10, 40))).is_false()
	assert_bool(is_legal(_grid, blocked, Vector2i(10, 20))).is_true()
	assert_bool(is_legal(_grid, blocked, Vector2i(40, 40))).is_true()


func test_the_holds_cover_every_tick_the_footprint_is_on_the_runway_or_lane() -> void:
	var started := Time.get_ticks_msec()
	var starts := FlightSim.schedule_starts(FIRST)
	var holds := FlightTimetable.flight_holds(starts)
	var zones := {
		FlightTimetable.RUNWAY: StandPlacement.runway_zone(),
		FlightTimetable.LANE: StandPlacement.lane_zone(),
	}
	var window := sample_times(starts, holds, false)
	var full := sample_times(starts, holds, true)
	print("%d window samples, %d boundary samples a stand" % [window.size(), full.size()])
	var legal := legal_cells()
	var edge := {}
	for cell in boundary_cells(legal):
		edge[cell] = true
	# The two door lines that put a stand on TaxiWest's and TaxiEast's x: the
	# shortest taxi out and in any stand can have, which are the latest the
	# arrival leaves the runway and the earliest the departure reaches it. With
	# those the bounds hold however wide the site grows. They are sampled in
	# full on the site's rows at both ends.
	var extra: Array[Dictionary] = []
	var rows := [legal[0].y, legal[legal.size() - 1].y]
	for waypoint in [&"TaxiWest", &"TaxiEast"]:
		for row in rows:
			var x := _airside.graph.position_of(waypoint).x + StandPlacement.DOOR_SIDE_M
			extra.append(StandPlacement.make(1, x, SITE.grid_origin.z + row))
	_seen = {}
	_site_seen = {}
	_on_site = true
	_occupied = 0
	_samples = 0
	_uncovered = []
	var push := starts[FlightSim.State.PUSHBACK]
	var stands := 0
	for cell in legal:
		var stand := StandPlacement.for_cell(_grid, cell)
		var on_edge := edge.has(cell)
		_run_stand(stand, full if on_edge else window, starts, holds, zones, push, not on_edge)
		stands += 1
	_on_site = false
	for stand in extra:
		_run_stand(stand, full, starts, holds, zones, push, false)
		stands += 1
	print("-- legal stands only:")
	_print_measured(starts, holds, _site_seen)
	print("-- with the extra door lines:")
	_print_measured(starts, holds, _seen)
	print(
		(
			(
				"%d legal stands of %d cells (%d on the boundary, every tick) + %d extra, "
				+ "%d samples, %d on a zone, %d ms"
			)
			% [
				legal.size(),
				SITE.grid_size.x * SITE.grid_size.y,
				edge.size(),
				extra.size(),
				_samples,
				_occupied,
				Time.get_ticks_msec() - started
			]
		)
	)
	print("uncovered: %s" % [_uncovered])
	assert_int(legal.size()).is_greater(10000)
	assert_int(edge.size()).is_greater(100)
	assert_int(stands).is_equal(legal.size() + extra.size())
	assert_int(_occupied).is_greater(1000)
	for key in [
		[FlightTimetable.RUNWAY, true],
		[FlightTimetable.LANE, true],
		[FlightTimetable.LANE, false],
		[FlightTimetable.RUNWAY, false]
	]:
		assert_bool(_seen.has(key)).override_failure_message("never on %s" % [key]).is_true()
	assert_array(_uncovered).is_empty()
	# The cuts at phase boundaries the design rejected are short: the arriving
	# plane is still on the runway after TAXI_IN starts, and the departing one
	# is on the lane before TAXI_OUT + 120.
	var taxi_in := starts[FlightSim.State.TAXI_IN]
	var taxi_out := starts[FlightSim.State.TAXI_OUT]
	assert_int(_seen[[FlightTimetable.RUNWAY, true]][1]).is_greater_equal(taxi_in)
	assert_int(_seen[[FlightTimetable.LANE, false]][0]).is_less(taxi_out + 120)
	_assert_shorter_holds_fail(starts, holds, zones, full, push)


## Negative control: with any one bound of any hold moved CONTROL_CUT_TICKS in,
## the stand that reached that bound is on its zone outside the holds. Hold i
## is the one whose first and last ticks _seen records under `keys[i]`. The
## LOOSE_BOUNDS are the exception: they stay at a phase edge although the
## plane is off the lane earlier or reaches it later, so the same cut is still
## covered there, and the test checks that instead.
func _assert_shorter_holds_fail(
	starts: Array[int], holds: Array, zones: Dictionary, times: Array[float], push: int
) -> void:
	var keys := [
		[FlightTimetable.RUNWAY, true],
		[FlightTimetable.LANE, true],
		[FlightTimetable.LANE, false],
		[FlightTimetable.RUNWAY, false]
	]
	var seen := _seen.duplicate(true)
	for index in keys.size():
		for at_end in [false, true]:
			var short := holds.duplicate(true)
			if at_end:
				short[index][2] -= CONTROL_CUT_TICKS
			else:
				short[index][1] += CONTROL_CUT_TICKS
			_uncovered = []
			_run_stand(
				seen[keys[index]][3 if at_end else 2], times, starts, short, zones, push, false
			)
			var bound: int = holds[index][2 if at_end else 1]
			var reached: int = seen[keys[index]][1 if at_end else 0]
			print(
				(
					"hold %d %s cut by %d: %s (bound %d, measured %d, slack %d)"
					% [
						index,
						"end" if at_end else "start",
						CONTROL_CUT_TICKS,
						_uncovered.size() > 0,
						bound,
						reached,
						absi(bound - reached)
					]
				)
			)
			var label := (
				"hold %d %s cut by %d ticks"
				% [index, "end" if at_end else "start", CONTROL_CUT_TICKS]
			)
			if LOOSE_BOUNDS.has([index, at_end]):
				assert_int(absi(bound - reached)).is_greater(CONTROL_CUT_TICKS)
				assert_array(_uncovered).override_failure_message(label + " failed").is_empty()
			else:
				(
					assert_array(_uncovered)
					. override_failure_message(label + " was still enough")
					. is_not_empty()
				)


## Poses the plane at `stand` at every one of `times` and records, in _seen,
## each tick its footprint is on a zone and whether a hold on that zone covers
## it. With `only_unheld`, the zones a hold covers at a sample are skipped.
func _run_stand(
	stand: Dictionary,
	times: Array[float],
	starts: Array[int],
	holds: Array,
	zones: Dictionary,
	push: int,
	only_unheld: bool
) -> void:
	assert_bool(StandPlacement.clears_lane(stand)).is_true()
	assert_bool(_airside.set_stand(stand)).is_true()
	_samples += times.size()
	for time in times:
		var tick := floori(time)
		var open: Array[String] = []
		for zone: String in zones:
			if not (only_unheld and held(holds, zone, tick)):
				open.append(zone)
		if open.is_empty():
			continue
		var shape := footprint(_view.pose_at(starts, time)["transform"])
		for zone in open:
			if not on_zone(shape, zones[zone]):
				continue
			_occupied += 1
			var key := [zone, tick < push]
			_note(_seen, key, tick, stand)
			if _on_site:
				_note(_site_seen, key, tick, stand)
			if not held(holds, zone, tick) and _uncovered.size() < 10:
				_uncovered.append("%s at tick %d, stand %s" % [zone, tick, _label(stand)])


## Widens seen[key] = [first tick, last tick, its stand, its stand] to `tick`.
static func _note(seen: Dictionary, key: Array, tick: int, stand: Dictionary) -> void:
	var span: Array = seen.get(key, [tick, tick, stand, stand])
	if tick < span[0]:
		span[0] = tick
		span[2] = stand
	if tick > span[1]:
		span[1] = tick
		span[3] = stand
	seen[key] = span


## A stand's door x and wall row, for the report.
func _label(stand: Dictionary) -> String:
	return "(door x %.2f, row %.1f)" % [stand["x"], float(stand["wall_z"]) - SITE.grid_origin.z]


func _print_measured(starts: Array[int], holds: Array, seen: Dictionary) -> void:
	var names := FlightSim.State.keys()
	for key: Array in seen:
		var span: Array = seen[key]
		print(
			(
				"%s %s: on it from tick %d (%s+%d) to %d (%s+%d), first at %s, last at %s"
				% [
					key[0],
					"arrival" if key[1] else "departure",
					span[0],
					names[FlightTimetable.state_at(starts, span[0])],
					span[0] - starts[FlightTimetable.state_at(starts, span[0])],
					span[1],
					names[FlightTimetable.state_at(starts, span[1])],
					span[1] - starts[FlightTimetable.state_at(starts, span[1])],
					_label(span[2]),
					_label(span[3]),
				]
			)
		)
	for hold in holds:
		print(
			(
				"hold %s [%d (%s+%d), %d (%s+%d))"
				% [
					hold[0],
					hold[1],
					names[FlightTimetable.state_at(starts, hold[1])],
					hold[1] - starts[FlightTimetable.state_at(starts, hold[1])],
					hold[2],
					names[FlightTimetable.state_at(starts, hold[2])],
					hold[2] - starts[FlightTimetable.state_at(starts, hold[2])],
				]
			)
		)
