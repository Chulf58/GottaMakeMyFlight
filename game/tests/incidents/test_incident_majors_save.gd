class_name TestIncidentMajorsSave
extends GdUnitTestSuite
## A true SaveGame round trip on the real main scene (board 03e71ed7): one
## OFFERED airline favour and one ANNOUNCED inspector visit, each with its saved
## plan, written to a file and read back. The records come back identical (the
## plan's numbers as ints, also after JSON), the announcement is shown by the
## panel with its own numbers, the quiet-night stop still sees the visit, and
## accepting the favour after the load has exactly the effects it has in the
## unbroken run (SaveTestKit checksum of every part). One boot of main.tscn.

const SEED := 2_611_312
const PLAY_TICKS := 300
const EXTRA := 2
const BONUS := 300

var _path := SaveTestKit.run_path("test_incident_majors_save")
var _base := SaveTestKit.run_path("test_incident_majors_save_base")
var _main: Node
var _save: SaveGame
var _director: IncidentDirector
var _clock: SimClock
var _flights: FlightSim
var _sim: PassengerSim
var _inspector := 0
var _favour := 0
var _flight := ""
var _visit := 0


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_director = _main.get_node("IncidentDirector")
	_clock = _main.get_node("SimClock")
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	SaveTestKit.start_airport(_main)
	for i in PLAY_TICKS:
		SaveTestKit.step(_main)
	assert_bool(_save.save_to_file(_base)).is_true()


## Each case starts from the world as it was booted and played, whatever the
## case before did to it.
func before_test() -> void:
	assert_bool(_save.load_from_file(_base)).is_true()


func after() -> void:
	_main.free()
	for file in [_path, _path + ".tmp", _base, _base + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## Puts the two records in through the director's own load, as a roll and a
## fire leave them, and returns the offered favour's flight.
func _put_in_records() -> void:
	var contracts := _flights.active_contract_ids()
	assert_array(contracts).is_not_empty()
	var contract := _flights.contract_of(contracts[0])
	var today := GameCalendar.day_of(_clock.tick)
	_flight = FlightTimetable.occurrence_id(contracts[0], today + 2)
	var departs := GameCalendar.tick_at(today + 2, int(contract["departure_minute"]))
	_visit = GameCalendar.day_start(today + 1) + 9000
	var data := _director.to_snapshot()
	_inspector = data["next_id"]
	_favour = _inspector + 1
	data["next_id"] = _favour + 1
	var inspector := _record_data(_inspector, IncidentCatalogue.INSPECTOR)
	inspector["state"] = IncidentCatalogue.ANNOUNCED
	# Rules unlike IncidentTuning's: no mess is allowed, so the one on the floor fails it.
	inspector["plan"] = {
		"window_from": _visit - 500,
		"window_to": _visit + 500,
		"visit_tick": _visit,
		"max_messes": 0,
		"max_full_queue": 0,
		"pass_money": 77,
		"fail_half_stars": 3,
		"seen_messes": 0,
		"seen_full_queue": 0,
	}
	var favour := _record_data(_favour, IncidentCatalogue.FAVOUR)
	favour["state"] = IncidentCatalogue.OFFERED
	favour["plan"] = {"flight": _flight, "departs": departs, "extra": EXTRA, "bonus": BONUS}
	(data["incidents"] as Array).append_array([inspector, favour])
	assert_bool(_director.from_snapshot(data)).is_true()
	var places := _director.spill_places()
	assert_array(places).is_not_empty()
	assert_int(_sim.messes.add(MessSim.Kind.SPILL, places[0]["cell"])).is_greater(0)


func _record_data(id: int, kind: String) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"roll_day": GameCalendar.day_of(_clock.tick),
		"state": IncidentCatalogue.SCHEDULED,
		"fire_tick": _clock.tick,
		"cell": [-1, -1],
		"mess_id": 0,
		"place": "",
		"outcome": "",
		"shown": false,
		"plan": {},
	}


func _record(id: int) -> Dictionary:
	for incident in _director.incidents():
		if incident["id"] == id:
			return incident
	return {}


## What accepting the favour did: balance, booked extra and the incident.
func _effects() -> Dictionary:
	return {
		"balance": _sim.wallet.balance,
		"extra": _sim.booking_override_of(_flight),
		"state": _record(_favour)["state"],
		"outcome": _record(_favour)["outcome"],
		"visit": _record(_inspector)["outcome"],
		"adjustments": _director.rating.active_adjustments(),
	}


func test_an_offered_and_an_announced_major_round_trip_with_identical_effects() -> void:
	_put_in_records()
	var offered := _record(_favour)
	var announced := _record(_inspector)
	assert_str(offered["state"]).is_equal(IncidentCatalogue.OFFERED)
	assert_str(announced["state"]).is_equal(IncidentCatalogue.ANNOUNCED)
	assert_bool(_save.save_to_file(_path)).is_true()
	var saved_tick := _clock.tick
	var start_balance := _sim.wallet.balance

	# The unbroken run: the player accepts. The panel is not part of the saved
	# state, so mirror what it does to the announcement (it is shown).
	assert_bool(_director.answer(_favour, true)).is_true()
	_director.acknowledge(_inspector)
	_director.on_tick(_visit)
	var unbroken := _effects()
	var unbroken_sum := SaveTestKit.checksum(_main)
	print("unbroken: %s" % [unbroken])
	assert_int(unbroken["extra"]).is_equal(EXTRA)
	assert_int(unbroken["balance"]).is_equal(start_balance + BONUS)
	assert_str(unbroken["outcome"]).is_equal(IncidentMajors.APPLIED)
	# The visit scored by the saved plan's rules (no mess allowed): a fail.
	assert_str(unbroken["visit"]).is_equal(IncidentMajors.FAILED)
	assert_int(unbroken["adjustments"].size()).is_equal(1)
	assert_int(unbroken["adjustments"][0]["half_star_delta"]).is_equal(-3)

	assert_bool(_save.load_from_file(_path)).is_true()
	assert_int(_clock.tick).is_equal(saved_tick)
	var offered_back := _record(_favour)
	var announced_back := _record(_inspector)
	print("reloaded: %s / %s" % [offered_back, announced_back])
	assert_dict(offered_back).is_equal(offered)
	assert_dict(offered_back["plan"]).is_equal(offered["plan"])
	assert_int(typeof(announced_back["plan"]["visit_tick"])).is_equal(TYPE_INT)
	assert_int(announced_back["plan"]["visit_tick"]).is_equal(_visit)
	assert_int(_sim.booking_override_of(_flight)).is_equal(0)
	assert_int(_sim.wallet.balance).is_equal(start_balance)
	# The panel showed the unshown announcement from the reload, with its numbers.
	var panel := _main.get_node("IncidentPanel") as IncidentPanel
	assert_bool(panel.is_open()).is_true()
	assert_str(panel.dialog().body_text()).contains(GameCalendar.clock_text(_visit - 500))
	assert_bool(announced_back["shown"]).is_true()
	assert_dict(_without_shown(announced_back)).is_equal(_without_shown(announced))
	# The quiet-night stop still sees the visit.
	assert_int(_director.next_event_tick(_clock.tick)).is_equal(_visit)

	assert_bool(_director.answer(_favour, true)).is_true()
	_director.on_tick(_visit)
	assert_dict(_effects()).is_equal(unbroken)
	assert_str(SaveTestKit.checksum(_main)).is_equal(unbroken_sum)


func _without_shown(incident: Dictionary) -> Dictionary:
	var out := incident.duplicate(true)
	out.erase("shown")
	return out


func test_a_declined_offer_after_a_load_changes_nothing() -> void:
	_put_in_records()
	assert_bool(_save.save_to_file(_path)).is_true()
	assert_bool(_save.load_from_file(_path)).is_true()
	var before := _sim.wallet.balance
	assert_bool(_director.answer(_favour, false)).is_true()
	assert_str(_record(_favour)["state"]).is_equal(IncidentCatalogue.DECLINED)
	assert_int(_sim.wallet.balance).is_equal(before)
	assert_int(_sim.booking_override_of(_flight)).is_equal(0)


## The visit's counts are saved with the plan, so the failure card after a load
## names the same breach: the one mess against a limit of none, and no queue.
func test_a_failed_visit_keeps_its_counts_through_a_save_and_names_only_the_breach() -> void:
	_put_in_records()
	# The visit is due now, so the penalty is dated at the clock (a save refuses a
	# rating adjustment from a tick the clock has not reached).
	var data := _director.to_snapshot()
	for saved: Dictionary in data["incidents"]:
		if saved["id"] == _inspector:
			saved["plan"]["visit_tick"] = _clock.tick
			saved["shown"] = true
	assert_bool(_director.from_snapshot(data)).is_true()
	_director.on_tick(_clock.tick)
	assert_str(_record(_inspector)["outcome"]).is_equal(IncidentMajors.FAILED)
	assert_bool(_record(_inspector)["shown"]).is_false()
	assert_int(_record(_inspector)["plan"]["seen_messes"]).is_equal(1)
	assert_int(_record(_inspector)["plan"]["seen_full_queue"]).is_equal(0)
	assert_bool(_save.save_to_file(_path)).is_true()
	assert_bool(_save.load_from_file(_path)).is_true()
	var plan: Dictionary = _record(_inspector)["plan"]
	assert_int(plan["seen_messes"]).is_equal(1)
	assert_int(plan["seen_full_queue"]).is_equal(0)
	var rail := _main.get_tree().get_first_node_in_group(AlertStack.GROUP) as AlertStack
	# User-ruled 2026-11-13, "All fade after 20 s (Recommended)": "Green, cream
	# and coral incident results all leave after 20 seconds of real time, like
	# the flight result card. The words stay in the alerts history, so nothing
	# is lost." This case used to read the breach off the failure card back on
	# the rail after the load; the card is no longer re-posted, so the same
	# words are read from the saved incident's plan through IncidentCopy, the
	# text the card is built from.
	assert_object(rail.notice_card(IncidentCards.key_of({"id": _inspector}))).is_null()
	var words := IncidentCopy.inspector_result(_record(_inspector))
	var text := "%s\n%s" % [words["title"], words["detail"]]
	print(text)
	assert_str(text).contains("1 mess on the floor (none allowed)")
	assert_str(text).not_contains("queue")
