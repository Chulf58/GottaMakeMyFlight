class_name TestStandLaneClearance
extends GdUnitTestSuite
## Stand and lane geometry the taxi bookings rest on: the shared runway and
## lane zones sit on the scene's runway and taxi lane, a north-row parked tail
## clears the lane band, and the legal-stand filter agrees with
## StandPlacement.aircraft_clear(). Kept from the shared-ground holds test,
## whose whole-lane holds GroundPlanner's bookings replaced (Runway R7,
## decision runway-and-taxi-technical-design-movement-plan-analytic-bookings-
## planned-pauses); its helpers serve the other airside tests.

const MAIN_SCENE := "res://main/main.tscn"
const SITE := preload("res://build/terminal_site.tres")
## An overlap smaller than this (m²) is two shapes sharing an edge, not a plane
## An overlap smaller than this (m²) is two shapes sharing an edge, not a plane
## on the zone: a plane on the runway has its wingtips on the lane zone's edge,
## and single-precision poses put them up to a few hundredths of a millimetre
## over it. 0.01 m² is 0.3 mm along the plane's whole length.
const TOUCH_M2 := 0.01

var _airside: Airside
var _grid: BuildGrid


func before() -> void:
	_airside = scene_airside()
	add_child(_airside)
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)


func after() -> void:
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
