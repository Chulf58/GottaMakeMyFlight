class_name TestStageKinds
extends GdUnitTestSuite
## The one stage classification (decision
## toilet-design-queue-free-reservable-stalls-per-stall-daily-u, point 4):
## every Passenger.Stage is classified for the facility that owns it, where
## the passenger is and how it is drawn, and has a follow panel text and (but
## made and missed) a missed-flight reason. A stage added to the enum without
## all of them fails here. The visit owner and the resumed journey come from
## the facility sims.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func test_every_stage_has_one_row_with_a_facility_a_location_and_a_pose() -> void:
	assert_int(StageKinds.KINDS.size()).is_equal(Passenger.Stage.size())
	var checked := 0
	for stage: int in Passenger.Stage.values():
		(
			assert_bool(StageKinds.KINDS.has(stage))
			. override_failure_message("stage %s has no row" % Passenger.Stage.keys()[stage])
			. is_true()
		)
		var row: Array = StageKinds.KINDS[stage]
		assert_int(row.size()).is_equal(3)
		assert_bool(StageKinds.Facility.values().has(row[0])).is_true()
		assert_bool(StageKinds.Location.values().has(row[1])).is_true()
		assert_bool(StageKinds.Pose.values().has(row[2])).is_true()
		checked += 1
	print("stages classified %d" % checked)
	assert_int(checked).is_equal(Passenger.Stage.size())


func test_every_stage_is_presented_in_the_follow_panel_and_the_flight_result() -> void:
	var fallback := FlightResult.MISSED_TEXT
	var reasons := 0
	for stage: int in Passenger.Stage.values():
		var stage_name: String = Passenger.Stage.keys()[stage]
		(
			assert_bool(PassengerHud.STAGE_TEXT.has(stage))
			. override_failure_message("stage %s has no follow panel text" % stage_name)
			. is_true()
		)
		if StageKinds.location(stage) == StageKinds.Location.SETTLED:
			continue
		var reason := FlightResult.reason_text(stage, Passenger.Stuck.NONE)
		(
			assert_str(reason)
			. override_failure_message("stage %s has no missed-flight reason" % stage_name)
			. is_not_equal(fallback)
		)
		reasons += 1
	print("fallback '%s', reasons %d" % [fallback, reasons])
	assert_int(reasons).is_equal(Passenger.Stage.size() - 2)


func test_cafe_stages_belong_to_the_cafe_and_no_other_stage_does() -> void:
	var cafe := 0
	for stage: int in Passenger.Stage.values():
		var stage_name: String = Passenger.Stage.keys()[stage]
		var expected := (
			StageKinds.Facility.CAFE
			if stage_name.begins_with("CAFE_")
			else StageKinds.Facility.NONE
		)
		assert_int(StageKinds.facility(stage)).is_equal(expected)
		assert_bool(StageKinds.in_visit(stage)).is_equal(expected != StageKinds.Facility.NONE)
		assert_bool(Passenger.in_cafe(stage)).is_equal(expected == StageKinds.Facility.CAFE)
		cafe += int(expected == StageKinds.Facility.CAFE)
	assert_int(cafe).is_equal(7)


func test_seats_and_poses() -> void:
	var gate := [Passenger.Stage.SITTING_DOWN, Passenger.Stage.SEATED, Passenger.Stage.STANDING_UP]
	var cafe := [
		Passenger.Stage.CAFE_SITTING_DOWN,
		Passenger.Stage.CAFE_SEATED,
		Passenger.Stage.CAFE_STANDING_UP,
	]
	var poses := [StageKinds.Pose.SITTING_DOWN, StageKinds.Pose.SEATED, StageKinds.Pose.STANDING_UP]
	for i in 3:
		assert_int(StageKinds.location(gate[i])).is_equal(StageKinds.Location.GATE_SEAT)
		assert_int(StageKinds.location(cafe[i])).is_equal(StageKinds.Location.FACILITY_SEAT)
		assert_int(StageKinds.pose(gate[i])).is_equal(poses[i])
		assert_int(StageKinds.pose(cafe[i])).is_equal(poses[i])
	var seated := 0
	for stage: int in Passenger.Stage.values():
		if StageKinds.pose(stage) != StageKinds.Pose.UPRIGHT:
			seated += 1
			assert_bool(gate.has(stage) or cafe.has(stage)).is_true()
	assert_int(seated).is_equal(6)


func test_outside_and_on_grid_stages() -> void:
	var outside := [
		Passenger.Stage.SPAWNED, Passenger.Stage.APRON, Passenger.Stage.MADE, Passenger.Stage.MISSED
	]
	var off_grid := [Passenger.Stage.APRON, Passenger.Stage.MADE, Passenger.Stage.MISSED]
	for stage: int in Passenger.Stage.values():
		assert_bool(StageKinds.is_outside(stage)).is_equal(outside.has(stage))
		assert_bool(StageKinds.on_grid(stage)).is_equal(not off_grid.has(stage))


func test_a_cafe_guest_has_its_visit_owner_and_resume_and_others_have_none() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var guest := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	var other := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	for p in [guest, other]:
		p.hunger = 0
		p.cafe_cooldown = 1000000
	while guest.stage != Passenger.Stage.TO_SECURITY and _world.clock.tick < 600:
		_world.step()
	assert_int(StageKinds.visit_facility(_world.sim, guest)).is_equal(StageKinds.Facility.NONE)
	assert_dict(StageKinds.resume_of(_world.sim, guest)).is_empty()
	assert_bool(_world.sim.cafes.try_visit(guest)).is_true()
	var visit := _world.sim.cafes.visit_of(guest.id)
	assert_int(StageKinds.visit_facility(_world.sim, guest)).is_equal(StageKinds.Facility.CAFE)
	var resume := StageKinds.resume_of(_world.sim, guest)
	print("resume %s, approach %s" % [resume, visit.seat["approach"]])
	assert_int(resume["stage"]).is_equal(Passenger.Stage.TO_SECURITY)
	assert_that(resume["cell"]).is_equal(visit.seat["approach"])
	assert_int(StageKinds.visit_facility(_world.sim, other)).is_equal(StageKinds.Facility.NONE)
	assert_dict(StageKinds.resume_of(_world.sim, other)).is_empty()


func test_every_stage_has_its_journey_leg_from_the_table_not_the_enum_order() -> void:
	var expected := {
		Passenger.Stage.SPAWNED: StageKinds.Leg.CHECKIN,
		Passenger.Stage.TO_CHECKIN: StageKinds.Leg.CHECKIN,
		Passenger.Stage.CHECKIN_QUEUE: StageKinds.Leg.CHECKIN,
		Passenger.Stage.CHECKIN: StageKinds.Leg.CHECKIN,
		Passenger.Stage.TO_SECURITY: StageKinds.Leg.SECURITY,
		Passenger.Stage.SECURITY_QUEUE: StageKinds.Leg.SECURITY,
		Passenger.Stage.SECURITY: StageKinds.Leg.SECURITY,
		Passenger.Stage.TO_GATE: StageKinds.Leg.AIRSIDE,
		Passenger.Stage.SITTING_DOWN: StageKinds.Leg.AIRSIDE,
		Passenger.Stage.SEATED: StageKinds.Leg.AIRSIDE,
		Passenger.Stage.STANDING: StageKinds.Leg.AIRSIDE,
		Passenger.Stage.STANDING_UP: StageKinds.Leg.AIRSIDE,
		Passenger.Stage.TO_EXIT: StageKinds.Leg.AIRSIDE,
		Passenger.Stage.APRON: StageKinds.Leg.APRON,
		Passenger.Stage.MADE: StageKinds.Leg.DONE,
		Passenger.Stage.MISSED: StageKinds.Leg.DONE,
		Passenger.Stage.CAFE_WALK: StageKinds.Leg.VISIT,
		Passenger.Stage.CAFE_QUEUE: StageKinds.Leg.VISIT,
		Passenger.Stage.CAFE_ORDER: StageKinds.Leg.VISIT,
		Passenger.Stage.CAFE_TO_SEAT: StageKinds.Leg.VISIT,
		Passenger.Stage.CAFE_SITTING_DOWN: StageKinds.Leg.VISIT,
		Passenger.Stage.CAFE_SEATED: StageKinds.Leg.VISIT,
		Passenger.Stage.CAFE_STANDING_UP: StageKinds.Leg.VISIT,
	}
	assert_int(expected.size()).is_equal(Passenger.Stage.size())
	assert_int(StageKinds.LEGS.size()).is_equal(Passenger.Stage.size())
	for stage: int in Passenger.Stage.values():
		(
			assert_int(StageKinds.leg(stage))
			. override_failure_message("stage %s leg" % Passenger.Stage.keys()[stage])
			. is_equal(expected[stage])
		)
		# A visit stage is the visit's facility's, every other stage the
		# journey's own.
		assert_bool(StageKinds.leg(stage) == StageKinds.Leg.VISIT).is_equal(
			StageKinds.in_visit(stage)
		)


func test_the_journey_forecast_refuses_a_passenger_on_a_visit() -> void:
	_world = PassengerTestWorld.reference_world()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.stage = Passenger.Stage.CAFE_QUEUE
	var arrival := [0]
	(
		assert_error(func() -> void: arrival[0] = JourneyForecast.arrival_tick(_world.sim, p))
		. is_push_error(
			(
				(
					"JourneyForecast: passenger %d is on a facility visit (CAFE_QUEUE);"
					+ " its facility forecasts it"
				)
				% p.id
			)
		)
	)
	assert_int(arrival[0]).is_equal(JourneyForecast.NEVER)
