class_name TestIncidentDirector
extends GdUnitTestSuite
## The IncidentDirector on a bare reference world (one check-in desk area and
## scanners, a contract departing 08:00, the airport open from tick 0): at
## most one roll per day boundary and none before the day after opening, none
## while off, no draw from SimClock.rng, a spill that fires at its saved tick
## at a valid cell and ends when its mess is gone, and next_event_tick. Each
## case drives on_tick by hand with the ticks it needs; the world is built once.

## The contract's departure minute: 08:00, so day 1's busy window is
## 06:00 to 08:00.
const DEPARTS := 480

var _world: PassengerTestWorld
var _director: IncidentDirector
var _started: Array[Dictionary] = []
var _ended: Array[Dictionary] = []


func before() -> void:
	_world = PassengerTestWorld.reference_world(7311042)
	_world.flights.open_airport()
	assert_bool(_world.flights.accept_contract(TestFlightContracts.terms("AM", DEPARTS))).is_true()


func after() -> void:
	_world.free_all()


func before_test() -> void:
	_started.clear()
	_ended.clear()
	_director = _new_director()


func after_test() -> void:
	for id in _world.sim.messes.mess_ids():
		_world.sim.messes.remove(id)


func _new_director() -> IncidentDirector:
	var director := auto_free(IncidentDirector.new()) as IncidentDirector
	director.bind(_world.clock, _world.flights, _world.sim)
	director.started.connect(func(incident: Dictionary) -> void: _started.append(incident))
	director.ended.connect(func(incident: Dictionary) -> void: _ended.append(incident))
	return director


func _forced_spill(director: IncidentDirector) -> void:
	director.set_enabled(true)
	director.forced_kind = IncidentCatalogue.SPILL


func test_a_new_director_is_off_and_never_rolls() -> void:
	assert_bool(_director.is_enabled()).is_false()
	for day in range(1, 6):
		_director.on_tick(GameCalendar.day_start(day))
	assert_int(_director.last_rolled_day()).is_equal(-1)
	assert_array(_director.incidents()).is_empty()
	assert_int(_director.next_event_tick(GameCalendar.day_start(5))).is_equal(-1)
	# The control: turned on, the same boundaries roll.
	_director.set_enabled(true)
	for day in range(6, 9):
		_director.on_tick(GameCalendar.day_start(day))
	print("rolled through day %d" % _director.last_rolled_day())
	assert_int(_director.last_rolled_day()).is_equal(8)


func test_no_roll_while_closed_or_on_the_opening_day() -> void:
	var flights := auto_free(FlightSim.new()) as FlightSim
	var director := auto_free(IncidentDirector.new()) as IncidentDirector
	director.bind(_world.clock, flights, _world.sim)
	_forced_spill(director)
	director.on_tick(GameCalendar.day_start(1))
	assert_int(director.last_rolled_day()).is_equal(-1)
	# Opened on day 1: its own boundary is behind it, day 2's rolls.
	flights.tick = GameCalendar.day_start(1) + 100
	assert_bool(flights.open_airport()).is_true()
	director.on_tick(GameCalendar.day_start(1) + 101)
	assert_int(director.last_rolled_day()).is_equal(-1)
	director.on_tick(GameCalendar.day_start(2))
	assert_int(director.last_rolled_day()).is_equal(2)


func test_at_most_one_roll_per_day_boundary() -> void:
	_forced_spill(_director)
	var boundary := GameCalendar.day_start(1)
	_director.on_tick(boundary)
	_director.on_tick(boundary)
	_director.on_tick(boundary + 1)
	assert_int(_director.incidents().size()).is_equal(1)
	# A load puts the director back on the clock's day (day 0 here); the day
	# already rolled does not roll again when the ticks come back to it.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_director.to_snapshot()))
	assert_bool(_director.from_snapshot(saved)).is_true()
	_director.on_tick(boundary + 2)
	print("incidents=%s" % [_director.incidents()])
	assert_int(_director.incidents().size()).is_equal(1)
	assert_int(_director.last_rolled_day()).is_equal(1)


func test_a_roll_draws_nothing_from_the_clock_rng() -> void:
	_forced_spill(_director)
	var state := _world.clock.rng.state
	_director.on_tick(GameCalendar.day_start(1))
	var scheduled := _director.incidents()
	assert_int(scheduled.size()).is_equal(1)
	assert_int(_world.clock.rng.state).is_equal(state)
	_director.on_tick(scheduled[0]["fire_tick"])
	assert_int(_director.active_incidents().size()).is_equal(1)
	assert_int(_world.clock.rng.state).is_equal(state)


func test_the_same_seed_and_day_roll_the_same_incident() -> void:
	var other := _new_director()
	_forced_spill(_director)
	_forced_spill(other)
	for day in range(1, 4):
		_director.on_tick(GameCalendar.day_start(day))
		other.on_tick(GameCalendar.day_start(day))
	print("rolled: %s" % [_director.incidents()])
	assert_int(_director.incidents().size()).is_equal(3)
	assert_array(other.incidents()).is_equal(_director.incidents())


func test_the_busy_window_runs_from_two_hours_before_the_first_departure_to_the_last() -> void:
	var departs := GameCalendar.tick_at(1, DEPARTS)
	var window := _director.busy_window(1, GameCalendar.day_start(1))
	print("window %s departs %d" % [window, departs])
	assert_int(window.x).is_equal(departs - IncidentDirector.BUSY_LEAD_TICKS)
	assert_int(window.y).is_equal(departs)


## A fire is never sooner than FIRE_FLOOR_TICKS after the roll (more than the
## quiet-night lead), so the quiet-night stop always lies ahead of the clock.
func test_the_busy_window_starts_no_sooner_than_the_fire_floor_after_now() -> void:
	assert_int(IncidentDirector.FIRE_FLOOR_TICKS).is_greater(QuietNight.LEAD_TICKS)
	var departs := GameCalendar.tick_at(1, DEPARTS)
	var now := departs - IncidentDirector.BUSY_LEAD_TICKS - 100
	var early := _director.busy_window(1, now)
	print("early window %s now %d" % [early, now])
	assert_int(early.x).is_equal(now + IncidentDirector.FIRE_FLOOR_TICKS)
	assert_int(early.y).is_equal(departs)
	# Too late for the floor: no window, so the day stays quiet.
	var late := _director.busy_window(1, departs - 10)
	assert_bool(late.x > late.y).is_true()


func test_a_spill_fires_at_its_saved_tick_at_a_valid_cell() -> void:
	_forced_spill(_director)
	_director.on_tick(GameCalendar.day_start(1))
	var incident: Dictionary = _director.incidents()[0]
	var fire: int = incident["fire_tick"]
	var window := _director.busy_window(1, GameCalendar.day_start(1))
	assert_int(fire).is_between(window.x, window.y)
	var messes := _world.sim.messes
	var before_count := messes.mess_count()
	_director.on_tick(fire - 1)
	assert_str(_director.incidents()[0]["state"]).is_equal(IncidentCatalogue.SCHEDULED)
	assert_int(messes.mess_count()).is_equal(before_count)
	_director.on_tick(fire)
	var active: Dictionary = _director.incidents()[0]
	var cells: Array = _director.spill_places().map(
		func(p: Dictionary) -> Vector2i: return p["cell"]
	)
	print("fired %s; places %s; messes %d" % [active, cells, messes.mess_count()])
	assert_str(active["state"]).is_equal(IncidentCatalogue.ACTIVE)
	assert_int(messes.mess_count()).is_equal(before_count + 1)
	var mess := messes.get_mess(active["mess_id"])
	assert_int(mess["kind"]).is_equal(MessSim.Kind.SPILL)
	assert_object(mess["cell"]).is_equal(active["cell"])
	assert_bool(cells.has(active["cell"])).is_true()
	assert_array([IncidentDirector.CHECKIN_PLACE, IncidentDirector.SECURITY_PLACE]).contains(
		[active["place"]]
	)
	assert_int(_started.size()).is_equal(1)
	# The mess is cleaned: the incident is over on the next tick.
	assert_bool(messes.clean(active["mess_id"])).is_true()
	_director.on_tick(fire + 1)
	assert_str(_director.incidents()[0]["state"]).is_equal(IncidentCatalogue.DONE)
	assert_int(_ended.size()).is_equal(1)
	assert_int(_ended[0]["id"]).is_equal(active["id"])


## Only a scheduled fire is an event: the day boundary is not one, so a quiet
## night is not slowed before midnight (decision quiet-nights-fast-forward-
## automatically-when-nothing-is-due).
func test_next_event_tick_is_the_next_fire_and_never_the_boundary() -> void:
	var boundary := GameCalendar.day_start(1)
	assert_int(_director.next_event_tick(boundary - 50)).is_equal(-1)
	_director.set_enabled(true)
	assert_int(_director.next_event_tick(boundary - 50)).is_equal(-1)
	_director.forced_kind = IncidentCatalogue.SPILL
	_director.on_tick(boundary)
	var fire: int = _director.incidents()[0]["fire_tick"]
	print("fire=%d next=%d" % [fire, _director.next_event_tick(boundary)])
	assert_int(_director.next_event_tick(boundary)).is_equal(fire)
	# Turned off, the scheduled spill is dropped and nothing is due.
	_director.set_enabled(false)
	assert_str(_director.incidents()[0]["state"]).is_equal(IncidentCatalogue.DONE)
	assert_int(_director.next_event_tick(boundary)).is_equal(-1)
	_director.on_tick(fire)
	assert_int(_started.size()).is_equal(0)


func test_the_card_words_name_the_cause_and_ask_for_a_cleaner_when_none_is_hired() -> void:
	var incident := {"id": 1, "kind": IncidentCatalogue.SPILL, "place": "Check-in"}
	assert_str(IncidentCatalogue.card_title(incident)).is_equal("Spill near Check-in")
	assert_str(IncidentCatalogue.card_detail(incident, true)).is_equal(
		"A passenger dropped a coffee. A cleaner will mop it up."
	)
	assert_str(IncidentCatalogue.card_detail(incident, false)).is_equal(
		"A passenger dropped a coffee. Hire a cleaner to clean it."
	)
