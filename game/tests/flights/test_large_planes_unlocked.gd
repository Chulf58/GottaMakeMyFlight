class_name TestLargePlanesUnlocked
extends GdUnitTestSuite
## Stage 2 S2-A (decision d19eb98b): PlaneClasses.max_offer_class() is LARGE,
## OfferBoard gates LARGE by runway size at Tier 1+, the north starter stand
## clears LARGE and docks tp_plane_06a / tp_plane_07a, and a drawn LARGE offer
## runs end-to-end from accept through landing, taxi-in, jet-bridge docking,
## boarding, pushback, taxi-out, takeoff, and fee settlement cleanly.

const SITE := preload("res://build/terminal_site.tres")
const DOCK_TOLERANCE_M := 0.01
const MAX_STEP_TICKS := 15000

var _main: Node


func after_test() -> void:
	if _main != null and is_instance_valid(_main):
		_main.free()
		_main = null


func test_plane_classes_offers_large() -> void:
	assert_str(PlaneClasses.max_offer_class()).is_equal(PlaneClasses.LARGE)
	assert_bool(PlaneClasses.is_offered(PlaneClasses.SMALL)).is_true()
	assert_bool(PlaneClasses.is_offered(PlaneClasses.MEDIUM)).is_true()
	assert_bool(PlaneClasses.is_offered(PlaneClasses.LARGE)).is_true()


func test_offer_board_offered_sizes_gate_large_by_runway() -> void:
	assert_bool(OfferBoard.offered_sizes(0, PlaneClasses.LARGE).has(PlaneClasses.LARGE)).is_false()
	assert_bool(OfferBoard.offered_sizes(0, PlaneClasses.MEDIUM).has(PlaneClasses.LARGE)).is_false()
	assert_bool(OfferBoard.offered_sizes(0, PlaneClasses.SMALL).has(PlaneClasses.LARGE)).is_false()
	for tier in range(1, OfferBoard.MAX_TIER + 1):
		(
			assert_bool(OfferBoard.offered_sizes(tier, PlaneClasses.SMALL).has(PlaneClasses.LARGE))
			. is_false()
		)
		(
			assert_bool(OfferBoard.offered_sizes(tier, PlaneClasses.MEDIUM).has(PlaneClasses.LARGE))
			. is_false()
		)
		var large_offered := OfferBoard.offered_sizes(tier, PlaneClasses.LARGE)
		assert_bool(large_offered.has(PlaneClasses.LARGE)).is_true()
		assert_array(large_offered[PlaneClasses.LARGE]).is_equal(
			OfferBoard.TIER_SIZES[tier][PlaneClasses.LARGE]
		)

	var rng_med := RandomNumberGenerator.new()
	rng_med.seed = 4242
	var board_med := OfferBoard.new()
	for day in 10:
		board_med.ensure_day(day, rng_med, 2, PlaneClasses.MEDIUM)
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			var offer := board_med.offer_of("O%dN%d" % [day, number])
			assert_str(offer["plane_size"]).is_not_equal(PlaneClasses.LARGE)

	var rng_large := RandomNumberGenerator.new()
	rng_large.seed = 4242
	var board_large := OfferBoard.new()
	var large_drawn := 0
	for day in 10:
		board_large.ensure_day(day, rng_large, 2, PlaneClasses.LARGE)
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			if board_large.offer_of("O%dN%d" % [day, number])["plane_size"] == PlaneClasses.LARGE:
				large_drawn += 1
	assert_int(large_drawn).is_greater(0)


func test_starter_north_stand_clears_large_and_docks_both_large_models() -> void:
	var grid := SiteGrid.new(SITE)
	assert_bool(StarterShell.place(grid, SITE.starter_offset)).is_true()
	assert_bool(ReferenceTerminal.fill_interior(grid, SITE.starter_offset).ok).is_true()
	assert_bool(grid.apply(ReferenceTerminal.gate_desk_edit(SITE.starter_offset)).ok).is_true()
	var flights := auto_free(FlightSim.new()) as FlightSim
	var gates := auto_free(GateDesks.new()) as GateDesks
	gates.bind(grid, flights)

	assert_str(gates.max_class("A")).is_equal(PlaneClasses.LARGE)
	var stand: Dictionary = gates.stands["A"]
	var ground := JetBridgePose.ground_y(stand)
	for model: String in PlaneClasses.CLASSES[PlaneClasses.LARGE]["models"]:
		assert_bool(JetBridgePose.reaches(stand, model, ground)).is_true()
		var pose := JetBridgePose.pose_for(stand, model, true, ground)
		assert_bool(pose["docked"]).is_true()
		assert_int((pose["walk"] as PackedVector3Array).size()).is_equal(5)
		var mount_door: Vector3 = pose["mounts"][&"Mount_Door"]
		var plane_door: Vector3 = pose["door"]
		assert_float(mount_door.distance_to(plane_door)).is_less(DOCK_TOLERANCE_M)

	# Building a floor cell inside the Large swing square (outside Medium) lowers max_class.
	var large_cell := Vector2i(45, 100) + LandKit.FIRST_SITE
	assert_bool(grid.apply(BuildEdit.paint_floor(large_cell, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	assert_str(gates.max_class("A")).is_equal(PlaneClasses.MEDIUM)


func test_large_offer_full_pipeline_from_draw_to_settlement() -> void:
	_main = SaveTestKit.boot(self, 912345)
	var clock: SimClock = _main.get_node("SimClock")
	var flights: FlightSim = _main.get_node("FlightSim")
	var desk: OfferDesk = _main.get_node("OfferDesk")
	var gates: GateDesks = _main.get_node("GateDesks")
	var rating: AirportRating = _main.get_node("AirportRating")
	var airside: Airside = _main.get_node("Airside")
	var fleet: PlaneFleet = _main.get_node("PlaneFleet")
	var passengers: PassengerSim = _main.get_node("PassengerSim")
	var finances: Finances = _main.get_node("Finances")
	var staff: StaffSim = _main.get_node("Staff")

	SaveTestKit.start_airport(_main)
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	while flights.opened_tick < 0 and clock.tick < MAX_STEP_TICKS:
		SaveTestKit.step(_main)
	assert_int(flights.opened_tick).is_greater_equal(0)

	# Finish the starter day-0 flight and stop day-1+ starter occurrences so
	# advancing to the next day boundary never skips past a live flight's window.
	flights.end_contract(FlightSim.DEFAULT_ID)
	_advance_until(
		clock,
		func() -> bool: return flights.flight_ids().is_empty(),
		MAX_STEP_TICKS,
	)
	assert_array(flights.flight_ids()).is_empty()

	# Upgrade runway to LARGE and reach Tier 1 rating so LARGE offers draw.
	flights.runway.size = PlaneClasses.LARGE
	assert_str(gates.max_class("A")).is_equal(PlaneClasses.LARGE)
	for i in 10:
		rating.record_passenger(10, true, PassengerSim.MOOD_MAX)
	assert_int(RatingFormula.tier(rating.stars())).is_greater_equal(1)

	var large_offer := {}
	for day in range(1, 20):
		clock.tick = GameCalendar.day_start(day, clock.epoch) - 1
		SaveTestKit.step(_main)
		for offer in desk.board.open_offers():
			if (
				offer["plane_size"] == PlaneClasses.LARGE
				and FlightFit.fits(flights, OfferBoard.terms_of(offer))
			):
				large_offer = offer
				break
		if not large_offer.is_empty():
			break
	assert_dict(large_offer).is_not_empty()

	assert_bool(desk.board.accept(large_offer["id"], flights)).is_true()
	var contract := flights.contract_of(large_offer["id"])
	assert_str(contract["plane_size"]).is_equal(PlaneClasses.LARGE)
	assert_str(contract["gate"]).is_equal("A")
	var occ_id := FlightTimetable.occurrence_id(contract["id"], int(contract["first_day"]))
	var expected_model := PlaneClasses.model_for(contract["airline"], PlaneClasses.LARGE)
	(
		assert_bool(
			(PlaneClasses.CLASSES[PlaneClasses.LARGE]["models"] as Array).has(expected_model)
		)
		. is_true()
	)

	var made_large := [0]
	passengers.outcome.connect(
		func(pid: int, made: bool) -> void:
			var p := passengers.get_passenger(pid)
			if p != null and p.flight_id == occ_id and made:
				made_large[0] += 1
	)
	var states_seen := {}
	flights.state_changed.connect(
		func(flight_id: String, new_state: int) -> void:
			if flight_id == occ_id:
				states_seen[new_state] = true
	)
	var fee_credits := [0]
	finances.wallet.transaction.connect(
		func(amount: int, category: int, _claimed: Dictionary, _tick: int) -> void:
			if category == Wallet.Category.FEES and amount > 0:
				fee_credits[0] += amount
	)

	var first_day := int(contract["first_day"])
	var planned_starts := FlightTimetable.starts_for(contract, first_day, clock.epoch)
	var scheduled := planned_starts[FlightSim.State.SCHEDULED]
	var issue := scheduled - FlightTimetable.ISSUE_LEAD_TICKS
	if clock.tick < issue - 1:
		clock.tick = issue - 1
	while flights.state_of(occ_id) < 0 and clock.tick < scheduled + 100:
		SaveTestKit.step(_main)
	assert_int(flights.state_of(occ_id)).is_greater_equal(FlightSim.State.SCHEDULED)

	var boarding_start := flights.state_start(occ_id, FlightSim.State.BOARDING)
	_advance_until(
		clock,
		func() -> bool: return clock.tick >= boarding_start + 5,
		MAX_STEP_TICKS,
	)
	assert_int(flights.state_of(occ_id)).is_equal(FlightSim.State.BOARDING)
	fleet.update_views()
	var boarding_view := _view_for_flight(fleet, occ_id)
	assert_object(boarding_view).is_not_null()
	assert_int(boarding_view.phase).is_equal(FlightSim.State.BOARDING)
	assert_str(boarding_view.model_name).is_equal(expected_model)
	var bridge: Dictionary = airside.props.bridges["A"]
	assert_bool(bridge["docked"]).is_true()
	var mount := (bridge["node"] as Node3D).find_child("Mount_Door", true, false) as Node3D
	var model_node := boarding_view.get_node("Pivot").get_child(0) as Node3D
	var door_pos: Vector3 = (
		model_node.global_transform * PlaneModels.PLANES[expected_model]["doors"][0]
	)
	assert_float(mount.global_position.distance_to(door_pos)).is_less(DOCK_TOLERANCE_M)

	var pushback_start := flights.state_start(occ_id, FlightSim.State.PUSHBACK)
	_advance_until(
		clock,
		func() -> bool: return clock.tick >= pushback_start + 2,
		MAX_STEP_TICKS,
	)
	assert_int(flights.state_of(occ_id)).is_equal(FlightSim.State.PUSHBACK)
	fleet.update_views()
	var push_view := _view_for_flight(fleet, occ_id)
	assert_object(push_view).is_not_null()
	assert_int(push_view.phase).is_equal(FlightSim.State.PUSHBACK)
	assert_bool(airside.props.bridges["A"]["docked"]).is_false()
	assert_bool(push_view.tug_visible()).is_true()

	var departed_tick := flights.state_start(occ_id, FlightSim.State.DEPARTED)
	_advance_until(
		clock,
		func() -> bool: return clock.tick >= departed_tick + 5,
		MAX_STEP_TICKS,
	)
	assert_int(flights.state_of(occ_id)).is_equal(FlightSim.State.DEPARTED)

	for required in [
		FlightSim.State.APPROACH,
		FlightSim.State.LANDING,
		FlightSim.State.TAXI_IN,
		FlightSim.State.AT_STAND,
		FlightSim.State.BOARDING,
		FlightSim.State.DOORS_CLOSED,
		FlightSim.State.PUSHBACK,
		FlightSim.State.TAXI_OUT,
		FlightSim.State.TAKEOFF,
		FlightSim.State.DEPARTED,
	]:
		(
			assert_bool(states_seen.has(required))
			. override_failure_message("missing state %d" % required)
			. is_true()
		)
	assert_int(made_large[0]).is_greater(0)
	assert_int(fee_credits[0]).is_greater_equal(made_large[0] * int(contract["fee_per_passenger"]))


static func _advance_until(clock: SimClock, done: Callable, max_ticks: int) -> void:
	var limit := clock.tick + max_ticks
	clock.set_paused(false)
	while not done.call() and clock.tick < limit:
		clock.advance(SimClock.STEP * SimClock.MAX_STEPS_PER_FRAME)
	clock.set_paused(true)


static func _view_for_flight(fleet: PlaneFleet, flight_id: String) -> PlaneView:
	for view in fleet.views:
		view.update_pose()
		if view.flight_id == flight_id:
			return view
	return null
