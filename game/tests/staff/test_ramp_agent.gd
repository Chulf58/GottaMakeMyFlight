class_name TestRampAgent
extends GdUnitTestSuite

const RAMP := StaffMember.Role.RAMP
const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY
const GATE := StaffMember.Role.GATE
const SITE := preload("res://build/terminal_site.tres")

var _world: PassengerTestWorld
var _bag_world: BagTestWorld
var _dispatch: RampDispatch
var _rating: AirportRating
var _finances: Finances
var _save_main: Node
var _save_control: Node
var _clean_save_snap := {}
var _shuttle_snap := {}
var _shuttle_fid := ""


func before() -> void:
	PassengerTestWorld.tracker = self
	_save_main = SaveTestKit.boot(self, 77)
	_save_control = SaveTestKit.boot(self, 77)
	_clean_save_snap = JSON.parse_string(
		JSON.stringify(SaveTestKit.save_game(_save_main).snapshot(), "", true, true)
	)


func after() -> void:
	PassengerTestWorld.tracker = null
	if _save_main != null:
		_save_main.free()
		_save_main = null
	if _save_control != null:
		_save_control.free()
		_save_control = null


func after_test() -> void:
	_dispatch = null
	_rating = null
	_finances = null
	if _world != null:
		_world.free_all()
		_world = null
	_bag_world = null


func _add_contract_flight(
	flights: FlightSim, cid: String, fid: String, plane_size: String, starts: Array[int]
) -> void:
	flights.runway.size = plane_size
	var terms := {
		"id": cid,
		"airline": "Nordic Jet",
		"destination": "Bergen",
		"departure_minute": 480,
		"plane_size": plane_size,
		"booked_passengers": 6 if plane_size == PlaneClasses.SMALL else 30,
		"fee_per_passenger": 50 if plane_size == PlaneClasses.SMALL else 30,
	}
	flights._contracts.append(flights._candidate(terms, "C", flights.gate_grounds()))
	flights._insert(flights._record(fid, starts, "C", cid, 0))
	flights._changed()


func _setup_tier_world(plane_size: String, starts: Array[int] = []) -> String:
	var grid := SiteGrid.new(SITE)
	StarterShell.place(grid, SITE.starter_offset)
	ReferenceTerminal.fill_interior(grid, SITE.starter_offset)
	var timing := starts if not starts.is_empty() else FlightSim.schedule_starts(0)
	_world = PassengerTestWorld.make(grid, timing, 17)
	_world.sim.site = SITE
	_world.auto_staff = false
	_world.flights._flights.clear()
	_world.flights._contracts.clear()
	_finances = auto_free(Finances.new()) as Finances
	_finances.clock = _world.clock
	_finances.start_new_game()
	_world.sim.wallet = _finances.wallet
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_dispatch = auto_free(RampDispatch.new()) as RampDispatch
	_dispatch.bind(_world.clock, _world.staff, null, _world.flights, _finances, _rating)
	var fid := "T2-d0"
	_add_contract_flight(_world.flights, "T2", fid, plane_size, timing)
	return fid


func _setup_bag_ramp_world(doors_close := 600) -> int:
	_bag_world = BagTestWorld.make(self, doors_close)
	var cart_id := PassengerTestWorld.place(_bag_world.grid, &"baggage_cart", Vector2i(11, 7), 0)
	var staff := auto_free(StaffSim.new()) as StaffSim
	var pax := auto_free(PassengerSim.new()) as PassengerSim
	pax.clock = _bag_world.clock
	pax.flights = _bag_world.flights
	pax.grid = _bag_world.grid
	pax.layout = TerminalLayout.new()
	pax.layout.rebuild(_bag_world.grid)
	pax.staff = staff
	staff.sim = pax
	_finances = auto_free(Finances.new()) as Finances
	_finances.clock = _bag_world.clock
	_finances.start_new_game()
	_dispatch = auto_free(RampDispatch.new()) as RampDispatch
	_dispatch.bind(_bag_world.clock, staff, _bag_world.sim, _bag_world.flights, _finances, null)
	return cart_id


func test_tier1_small_plane_exempt_from_ramp_and_airport_opens() -> void:
	var grid := SiteGrid.new(SITE)
	StarterShell.place(grid, SITE.starter_offset)
	ReferenceTerminal.fill_interior(grid, SITE.starter_offset)
	grid.apply(ReferenceTerminal.gate_desk_edit(SITE.starter_offset))
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 17)
	_world.sim.site = SITE
	_world.auto_staff = false
	_world.flights._flights.clear()
	_world.flights._contracts.clear()
	_world.flights.opened_tick = -1
	var gates := auto_free(GateDesks.new()) as GateDesks
	gates.bind(grid, _world.flights)
	var apron := auto_free(ApronStand.new()) as ApronStand
	apron.passengers = _world.sim
	apron.bind(grid, SITE, _world.flights, gates)
	var gate := auto_free(AirportGate.new()) as AirportGate
	gate.bind(_world.flights, _world.staff)
	StaffTestKit.staff_all(_world.staff, [CHECKIN, SECURITY, GATE])
	assert_int(_world.staff.count(RAMP)).is_equal(0)
	assert_bool(gate.ready_to_open()).is_true()
	_world.step()
	assert_bool(gate.is_open()).is_true()

	_finances = auto_free(Finances.new()) as Finances
	_finances.clock = _world.clock
	_finances.start_new_game()
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_dispatch = auto_free(RampDispatch.new()) as RampDispatch
	_dispatch.bind(_world.clock, _world.staff, null, _world.flights, _finances, _rating)
	var emergencies := []
	_dispatch.emergency_pushback.connect(
		func(fid: String, fee: int) -> void: emergencies.append([fid, fee])
	)
	var start_balance := _finances.wallet.balance
	var fid := _world.flights.flight_ids()[0]
	var model := PlaneClasses.flight_model(_world.flights, fid)
	assert_bool(PlaneClasses.self_taxis(model)).is_true()
	var taxi_out := _world.flights.state_start(fid, FlightSim.State.TAXI_OUT)
	_world.run_to(taxi_out + 5)
	assert_array(emergencies).is_empty()
	assert_int(_finances.wallet.balance).is_equal(start_balance)
	assert_array(_rating.active_adjustments()).is_empty()


func test_baggage_cart_hard_wait_none_hired_vs_all_busy_and_release_on_return() -> void:
	var cart_id := _setup_bag_ramp_world(600)
	var cart2_id := PassengerTestWorld.place(_bag_world.grid, &"baggage_cart", Vector2i(12, 7), 0)
	_bag_world.flights.add_flight("Z2", PassengerTestWorld.starts_with(3900, 4000))
	var staff := _dispatch.staff
	var desk := _bag_world.line()
	var bag := _bag_world.sim.check_in(1, BagTestWorld.FLIGHT, desk)
	_bag_world.run_to(BagTestWorld.ARRIVAL)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_str(_dispatch.block_state()).is_equal("none")

	_bag_world.run_to(bag.cutoff_tick)
	assert_array(_bag_world.sim.shuttles()).is_empty()
	assert_str(_dispatch.block_state()).is_equal("none_hired")
	var alerts := AlertSources.ramp(_dispatch.staff.sim, _bag_world.sim, _dispatch)
	assert_int(alerts.size()).is_equal(1)
	assert_that(alerts[0]["key"]).is_equal(AlertSources.RAMP_BAGGAGE)
	assert_str(alerts[0]["detail"]).contains("No ramp agents hired")
	assert_vector(alerts[0]["targets"][0]).is_equal(
		AlertSources.object_point(_bag_world.grid, cart_id)
	)

	var bag2 := _bag_world.sim.check_in(2, "Z2", desk)
	bag2.state = Bag.State.IN_ROOM
	bag2.cell = Vector2i(11, 6)
	bag2.cutoff_tick = _bag_world.clock.tick + 1
	var busy_id := staff.hire(RAMP)
	_bag_world.step()
	assert_int(_bag_world.sim.shuttles().size()).is_equal(1)
	var shuttle1 := _bag_world.sim.shuttles()[0]
	var worker := staff.get_member(busy_id)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.SHUTTLE)
	assert_int(worker.ramp_shuttle_id).is_equal(shuttle1.id)
	assert_int(shuttle1.driver_staff_id).is_equal(busy_id)
	assert_str(_dispatch.block_state()).is_equal("all_busy")
	alerts = AlertSources.ramp(_dispatch.staff.sim, _bag_world.sim, _dispatch)
	assert_int(alerts.size()).is_equal(1)
	assert_str(alerts[0]["detail"]).contains("All ramp agents busy")
	assert_vector(alerts[0]["targets"][0]).is_equal(
		AlertSources.object_point(_bag_world.grid, cart2_id)
	)

	_bag_world.run_to(shuttle1.return_tick)
	assert_int(_bag_world.sim.shuttles().size()).is_equal(1)
	var shuttle2 := _bag_world.sim.shuttles()[0]
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.SHUTTLE)
	assert_int(worker.ramp_shuttle_id).is_equal(shuttle2.id)
	assert_str(_dispatch.block_state()).is_equal("none")

	var bag3 := _bag_world.sim.check_in(3, BagTestWorld.FLIGHT, desk)
	bag3.state = Bag.State.IN_ROOM
	bag3.cell = Vector2i(11, 6)
	bag3.cutoff_tick = _bag_world.clock.tick
	_bag_world.step()
	assert_str(_dispatch.block_state()).is_equal("none")

	_bag_world.run_to(shuttle2.return_tick)
	assert_array(_bag_world.sim.shuttles()).is_empty()
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.NONE)
	assert_int(worker.ramp_shuttle_id).is_equal(0)
	assert_int(worker.state).is_equal(StaffMember.State.IDLE)


func test_cart_demolition_mid_trip_cancels_shuttle_and_releases_worker() -> void:
	var cart_id := _setup_bag_ramp_world(600)
	var staff := _dispatch.staff
	var ramp_id := staff.hire(RAMP)
	var desk := _bag_world.line()
	var bag := _bag_world.sim.check_in(1, BagTestWorld.FLIGHT, desk)
	_bag_world.run_to(bag.cutoff_tick)
	assert_int(_bag_world.sim.shuttles().size()).is_equal(1)
	var worker := staff.get_member(ramp_id)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.SHUTTLE)

	var cancelled := []
	_bag_world.sim.shuttle_cancelled.connect(
		func(sid: int, cid: int) -> void: cancelled.append([sid, cid])
	)
	assert_bool(_bag_world.grid.apply(BuildEdit.remove_object(cart_id)).ok).is_true()
	_bag_world.step()
	assert_int(cancelled.size()).is_equal(1)
	assert_array(_bag_world.sim.shuttles()).is_empty()
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.NONE)
	assert_int(worker.ramp_shuttle_id).is_equal(0)
	assert_int(worker.state).is_equal(StaffMember.State.IDLE)


func test_tier2_pushback_unstaffed_charges_fee_rating_and_alert() -> void:
	var starts := PassengerTestWorld.starts_with(100, 200)
	var fid := _setup_tier_world(PlaneClasses.MEDIUM, starts)
	var pushback := _world.flights.state_start(fid, FlightSim.State.PUSHBACK)
	var taxi_out := _world.flights.state_start(fid, FlightSim.State.TAXI_OUT)
	var start_balance := _finances.wallet.balance
	var start_stars := _rating.stars()

	_world.run_to(pushback)
	assert_int(_world.flights.state_of(fid)).is_equal(FlightSim.State.PUSHBACK)
	assert_int(_finances.wallet.balance).is_equal(start_balance - PriceTable.EMERGENCY_PUSHBACK_FEE)
	assert_int(_rating.active_adjustments().size()).is_equal(1)
	assert_float(_rating.stars()).is_less(start_stars)
	var alerts := AlertSources.ramp(_world.sim, null, _dispatch)
	assert_int(alerts.size()).is_equal(1)
	assert_that(alerts[0]["key"]).is_equal(AlertSources.RAMP_PUSHBACK)
	assert_str(alerts[0]["title"]).is_equal("Ramp agent needed for pushback")
	assert_str(alerts[0]["detail"]).contains("Hire a ramp agent on Staff")
	assert_bool(alerts[0].get("coral", false)).is_true()

	_world.run_to(taxi_out)
	assert_int(_world.flights.state_of(fid)).is_equal(FlightSim.State.TAXI_OUT)
	assert_int(_finances.wallet.balance).is_equal(start_balance - PriceTable.EMERGENCY_PUSHBACK_FEE)
	assert_int(_rating.active_adjustments().size()).is_equal(1)


func test_tier2_pushback_staffed_no_fee_and_releases_on_taxi_out() -> void:
	var starts := PassengerTestWorld.starts_with(100, 200)
	var fid := _setup_tier_world(PlaneClasses.MEDIUM, starts)
	var doors_closed := _world.flights.state_start(fid, FlightSim.State.DOORS_CLOSED)
	var pushback := _world.flights.state_start(fid, FlightSim.State.PUSHBACK)
	var taxi_out := _world.flights.state_start(fid, FlightSim.State.TAXI_OUT)
	var ramp_id := _world.staff.hire(RAMP)
	var worker := _world.staff.get_member(ramp_id)
	var start_balance := _finances.wallet.balance
	_world.run_to(doors_closed)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.PUSHBACK)
	assert_str(worker.ramp_flight_id).is_equal(fid)
	_world.run_to(pushback + 10)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.PUSHBACK)
	assert_int(_finances.wallet.balance).is_equal(start_balance)
	assert_array(_rating.active_adjustments()).is_empty()
	_world.run_to(taxi_out)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.NONE)
	assert_str(worker.ramp_flight_id).is_equal("")
	assert_int(worker.state).is_equal(StaffMember.State.IDLE)


func test_marshal_best_effort_and_preempted_by_mandatory_jobs() -> void:
	var starts := PassengerTestWorld.starts_with(2000, 3200)
	var fid := _setup_tier_world(PlaneClasses.MEDIUM, starts)
	var taxi_in := _world.flights.state_start(fid, FlightSim.State.TAXI_IN)
	var at_stand := _world.flights.state_start(fid, FlightSim.State.AT_STAND)
	var ramp_id := _world.staff.hire(RAMP)
	var worker := _world.staff.get_member(ramp_id)

	_world.run_to(taxi_in)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.MARSHAL)
	assert_str(worker.ramp_flight_id).is_equal(fid)
	assert_int(worker.state).is_equal(StaffMember.State.ON_DUTY)

	var fid2 := "T2-d1"
	var starts2 := PassengerTestWorld.starts_with(200, 300)
	_add_contract_flight(_world.flights, "T2B", fid2, PlaneClasses.MEDIUM, starts2)
	var doors2 := _world.flights.state_start(fid2, FlightSim.State.DOORS_CLOSED)
	_world.run_to(doors2)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.PUSHBACK)
	assert_str(worker.ramp_flight_id).is_equal(fid2)

	var taxi_out2 := _world.flights.state_start(fid2, FlightSim.State.TAXI_OUT)
	_world.run_to(taxi_out2)
	if _world.flights.state_of(fid) == FlightSim.State.TAXI_IN:
		assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.MARSHAL)
	_world.run_to(at_stand)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.NONE)
	assert_int(worker.state).is_equal(StaffMember.State.IDLE)


func test_fire_idle_and_marshal_immediately_but_defer_pushback_leaving() -> void:
	var starts := PassengerTestWorld.starts_with(2000, 3200)
	var fid := _setup_tier_world(PlaneClasses.MEDIUM, starts)
	var id1 := _world.staff.hire(RAMP)
	assert_bool(_world.staff.fire(RAMP)).is_true()
	assert_int(_world.staff.count(RAMP)).is_equal(0)
	assert_object(_world.staff.get_member(id1)).is_null()

	var id2 := _world.staff.hire(RAMP)
	_world.run_to(_world.flights.state_start(fid, FlightSim.State.TAXI_IN))
	assert_int(_world.staff.get_member(id2).ramp_job).is_equal(StaffMember.RampJob.MARSHAL)
	assert_bool(_world.staff.fire(RAMP)).is_true()
	assert_int(_world.staff.count(RAMP)).is_equal(0)
	assert_int(_world.staff.leaving_count(RAMP)).is_equal(0)
	assert_object(_world.staff.get_member(id2)).is_null()

	var id3 := _world.staff.hire(RAMP)
	_world.run_to(_world.flights.state_start(fid, FlightSim.State.PUSHBACK))
	var w3 := _world.staff.get_member(id3)
	assert_int(w3.ramp_job).is_equal(StaffMember.RampJob.PUSHBACK)
	assert_bool(_world.staff.fire(RAMP)).is_true()
	assert_bool(w3.leaving).is_true()
	assert_int(_world.staff.count(RAMP)).is_equal(1)
	assert_int(_world.staff.leaving_count(RAMP)).is_equal(1)
	assert_bool(_world.staff.fire(RAMP)).is_false()
	_world.run_to(_world.flights.state_start(fid, FlightSim.State.TAXI_OUT))
	assert_int(_world.staff.count(RAMP)).is_equal(0)
	assert_int(_world.staff.leaving_count(RAMP)).is_equal(0)
	assert_object(_world.staff.get_member(id3)).is_null()


func test_fire_shuttle_mid_trip_defers_leaving_until_return() -> void:
	_setup_bag_ramp_world(600)
	var id4 := _dispatch.staff.hire(RAMP)
	var bag := _bag_world.sim.check_in(1, BagTestWorld.FLIGHT, _bag_world.line())
	_bag_world.run_to(bag.cutoff_tick)
	var shuttle := _bag_world.sim.shuttles()[0]
	var w4 := _dispatch.staff.get_member(id4)
	assert_int(w4.ramp_job).is_equal(StaffMember.RampJob.SHUTTLE)
	assert_bool(_dispatch.staff.fire(RAMP)).is_true()
	assert_bool(w4.leaving).is_true()
	assert_int(_dispatch.staff.count(RAMP)).is_equal(1)
	assert_int(_dispatch.staff.leaving_count(RAMP)).is_equal(1)
	_bag_world.run_to(shuttle.return_tick)
	assert_int(_dispatch.staff.count(RAMP)).is_equal(0)
	assert_int(_dispatch.staff.leaving_count(RAMP)).is_equal(0)
	assert_object(_dispatch.staff.get_member(id4)).is_null()


func _ensure_shuttle_snap() -> void:
	if not _shuttle_snap.is_empty():
		return
	assert_bool(SaveTestKit.save_game(_save_main).load_world(_clean_save_snap)).is_true()
	SaveTestKit.start_airport(_save_main)
	var flights: FlightSim = _save_main.get_node("FlightSim")
	var clock: SimClock = _save_main.get_node("SimClock")
	while flights.opened_tick < 0 and clock.tick < 5000:
		SaveTestKit.step(_save_main)
	var build: BuildMode = _save_main.get_node("BuildMode")
	var offset := ReferenceTerminal.offset_on(build.grid)
	RoomTool.mark(
		build.grid, Rect2i(Vector2i(13, 14) + offset, Vector2i(4, 3)), &"bag_room", build.wallet()
	)
	build.grid.apply(BuildEdit.remove_wall(Vector2i(16, 14) + offset, BuildGrid.Side.NORTH))
	build.grid.apply(
		BuildEdit.place_wall(
			Vector2i(14, 14) + offset, BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR
		)
	)
	build.set_tool(BuildMode.Tool.BELT)
	build.lay_belt(Vector2i(15, 10) + offset, Vector2i(16, 10) + offset)
	build.lay_belt(Vector2i(16, 10) + offset, Vector2i(16, 14) + offset)
	build.set_tool(BuildMode.Tool.NONE)
	build.grid.apply(BuildEdit.place_object(&"baggage_cart", Vector2i(14, 15) + offset, 0))
	SaveTestKit.step(_save_main)
	var staff: StaffSim = _save_main.get_node("Staff")
	var bag_sim: BaggageSim = _save_main.get_node("BaggageSim")
	staff.hire(RAMP)
	var fid := flights.flight_ids()[0]
	var bag := bag_sim.check_in(99, fid, build.grid.object_at(Vector2i(15, 9) + offset))
	assert_object(bag).is_not_null()
	while bag_sim.shuttles().is_empty() and clock.tick < 6000:
		SaveTestKit.step(_save_main)
	assert_int(bag_sim.shuttles().size()).is_equal(1)
	_shuttle_fid = fid
	_shuttle_snap = JSON.parse_string(
		JSON.stringify(SaveTestKit.save_game(_save_main).snapshot(), "", true, true)
	)


func test_save_load_v7_v27_bidirectional_savelinks_and_determinism() -> void:
	_ensure_shuttle_snap()
	var main := _save_main
	var clock: SimClock = main.get_node("SimClock")
	if clock.tick != int(_shuttle_snap["clock"]["tick"]):
		assert_bool(SaveTestKit.save_game(main).load_world(_shuttle_snap)).is_true()
	var staff: StaffSim = main.get_node("Staff")
	var bag_sim: BaggageSim = main.get_node("BaggageSim")
	assert_int(bag_sim.shuttles().size()).is_equal(1)
	var ramp_id := bag_sim.shuttles()[0].driver_staff_id
	var worker := staff.get_member(ramp_id)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.SHUTTLE)
	assert_bool(staff.fire(RAMP)).is_true()
	assert_bool(worker.leaving).is_true()

	var save := SaveTestKit.save_game(main)
	var data := JSON.parse_string(JSON.stringify(save.snapshot(), "", true, true)) as Dictionary
	assert_int(int(data["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	assert_int(int(data["staff"]["save_version"])).is_equal(StaffSim.SAVE_VERSION)

	var control := _save_control
	var control_save := SaveTestKit.save_game(control)
	assert_bool(control_save.load_world(data)).is_true()
	assert_str(StaffTestKit.signature(control.get_node("Staff"))).is_equal(
		StaffTestKit.signature(staff)
	)
	var remaining := maxi(1, bag_sim.shuttles()[0].return_tick - clock.tick + 2)
	for _i in remaining:
		SaveTestKit.step(main)
		SaveTestKit.step(control)
		assert_str(StaffTestKit.signature(control.get_node("Staff"))).is_equal(
			StaffTestKit.signature(staff)
		)
	assert_int(staff.count(RAMP)).is_equal(0)
	assert_int((control.get_node("Staff") as StaffSim).count(RAMP)).is_equal(0)


func test_savelinks_and_snapshot_refuse_malformed_ramp_claims() -> void:
	_ensure_shuttle_snap()
	var fid := _shuttle_fid
	var save := SaveTestKit.save_game(_save_control)
	var valid := _shuttle_snap

	# 1. Shuttle driver_staff_id disagrees with worker's ramp_shuttle_id.
	var bad1: Dictionary = valid.duplicate(true)
	bad1["baggage"]["shuttles"][0]["driver_staff_id"] = 999
	assert_bool(save.load_world(bad1)).is_false()

	# 2. Duplicate worker claiming same shuttle.
	var bad2: Dictionary = valid.duplicate(true)
	var dup_rec: Dictionary = bad2["staff"]["members"].back().duplicate(true)
	dup_rec["id"] = int(bad2["staff"]["next_id"])
	bad2["staff"]["next_id"] = int(dup_rec["id"]) + 1
	bad2["staff"]["members"].append(dup_rec)
	assert_bool(save.load_world(bad2)).is_false()

	# 3. Non-RAMP member holding a ramp_job.
	var bad3: Dictionary = valid.duplicate(true)
	bad3["staff"]["members"][0]["ramp_job"] = StaffMember.RampJob.MARSHAL
	bad3["staff"]["members"][0]["ramp_flight_id"] = fid
	assert_bool(save.load_world(bad3)).is_false()

	# 4. leaving=true on MARSHAL or NONE ramp agent refused.
	var bad4: Dictionary = valid.duplicate(true)
	for rec: Dictionary in bad4["staff"]["members"]:
		if int(rec["role"]) == RAMP:
			rec["ramp_job"] = StaffMember.RampJob.MARSHAL
			rec["ramp_shuttle_id"] = 0
			rec["ramp_flight_id"] = fid
			rec["leaving"] = true
	assert_bool(save.load_world(bad4)).is_false()

	# 5. PUSHBACK / MARSHAL naming self_taxis starter flight refused.
	var bad5: Dictionary = valid.duplicate(true)
	bad5["baggage"]["shuttles"] = []
	for rec: Dictionary in bad5["staff"]["members"]:
		if int(rec["role"]) == RAMP:
			rec["ramp_job"] = StaffMember.RampJob.MARSHAL
			rec["ramp_shuttle_id"] = 0
			rec["ramp_flight_id"] = fid
	assert_bool(save.load_world(bad5)).is_false()

	# 6. Role.RAMP with indoor at != NO_CELL refused by StaffSnapshot.
	var bad6: Dictionary = valid.duplicate(true)
	for rec: Dictionary in bad6["staff"]["members"]:
		if int(rec["role"]) == RAMP:
			rec["at"] = [10, 10]
			rec["path"] = [[10, 10]]
	assert_bool(save.load_world(bad6)).is_false()

	# 7. Active shuttle with driver_staff_id == 0 refused by whole-world SaveLinks.
	var bad7: Dictionary = valid.duplicate(true)
	bad7["baggage"]["shuttles"][0]["driver_staff_id"] = 0
	for rec: Dictionary in bad7["staff"]["members"]:
		if int(rec["role"]) == RAMP:
			rec["ramp_job"] = StaffMember.RampJob.NONE
			rec["ramp_shuttle_id"] = 0
			rec["state"] = StaffMember.State.IDLE
	assert_bool(save.load_world(bad7)).is_false()
	assert_str(save.message_text()).contains("is not a matching ramp agent")


func test_unstaffed_pushback_save_load_restores_alert_without_double_charge_and_savelinks() -> void:
	var main := _save_main
	var save := SaveTestKit.save_game(main)
	assert_bool(save.load_world(_clean_save_snap)).is_true()
	SaveTestKit.start_airport(main)
	var flights: FlightSim = main.get_node("FlightSim")
	var clock: SimClock = main.get_node("SimClock")
	var finances: Finances = main.get_node("Finances")
	var rating: AirportRating = main.get_node("AirportRating")
	var pax: PassengerSim = main.get_node("PassengerSim")
	var dispatch: RampDispatch = main.get_node("RampDispatch")
	while flights.opened_tick < 0 and clock.tick < 5000:
		SaveTestKit.step(main)
	flights.runway.size = PlaneClasses.MEDIUM
	var board := (main.get_node("OfferDesk") as OfferDesk).board
	var offers := board.to_snapshot()
	var chosen_id := ""
	for offer: Dictionary in offers["offers"]:
		if String(offer["status"]) == OfferBoard.OPEN:
			offer["traits"] = {}
			offer["plane_size"] = PlaneClasses.MEDIUM
			offer["booked_passengers"] = OfferBoard.STARTER_SIZES[PlaneClasses.MEDIUM][0]
			offer["fee_per_passenger"] = (
				OfferBoard.TIER_FEES[OfferBoard.tier_of(offer["airline"])][0]
			)
			offer["departure_minute"] = 720
			chosen_id = String(offer["id"])
			break
	assert_bool(board.from_snapshot(offers)).is_true()
	assert_bool(board.accept(chosen_id, flights)).is_true()
	var fid := FlightTimetable.occurrence_id(
		chosen_id, int(flights.contract_of(chosen_id)["first_day"])
	)
	while flights.state_start(fid, FlightSim.State.PUSHBACK) < 0 and clock.tick < 20000:
		SaveTestKit.step(main)
	var pushback_tick := flights.state_start(fid, FlightSim.State.PUSHBACK)
	assert_int(pushback_tick).is_greater(0)
	var balance_before := 0
	while clock.tick < pushback_tick:
		if clock.tick == pushback_tick - 1:
			balance_before = finances.wallet.balance
		SaveTestKit.step(main)
	assert_int(flights.state_of(fid)).is_equal(FlightSim.State.PUSHBACK)
	assert_int(finances.wallet.balance).is_equal(balance_before - PriceTable.EMERGENCY_PUSHBACK_FEE)
	assert_int(rating.active_adjustments().size()).is_equal(1)
	var alerts_before := AlertSources.ramp(pax, null, dispatch)
	assert_int(alerts_before.size()).is_equal(1)
	assert_that(alerts_before[0]["key"]).is_equal(AlertSources.RAMP_PUSHBACK)

	var valid := JSON.parse_string(JSON.stringify(save.snapshot(), "", true, true)) as Dictionary

	var bad_no_adj: Dictionary = valid.duplicate(true)
	bad_no_adj["rating"]["adjustments"] = []
	assert_bool(save.load_world(bad_no_adj)).is_false()
	assert_str(save.message_text()).contains("lacks a ramp agent or emergency pushback adjustment")

	var bad_both: Dictionary = valid.duplicate(true)
	var next_staff_id := int(bad_both["staff"]["next_id"])
	bad_both["staff"]["next_id"] = next_staff_id + 1
	(
		bad_both["staff"]["members"]
		. append(
			{
				"id": next_staff_id,
				"role": RAMP,
				"state": StaffMember.State.ON_DUTY,
				"station": 0,
				"slot": 0,
				"at": [-1, -1],
				"path": [],
				"path_index": 0,
				"seg_mm": 0,
				"needs_replan": false,
				"search_failed": false,
				"leaving": false,
				"backing_out": false,
				"job": 0,
				"job_bin": false,
				"work_left": 0,
				"ramp_job": StaffMember.RampJob.PUSHBACK,
				"ramp_shuttle_id": 0,
				"ramp_flight_id": fid,
			}
		)
	)
	assert_bool(save.load_world(bad_both)).is_false()
	assert_str(save.message_text()).contains("both ramp agent and emergency pushback adjustment")

	var control := _save_control
	var control_save := SaveTestKit.save_game(control)
	assert_bool(control_save.load_world(valid)).is_true()
	var c_finances: Finances = control.get_node("Finances")
	var c_rating: AirportRating = control.get_node("AirportRating")
	var c_pax: PassengerSim = control.get_node("PassengerSim")
	var c_dispatch: RampDispatch = control.get_node("RampDispatch")
	assert_int(c_finances.wallet.balance).is_equal(finances.wallet.balance)
	assert_int(c_rating.active_adjustments().size()).is_equal(1)
	assert_int(c_dispatch.recent_emergencies().size()).is_equal(1)
	var alerts_loaded := AlertSources.ramp(c_pax, null, c_dispatch)
	assert_int(alerts_loaded.size()).is_equal(1)
	assert_that(alerts_loaded[0]["key"]).is_equal(AlertSources.RAMP_PUSHBACK)

	var bal_after_load := c_finances.wallet.balance
	for _i in 15:
		SaveTestKit.step(control)
	assert_int(c_finances.wallet.balance).is_equal(bal_after_load)
	assert_int(c_rating.active_adjustments().size()).is_equal(1)


func test_fired_leaving_ramp_agent_removed_on_shuttle_cancel() -> void:
	var cart_id := _setup_bag_ramp_world(600)
	var staff := _dispatch.staff
	var ramp_id := staff.hire(RAMP)
	var bag := _bag_world.sim.check_in(1, BagTestWorld.FLIGHT, _bag_world.line())
	_bag_world.run_to(bag.cutoff_tick)
	var worker := staff.get_member(ramp_id)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.SHUTTLE)
	assert_bool(staff.fire(RAMP)).is_true()
	assert_bool(worker.leaving).is_true()
	assert_bool(_bag_world.grid.apply(BuildEdit.remove_object(cart_id)).ok).is_true()
	_bag_world.step()
	assert_int(staff.count(RAMP)).is_equal(0)
	assert_int(staff.leaving_count(RAMP)).is_equal(0)
	assert_object(staff.get_member(ramp_id)).is_null()


func test_fired_leaving_ramp_agent_removed_when_pushback_flight_pruned() -> void:
	var starts := PassengerTestWorld.starts_with(200, 300)
	var fid := _setup_tier_world(PlaneClasses.MEDIUM, starts)
	var ramp_id := _world.staff.hire(RAMP)
	_world.run_to(_world.flights.state_start(fid, FlightSim.State.PUSHBACK))
	var worker := _world.staff.get_member(ramp_id)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.PUSHBACK)
	assert_bool(_world.staff.fire(RAMP)).is_true()
	assert_bool(worker.leaving).is_true()
	_world.flights._flights.clear()
	_world.flights._changed()
	_world.step()
	assert_int(_world.staff.count(RAMP)).is_equal(0)
	assert_int(_world.staff.leaving_count(RAMP)).is_equal(0)
	assert_object(_world.staff.get_member(ramp_id)).is_null()


func test_staff_characters_marshal_pose_visible_and_clears_at_stand() -> void:
	var starts := PassengerTestWorld.starts_with(2000, 3200)
	var fid := _setup_tier_world(PlaneClasses.MEDIUM, starts)
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	chars.clock = _world.clock
	chars.staff = _world.staff
	chars.flights = _world.flights
	add_child(chars)

	var ramp_id := _world.staff.hire(RAMP)
	_world.run_to(_world.flights.state_start(fid, FlightSim.State.TAXI_IN))
	var worker := _world.staff.get_member(ramp_id)
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.MARSHAL)
	chars.sync(true)
	var ramp_node := chars.node_for(ramp_id)
	assert_object(ramp_node).is_not_null()
	assert_bool(ramp_node.visible).is_true()
	assert_str(ramp_node.get_meta(&"clip", "")).is_equal("idle")

	_world.run_to(_world.flights.state_start(fid, FlightSim.State.AT_STAND))
	assert_int(worker.ramp_job).is_equal(StaffMember.RampJob.NONE)
	chars.sync(true)
	var staged_node := chars.node_for(ramp_id)
	assert_object(staged_node).is_not_null()
	assert_bool(staged_node.visible).is_true()
	assert_str(staged_node.get_meta(&"clip", "")).is_equal("idle")
	assert_int(chars.hand_prop_of(ramp_id)).is_equal(StaffHandProps.PropKind.NONE)


func test_staff_panel_tier1_5_cols_and_tier2_6_cols_fit_1280() -> void:
	var port := auto_free(SubViewport.new()) as SubViewport
	port.size = Vector2i(1280, 720)
	add_child(port)
	var unlocks := BuildUnlocks.new()
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	mode.unlocks = unlocks
	mode.require_unlocks = true
	port.add_child(unlocks)
	port.add_child(mode)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	_world = PassengerTestWorld.reference_world()
	_world.auto_staff = false
	var panel := auto_free(StaffPanel.new()) as StaffPanel
	panel.staff = _world.staff
	panel.menu = menu
	panel.unlocks = unlocks
	port.add_child(panel)

	menu.staff_button.pressed.emit()
	await await_idle_frame()
	var cols := (panel.card().get_child(0) as Control).get_children()
	var visible_tier1 := 0
	for c in cols:
		if (c as Control).visible:
			visible_tier1 += 1
	assert_int(visible_tier1).is_equal(4)
	assert_bool(panel.is_role_visible(StaffMember.Role.SHOP)).is_false()
	assert_bool((cols[cols.size() - 1] as Control).visible).is_false()

	# Unlock Tier 2 -> Ramp agents column reveals live, 6 columns fit inside 1280x720 without overlap.
	unlocks._tier = 2
	unlocks.tier_changed.emit(2)
	await await_idle_frame()
	var visible_tier2 := 0
	var col_rects: Array[Rect2] = []
	for c in cols:
		var ctrl := c as Control
		if ctrl.visible:
			visible_tier2 += 1
			var r := ctrl.get_global_rect()
			assert_bool(r.has_area()).is_true()
			for prev in col_rects:
				assert_bool(prev.intersects(r)).is_false()
			col_rects.append(r)
	assert_int(visible_tier2).is_equal(6)
	var card_rect := panel.card().get_global_rect()
	assert_float(card_rect.position.x).is_greater_equal(0.0)
	assert_float(card_rect.end.x).is_less_equal(1280.0)
	assert_float(card_rect.get_center().x).is_equal_approx(640.0, 2.0)
	assert_str(panel.hire_button(RAMP).text).contains("70")
	panel.hire_button(RAMP).pressed.emit()
	assert_int(_world.staff.count(RAMP)).is_equal(1)
	assert_str(panel.counts_text(RAMP)).is_equal("1 hired, 0 on duty")


func test_staff_characters_hi_vis_uniform_and_apron_poses() -> void:
	_setup_bag_ramp_world(600)
	var staff := _dispatch.staff
	var chars := auto_free(StaffCharacters.new()) as StaffCharacters
	chars.clock = _bag_world.clock
	chars.staff = staff
	chars.baggage = _bag_world.sim
	chars.flights = _bag_world.flights
	add_child(chars)

	var officer_id := staff.hire(SECURITY)
	var ramp_id := staff.hire(RAMP)
	chars.sync(true)
	# Idle Ramp Agent is staged visibly airside (not hidden in pool).
	var idle_ramp := chars.node_for(ramp_id)
	assert_object(idle_ramp).is_not_null()
	assert_bool(idle_ramp.visible).is_true()
	assert_str(idle_ramp.get_meta(&"clip", "")).is_equal("idle")
	assert_int(chars.hand_prop_of(ramp_id)).is_equal(StaffHandProps.PropKind.NONE)

	var bag := _bag_world.sim.check_in(1, BagTestWorld.FLIGHT, _bag_world.line())
	_bag_world.run_to(bag.cutoff_tick)
	var shuttle := _bag_world.sim.shuttles()[0]
	chars.sync(true)
	var ramp_node := chars.node_for(ramp_id)
	assert_object(ramp_node).is_not_null()
	assert_str(ramp_node.get_meta(&"clip", "")).is_equal("walk")
	var cart_pos := shuttle.pose_at(_bag_world.sim.tick, _bag_world.grid).origin
	assert_float(ramp_node.position.distance_to(cart_pos)).is_greater_equal(0.8)

	# Unloading plays "idle".
	_bag_world.run_to(shuttle.arrive_tick)
	chars.sync(true)
	assert_str(ramp_node.get_meta(&"clip", "")).is_equal("idle")

	# Check hi-vis orange cloth split & pixel hue compared to Security Officer.
	var officer_node := chars._take(SECURITY)
	var officer_mesh := PassengerLooks.body_mesh(officer_node).mesh
	var ramp_mesh := PassengerLooks.body_mesh(ramp_node).mesh
	assert_object(ramp_mesh).is_not_same(officer_mesh)
	assert_int(ramp_mesh.get_surface_count()).is_equal(2)
	var mat := ramp_mesh.surface_get_material(1) as ShaderMaterial
	var img := (mat.get_shader_parameter("albedo_texture") as Texture2D).get_image()
	var orange_pixels := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.s > 0.8 and c.v > 0.7 and c.h >= 0.02 and c.h <= 0.12:
				orange_pixels += 1
	assert_int(orange_pixels).is_greater(20)
	officer_node.free()
	assert_int(officer_id).is_greater(0)
