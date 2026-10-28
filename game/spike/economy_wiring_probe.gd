extends SceneTree
## Headless probe of Economy 5/8 on the real main scene: Settlement and
## RescueGrant are bound, a passenger who makes an accepted contract's flight
## credits the wallet with the captured fee, and a rescue grant's message
## reaches BuildMenu's status line.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/economy_wiring_probe.gd
##
## Boots main.tscn with a new random world seed (printed), builds the starter
## terminal with the HUD button, accepts a contract for 11:40 and runs the sim
## until its occurrence has departed. The hired staff open the airport, so the
## starter contract flies too. The pass value is a positive: the wallet grew by
## exactly the fee times the contract's made passengers plus the starter's fee
## times its made passengers, and at least one passenger made the contract's
## flight. Then it empties the wallet and takes away every
## scanner, steps one tick, and passes when exactly one grant was paid, the
## wallet grew by its amount and the status label shows its message word for
## word. Otherwise it prints PROBE_INVALID and exits 1. A
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
## Passengers who made another contract's flight (the starter's), and their fees.
var _other_made := 0
var _other_fees := 0
var _grants := 0
var _grant_amount := 0
var _grant_text := ""


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
		3:
			_stick()
			return true
	return false


## A new game has no staff: one hire per desk and scanner, as the staff
## panel's Hire buttons do; the staff walk to the stations on their own.
func _hire_staff() -> void:
	var staff := _main.get_node("Staff") as StaffSim
	for i in _sim.layout.desks.size():
		staff.hire(StaffMember.Role.CHECKIN)
	for i in _sim.layout.scanners.size():
		staff.hire(StaffMember.Role.SECURITY)
	print(
		(
			"PROBE hired checkin=%d security=%d"
			% [staff.count(StaffMember.Role.CHECKIN), staff.count(StaffMember.Role.SECURITY)]
		)
	)


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
	rescue.granted.connect(_on_granted)
	_sim.outcome.connect(_on_outcome)
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	_hire_staff()
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


func _on_granted(amount: int, text: String) -> void:
	_grants += 1
	_grant_amount = amount
	_grant_text = text


func _on_outcome(id: int, made: bool) -> void:
	var p := _sim.get_passenger(id)
	if p == null:
		return
	if p.flight_id != OCCURRENCE:
		if made:
			var contract := _flights.contract_of(_flights.flight_contract_id(p.flight_id))
			_other_made += 1
			_other_fees += int(contract.get("fee_per_passenger", 0))
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
	print("PROBE other contracts made=%d fees=%d" % [_other_made, _other_fees])
	print("PROBE balance before=%d after=%d delta=%d" % [_before, after, after - _before])
	if _contract_made <= 0:
		_invalid("no passenger made the contract's flight")
	elif after - _before != _contract_made * FEE + _other_fees:
		_invalid(
			(
				"delta %d is not %d made x fee %d + other fees %d"
				% [after - _before, _contract_made, FEE, _other_fees]
			)
		)
	elif _grants != 0:
		_invalid("a rescue grant was paid in a working terminal")
	else:
		print("PROBE fee pass: the wallet grew by the captured fee per made passenger")
		_phase = 3


## Leaves the terminal with no scanner and no money, then steps one tick.
func _stick() -> void:
	_wallet.spend(_wallet.balance, Wallet.Category.BUILD)
	var grid := _sim.grid
	var removed := 0
	for id in grid.object_ids():
		if grid.get_object(id)["def"] == &"security_scanner":
			if grid.apply(BuildEdit.remove_object(id)).ok:
				removed += 1
	var label := (_main.get_node("BuildMenu") as BuildMenu).status_label()
	var before := label.text
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	_clock.set_paused(true)
	var counts := [removed, _sim.active_count(), _grants, _grant_amount]
	print("PROBE scanners removed=%d active=%d grants=%d amount=%d" % counts)
	print("PROBE balance=%d label before='%s'" % [_wallet.balance, before])
	print("PROBE label after='%s'" % label.text)
	print("PROBE message='%s'" % _grant_text)
	if removed <= 0:
		_invalid("no scanner was removed")
	elif _grants != 1 or _grant_amount <= 0 or _wallet.balance != _grant_amount:
		_invalid("expected one grant credited to an empty wallet")
	elif _grant_text == "" or label.text != _grant_text:
		_invalid("the grant message did not reach the status label")
	else:
		print("PROBE_DONE fees settle and the grant message reaches the HUD label")
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
