extends SceneTree
## Headless probe of the whole-world save (Economy 8/8) on the real main scene.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/save_game_probe.gd
##
## Boots two main scenes from one new random world seed (printed): a control
## that is never saved and a source. Both build the starter terminal, hire an
## agent and an officer, accept the day-0 offers that fit and play in
## lockstep past the opening, a fee payout and the first day rollover. The
## source then quick-saves to a file, and a third main scene, booted from
## another seed, quick-loads that file. All three play FUTURE_TICKS more ticks
## (another payout among them, and one offer accepted in each after the
## load) and their state checksums (SaveTestKit.checksum) must match on every
## tick. The pass values are positives: ticks compared, the payouts seen
## (made passengers with the fee credited) and the day reached. Otherwise it
## prints PROBE_INVALID and exits 1. A guard thread ends a hang (anti-pattern
## a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const SAVE_PATH := "user://saves/save_game_probe.json"
const TICKS_PER_FRAME := 200
const PLAY_LIMIT := 30000
const FUTURE_TICKS := 12000
const ACCEPT_AFTER_LOAD := 100
const PRINT_EVERY := 2000
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 900000

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _control: Node
var _source: Node
var _loaded: Node
var _phase := -1
var _payouts := {}
var _rolled_at := -1
var _future := 0
var _compared := 0
var _started_ms := 0


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_control = SaveTestKit.boot(root, world_seed)
	_source = SaveTestKit.boot(root, world_seed)
	_started_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	_beat("phase %d tick %d" % [_phase, _clock(_source).tick])
	if _done:
		return true
	match _phase:
		-1:
			# The scenes are ready from the first frame on.
			for main in [_control, _source]:
				SaveTestKit.start_airport(main)
				_payouts[main] = 0
			_phase = 0
		0:
			_play()
		1:
			_save_and_load()
		2:
			_play_on()
	return _done


## Lockstep play until the source has opened, been paid and seen day 1.
func _play() -> void:
	for i in TICKS_PER_FRAME:
		_step_all([_control, _source])
		var tick := _clock(_source).tick
		if _flights(_source).opened_tick >= 0 and _flights(_source).opened_tick == tick:
			for main in [_control, _source]:
				_accept_open_offers(main)
		if _rolled_at < 0 and GameCalendar.day_of(tick) >= 1:
			_rolled_at = tick
		if not _same([_control, _source], "before the save"):
			return
		if _payouts[_source] > 0 and _rolled_at >= 0 and tick >= _rolled_at + 20:
			_phase = 1
			return
	if _clock(_source).tick > PLAY_LIMIT:
		_fail("no payout and day rollover by tick %d" % PLAY_LIMIT)


func _save_and_load() -> void:
	var tick := _clock(_source).tick
	var save := SaveTestKit.save_game(_source)
	save.quick_save_path = SAVE_PATH
	var saved_ok := save.quick_save()
	var tmp_left := FileAccess.file_exists(SAVE_PATH + ".tmp")
	var size := FileAccess.get_file_as_bytes(SAVE_PATH).size()
	print(
		(
			(
				"PROBE saved tick=%d day=%d opened_tick=%d payouts_before_save=%d rolled_at=%d ok=%s"
				+ " bytes=%d tmp_left=%s message='%s' ticks_compared=%d elapsed_ms=%d"
			)
			% [
				tick,
				GameCalendar.day_of(tick),
				_flights(_source).opened_tick,
				_payouts[_source],
				_rolled_at,
				saved_ok,
				size,
				tmp_left,
				save.message_text(),
				_compared,
				Time.get_ticks_msec() - _started_ms,
			]
		)
	)
	if not saved_ok or size == 0 or tmp_left:
		_fail("the quick save was not written")
		return
	_loaded = SaveTestKit.boot(root, randi())
	var loader := SaveTestKit.save_game(_loaded)
	loader.quick_save_path = SAVE_PATH
	var loaded_ok := loader.quick_load()
	print(
		(
			"PROBE loaded ok=%s tick=%d balance=%d control_balance=%d message='%s'"
			% [
				loaded_ok,
				_clock(_loaded).tick,
				_wallet(_loaded).balance,
				_wallet(_control).balance,
				loader.message_text(),
			]
		)
	)
	if not loaded_ok:
		_fail("the quick save did not load")
		return
	_payouts[_loaded] = 0
	for main in [_control, _source]:
		_payouts[main] = 0
	if not _same([_control, _source, _loaded], "right after the load"):
		return
	_phase = 2


func _play_on() -> void:
	var all := [_control, _source, _loaded]
	for i in TICKS_PER_FRAME:
		if _future == ACCEPT_AFTER_LOAD:
			for main in all:
				_accept_open_offers(main)
		_step_all(all)
		_future += 1
		if not _same(all, "after the load"):
			return
		if _future % PRINT_EVERY == 0:
			print(
				(
					"PROBE future=%d tick=%d checksum=%s %s %s"
					% [
						_future,
						_clock(_control).tick,
						SaveTestKit.checksum(_control).left(12),
						SaveTestKit.checksum(_source).left(12),
						SaveTestKit.checksum(_loaded).left(12),
					]
				)
			)
		if _future >= FUTURE_TICKS:
			_finish_pass()
			return


func _finish_pass() -> void:
	var tick := _clock(_control).tick
	print(
		(
			(
				"PROBE result ticks_compared=%d future_ticks=%d day=%d payouts_after_load"
				+ " control=%d source=%d loaded=%d balance=%d/%d/%d made=%d/%d/%d"
				+ " contracts=%s elapsed_ms=%d"
			)
			% [
				_compared,
				_future,
				GameCalendar.day_of(tick),
				_payouts[_control],
				_payouts[_source],
				_payouts[_loaded],
				_wallet(_control).balance,
				_wallet(_source).balance,
				_wallet(_loaded).balance,
				_sim(_control).made_count(),
				_sim(_source).made_count(),
				_sim(_loaded).made_count(),
				_flights(_control).contract_ids(),
				Time.get_ticks_msec() - _started_ms,
			]
		)
	)
	DirAccess.remove_absolute(SAVE_PATH)
	if _payouts[_loaded] < 1 or _payouts[_control] != _payouts[_loaded]:
		_fail("no payout after the load, or a different number of them")
		return
	print("PROBE_PASS")
	_finish(0)


## Steps each world one tick and counts a payout when the made total grew and
## the wallet gained at least the fees of the new made passengers.
func _step_all(worlds: Array) -> void:
	for main in worlds:
		var made_before := _sim(main).made_count()
		var balance_before := _wallet(main).balance
		SaveTestKit.step(main)
		var made := _sim(main).made_count() - made_before
		if made > 0 and _wallet(main).balance - balance_before >= made * _least_fee(main):
			_payouts[main] += 1


func _least_fee(main: Node) -> int:
	var least := 0
	for id in _flights(main).contract_ids():
		var fee: int = _flights(main).contract_of(id)["fee_per_passenger"]
		least = fee if least == 0 else mini(least, fee)
	return maxi(least, 1)


func _accept_open_offers(main: Node) -> void:
	var desk: OfferDesk = main.get_node("OfferDesk")
	for offer in desk.board.open_offers():
		if _flights(main).accept_problem(OfferBoard.terms_of(offer)) == "":
			desk.board.accept(offer["id"], _flights(main))


func _same(worlds: Array, when: String) -> bool:
	var first := SaveTestKit.checksum(worlds[0])
	for main in worlds.slice(1):
		var other := SaveTestKit.checksum(main)
		if other != first:
			_fail(
				(
					"checksums differ %s at tick %d: %s vs %s"
					% [when, _clock(worlds[0]).tick, first.left(12), other.left(12)]
				)
			)
			return false
	_compared += 1
	return true


func _clock(main: Node) -> SimClock:
	return main.get_node("SimClock")


func _flights(main: Node) -> FlightSim:
	return main.get_node("FlightSim")


func _sim(main: Node) -> PassengerSim:
	return main.get_node("PassengerSim")


func _wallet(main: Node) -> Wallet:
	return (main.get_node("Finances") as Finances).wallet


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	DirAccess.remove_absolute(SAVE_PATH)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	for main in [_control, _source, _loaded]:
		if main != null:
			main.queue_free()
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
			OS.crash("save game probe hung")
