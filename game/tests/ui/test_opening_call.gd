class_name TestOpeningCall
extends GdUnitTestSuite
## Gotta Air's opening phone call (board D3e, decisions
## opening-phone-call-right-after-the-airport-opens-the-airline,
## day-clock-stops-until-the-airport-opens-the-opening-call-pau and
## the-airline-s-opening-phone-call-shows-a-new-gotta-air-stati): on
## AirportGate's opening edge, UnlockGuide takes the clock hold synchronously
## on the opening tick, shows the station manager's portrait and GOTTA AIR
## nameplate with the starter flight's departure time once per game (saved in
## BuildUnlocks), and never mixes speakers in one box.

const MAIN := "res://main/main.tscn"
const POT_ENTRIES := [
	["", "GOTTA AIR"],
	["", "Station manager"],
	[
		"",
		(
			"Gotta Air here. Welcome, your airport is open, and I hear it is the only one with"
			+ " a dent in the carpet."
		),
	],
	[
		"",
		(
			"Our first flight to Oslo leaves at {departure_time}. It is a small plane, so please"
			+ " keep the luggage small too."
		),
	],
	["", "Your first passengers are on their way in now."],
	["", "Good luck. Gotta make that flight!"],
]

var _port: SubViewport
var _clock: SimClock
var _flights: FlightSim
var _pax: PassengerSim
var _staff: StaffSim
var _gate: AirportGate
var _rating: AirportRating
var _unlocks: BuildUnlocks
var _save: SaveGame
var _director: IncidentDirector
var _guide: UnlockGuide
var _rings: Array[int] = []
var _changes: Array[bool] = []


func before_test() -> void:
	_rings.clear()
	_changes.clear()
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)


func after_test() -> void:
	PseudoLocale.disable()
	_port.free()


func _build_unit_world(mode := UnlockGuide.Mode.PROFILE) -> void:
	_rings.clear()
	_changes.clear()
	for child in _port.get_children():
		child.free()
	_clock = SimClock.new()
	_port.add_child(_clock)
	_flights = FlightSim.new()
	_flights.clock = _clock
	_port.add_child(_flights)
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_staff = StaffSim.new()
	_pax = PassengerSim.new()
	_pax.wallet = Wallet.new()
	_pax.staff = _staff
	_pax.bind(_clock, _flights, grid)
	_port.add_child(_pax)
	_port.add_child(_staff)
	_gate = AirportGate.new()
	_gate.flights = _flights
	_gate.staff = _staff
	_port.add_child(_gate)
	_rating = auto_free(AirportRating.new())
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = _rating
	_unlocks.passengers = _pax
	_unlocks.manual = true
	_port.add_child(_unlocks)
	_save = SaveGame.new()
	_port.add_child(_save)
	_director = auto_free(IncidentDirector.new())
	_guide = UnlockGuide.new()
	_guide.mode = mode
	_guide.unlocks = _unlocks
	_guide.clock = _clock
	_guide.save_game = _save
	_guide.gate = _gate
	_guide.flights = _flights
	_guide.runway = _flights.runway
	_guide.director = _director
	_guide.phone_ring.connect(func(tier: int) -> void: _rings.append(tier))
	_guide.dialog_changed.connect(func(open: bool) -> void: _changes.append(open))
	_port.add_child(_guide)


func _staff_and_step_until_open() -> void:
	_staff.hire(StaffMember.Role.CHECKIN)
	_staff.hire(StaffMember.Role.SECURITY)
	for _guard in 60:
		if _flights.opened_tick >= 0:
			return
		# Advance up to 10 steps per call so a missed synchronous hold would run past opened_tick.
		_clock.advance(SimClock.STEP * 10.0)


func _starter_departure_text(flights: FlightSim, clock: SimClock) -> String:
	var dep := flights.state_start(UnlockGuide.STARTER_OCCURRENCE, FlightSim.State.PUSHBACK)
	return GameCalendar.clock_text(dep, clock.epoch)


func test_opening_pauses_synchronously_on_the_opening_tick_and_shows_gotta_air() -> void:
	_build_unit_world()
	_clock.set_speed(2)
	_clock.set_paused(false)
	_staff_and_step_until_open()
	assert_int(_flights.opened_tick).is_greater(0)
	# Synchronous hold: SimClock stopped on the exact opening tick, with 0 extra ticks after.
	assert_int(_clock.tick).is_equal(_flights.opened_tick)
	assert_bool(_clock.paused).is_true()
	assert_bool(_guide.is_open()).is_true()
	assert_bool(_guide.is_ringing()).is_true()
	assert_object(_guide.dialog()).is_null()
	assert_array(_rings).is_equal([UnlockGuide.NO_TIER])
	assert_bool(_guide.answer_ring()).is_true()
	assert_bool(_guide.is_ringing()).is_false()
	var dlg := _guide.dialog()
	assert_object(dlg).is_not_null()
	assert_int(dlg.speaker()).is_equal(IntroDialogue.Speaker.GOTTA_AIR)
	assert_object((dlg.find_child("Portrait", true, false) as TextureRect).texture).is_same(
		IntroDialogue.GOTTA_AIR_PORTRAIT
	)
	assert_str((dlg.find_child("Name", true, false) as Label).text).is_equal("GOTTA AIR")
	assert_str((dlg.find_child("Title", true, false) as Label).text).is_equal("Station manager")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(dlg.scrolls()).is_false()
	var dep_time := _starter_departure_text(_flights, _clock)
	assert_str(dep_time).is_not_empty()
	assert_str(dlg.body_text()).is_equal(BigFirsts.body_for([BigFirsts.OPENING], dep_time))
	assert_str(dlg.body_text()).contains("dent in the carpet")
	assert_str(dlg.body_text()).contains("leaves at %s." % dep_time)
	assert_str(dlg.body_text()).contains("Gotta make that flight!")
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)
	_clock.advance(SimClock.STEP * 2.0)
	assert_int(_clock.tick).is_greater(_flights.opened_tick)


func test_other_unlock_guide_dialogs_keep_the_terminal_manager_speaker() -> void:
	_build_unit_world()
	_director.major_presented.emit({"id": 1, "kind": IncidentCatalogue.INSPECTOR})
	_guide.answer_ring()
	assert_int(_guide.dialog().speaker()).is_equal(IntroDialogue.Speaker.TERMINAL_MANAGER)
	(
		assert_object((_guide.dialog().find_child("Portrait", true, false) as TextureRect).texture)
		. is_same(IntroDialogue.PORTRAIT)
	)
	assert_str((_guide.dialog().find_child("Name", true, false) as Label).text).is_equal(
		"TERMINAL MANAGER"
	)
	_guide.dismiss()
	for i in 60:
		_rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in 50:
		_pax.outcome.emit(i, true)
	_unlocks.check()
	_guide.answer_ring()
	assert_int(_guide.dialog().speaker()).is_equal(IntroDialogue.Speaker.TERMINAL_MANAGER)
	assert_str((_guide.dialog().find_child("Name", true, false) as Label).text).is_equal(
		"TERMINAL MANAGER"
	)


func test_opening_call_never_shares_one_box_with_terminal_manager_firsts() -> void:
	_build_unit_world()
	var blocker_owner := Node.new()
	_port.add_child(blocker_owner)
	var other_hold := _clock.holds.take_turn(blocker_owner, func() -> void: pass)
	assert_bool(_gate.open()).is_true()
	_director.major_presented.emit({"id": 1, "kind": IncidentCatalogue.INSPECTOR})
	assert_bool(_guide.is_open()).is_false()
	_clock.holds.release(other_hold)
	# Gotta Air speaks alone first, then swaps in place to Terminal Manager under one hold.
	assert_bool(_guide.is_open()).is_true()
	_guide.answer_ring()
	assert_int(_guide.dialog().speaker()).is_equal(IntroDialogue.Speaker.GOTTA_AIR)
	assert_str(_guide.dialog().body_text()).contains("Gotta Air here.")
	assert_str(_guide.dialog().body_text()).not_contains("A big event has come up.")
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_true()
	assert_int(_guide.dialog().speaker()).is_equal(IntroDialogue.Speaker.TERMINAL_MANAGER)
	assert_str(_guide.dialog().body_text()).is_equal(BigFirsts.body_for([BigFirsts.INCIDENT]))
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_false()
	assert_array(_changes).is_equal([true, false])


func test_open_dialog_while_gotta_air_is_open_queues_tiers_until_dismissed() -> void:
	_build_unit_world()
	assert_bool(_gate.open()).is_true()
	assert_bool(_guide.is_open()).is_true()
	assert_bool(_guide.is_ringing()).is_true()
	# Tier arriving while Gotta Air is still ringing also queues behind Gotta Air.
	_guide.open_dialog([2])
	assert_array(_rings).is_equal([UnlockGuide.NO_TIER])
	_guide.answer_ring()
	assert_int(_guide.dialog().speaker()).is_equal(IntroDialogue.Speaker.GOTTA_AIR)
	assert_str(_guide.dialog().body_text()).contains("Gotta Air here.")
	assert_array(_rings).is_equal([UnlockGuide.NO_TIER])
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_true()
	assert_int(_guide.dialog().speaker()).is_equal(IntroDialogue.Speaker.TERMINAL_MANAGER)
	assert_str(_guide.dialog().body_text()).contains("Food:")
	assert_array(_rings).is_equal([UnlockGuide.NO_TIER, 2])
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_false()
	assert_array(_changes).is_equal([true, false])


func test_opening_shows_once_per_game_and_round_trips_in_the_save_snapshot() -> void:
	_build_unit_world()
	_staff_and_step_until_open()
	assert_bool(_unlocks.first_shown(BigFirsts.OPENING)).is_true()
	_guide.dismiss()
	var snap := JSON.parse_string(JSON.stringify(_unlocks.to_snapshot())) as Dictionary
	assert_array(snap["firsts"]).is_equal([BigFirsts.OPENING])
	_build_unit_world()
	assert_bool(_unlocks.from_snapshot(snap)).is_true()
	assert_bool(_unlocks.first_shown(BigFirsts.OPENING)).is_true()
	_staff_and_step_until_open()
	assert_int(_flights.opened_tick).is_greater(0)
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_empty()
	# Fresh new game shows it again.
	_build_unit_world()
	_staff_and_step_until_open()
	assert_bool(_guide.is_open()).is_true()


func test_guide_off_leaves_opening_unblocked_and_unmarked() -> void:
	_build_unit_world(UnlockGuide.Mode.OFF)
	_staff_and_step_until_open()
	assert_int(_flights.opened_tick).is_greater(0)
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_bool(_unlocks.first_shown(BigFirsts.OPENING)).is_false()


func test_mode_for_returns_off_in_plain_playtest_and_profile_with_hints_switch() -> void:
	assert_int(UnlockGuide.mode_for(PackedStringArray(), "", true)).is_equal(UnlockGuide.Mode.OFF)
	assert_int(UnlockGuide.mode_for(PackedStringArray(), "0", true)).is_equal(UnlockGuide.Mode.OFF)
	assert_int(UnlockGuide.mode_for(PackedStringArray(["--hints"]), "", true)).is_equal(
		UnlockGuide.Mode.PROFILE
	)
	assert_int(UnlockGuide.mode_for(PackedStringArray(), "1", true)).is_equal(
		UnlockGuide.Mode.PROFILE
	)
	assert_int(UnlockGuide.mode_for(PackedStringArray(), "", false)).is_equal(
		UnlockGuide.Mode.PROFILE
	)


func test_opening_strings_are_routed_through_tr_and_present_in_messages_pot() -> void:
	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	for pair: Array in POT_ENTRIES:
		(
			assert_int(PotEntries.count(entries, pair[0], pair[1]))
			. override_failure_message(pair[1])
			. is_equal(1)
		)
		(
			assert_int(PotEntries.complete(entries, pair[0], pair[1]))
			. override_failure_message(pair[1])
			. is_equal(1)
		)
	PseudoLocale.enable(0.4)
	assert_str(BigFirsts.opening_title_text()).starts_with("[")
	var body := BigFirsts.body_for([BigFirsts.OPENING], "08:13")
	for line in body.split("\n"):
		assert_str(line).starts_with("[")
	assert_str(body).contains("08:13")
	var dlg := IntroDialogue.new(
		BigFirsts.opening_title_text(),
		body,
		UnlockGuide.BOX_HEIGHT,
		false,
		IntroDialogue.Speaker.GOTTA_AIR
	)
	_port.add_child(dlg)
	assert_str((dlg.find_child("Name", true, false) as Label).text).starts_with("[")
	assert_str((dlg.find_child("Name", true, false) as Label).text).contains("GOTTA AIR")
	dlg.free()


func test_main_scene_wires_gate_and_flights_into_unlock_guide_on_opening() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	var hud := main.get_node("PassengerHud") as PassengerHud
	hud.unlock_guide().mode = UnlockGuide.Mode.PROFILE
	_port.add_child(main)
	var clock := main.get_node("SimClock") as SimClock
	var flights := main.get_node("FlightSim") as FlightSim
	var staff := main.get_node("Staff") as StaffSim
	hud.press_starter_terminal()
	staff.hire(StaffMember.Role.CHECKIN)
	staff.hire(StaffMember.Role.SECURITY)
	staff.hire(StaffMember.Role.GATE)
	clock.set_paused(false)
	for _guard in 100:
		if flights.opened_tick >= 0:
			break
		clock.advance(SimClock.STEP * 10.0)
	assert_int(flights.opened_tick).is_greater(0)
	assert_int(clock.tick).is_equal(flights.opened_tick)
	assert_bool(clock.paused).is_true()
	assert_bool(hud.unlock_guide().is_open()).is_true()
	assert_bool(hud.unlock_guide().is_ringing()).is_true()
	hud.unlock_guide().answer_ring()
	assert_int(hud.unlock_guide().dialog().speaker()).is_equal(IntroDialogue.Speaker.GOTTA_AIR)
	var dep := _starter_departure_text(flights, clock)
	assert_str(hud.unlock_guide().dialog().body_text()).contains("leaves at %s." % dep)
	hud.unlock_guide().dismiss()
	assert_bool(clock.paused).is_false()
	main.free()
