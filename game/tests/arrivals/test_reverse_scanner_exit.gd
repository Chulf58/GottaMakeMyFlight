class_name TestReverseScannerExit
extends GdUnitTestSuite
## Regression tests for TO_AIRSIDE_EXIT arriving passengers walking out through
## a reverse security scanner or security lane passage without being
## false-recovered back to the airside exit cell by PassengerEdits.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _spawn_airside_arrival(at: Vector2i) -> Passenger:
	var p := PassengerArrivals.spawn(_world.sim, PassengerTestWorld.FLIGHT, 0)
	assert_object(p).is_not_null()
	p.apron.clear()
	p.apron_mm = 0
	p.clear_path()
	p.at = at
	p.arrival_stop_cap = 0
	_world.sim._set_stage(p, Passenger.Stage.TO_AIRSIDE_EXIT)
	return p


func test_arriving_stream_walks_through_reverse_scanner_into_landside() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 17)
	_world.step()

	var lead := _spawn_airside_arrival(Vector2i(17, 6))
	var follow := _spawn_airside_arrival(Vector2i(17, 5))

	for _i in 400:
		_world.step()
		if (
			_world.sim.get_passenger(lead.id) == null
			and _world.sim.get_passenger(follow.id) == null
		):
			break

	assert_bool(lead.arrival_done).is_true()
	assert_bool(follow.arrival_done).is_true()


func test_mid_scanner_arrival_recovers_if_scanner_is_removed() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 23)
	_world.step()

	var scanner_id: int = ReferenceTerminal.object_ids(grid)["scanners"][0]
	var p := _spawn_airside_arrival(Vector2i(17, 7))
	var entered_scanner := false
	for _i in 40:
		_world.step()
		if p.at == Vector2i(17, 8):
			entered_scanner = true
			break
	assert_bool(entered_scanner).is_true()

	# Place a wall across the scanner's landside exit and remove the scanner:
	# the passenger must still recover onto a valid passenger cell and exit.
	assert_bool(grid.apply(BuildEdit.remove_object(scanner_id)).ok).is_true()
	(
		assert_bool(grid.apply(BuildEdit.place_object(&"statue_indoor", Vector2i(17, 8), 0)).ok)
		. is_true()
	)
	_world.step()
	assert_bool(grid.is_passenger_cell(p.at)).is_true()
	assert_int(grid.object_at(p.at)).is_equal(0)
