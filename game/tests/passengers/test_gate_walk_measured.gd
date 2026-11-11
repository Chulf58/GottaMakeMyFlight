class_name TestGateWalkMeasured
extends GdUnitTestSuite
## The gate walk readout (GateWalk; decision gate-walk-time-shows-on-desk-card-
## and-build-caption-longest-walk-from-security) matches a measured walk: one
## gate, two security exits at different distances, a calm passenger cleared
## at the FARTHER exit. The minutes the readout gives are at least the minutes
## the passenger took from leaving the exit to reaching its seat (or standing
## spot), and no more than one game minute over them. The control proves the
## passenger walked and that the exits are not the same distance away.

var _gate: GateWalkWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _gate != null:
		_gate.free_all()
	_gate = null


func _measure(seats: bool, arrive: Passenger.Stage) -> void:
	_gate = GateWalkWorld.make(self, seats)
	var sim := _gate.world.sim
	var walk := GateWalk.new()
	walk.bind(sim)
	var readout := walk.minutes("A")
	var near_exit := sim.security.exit_cell(_gate.near_station)
	var far_exit := sim.security.exit_cell(_gate.far_station)
	var id := _gate.send()
	assert_bool(_gate.run_until_stage(id, arrive)).is_true()
	var left := _gate.tick_of(id, Passenger.Stage.TO_GATE)
	var reached := _gate.tick_of(id, arrive)
	var measured := float(reached - left) / GameCalendar.TICKS_PER_MINUTE
	var started: Vector2i = _gate.stage_cells[id][Passenger.Stage.TO_GATE]
	var arrived: Vector2i = _gate.stage_cells[id][arrive]
	var travelled := Passenger.octile_mm(started, arrived)
	print(
		(
			"readout %d min; walked %d ticks (%.2f min) from %s (far exit %s, near exit %s)"
			% [readout, reached - left, measured, started, far_exit, near_exit]
		)
	)
	# The passenger left by the far exit, and the exits are not equidistant.
	assert_vector(started).is_equal(far_exit)
	assert_int(Passenger.octile_mm(far_exit, GateWalkWorld.EXIT)).is_greater(
		Passenger.octile_mm(near_exit, GateWalkWorld.EXIT)
	)
	# Positive control: it walked a real distance, not nothing.
	assert_int(reached - left).is_greater(GameCalendar.TICKS_PER_MINUTE)
	assert_int(travelled).is_greater(10000)
	assert_int(readout).is_greater(0)
	assert_float(float(readout)).is_greater_equal(measured)
	assert_float(float(readout) - measured).is_less(1.0)


func test_the_seat_walk_from_the_far_exit_matches_the_readout() -> void:
	_measure(true, Passenger.Stage.SITTING_DOWN)


func test_the_standing_spot_walk_from_the_far_exit_matches_the_readout() -> void:
	_measure(false, Passenger.Stage.STANDING)
