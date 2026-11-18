class_name TestQuitLogSimEvents
extends GdUnitTestSuite
## The quit log's events that come from the sim's own code: a passenger counted
## missed (the normal path and a passenger held outside by a full entrance
## line, which sends no outcome signal) and every flight result that closes
## between two HUD refreshes, not only the one whose card is shown.

var _dir := ""
var _world: PassengerTestWorld
var _session: QuitLog
var _port: SubViewport


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_dir = SaveTestKit.run_dir("quit_log_sim")
	QuitLog.current = null
	_world = HoldLineKit.desk_hall()
	_session = QuitLog.new()
	_session.open(_dir, "sim")


func after_test() -> void:
	QuitLog.current = null
	if is_instance_valid(_port):
		_port.free()
	_world.free_all()
	var absolute := ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	for name in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute("%s/%s" % [absolute, name])
	DirAccess.remove_absolute(absolute)


func _records(type: String) -> Array:
	_session.end("test")
	var out := []
	for line in FileAccess.get_file_as_string(_session.path).strip_edges().split("\n", false):
		var record: Dictionary = JSON.parse_string(line)
		if record["type"] == type:
			out.append(record)
	return out


func test_a_missed_passenger_is_logged_with_its_stage_and_cause() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.stage = Passenger.Stage.SECURITY_QUEUE
	PassengerLifecycle.finish(_world.sim, p, false)
	var missed := _records("passenger_missed")
	assert_int(missed.size()).is_equal(1)
	assert_str(missed[0]["data"]["stage"]).is_equal("security_queue")
	assert_str(missed[0]["data"]["cause"]).is_equal(
		Passenger.Stuck.keys()[p.missed_stuck].to_lower()
	)


func test_a_passenger_who_made_it_is_not_a_miss() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	PassengerLifecycle.finish(_world.sim, p, true)
	assert_array(_records("passenger_missed")).is_empty()


func test_a_passenger_held_outside_by_a_full_line_is_logged_as_queue_full() -> void:
	PassengerLifecycle._count_line_miss(_world.sim, PassengerTestWorld.FLIGHT)
	var missed := _records("passenger_missed")
	assert_int(missed.size()).is_equal(1)
	assert_str(missed[0]["data"]["stage"]).is_equal("spawned")
	assert_str(missed[0]["data"]["cause"]).is_equal("queue_full")


func test_every_flight_that_closes_between_refreshes_is_logged() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(10, 10)
	_port.add_child(mode)
	var hud := PassengerHud.new()
	hud.clock = _world.clock
	hud.flights = _world.flights
	hud.sim = _world.sim
	hud.build_mode = mode
	_port.add_child(hud)
	_world.sim.flight_results["F1"] = {"made": 3, "missed": 1, "causes": {}}
	_world.sim.flight_results["F2"] = {"made": 5, "missed": 0, "causes": {}}
	_world.flights.doors_closed.emit("F1")
	_world.flights.doors_closed.emit("F2")
	hud.refresh()
	var results := _records("flight_result")
	assert_int(results.size()).is_equal(2)
	assert_int(int(results[0]["data"]["made"])).is_equal(3)
	assert_int(int(results[0]["data"]["missed"])).is_equal(1)
	assert_int(int(results[1]["data"]["made"])).is_equal(5)
