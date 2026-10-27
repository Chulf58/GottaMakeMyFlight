extends SceneTree
## Headless probe of hiring through the staff panel on the real main scene.
##
## Run:
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://tests/staff/staff_main_probe.gd
##
## Rewritten for the closed start (rulings the-airport-opens-when-staffed-no-
## flights-are-scheduled-unti and staff-a-new-game-starts-with-an-empty-staff-
## pool-and-a-hint). A new game has no staff and a closed airport: no flight is
## issued, so no passenger arrives at an unstaffed desk, and the old premise of
## passengers waiting there cannot happen. Boots main.tscn with a new random
## world seed (printed), builds the starter terminal with the HUD button and
## runs CLOSED_TICKS with the staff pool empty: nobody arrives, nobody checks
## in and the hint names what keeps the airport closed. It opens the bar's
## Staff card and presses Hire in the StaffPanel for one check-in agent and one
## security officer (the hiring lines go at once), then runs until the first
## flight has departed: the staff walk to their stations, the airport opens, the
## hint clears, and passengers check in, are screened and make the flight. Each
## phase prints the counts it compared; any check that fails prints
## PROBE_INVALID and exits 1. A guard thread ends a hang with OS.crash()
## (anti-pattern a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const MAIN := "res://main/main.tscn"
const CLOSED_TICKS := 400
const TICKS_PER_FRAME := 200
const AFTER_DEPARTED_TICKS := 40
const LIMIT_TICKS := 20000
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
var _panel: StaffPanel
var _phase := 0
var _spawned := 0
var _reached: Dictionary = {}
var _departed_at := -1
var _first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)


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
	_panel = _main.get_node("StaffPanel")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_sim.passenger_spawned.connect(func(_id: int) -> void: _spawned += 1)
	_sim.stage_changed.connect(
		func(_id: int, stage: Passenger.Stage) -> void:
			_reached[stage] = int(_reached.get(stage, 0)) + 1
	)


func _process(_delta: float) -> bool:
	_beat(_stage)
	if _done:
		return true
	match _phase:
		0:
			_build()
		1:
			_run_closed()
		2:
			return _run_flight()
	return false


func _build() -> void:
	_beat("build")
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var desks := _sim.layout.desks.size()
	var scanners := _sim.layout.scanners.size()
	var hired := _staff.member_ids().size()
	print("PROBE built desks=%d scanners=%d staff_at_start=%d" % [desks, scanners, hired])
	if desks == 0 or scanners == 0 or hired != 0:
		_invalid("the starter terminal needs desks and scanners and a new game no staff")
		return
	_phase = 1


func _run_closed() -> void:
	_beat("closed")
	_advance(CLOSED_TICKS)
	var gate := _main.get_node("AirportGate") as AirportGate
	var occurrences := _flights.flight_ids().size()
	print(
		(
			"PROBE closed tick=%d open=%s occurrences=%d spawned=%d checked_in=%d hint='%s'"
			% [
				_clock.tick,
				gate.is_open(),
				occurrences,
				_spawned,
				_count(Passenger.Stage.CHECKIN),
				_panel.hint_text().replace("\n", " | "),
			]
		)
	)
	if gate.is_open() or occurrences != 0 or _spawned != 0:
		_invalid("the airport opened or issued flights with nobody hired")
		return
	if not _panel.hint_text().begins_with("Airport closed:"):
		_invalid("the panel's hint does not say why the airport is closed")
		return
	var menu := _main.get_node("BuildMenu") as BuildMenu
	menu.press_staff()
	if not _panel.card().is_visible_in_tree():
		_invalid("the Staff button did not open the staff card")
		return
	var hint_before := _panel.hint_text().replace("\n", " | ")
	_panel.hire_button(StaffMember.Role.CHECKIN).pressed.emit()
	_panel.hire_button(StaffMember.Role.SECURITY).pressed.emit()
	print(
		(
			"PROBE pressed Hire in the panel at tick %d: hint before '%s', after '%s', %s / %s"
			% [
				_clock.tick,
				hint_before,
				_panel.hint_text().replace("\n", " | "),
				_panel.counts_text(StaffMember.Role.CHECKIN),
				_panel.counts_text(StaffMember.Role.SECURITY),
			]
		)
	)
	if _panel.hint_text().contains("Hire a") or _staff.member_ids().size() != 2:
		_invalid("the panel's Hire buttons did not hire or did not clear the hiring lines")
		return
	_phase = 2


func _run_flight() -> bool:
	_beat("flight tick %d" % _clock.tick)
	_advance(TICKS_PER_FRAME)
	var state := _flights.state_of(_first)
	if state == FlightSim.State.DEPARTED and _departed_at < 0:
		_departed_at = _clock.tick
	if _departed_at < 0 and _clock.tick < LIMIT_TICKS:
		return false
	if _departed_at < 0:
		_invalid("the flight never departed")
		return true
	if _clock.tick < _departed_at + AFTER_DEPARTED_TICKS:
		return false
	var on_duty := (
		_staff.on_duty_count(StaffMember.Role.CHECKIN)
		+ _staff.on_duty_count(StaffMember.Role.SECURITY)
	)
	print(
		(
			(
				"PROBE staffed departed_tick=%d on_duty=%d hint='%s' spawned=%d"
				+ " checked_in=%d screened=%d made=%d missed=%d"
			)
			% [
				_departed_at,
				on_duty,
				_panel.hint_text(),
				_spawned,
				_count(Passenger.Stage.CHECKIN),
				_count(Passenger.Stage.SECURITY),
				_sim.made_count(),
				_sim.missed_count(),
			]
		)
	)
	if on_duty != 2 or _panel.hint_text() != "":
		_invalid("the staff are not both on duty or the hint did not clear once open")
		return true
	if _count(Passenger.Stage.CHECKIN) == 0 or _sim.made_count() == 0:
		_invalid("staffed stations did not get passengers onto the flight")
		return true
	print("PROBE ok")
	_finish(0)
	return true


func _advance(ticks: int) -> void:
	_clock.set_paused(false)
	var target := _clock.tick + ticks
	while _clock.tick < target:
		_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


func _count(stage: Passenger.Stage) -> int:
	return int(_reached.get(stage, 0))


func _invalid(why: String) -> void:
	print("PROBE_INVALID %s" % why)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
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
			OS.crash("staff main probe hung")
