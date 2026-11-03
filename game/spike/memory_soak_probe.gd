extends SceneTree
## Headless soak probe for runaway memory or a frame that never ends (board
## "The game now froze", playtest 2026-11-03). It boots main.tscn with the real
## HUD and a new random world seed (printed), builds the starter terminal with
## the HUD button, hires one member per station, and accepts every open offer
## the flight sim takes each game day. Then it runs DAYS game days, stepping
## TICKS_PER_FRAME ticks per real frame (3 ticks is about 3x at 20 frames a
## second), so the views and the HUD run their _process every frame as in play.
##
## Every game hour it prints the static memory, the object, node and orphan
## counts, the passenger count, the frame time and the largest script
## containers (Array, Dictionary, Packed*) found on every node in the tree and
## on the RefCounted objects those nodes hold. At the end it prints each
## container that grew the most since the first open hour.
##
## Run (user args after `--`: days, ticks per frame):
##   timeout 1800 Godot_v4.7.2-stable_win64_console.exe --headless \
##     --audio-driver Dummy --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/memory_soak_probe.gd -- --days=3 --tpf=3
##
## The pass values are positives: the ticks run, the hours sampled and the
## passengers seen. A guard thread prints PROBE_INVALID and calls OS.crash on a
## hang (anti-pattern a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const MAIN := "res://main/main.tscn"
const StarterFlight := preload("res://spike/starter_flight.gd")
const HOUR := GameCalendar.TICKS_PER_MINUTE * 60
const HANG_LIMIT_MS := 60000
const TOP := 12

var _days := 3
var _ticks_per_frame := 3
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
var _desk: OfferDesk
var _phase := 0
var _end_tick := 0
var _next_sample := 0
var _first_sizes: Dictionary = {}
var _last_sizes: Dictionary = {}
var _hours := 0
var _max_passengers := 0
var _frame_ms_sum := 0.0
var _frames := 0
var _frame_start := 0
var _offer_day := -1


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			_days = int(arg.trim_prefix("--days="))
		elif arg.begins_with("--tpf="):
			_ticks_per_frame = int(arg.trim_prefix("--tpf="))
	_beat("boot")
	_guard.start(_watch)
	var world_seed := randi()
	print("PROBE world_seed=%d days=%d tpf=%d" % [world_seed, _days, _ticks_per_frame])
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_desk = _main.get_node("OfferDesk")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)


func _process(_delta: float) -> bool:
	_beat("phase %d tick %d" % [_phase, _clock.tick])
	if _done:
		return true
	match _phase:
		0:
			_start()
		1:
			_run()
	return _done


func _start() -> void:
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	StarterFlight.add_gate_desk(_main.get_node("BuildMode").grid)
	var hired := StarterFlight.hire_per_station(_sim, _staff)
	var open_tick := StarterFlight.advance_until_open(_clock, _flights, _staff)
	print("PROBE started hired=%d open_tick=%d tick=%d" % [hired, open_tick, _clock.tick])
	if hired < 2 or open_tick < 0:
		_fail("the airport did not open")
		return
	_end_tick = _clock.tick + _days * GameCalendar.TICKS_PER_DAY
	_next_sample = _clock.tick
	_frame_start = Time.get_ticks_usec()
	_phase = 1


func _run() -> void:
	var now := Time.get_ticks_usec()
	_frame_ms_sum += (now - _frame_start) / 1000.0
	_frames += 1
	_frame_start = now
	_accept_offers()
	for i in _ticks_per_frame:
		_clock.set_paused(false)
		_clock.advance(SimClock.STEP)
		_clock.set_paused(true)
	_max_passengers = maxi(_max_passengers, _sim.active_count())
	if _clock.tick >= _next_sample:
		_sample()
		_next_sample += HOUR
	if _clock.tick >= _end_tick:
		_report()


func _accept_offers() -> void:
	var day := GameCalendar.day_of(_clock.tick)
	if day == _offer_day:
		return
	_offer_day = day
	var accepted := 0
	for offer in _desk.board.open_offers():
		var id: String = offer["id"]
		if _flights.accept_problem(OfferBoard.terms_of(offer)) == "":
			accepted += int(_desk.board.accept(id, _flights))
	var contracts := _flights.contract_ids().size()
	print("PROBE day=%d offers_accepted=%d contracts=%d" % [day, accepted, contracts])


func _sample() -> void:
	var sizes := _container_sizes()
	if _first_sizes.is_empty():
		_first_sizes = sizes
	var growth: Array = []
	for key in sizes:
		growth.append([int(sizes[key]) - int(_last_sizes.get(key, 0)), key, sizes[key]])
	growth.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var largest: Array = []
	for key in sizes:
		largest.append([sizes[key], key])
	largest.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print(
		(
			"PROBE hour=%d tick=%d mem_mb=%.1f objects=%d nodes=%d orphans=%d passengers=%d frame_ms=%.2f"
			% [
				_hours,
				_clock.tick,
				OS.get_static_memory_usage() / 1048576.0,
				Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
				_sim.active_count(),
				_frame_ms_sum / maxf(1.0, _frames),
			]
		)
	)
	var line := "PROBE   largest:"
	for i in mini(TOP, largest.size()):
		line += " %s=%d" % [largest[i][1], largest[i][0]]
	print(line)
	line = "PROBE   grew:"
	for i in mini(TOP, growth.size()):
		if int(growth[i][0]) > 0:
			line += " %s+%d" % [growth[i][1], growth[i][0]]
	print(line)
	_last_sizes = sizes
	_hours += 1
	_frame_ms_sum = 0.0
	_frames = 0


## Sizes of every script container on every node in the tree, and on the
## RefCounted objects those nodes hold directly, keyed "Node.property".
func _container_sizes() -> Dictionary:
	var sizes := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		_measure(node, String(node.name), sizes, 2)
		for child in node.get_children(true):
			stack.append(child)
	return sizes


## Adds the sizes of `object`'s script containers under `label`. With depth
## left it also measures the RefCounted objects it holds, and sums the
## containers of the RefCounted objects inside its Arrays and Dictionaries
## under "label.prop[*]".
func _measure(object: Object, label: String, sizes: Dictionary, depth: int) -> void:
	if object.get_script() == null:
		return
	for prop in object.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value: Variant = object.get(prop["name"])
		var key := "%s.%s" % [label, prop["name"]]
		var size := _size_of(value)
		if size >= 0:
			sizes[key] = int(sizes.get(key, 0)) + size
			if depth > 0 and (value is Array or value is Dictionary):
				var items: Array = value.values() if value is Dictionary else value
				for item in items:
					if item is RefCounted:
						_measure(item, key + "[*]", sizes, depth - 1)
		elif depth > 0 and value is RefCounted:
			_measure(value, key, sizes, depth - 1)


func _size_of(value: Variant) -> int:
	match typeof(value):
		TYPE_ARRAY, TYPE_DICTIONARY:
			return value.size()
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			return value.size()
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return value.size()
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return value.size()
	return -1


func _report() -> void:
	_sample()
	var growth: Array = []
	for key in _last_sizes:
		growth.append([int(_last_sizes[key]) - int(_first_sizes.get(key, 0)), key])
	growth.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var line := "PROBE total growth since open:"
	for i in mini(TOP, growth.size()):
		line += " %s+%d" % [growth[i][1], growth[i][0]]
	print(line)
	print("PROBE ran ticks=%d hours=%d max_passengers=%d" % [_clock.tick, _hours, _max_passengers])
	if _hours < 2 or _max_passengers < 1:
		_fail("the soak did not run with passengers")
		return
	print("PROBE_DONE")
	_finish(0)


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
		if now - beat > HANG_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang in stage '%s': %d ms since the last beat, mem_mb=%.1f"
					% [stage, now - beat, OS.get_static_memory_usage() / 1048576.0]
				)
			)
			OS.crash("memory soak probe hung")
