class_name TestArrivalsSaveLoad
extends GdUnitTestSuite
## Arrivals Slice A1: SaveGame JSON round-trip with active DEBOARDING flight,
## ARRIVING passengers in DEPLANING / TO_AIRSIDE_EXIT / TO_ROAD_EXIT, and a
## placed airside_exit_door.

var _main: Node
var _loaded: Node
var _save_path := SaveTestKit.run_path("test_arrivals_save_load")


func after_test() -> void:
	if _main != null:
		_main.free()
		_main = null
	if _loaded != null:
		_loaded.free()
		_loaded = null
	DirAccess.remove_absolute(_save_path)
	DirAccess.remove_absolute(_save_path + ".tmp")


func test_save_and_load_preserves_deboarding_arriving_passengers_and_airside_exit() -> void:
	_main = SaveTestKit.boot(self, 202611)
	SaveTestKit.start_airport(_main)
	var clock: SimClock = _main.get_node("SimClock")
	var flights: FlightSim = _main.get_node("FlightSim")
	var sim: PassengerSim = _main.get_node("PassengerSim")
	var grid: BuildGrid = sim.grid

	for _i in 300:
		SaveTestKit.step(_main)
		if flights.opened_tick >= 0:
			break
	assert_int(flights.opened_tick).is_greater_equal(0)

	# Place an airside_exit_door on the starter terminal's divider wall.
	var offset: Vector2i = sim.site.starter_offset
	var place := BuildEdit.place_object(BuildCatalog.AIRSIDE_EXIT_ID, Vector2i(13, 8) + offset, 2)
	for edit: BuildEdit in DoorPlacement.edits_for(grid, place):
		assert_bool(grid.apply(edit).ok).is_true()

	# Advance into GMF101-d0 DEBOARDING so arriving passengers are active.
	var starter_id := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var deboard_tick := flights.state_start(starter_id, FlightSim.State.DEBOARDING)
	assert_int(deboard_tick).is_greater(0)
	while clock.tick < deboard_tick + 25:
		SaveTestKit.step(_main)
	assert_int(flights.state_of(starter_id)).is_equal(FlightSim.State.DEBOARDING)

	# Spawn arriving passengers covering DEPLANING, TO_AIRSIDE_EXIT, and TO_ROAD_EXIT.
	var p_deplane := PassengerArrivals.spawn(sim, starter_id, 0)
	var p_airside := PassengerArrivals.spawn(sim, starter_id, 1)
	p_airside.apron.clear()
	p_airside.apron_mm = 0
	sim._set_stage(p_airside, Passenger.Stage.TO_AIRSIDE_EXIT)
	var p_road := PassengerArrivals.spawn(sim, starter_id, 0)
	p_road.apron.clear()
	p_road.apron_mm = 0
	p_road.cleared = false
	p_road.at = Vector2i(13, 9) + offset
	sim._set_stage(p_road, Passenger.Stage.TO_ROAD_EXIT)

	assert_bool(SaveTestKit.save_game(_main).save_to_file(_save_path)).is_true()

	_loaded = SaveTestKit.boot(self, 999)
	assert_bool(SaveTestKit.save_game(_loaded).load_from_file(_save_path)).is_true()

	var l_flights: FlightSim = _loaded.get_node("FlightSim")
	var l_sim: PassengerSim = _loaded.get_node("PassengerSim")
	assert_int(l_flights.state_of(starter_id)).is_equal(FlightSim.State.DEBOARDING)
	assert_int(l_flights.arriving_passengers_of(starter_id)).is_equal(
		flights.arriving_passengers_of(starter_id)
	)
	assert_int(l_sim.layout.airside_exits.size()).is_equal(1)

	for pair in [
		[p_deplane.id, Passenger.Stage.DEPLANING, true],
		[p_airside.id, Passenger.Stage.TO_AIRSIDE_EXIT, true],
		[p_road.id, Passenger.Stage.TO_ROAD_EXIT, false],
	]:
		var lp := l_sim.get_passenger(pair[0])
		assert_object(lp).is_not_null()
		assert_bool(lp.is_arriving()).is_true()
		assert_int(lp.stage).is_equal(pair[1])
		assert_bool(lp.cleared).is_equal(pair[2])

	# Version mismatch refusal sanity check on SaveGame.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	assert_int(int(raw["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	var old_raw := raw.duplicate(true)
	old_raw["save_version"] = SaveGame.SAVE_VERSION - 1
	FileAccess.open(_save_path, FileAccess.WRITE).store_string(JSON.stringify(old_raw))
	var reject_world := SaveTestKit.boot(self, 777)
	assert_bool(SaveTestKit.save_game(reject_world).load_from_file(_save_path)).is_false()
	reject_world.free()
