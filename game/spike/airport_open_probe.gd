extends SceneTree
## Headless probe of the airport opening on the real main scene (decision
## airport-opening-design-stays-open-once-opened-starter-flight-placed-after-
## opening).
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/airport_open_probe.gd
##
## Boots main.tscn with a new random world seed (printed), builds the starter
## terminal with the HUD button and runs CLOSED_TICKS ticks with nobody hired:
## no flight occurrence may exist. Then it hires one check-in agent and one
## security officer through StaffSim (they walk to their stations) and runs
## until the airport opens, then until the starter's first flight is issued
## and has departed. The pass values are positives: the ticks run while
## closed, the members on duty, the opening tick, the starter's occurrences
## and the passengers settled on its first flight. Each compared value is
## printed. Otherwise it prints PROBE_INVALID and exits 1. A guard thread ends
## a hang (anti-pattern a-frame-counting-watchdog-cannot-catch-a-stuck-main-
## thread).

const MAIN := "res://main/main.tscn"
const CLOSED_TICKS := 1200
const TICKS_PER_FRAME := 80
const OPEN_LIMIT := 4000
const HANG_LIMIT_MS := 30000
const TOTAL_LIMIT_MS := 300000

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _sim: PassengerSim
var _staff: StaffSim
var _phase := 0
var _closed_ticks := 0
var _closed_occurrences := 0
var _hired_at := 0
var _first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
var _issued_at := -1


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_flights.occurrence_added.connect(_on_added)


func _process(_delta: float) -> bool:
	_beat("phase %d tick %d" % [_phase, _clock.tick])
	if _done:
		return true
	match _phase:
		0:
			_closed()
		1:
			_opening()
		2:
			_flying()
	return _done


func _closed() -> void:
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	for i in CLOSED_TICKS:
		_step()
		_closed_ticks += 1
		_closed_occurrences += _flights.flight_ids().size()
	print(
		(
			"PROBE closed ticks_run=%d occurrences_seen=%d contracts=%d opened_tick=%d"
			% [
				_closed_ticks,
				_closed_occurrences,
				_flights.contract_ids().size(),
				_flights.opened_tick
			]
		)
	)
	if _closed_ticks != CLOSED_TICKS or _closed_occurrences != 0 or _flights.opened_tick != -1:
		_fail("flights existed while the airport was closed")
		return
	_staff.hire(StaffMember.Role.CHECKIN)
	_staff.hire(StaffMember.Role.SECURITY)
	_hired_at = _clock.tick
	_phase = 1


func _opening() -> void:
	for i in TICKS_PER_FRAME:
		if _flights.opened_tick >= 0:
			break
		_step()
	if _flights.opened_tick < 0:
		if _clock.tick - _hired_at > OPEN_LIMIT:
			_fail("the airport did not open %d ticks after hiring" % OPEN_LIMIT)
		return
	var checkin := _staff.on_duty_count(StaffMember.Role.CHECKIN)
	var security := _staff.on_duty_count(StaffMember.Role.SECURITY)
	print(
		(
			(
				"PROBE opened hired_at=%d opened_tick=%d checkin_on_duty=%d"
				+ " security_on_duty=%d contracts=%s"
			)
			% [_hired_at, _flights.opened_tick, checkin, security, _flights.contract_ids()]
		)
	)
	if checkin < 1 or security < 1 or _flights.opened_tick <= _hired_at:
		_fail("the airport opened without an agent and an officer on duty")
		return
	if _flights.contract_ids() != [FlightSim.DEFAULT_ID]:
		_fail("the opening did not accept the starter contract")
		return
	_phase = 2


func _flying() -> void:
	for i in TICKS_PER_FRAME:
		_step()
	if _flights.state_of(_first) != FlightSim.State.DEPARTED:
		if _clock.tick - _flights.opened_tick > 3 * FlightTimetable.ISSUE_LEAD_TICKS + 2600:
			_fail("the starter's first flight never departed")
		return
	var first_state := _flights.state_start(_first, FlightSim.State.SCHEDULED)
	var lead := first_state - _flights.opened_tick
	var result: Dictionary = _sim.flight_results.get(_first, {})
	var settled := int(result.get("made", 0)) + int(result.get("missed", 0))
	print(
		(
			(
				"PROBE starter issued_at=%d first_state=%d lead=%d (expected >= %d)"
				+ " made=%d missed=%d settled=%d booked=%d"
			)
			% [
				_issued_at,
				first_state,
				lead,
				FlightTimetable.ISSUE_LEAD_TICKS,
				int(result.get("made", 0)),
				int(result.get("missed", 0)),
				settled,
				FlightSim.STARTER_TERMS["booked_passengers"],
			]
		)
	)
	if _issued_at < _flights.opened_tick or lead < FlightTimetable.ISSUE_LEAD_TICKS:
		_fail("the starter's first flight left less than the lead after opening")
		return
	if settled < 1:
		_fail("no passenger of the starter's first flight was settled")
		return
	print("PROBE_PASS")
	_finish(0)


func _step() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


func _on_added(id: String) -> void:
	if id == _first and _issued_at < 0:
		_issued_at = _clock.tick


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null:
		_main.queue_free()
	quit(code)


func _beat(stage: String) -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_stage = stage
	_mutex.unlock()


func _watch() -> void:
	var started := Time.get_ticks_msec()
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var beat := _beat_ms
		var stage := _stage
		_mutex.unlock()
		if done:
			return
		var now := Time.get_ticks_msec()
		if now - beat > HANG_LIMIT_MS or now - started > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang in stage '%s': %d ms since the last beat, %d ms in all"
					% [stage, now - beat, now - started]
				)
			)
			OS.crash("airport open probe hung")
