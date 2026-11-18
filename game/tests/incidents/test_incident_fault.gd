class_name TestIncidentFault
extends GdUnitTestSuite
## The scanner fault incident (IncidentFault, decision scanner-fault-incident-
## design-stationfaults-beside-stationcl) on the reference terminal's two
## staffed scanners: it fires on its tick, stops one scanner until a repair
## 400 to 800 ticks later drawn from its own stream, ends on that tick, and
## does not happen when the passengers it would send away have no reachable
## open scanner to go to. The director is driven by hand (on_tick), as in
## TestIncidentDirector.

const DEPARTS := 480

var _w: PassengerTestWorld
var _director: IncidentDirector
var _started: Array[Dictionary] = []
var _ended: Array[Dictionary] = []
var _a := 0
var _b := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_started.clear()
	_ended.clear()
	_w = PassengerTestWorld.reference_world(7311042)
	_w.flights.open_airport()
	assert_bool(_w.flights.accept_contract(TestFlightContracts.terms("AM", DEPARTS))).is_true()
	var scanners := _w.sim.layout.scanners.duplicate()
	scanners.sort()
	_a = scanners[0]
	_b = scanners[1]
	# Both scanners staffed (auto_staff seats them before the tick).
	_w.step()
	_director = _new_director()


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func _new_director() -> IncidentDirector:
	var director := auto_free(IncidentDirector.new()) as IncidentDirector
	director.bind(_w.clock, _w.flights, _w.sim)
	director.started.connect(func(incident: Dictionary) -> void: _started.append(incident))
	director.ended.connect(func(incident: Dictionary) -> void: _ended.append(incident))
	director.set_enabled(true)
	director.forced_kind = IncidentCatalogue.FAULT
	return director


## Rolls day 1's fault and returns its scheduled record.
func _scheduled(director: IncidentDirector) -> Dictionary:
	director.on_tick(GameCalendar.day_start(1, 0))
	var all := director.incidents()
	assert_int(all.size()).is_equal(1)
	assert_str(all[0]["kind"]).is_equal(IncidentCatalogue.FAULT)
	return all[0]


func test_a_fault_stops_one_scanner_until_a_repair_drawn_on_its_fire() -> void:
	var incident := _scheduled(_director)
	var fire: int = incident["fire_tick"]
	assert_bool(_w.staff.is_open(_a) and _w.staff.is_open(_b)).is_true()
	_director.on_tick(fire)
	var active := _director.active_incidents()
	assert_int(active.size()).is_equal(1)
	var plan: Dictionary = active[0]["plan"]
	var station: int = plan["station"]
	var repair: int = plan["repair_tick"]
	print(
		"fire %d: station %d faulted until %d (%d ticks)" % [fire, station, repair, repair - fire]
	)
	assert_array([_a, _b]).contains([station])
	assert_int(repair - fire).is_between(
		IncidentTuning.FAULT_MIN_TICKS, IncidentTuning.FAULT_MAX_TICKS
	)
	assert_int(_w.staff.faults.repair_tick(station)).is_equal(repair)
	assert_bool(_w.staff.is_open(station)).is_false()
	var other := _b if station == _a else _a
	assert_bool(_w.staff.is_open(other)).is_true()
	assert_int(_started.size()).is_equal(1)
	# The repair is no quiet-night stop.
	assert_int(_director.next_event_tick(fire)).is_equal(-1)
	_director.on_tick(repair - 1)
	assert_int(_ended.size()).is_equal(0)
	_director.on_tick(repair)
	assert_int(_ended.size()).is_equal(1)
	assert_str(_director.incidents()[0]["state"]).is_equal(IncidentCatalogue.DONE)


func test_the_station_and_repair_come_from_the_incidents_own_stream() -> void:
	var first := _scheduled(_director)
	_director.on_tick(first["fire_tick"])
	var plan_one: Dictionary = _director.active_incidents()[0]["plan"]
	_w.staff.faults.assign([])
	# Draws from the clock's own stream change nothing of the fault.
	for i in 17:
		_w.clock.rng.randi()
	var again := _new_director()
	var second := _scheduled(again)
	assert_int(second["fire_tick"]).is_equal(first["fire_tick"])
	again.on_tick(second["fire_tick"])
	var plan_two: Dictionary = again.active_incidents()[0]["plan"]
	print("plans %s and %s" % [plan_one, plan_two])
	assert_dict(plan_two).is_equal(plan_one)


func test_no_fault_when_only_one_scanner_is_open() -> void:
	var incident := _scheduled(_director)
	_w.staff.closures.set_closed(_b, true)
	print("stations that may fault: %s" % [IncidentFault.stations(_w.sim)])
	assert_array(IncidentFault.stations(_w.sim)).is_empty()
	assert_int(_director.next_event_tick(_w.sim.tick)).is_equal(-1)
	_director.on_tick(incident["fire_tick"])
	var done: Dictionary = _director.incidents()[0]
	assert_str(done["state"]).is_equal(IncidentCatalogue.DONE)
	assert_str(done["outcome"]).is_equal(IncidentSnapshot.NO_PLACE)
	assert_int(_started.size()).is_equal(0)
	assert_bool(_w.staff.faults.is_faulted(_a)).is_false()
	assert_bool(_w.staff.is_open(_a)).is_true()


func test_both_scanners_open_may_fault_and_the_fire_is_a_quiet_night_stop() -> void:
	var incident := _scheduled(_director)
	print("stations that may fault: %s" % [IncidentFault.stations(_w.sim)])
	assert_array(IncidentFault.stations(_w.sim)).is_equal([_a, _b])
	assert_int(_director.next_event_tick(_w.sim.tick)).is_equal(incident["fire_tick"])


## A walled-in cell on the landside: no way out of it.
func _pocket() -> Vector2i:
	var cell := Vector2i(12, 15)
	for side in [
		BuildGrid.Side.NORTH, BuildGrid.Side.SOUTH, BuildGrid.Side.EAST, BuildGrid.Side.WEST
	]:
		assert_bool(_w.grid.apply(BuildEdit.place_wall(cell, side)).ok).is_true()
	return cell


## A passenger committed to `station`, walking to it from `at`.
func _walker(station: int, at: Vector2i) -> Passenger:
	var p := _w.passenger(_w.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.stage = Passenger.Stage.TO_SECURITY
	p.station = station
	p.at = at
	p.clear_path()
	return p


func test_no_fault_where_a_passenger_it_sends_away_cannot_reach_another_scanner() -> void:
	var pocket := _pocket()
	var walker := _walker(_a, pocket + Vector2i(0, -1))
	# The control: from outside the pocket it can reach the other scanner.
	var outside := IncidentFault.stations(_w.sim)
	walker.at = pocket
	var inside := IncidentFault.stations(_w.sim)
	print("may fault: walker outside %s, walled in %s" % [outside, inside])
	assert_array(outside).is_equal([_a, _b])
	assert_array(inside).is_equal([_b])
	# With a walled-in walker at each, neither may fault, so none happens.
	_walker(_b, pocket)
	assert_array(IncidentFault.stations(_w.sim)).is_empty()
	var incident := _scheduled(_director)
	_director.on_tick(incident["fire_tick"])
	assert_str(_director.incidents()[0]["outcome"]).is_equal(IncidentSnapshot.NO_PLACE)
	assert_int(_started.size()).is_equal(0)
	assert_bool(_w.staff.is_open(_a) and _w.staff.is_open(_b)).is_true()


func test_the_card_names_the_cause_and_the_fix_time() -> void:
	var incident := _scheduled(_director)
	_director.on_tick(incident["fire_tick"])
	var active: Dictionary = _director.active_incidents()[0]
	var title := IncidentCatalogue.card_title(active)
	var detail := IncidentCatalogue.card_detail(active, false, 0)
	var fixed := GameCalendar.clock_text(active["plan"]["repair_tick"], 0)
	print("%s: %s" % [title, detail])
	assert_str(title).is_equal("Scanner fault")
	assert_str(detail).contains("fixed by %s" % fixed)
	assert_str(title + detail).not_contains("Closed by you")


func test_the_catalogue_weighs_the_fault_by_the_stations_that_may_fault() -> void:
	assert_int(IncidentCatalogue.VERSION).is_equal(3)
	assert_int(IncidentCatalogue.weight(IncidentCatalogue.FAULT, {"faults": 0})).is_zero()
	assert_int(IncidentCatalogue.weight(IncidentCatalogue.FAULT, {"faults": 2})).is_equal(
		IncidentTuning.FAULT_WEIGHT
	)
	assert_bool(IncidentCatalogue.is_major(IncidentCatalogue.FAULT)).is_false()
	assert_array(IncidentCatalogue.states_for(IncidentCatalogue.FAULT)).is_equal(
		[IncidentCatalogue.SCHEDULED, IncidentCatalogue.ACTIVE, IncidentCatalogue.DONE]
	)
