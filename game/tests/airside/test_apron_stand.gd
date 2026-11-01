class_name TestApronStand
extends GdUnitTestSuite
## The live and wanted plane stands (ApronStand, decision plane-stand-design-
## airside-moves-110-m-north-stand-snaps-to, points 3, 4 and 8): a better
## stand waits for the outgoing flight's TAKEOFF, never moves mid-turnaround,
## and moves at once with no flight there; while a flight uses the stand,
## building on its footprint and remaining route is refused and removals
## pass; the live stand survives a save.

const SITE := preload("res://build/terminal_site.tres")
const STARTER_EXIT := Vector2i(20, 112)
const WEST_EXIT := Vector2i(11, 112)
## Under the parked plane at the starter stand (x -26, z -115).
const FOOTPRINT_CELL := Vector2i(17, 95)
## On the starter stand's way north, z -205.
const ROUTE_CELL := Vector2i(17, 5)
## Well east of everything the plane sweeps (x 17).
const FREE_CELL := Vector2i(60, 30)
## The first flight's start ticks.
const FIRST := 1000

var _grid: SiteGrid
var _flights: FlightSim
var _apron: ApronStand
var _starts: Array[int] = []


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.bind(_grid, SITE, _flights)
	_grid.guard = _apron.edit_problem
	_starts = FlightSim.schedule_starts(FIRST)


func _to(tick: int) -> void:
	_flights.on_tick(tick)


func _paint(cell: Vector2i) -> BuildResult:
	return _grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))


## Makes the west exit the better stand without building where a plane goes:
## a second north exit, and floor in the gap straight out of the starter exit
## so its walk goes round.
func _make_west_better() -> int:
	assert_bool(_grid.apply(BuildEdit.remove_wall(WEST_EXIT, BuildGrid.Side.NORTH)).ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", WEST_EXIT, 0))
	assert_bool(placed.ok).is_true()
	assert_bool(_paint(Vector2i(20, 110)).ok).is_true()
	return placed.object_id


func test_a_better_stand_waits_for_the_outgoing_takeoff_and_never_moves_mid_turnaround() -> void:
	var starter := _grid.object_at(STARTER_EXIT)
	assert_bool(_flights.add_flight("F1", _starts)).is_true()
	_to(_starts[FlightSim.State.TAXI_IN])
	var west := _make_west_better()
	print("wanted exit %d, live exit %d" % [_apron.wanted["exit"], _apron.live["exit"]])
	assert_int(_apron.wanted["exit"]).is_equal(west)
	assert_int(_apron.live["exit"]).is_equal(starter)
	for state in [
		FlightSim.State.AT_STAND,
		FlightSim.State.BOARDING,
		FlightSim.State.PUSHBACK,
		FlightSim.State.TAXI_OUT
	]:
		_to(_starts[state])
		_apron.refresh()
		assert_int(_apron.live["exit"]).is_equal(starter)
	assert_str(_apron.status_text()).contains("Stand moves")
	_to(_starts[FlightSim.State.TAKEOFF])
	print(
		(
			"released at tick %d, TAKEOFF starts at %d, live exit %d"
			% [_apron.last_release_tick, _starts[FlightSim.State.TAKEOFF], _apron.live["exit"]]
		)
	)
	assert_int(_apron.live["exit"]).is_equal(west)
	assert_int(_apron.last_release_tick).is_equal(_starts[FlightSim.State.TAKEOFF])
	assert_str(_apron.status_text()).is_equal("")


func test_with_no_flight_a_better_stand_is_taken_at_once() -> void:
	var west := _make_west_better()
	print("live exit %d released at tick %d" % [_apron.live["exit"], _apron.last_release_tick])
	assert_int(_apron.live["exit"]).is_equal(west)
	assert_int(_apron.last_release_tick).is_equal(0)


func test_the_guard_refuses_building_on_the_plane_footprint_and_route_while_busy() -> void:
	# Built before any flight, removed while one is at the stand.
	assert_bool(_paint(FREE_CELL + Vector2i(0, 1)).ok).is_true()
	assert_bool(_flights.add_flight("F1", _starts)).is_true()
	_to(_starts[FlightSim.State.BOARDING])
	var footprint := _paint(FOOTPRINT_CELL)
	var route := _paint(ROUTE_CELL)
	var wall := _grid.apply(BuildEdit.place_wall(ROUTE_CELL + Vector2i(0, 1), BuildGrid.Side.NORTH))
	var free := _paint(FREE_CELL)
	var removal := _grid.apply(BuildEdit.remove_floor(FREE_CELL + Vector2i(0, 1)))
	print(
		(
			"boarding: footprint %s route %s wall %s free %s removal %s"
			% [
				footprint.reason_text(),
				route.reason_text(),
				wall.reason_text(),
				free.ok,
				removal.ok
			]
		)
	)
	assert_int(footprint.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_int(route.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_int(wall.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_bool(free.ok).is_true()
	assert_bool(removal.ok).is_true()
	# Halfway out, the stand is behind the plane but the way north is not.
	var mid := (_starts[FlightSim.State.TAXI_OUT] + _starts[FlightSim.State.TAKEOFF]) / 2
	_to(mid)
	var left := _paint(FOOTPRINT_CELL)
	var ahead := _paint(ROUTE_CELL)
	print("taxi out: stand %s, route ahead %s" % [left.ok, ahead.reason_text()])
	assert_bool(left.ok).is_true()
	assert_int(ahead.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	_to(_starts[FlightSim.State.TAKEOFF])
	assert_bool(_paint(ROUTE_CELL).ok).is_true()


func test_nothing_is_guarded_with_no_flight_at_the_stand() -> void:
	assert_array(_apron.guard_rects()).is_empty()
	assert_bool(_paint(FOOTPRINT_CELL).ok).is_true()


func test_the_live_stand_round_trips_a_snapshot_and_wanted_is_worked_out_again() -> void:
	assert_bool(_flights.add_flight("F1", _starts)).is_true()
	_to(_starts[FlightSim.State.BOARDING])
	var west := _make_west_better()
	var saved := JSON.parse_string(JSON.stringify(_apron.to_snapshot())) as Dictionary
	var twin := auto_free(ApronStand.new()) as ApronStand
	twin.bind(_grid, SITE, _flights)
	assert_bool(twin.from_snapshot(saved)).is_true()
	print("saved %s, twin live %s wanted %s" % [saved, twin.live, twin.wanted])
	assert_bool(ApronStand.same_stand(twin.live, _apron.live)).is_true()
	assert_int(twin.wanted["exit"]).is_equal(west)
	assert_bool(ApronStand.same_stand(twin.wanted, twin.live)).is_false()


func test_a_malformed_or_out_of_range_stand_is_refused() -> void:
	var good := _apron.to_snapshot()
	var outside := good.duplicate(true)
	outside["live"]["wall_z"] = -400.0
	var wrong_type := good.duplicate(true)
	wrong_type["live"]["x"] = "west"
	var fraction := good.duplicate(true)
	fraction["live"]["exit"] = 1.5
	for bad: Dictionary in [outside, wrong_type, fraction, {}]:
		var problem := ApronStand.checked(bad, SITE)
		print("refused: %s" % problem)
		assert_bool(problem.has("error")).is_true()
		(
			assert_error(func() -> void: _apron.from_snapshot(bad))
			. is_push_error("ApronStand.from_snapshot: %s" % problem["error"])
		)
	assert_bool(ApronStand.checked(good, SITE).has("live")).is_true()
