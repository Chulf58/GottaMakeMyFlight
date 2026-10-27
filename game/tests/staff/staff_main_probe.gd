extends SceneTree
## Headless probe of staffing on the real main scene.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://tests/staff/staff_main_probe.gd
##
## Boots main.tscn with a new random world seed (printed), builds the starter
## terminal with the HUD button and runs UNSTAFFED_TICKS with the staff pool
## as a new game leaves it, empty: passengers arrive and nobody checks in.
## Then it presses Hire in the StaffPanel for one check-in agent and one
## security officer (the hint must show before and clear after) and runs the
## first flight until it has departed: the staff walk to their stations and
## passengers check in, are screened and make the flight. Each phase prints
## the counts it compared; any check that fails prints PROBE_INVALID and exits 1.

const MAIN := "res://main/main.tscn"
const UNSTAFFED_TICKS := 400
const TICKS_PER_FRAME := 200
const AFTER_DEPARTED_TICKS := 40
const LIMIT_TICKS := 20000

var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _sim: PassengerSim
var _staff: StaffSim
var _phase := 0
var _spawned := 0
var _reached: Dictionary = {}
var _departed_at := -1


func _initialize() -> void:
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
	_sim.passenger_spawned.connect(func(_id: int) -> void: _spawned += 1)
	_sim.stage_changed.connect(
		func(_id: int, stage: Passenger.Stage) -> void:
			_reached[stage] = int(_reached.get(stage, 0)) + 1
	)


func _process(_delta: float) -> bool:
	match _phase:
		0:
			_build()
		1:
			_run_unstaffed()
		2:
			return _run_flight()
	return false


func _build() -> void:
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var desks := _sim.layout.desks.size()
	var scanners := _sim.layout.scanners.size()
	var hired := _staff.member_ids().size()
	print("PROBE built desks=%d scanners=%d staff_at_start=%d" % [desks, scanners, hired])
	if desks == 0 or scanners == 0 or hired != 0:
		_invalid("the starter terminal needs desks and scanners and a new game no staff")
		return
	_phase = 1


func _run_unstaffed() -> void:
	_advance(UNSTAFFED_TICKS)
	var stuck := 0
	for id in _sim.passenger_ids():
		stuck += int(_sim.get_passenger(id).stuck == Passenger.Stuck.NO_CHECKIN)
	print(
		(
			"PROBE unstaffed tick=%d spawned=%d stuck_no_checkin=%d checked_in=%d"
			% [_clock.tick, _spawned, stuck, _count(Passenger.Stage.CHECKIN)]
		)
	)
	if _spawned == 0 or stuck == 0:
		_invalid("no passenger arrived to wait at the closed desks")
		return
	if _count(Passenger.Stage.CHECKIN) != 0:
		_invalid("a passenger checked in with no staff")
		return
	var panel := _main.get_node("StaffPanel") as StaffPanel
	var hint_before := panel.hint_text().replace("\n", " | ")
	panel.hire_button(StaffMember.Role.CHECKIN).pressed.emit()
	panel.hire_button(StaffMember.Role.SECURITY).pressed.emit()
	print(
		(
			"PROBE pressed Hire in the panel at tick %d: hint before '%s', after '%s', %s / %s"
			% [
				_clock.tick,
				hint_before,
				panel.hint_text(),
				panel.counts_text(StaffMember.Role.CHECKIN),
				panel.counts_text(StaffMember.Role.SECURITY),
			]
		)
	)
	if hint_before == "" or panel.hint_text() != "" or _staff.member_ids().size() != 2:
		_invalid("the panel's hint or Hire buttons did not work")
		return
	_phase = 2


func _run_flight() -> bool:
	_advance(TICKS_PER_FRAME)
	var state := _flights.state_of(FlightSim.DEFAULT_ID)
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
				"PROBE staffed departed_tick=%d on_duty=%d spawned=%d"
				+ " checked_in=%d screened=%d made=%d missed=%d"
			)
			% [
				_departed_at,
				on_duty,
				_spawned,
				_count(Passenger.Stage.CHECKIN),
				_count(Passenger.Stage.SECURITY),
				_sim.made_count(),
				_sim.missed_count(),
			]
		)
	)
	if on_duty != 2 or _count(Passenger.Stage.CHECKIN) == 0 or _sim.made_count() == 0:
		_invalid("staffed stations did not get passengers onto the flight")
		return true
	print("PROBE ok")
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
	quit(1)
