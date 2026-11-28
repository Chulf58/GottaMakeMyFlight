class_name TestDemoPacingEvents
extends GdUnitTestSuite
## Regression coverage for Demo Engagement & Pacing Slice 1 (b2091992) and the
## Day 4 Opt-in "Big Jet Showcase" Medium Jet Charter Event (02da9294).

var _main: Node
var _save_path := SaveTestKit.run_path("test_demo_pacing_events")
var _day1_made := 0
var _day1_missed := 0
var _day1_state := -1


func before() -> void:
	DemoMode.set_override_for_test(true)
	_main = SaveTestKit.boot(self, 20261128)
	SaveTestKit.start_airport(_main)
	var flights: FlightSim = _main.get_node("FlightSim")
	var clock: SimClock = _main.get_node("SimClock")
	var guide := _main.get_node_or_null("UnlockGuide") as UnlockGuide
	while flights.opened_tick < 0 and clock.tick < 2000:
		if guide != null and guide.is_open():
			guide.dismiss()
		SaveTestKit.step(_main)
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	while not flights.flight_ids().has(first) and clock.tick < 4000:
		SaveTestKit.step(_main)
	var doors_closed := flights.state_start(first, FlightSim.State.DOORS_CLOSED)
	var settled := doors_closed + 300
	while clock.tick < settled:
		if guide != null and guide.is_open():
			guide.dismiss()
		SaveTestKit.step(_main)
	var sim: PassengerSim = _main.get_node("PassengerSim")
	_day1_made = sim.made_count()
	_day1_missed = sim.missed_count()
	_day1_state = flights.state_of(first)
	DemoMode.clear_override()


func after() -> void:
	DemoMode.clear_override()
	if _main != null:
		_main.free()
		_main = null
	DirAccess.remove_absolute(_save_path)
	DirAccess.remove_absolute(_save_path + ".tmp")


func after_test() -> void:
	DemoMode.clear_override()


func test_bottleneck_and_charter_constants_plus_snapshot_80_ticks() -> void:
	assert_int(PassengerSim.CHECKIN_TICKS).is_equal(80)
	assert_int(SecurityRuntime.BASIC_SCAN_TICKS).is_equal(80)
	assert_int(InfoDesk.HELP_TICKS).is_equal(80)
	assert_array(OfferBoard.STARTER_SIZES[PlaneClasses.SMALL]).is_equal([6, 8])
	assert_int(FlightSim.STARTER_TERMS["booked_passengers"]).is_equal(8)
	assert_int(OfferBoard.CHARTER_MIN_LEAD_MINUTES).is_greater_equal(100)
	assert_int(OfferBoard.CHARTER_MIN_LEAD_MINUTES * GameCalendar.TICKS_PER_MINUTE).is_greater(
		OfferBoard.CHARTER_CUTOFF_LEAD_TICKS
	)
	assert_int(OfferBoard.CHARTER_COOLDOWN_MINUTES).is_equal(75)
	assert_int(OfferBoard.CHARTER_MAX_LEAD_MINUTES).is_equal(180)
	assert_int(OfferBoard.MAX_CHARTERS_PER_DAY).is_equal(4)

	# Mid-check-in passenger with CHECKIN_TICKS = 80 saves and reloads cleanly.
	var world := PassengerTestWorld.reference_world(901)
	var pid := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := world.passenger(pid)
	var guard := 0
	while p.stage != Passenger.Stage.CHECKIN and guard < 600:
		world.step()
		guard += 1
	assert_int(p.stage).is_equal(Passenger.Stage.CHECKIN)
	assert_int(p.service_end - world.clock.tick).is_equal(80)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(world.sim.to_snapshot()))
	var loaded := PassengerSnapshot.load(snap, world.grid)
	assert_str(str(loaded.get("error", ""))).is_empty()
	world.free_all()


func test_day1_starter_flight_boards_all_8_passengers_at_80_ticks() -> void:
	assert_int(_day1_state).is_greater_equal(FlightSim.State.DOORS_CLOSED)
	assert_int(_day1_made).is_equal(8)
	assert_int(_day1_missed).is_equal(0)


func test_demo_incidents_ramp_days_2_to_5_and_preserve_full_game() -> void:
	# Full game defaults remain intact.
	DemoMode.set_override_for_test(false)
	assert_int(IncidentRoll.MAJOR_GAP_DAYS).is_equal(2)
	assert_int(IncidentCatalogue.NONE_WEIGHT).is_equal(4)

	# Demo mode guarantees active events on Days 2-4 (0-based 1..3), enables
	# INSPECTOR and VIP even at tier 0, and keeps Day 5 quiet weight low.
	DemoMode.set_override_for_test(true)
	var world := PassengerTestWorld.reference_world(5150)
	world.flights.open_airport()
	assert_bool(world.flights.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	var director: IncidentDirector = auto_free(IncidentDirector.new())
	director.bind(world.clock, world.flights, world.sim)
	director.set_enabled(true)

	var seen_kinds := {}
	for day in [1, 2, 3]:
		director.on_tick(GameCalendar.day_start(day, 0))
		assert_int(director.last_rolled_day()).is_equal(day)
		var rolled := director.incidents()
		assert_bool(rolled.is_empty()).is_false()
		for inc in rolled:
			if int(inc["roll_day"]) == day:
				seen_kinds[inc["kind"]] = true
				assert_str(inc["kind"]).is_not_equal(IncidentCatalogue.NONE)
	assert_int(seen_kinds.size()).is_greater(0)

	# Verify VIP and INSPECTOR can both roll in DemoMode at tier 0 without FAVOUR.
	var demo_world := {"tier": 0, "places": 4, "faults": 2, "contracts": 1}
	var demo_cands := IncidentCatalogue.candidates(demo_world)
	var kind_names := demo_cands.map(func(c: Dictionary) -> String: return c["kind"])
	assert_array(kind_names).contains([IncidentCatalogue.INSPECTOR, IncidentCatalogue.VIP])
	assert_array(kind_names).not_contains([IncidentCatalogue.FAVOUR])
	world.free_all()


func test_day4_big_jet_showcase_panel_accept_decline_and_save_round_trip() -> void:
	DemoMode.set_override_for_test(true)
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1280, 720)
	add_child(port)

	var clock: SimClock = auto_free(SimClock.new())
	clock.seed_rng(42)
	port.add_child(clock)

	var finances: Finances = auto_free(Finances.new())
	finances.name = "Finances"
	port.add_child(finances)

	var flights: FlightSim = auto_free(FlightSim.new())
	flights.runway_start = PlaneClasses.SMALL
	flights.bind_clock(clock)
	flights.open_airport()
	(
		assert_bool(flights.accept_contract(TestFlightFit.terms("AM", 480, PlaneClasses.SMALL)))
		. is_true()
	)

	var desk: OfferDesk = auto_free(OfferDesk.new())
	desk.name = "OfferDesk"
	desk.flights = flights
	desk.wallet = finances.wallet
	desk.bind_clock(clock)

	var passengers: PassengerSim = auto_free(PassengerSim.new())
	var director: IncidentDirector = auto_free(IncidentDirector.new())
	director.bind(clock, flights, passengers)

	var panel: IncidentPanel = auto_free(IncidentPanel.new())
	panel.director = director
	panel.clock = clock
	panel.offer_desk = desk
	port.add_child(panel)

	var offered_events: Array[Dictionary] = []
	desk.showcase_offered.connect(func(info: Dictionary) -> void: offered_events.append(info))

	# Days 1-3 must not trigger the Day-4 showcase.
	for day in [0, 1, 2]:
		var noon := GameCalendar.tick_at(day, 12 * 60, clock.epoch)
		clock.tick = noon
		desk.on_tick(noon)
	assert_int(offered_events.size()).is_equal(0)
	assert_bool(panel.is_open()).is_false()

	# Day 4 (0-based day == 3) at 06:00 fires the Big Jet Showcase once.
	var day4_morning := GameCalendar.tick_at(3, 6 * 60, clock.epoch)
	clock.tick = day4_morning
	desk.on_tick(day4_morning)
	desk.on_tick(day4_morning + 20)
	assert_int(offered_events.size()).is_equal(1)
	assert_bool(panel.is_open()).is_true()
	assert_bool(clock.paused).is_true()
	var dlg := panel.dialog()
	assert_str(dlg.body_text()).contains("Medium Jet charter")
	var chips := "\n".join(dlg.chip_texts())
	assert_str(chips).contains("Reward: +1,500 money")
	assert_str(chips).contains("Risk: Extra queues")

	# OfferBoard snapshot preserves the pending showcase cleanly across JSON,
	# and IncidentPanel re-presents an unanswered showcase after SaveGame load.
	var snap: Dictionary = JSON.parse_string(JSON.stringify(desk.board.to_snapshot()))
	var reloaded := OfferBoard.new()
	assert_bool(reloaded.from_snapshot(snap)).is_true()
	assert_bool(reloaded.has_pending_showcase()).is_true()
	assert_dict(reloaded.to_snapshot()).is_equal(desk.board.to_snapshot())
	panel.close_for_modal()
	assert_bool(panel.is_open()).is_false()
	panel._on_loaded(true)
	assert_bool(panel.is_open()).is_true()
	dlg = panel.dialog()

	# Accepting grants the free Medium Runway upgrade and schedules the Medium Jet charter.
	var bal_before := finances.wallet.balance
	dlg.accept_button().pressed.emit()
	assert_bool(panel.is_open()).is_false()
	assert_bool(desk.pending_showcase().is_empty()).is_true()
	assert_str(flights.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_int(finances.wallet.balance).is_equal(bal_before)
	var contract := flights.contract_of(OfferDesk.SHOWCASE_ID)
	assert_bool(contract.is_empty()).is_false()
	assert_str(contract["plane_size"]).is_equal(PlaneClasses.MEDIUM)
	assert_int(int(contract["booked_passengers"])).is_between(30, 36)
	assert_bool(FlightContract.is_charter(contract)).is_true()

	# Real FlightSim lifecycle through DEPARTED pays the +$1,500 bonus once
	# without any manual signal emission.
	var show_day := FlightContract.one_off_day(contract)
	var occ_id := FlightTimetable.occurrence_id(OfferDesk.SHOWCASE_ID, show_day)
	var starts := FlightTimetable.starts_for(contract, show_day, clock.epoch)
	flights.on_tick(starts[0])
	assert_bool(flights.flight_ids().has(occ_id)).is_true()
	for s in range(1, FlightSim.STATE_COUNT):
		flights.on_tick(starts[s])
	assert_int(flights.state_of(occ_id)).is_equal(FlightSim.State.DEPARTED)
	flights.on_tick(starts[FlightSim.State.DEPARTED] + 20)
	assert_int(finances.wallet.balance).is_equal(bal_before + OfferDesk.SHOWCASE_BONUS)

	# Atomic rollback: if all gates on Day 4 and Day 5 are packed, accepting fails
	# cleanly without upgrading the runway from SMALL.
	var clock3: SimClock = auto_free(SimClock.new())
	var flights3: FlightSim = auto_free(FlightSim.new())
	flights3.runway_start = PlaneClasses.SMALL
	flights3.bind_clock(clock3)
	flights3.open_airport()
	var desk3: OfferDesk = auto_free(OfferDesk.new())
	desk3.flights = flights3
	desk3.bind_clock(clock3)
	clock3.tick = day4_morning
	desk3.on_tick(day4_morning)
	assert_bool(desk3.pending_showcase().is_empty()).is_false()
	for minute in [420, 555, 690, 825, 960, 1095, 1230]:
		(
			assert_bool(
				flights3.accept_contract(
					TestFlightFit.terms("P%d" % minute, minute, PlaneClasses.SMALL)
				)
			)
			. is_true()
		)
	assert_bool(desk3.answer_showcase(true)).is_false()
	assert_str(flights3.runway.size).is_equal(PlaneClasses.SMALL)
	assert_bool(flights3.contract_of(OfferDesk.SHOWCASE_ID).is_empty()).is_true()

	# Declining path: leaves runway SMALL and schedule untouched, and never re-triggers.
	var clock2: SimClock = auto_free(SimClock.new())
	var flights2: FlightSim = auto_free(FlightSim.new())
	flights2.runway_start = PlaneClasses.SMALL
	flights2.bind_clock(clock2)
	flights2.open_airport()
	(
		assert_bool(flights2.accept_contract(TestFlightFit.terms("AM", 480, PlaneClasses.SMALL)))
		. is_true()
	)
	var desk2: OfferDesk = auto_free(OfferDesk.new())
	desk2.flights = flights2
	desk2.bind_clock(clock2)
	clock2.tick = day4_morning
	desk2.on_tick(day4_morning)
	assert_bool(desk2.answer_showcase(false)).is_true()
	assert_str(flights2.runway.size).is_equal(PlaneClasses.SMALL)
	assert_bool(flights2.contract_of(OfferDesk.SHOWCASE_ID).is_empty()).is_true()
	desk2.on_tick(day4_morning + 100)
	assert_bool(desk2.pending_showcase().is_empty()).is_true()


func test_full_world_save_game_round_trip_for_open_and_accepted_showcase() -> void:
	DemoMode.set_override_for_test(true)
	var flights: FlightSim = _main.get_node("FlightSim")
	var clock: SimClock = _main.get_node("SimClock")
	var desk: OfferDesk = _main.get_node("OfferDesk")
	var save_game := SaveTestKit.save_game(_main)
	var path_open := SaveTestKit.run_path("showcase_open")
	var path_accepted := SaveTestKit.run_path("showcase_accepted")
	var loaded_open: Node = null
	var loaded_accepted: Node = null

	# Pre-schedule Medium runway works before the Showcase offer arrives.
	assert_bool(flights.runway.size == PlaneClasses.SMALL).is_true()
	assert_bool(flights.start_works(PlaneClasses.MEDIUM)).is_true()
	assert_bool(flights.runway.works.scheduled()).is_true()

	# Post the Showcase offer as OPEN for a valid Day-0 slot after current tick.
	var dep_min := 11 * 60
	var open_info := {
		"id": OfferDesk.SHOWCASE_ID,
		"day": GameCalendar.day_of(clock.tick, clock.epoch),
		"departure_minute": dep_min,
		"airline": OfferDesk.SHOWCASE_AIRLINE,
		"destination": OfferDesk.SHOWCASE_DESTINATION,
		"booked_passengers": OfferDesk.SHOWCASE_PASSENGERS,
		"fee_per_passenger": OfferDesk.SHOWCASE_FEE,
		"bonus": OfferDesk.SHOWCASE_BONUS,
		"needs_runway": true,
		"state": OfferBoard.OPEN,
	}
	desk.board.set_showcase(open_info)
	assert_bool(save_game.save_to_file(path_open)).is_true()

	# Reload OPEN state into a fresh main scene: SaveLinks allows it and
	# IncidentPanel opens with the pending Big Jet Showcase dialog.
	loaded_open = SaveTestKit.boot(self, 9911)
	assert_bool(SaveTestKit.save_game(loaded_open).load_from_file(path_open)).is_true()
	var open_panel: IncidentPanel = loaded_open.get_node("IncidentPanel")
	var open_desk: OfferDesk = loaded_open.get_node("OfferDesk")
	assert_bool(open_panel.is_open()).is_true()
	assert_bool(open_desk.pending_showcase().is_empty()).is_false()

	# Accept on the reloaded world: pre-scheduled Medium works clear cleanly,
	# runway becomes MEDIUM, and BJSHOW4 is scheduled.
	open_panel.dialog().accept_button().pressed.emit()
	var open_flights: FlightSim = loaded_open.get_node("FlightSim")
	assert_str(open_flights.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_bool(open_flights.runway.works.scheduled()).is_false()
	assert_int(open_flights.runway.works.start).is_equal(RunwayWorks.NO_TICK)
	assert_bool(open_flights.contract_of(OfferDesk.SHOWCASE_ID).is_empty()).is_false()

	# Save ACCEPTED state and reload into a second fresh main scene (SaveLinks +
	# SaveGame._runway_problem must both pass cleanly).
	assert_bool(SaveTestKit.save_game(loaded_open).save_to_file(path_accepted)).is_true()
	loaded_accepted = SaveTestKit.boot(self, 9922)
	assert_bool(SaveTestKit.save_game(loaded_accepted).load_from_file(path_accepted)).is_true()
	var acc_flights: FlightSim = loaded_accepted.get_node("FlightSim")
	var acc_desk: OfferDesk = loaded_accepted.get_node("OfferDesk")
	var acc_panel: IncidentPanel = loaded_accepted.get_node("IncidentPanel")
	assert_str(acc_flights.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_bool(acc_flights.runway.works.scheduled()).is_false()
	assert_bool(acc_flights.contract_of(OfferDesk.SHOWCASE_ID).is_empty()).is_false()
	assert_str(acc_desk.board.showcase().get("state", "")).is_equal(OfferBoard.ACCEPTED)
	assert_bool(acc_panel.is_open()).is_false()

	loaded_open.free()
	loaded_accepted.free()
	for p in [path_open, path_open + ".tmp", path_accepted, path_accepted + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
