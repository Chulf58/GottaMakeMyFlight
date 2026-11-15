class_name TestApronStandUnroutable
extends GdUnitTestSuite
## ApronStand's guard on an airside that cannot route (taxiroutes-as-built,
## board item taxiroutes-residual-edge-cases-on-malformed-scenes): a required
## waypoint missing gives an empty TAXI_OUT path, so the guard cannot tell how
## far the plane has gone and keeps everything its stand sweeps, instead of
## indexing the empty path.

const SITE := preload("res://build/terminal_site.tres")
## The side land's 85 grid columns west of the first site (SiteDefinition).
const SIDE_LAND := Vector2i(85, 0)
## Under the parked plane at the starter stand (x -26, z -115).
const FOOTPRINT_CELL := Vector2i(17, 95) + SIDE_LAND
## On the starter stand's way north, z -205.
const ROUTE_CELL := Vector2i(17, 5) + SIDE_LAND
const FIRST := 1000

var _grid: SiteGrid
var _flights: FlightSim
var _airside: Airside
var _apron: ApronStand
var _starts: Array[int] = []


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_airside = auto_free(TestStandLaneClearance.scene_airside()) as Airside
	add_child(_airside)
	_flights = auto_free(FlightSim.new()) as FlightSim
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.airside = _airside
	_apron.bind(_grid, SITE, _flights)
	_grid.guard = _apron.edit_problem
	_starts = FlightSim.schedule_starts(FIRST)


func _paint(cell: Vector2i) -> BuildResult:
	return _grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))


## A flight taxiing out halfway along a lane with a waypoint missing: building
## near the stand is refused over everything the stand sweeps, the footprint
## the plane would have left behind included. Control: with the waypoint in,
## the same moment has the plane well clear of the stand, which is free.
func test_a_missing_waypoint_keeps_the_full_swept_guard_while_a_flight_taxis_out() -> void:
	assert_bool(_flights.add_flight("F1", _starts)).is_true()
	var mid := (_starts[FlightSim.State.TAXI_OUT] + _starts[FlightSim.State.TAKEOFF]) / 2
	_flights.on_tick(mid)
	assert_int(_flights.state_of("F1")).is_equal(FlightSim.State.TAXI_OUT)
	assert_bool(_airside.routes_gate("")).is_true()
	assert_array(_apron.guard_rects()).is_not_equal(StandPlacement.swept_rects(_apron.live))
	assert_bool(_paint(FOOTPRINT_CELL).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.remove_floor(FOOTPRINT_CELL)).ok).is_true()
	_airside.get_node("RunwayExit").free()
	assert_bool(_airside.rebuild()).is_false()
	assert_bool(_airside.routes_gate("")).is_false()
	assert_int(_airside.phase_path(FlightSim.State.TAXI_OUT).size()).is_equal(0)
	# The guarded cells are worked out once per tick, so take the next tick.
	_flights.on_tick(mid + 1)
	var footprint := _paint(FOOTPRINT_CELL)
	var route := _paint(ROUTE_CELL)
	print(
		(
			"no route: guard %d rects, footprint %s, route %s"
			% [_apron.guard_rects().size(), footprint.reason_text(), route.reason_text()]
		)
	)
	assert_array(_apron.guard_rects()).is_equal(StandPlacement.swept_rects(_apron.live))
	assert_int(footprint.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_int(route.reason).is_equal(BuildResult.Reason.PLANE_AREA)
