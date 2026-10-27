extends SceneTree
## Headless probe of Economy 5/8 on the real main scene: Settlement and
## RescueGrant are bound, and a passenger who makes an accepted contract's
## flight credits the wallet with the captured fee.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/economy_wiring_probe.gd
##
## Boots main.tscn with a new random world seed (printed), builds the starter
## terminal with the HUD button, accepts a contract for 11:40 and runs the sim
## until its occurrence has departed. The pass value is a positive: the wallet
## grew by exactly the fee times the contract's made passengers, and at least
## one passenger made it. Otherwise it prints PROBE_INVALID and exits 1. A
## guard thread ends a hang (anti-pattern a-frame-counting-watchdog-cannot-
## catch-a-stuck-main-thread).

const MAIN := "res://main/main.tscn"
const CONTRACT := "ECO1"
const OCCURRENCE := "ECO1-d0"
const MINUTE := 700
const BOOKED := 6
const FEE := 50
const TICKS_PER_FRAME := 80
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
var _wallet: Wallet
var _phase := 0
var _before := 0
var _contract_made := 0
var _contract_missed := 0
var _grants := 0


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
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)


func _process(_delta: float) -> bool:
	_beat("phase %d tick %d" % [_phase, _clock.tick])
	if _done:
		return true
	match _phase:
		0:
			_setup()
		1:
			_run()
		2:
			_report()
			return true
	return false


func _setup() -> void:
	var settlement := _main.get_node("Settlement")
	var rescue := _main.get_node("RescueGrant")
	var finances: Finances = _main.get_node("Finances")
	_wallet = finances.wallet
	var bound: bool = settlement._sim == _sim and settlement._wallet == _wallet
	bound = bound and rescue._clock == _clock and rescue._sim == _sim and rescue._wallet == _wallet
	print("PROBE settlement bound=%s rescue_grant bound=%s" % [settlement._sim != null, bound])
	if not bound:
		_invalid("Settlement or RescueGrant is not bound to the scene's nodes")
		return
	rescue.granted.connect(func(_amount: int, _text: String) -> void: _grants += 1)
	_sim.outcome.connect(_on_outcome)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var terms := {
		"id": CONTRACT,
		"airline": "Gotta Air",
		"destination": "Oslo",
		"departure_minute": MINUTE,
		"gate": "C",
		"plane_size": "medium",
		"booked_passengers": BOOKED,
		"fee_per_passenger": FEE,
	}
	if not _flights.accept_contract(terms):
		_invalid("the contract was refused")
		return
	_before = _wallet.balance
	print("PROBE balance before=%d" % _before)
	_phase = 1


func _on_outcome(id: int, made: bool) -> void:
	var p := _sim.get_passenger(id)
	if p == null or p.flight_id != OCCURRENCE:
		return
	if made:
		_contract_made += 1
	else:
		_contract_missed += 1


func _run() -> void:
	_clock.set_paused(false)
	var target := _clock.tick + TICKS_PER_FRAME
	while _clock.tick < target:
		_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
	if _flights.is_doors_closed(OCCURRENCE) and _sim.active_count() == 0:
		_phase = 2


func _report() -> void:
	var after := _wallet.balance
	print(
		(
			"PROBE tick=%d contract made=%d missed=%d fee=%d grants=%d"
			% [_clock.tick, _contract_made, _contract_missed, FEE, _grants]
		)
	)
	print("PROBE balance before=%d after=%d delta=%d" % [_before, after, after - _before])
	if _contract_made <= 0:
		_invalid("no passenger made the contract's flight")
	elif after - _before != _contract_made * FEE:
		_invalid("delta %d is not %d made x fee %d" % [after - _before, _contract_made, FEE])
	elif _grants != 0:
		_invalid("a rescue grant was paid in a working terminal")
	else:
		print("PROBE_DONE the wallet grew by the captured fee per made passenger")
		_finish(0)


func _invalid(why: String) -> void:
	print("PROBE_INVALID %s" % why)
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
			OS.crash("economy wiring probe hung")
