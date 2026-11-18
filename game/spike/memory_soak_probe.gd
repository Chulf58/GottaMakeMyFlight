extends SceneTree
## Headless soak probe for runaway memory, a stuck passenger or a frame that
## never ends (board "The game now froze", playtest 2026-11-03; the demo soak,
## decision demo-slice-is-3-5-game-days). It boots main.tscn with the real HUD
## and a world seed (random, or --seed=<n>; always printed), builds the starter
## terminal with the HUD button, hires one member per station, and accepts every
## open offer the flight sim takes each game day. Then it runs DAYS game days
## (default 5) at top speed: set_speed(3), then SimClock.advance(1/20) once per
## frame with that fixed delta, the same accumulator real play uses, so the
## views and the HUD run their _process every frame and a run is deterministic.
##
## A passenger is stuck by the PlaytestHook's rule (playtest_hook.gd
## _poll_stuck and _check_passengers, STUCK_LIMIT_S): Passenger.stuck is not NONE
## continuously for STUCK_LIMIT_S sim seconds (200 ticks). The probe mirrors it
## per tick instead of attaching the hook, whose checks run on real time and
## write user:// logs. A passenger alive at the end with no movement for
## HUNG_TICKS while stuck is NONE is counted as hung (the hook misses it).
## Headless counts no GPU memory, so peak_mem_mb under-counts a windowed run.
##
## Every game hour it prints the static memory, the object, node and orphan
## counts, the passenger count, the frame time and the largest script
## containers (Array, Dictionary, Packed*) found on every node in the tree and
## on the RefCounted objects those nodes hold. At the end it prints each
## container that grew the most since the first open hour.
##
## Run (user args after `--`: days, seed, control):
##   timeout 3000 Godot_v4.7.2-stable_win64_console.exe --headless \
##     --audio-driver Dummy --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/memory_soak_probe.gd -- --days=5
## --control forces one passenger stuck and passes only when the detector fires;
## otherwise it prints PROBE_INVALID detector dead and exits 1.
##
## Per seed it prints one PROBE_SEED_DONE line and exits 0 only when ticks >=
## days * TICKS_PER_DAY, max_passengers >= 1, flights_made >= 1, stuck_events == 0
## and hung == 0. A guard thread prints PROBE_INVALID and calls OS.crash on a
## hang (anti-pattern a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const MAIN := "res://main/main.tscn"
const StarterFlight := preload("res://spike/starter_flight.gd")
const IntroClose := preload("res://spike/intro_close.gd")
const HOUR := GameCalendar.TICKS_PER_MINUTE * 60
const HANG_LIMIT_MS := 60000
const TOP := 12
## The hook's STUCK_LIMIT_S (10 s) in ticks.
const STUCK_TICKS := int(10.0 * SimClock.TICK_RATE)
## A live passenger with stuck NONE and no movement for this long is hung.
const HUNG_TICKS := 600
const SPEED := 3
## Keys of _breakdown() always printed, grower or not.
const WATCH: Array[String] = [
	"pool:PassengerViews free nodes",
	"pool:PassengerViews nodes in use",
	"pool:PassengerViews direct children",
	"cont:PassengerSim._passengers",
	"cont:PassengerSim._by_id",
	"cont:FlightSim._plans.planner._bookings",
	"cont:FlightSim._trial_plans.planner._bookings",
	"cont:OfferDesk.board._offers",
	"cont:AlertStack._board._history",
]
## Frames the clock may stay still before the probe calls it stalled.
const STALL_FRAMES := 200

var _days := 5
var _seed := 0
var _control := false
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
## One _breakdown() per game day end.
var _day_snaps: Array[Dictionary] = []
var _hours := 0
var _max_passengers := 0
var _frame_ms_sum := 0.0
var _frames := 0
var _frame_start := 0
var _offer_day := -1
var _start_tick := 0
var _next_day_end := 0
var _day_ends := 0
var _peak_static := 0
var _flights_made := 0
var _stuck_events := 0
var _first_stuck := ""
## Passenger id -> {"reason": Passenger.Stuck, "since": tick, "flagged": bool}.
var _stuck: Dictionary = {}
## Passenger id -> {"sig": Array, "since": tick}, the last movement seen.
var _moved: Dictionary = {}
var _forced_id := -1
var _last_tick := -1
var _still_frames := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			_days = int(arg.trim_prefix("--days="))
		elif arg == "--control":
			_control = true
	_beat("boot")
	_guard.start(_watch)
	var world_seed := IntroClose.seed_or_random()
	_seed = world_seed
	print(
		(
			"PROBE world_seed=%d days=%d speed=%d delta=%.4f control=%s"
			% [world_seed, _days, SPEED, SimClock.STEP, _control]
		)
	)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_desk = _main.get_node("OfferDesk")
	root.add_child(_main)
	current_scene = _main
	# SimClock's own _process would add the real frame time on top of the probe's
	# fixed delta; the probe is the only caller of advance().
	_clock.set_process(false)
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
	var intro_problem := IntroClose.close(_main)
	if intro_problem != "":
		_fail(intro_problem)
		return
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var hired := StarterFlight.hire_per_station(_sim, _staff)
	var open_tick := StarterFlight.advance_until_open(_clock, _flights, _staff)
	print("PROBE started hired=%d open_tick=%d tick=%d" % [hired, open_tick, _clock.tick])
	if hired < 2 or open_tick < 0:
		_fail("the airport did not open")
		return
	_start_tick = _clock.tick
	_end_tick = _start_tick + _days * GameCalendar.TICKS_PER_DAY
	_next_sample = _clock.tick
	_next_day_end = _start_tick + GameCalendar.TICKS_PER_DAY
	_flights.state_changed.connect(_on_flight_state)
	_clock.ticked.connect(_on_tick)
	_clock.set_speed(SPEED)
	_clock.set_paused(false)
	_frame_start = Time.get_ticks_usec()
	_phase = 1


func _run() -> void:
	var now := Time.get_ticks_usec()
	_frame_ms_sum += (now - _frame_start) / 1000.0
	_frames += 1
	_frame_start = now
	_accept_offers()
	_clock.advance(SimClock.STEP)
	if _clock.tick == _last_tick:
		_still_frames += 1
		if _still_frames >= STALL_FRAMES:
			_fail(
				(
					"the clock stalled at tick %d for %d frames (paused=%s player_paused=%s)"
					% [_clock.tick, _still_frames, _clock.paused, _clock.player_paused]
				)
			)
			return
	else:
		_still_frames = 0
		_last_tick = _clock.tick
	_peak_static = maxi(_peak_static, OS.get_static_memory_usage())
	_max_passengers = maxi(_max_passengers, _sim.active_count())
	while _clock.tick >= _next_day_end:
		_day_end()
		_next_day_end += GameCalendar.TICKS_PER_DAY
	if _clock.tick >= _next_sample:
		_sample()
		_next_sample += HOUR
	if _clock.tick >= _end_tick:
		_report()


func _on_flight_state(_flight_id: String, new_state: int) -> void:
	if new_state == FlightSim.State.DEPARTED:
		_flights_made += 1


## Runs after PassengerSim on every tick (it connects later), so the stuck
## status it reads is this tick's. The rule is the hook's: a reason change
## restarts the count, NONE clears it, and STUCK_TICKS of one unbroken reason
## is a stuck_too_long event (counted once per episode).
func _on_tick(tick: int) -> void:
	var alive := {}
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.is_done():
			continue
		alive[id] = true
		if _control:
			_force_stuck(p)
		_track_stuck(p, tick)
		if tick % SimClock.TICK_RATE == 0:
			_track_motion(p, tick)
	for id in _stuck.keys():
		if not alive.has(id):
			_stuck.erase(id)
	if tick % SimClock.TICK_RATE == 0:
		for id in _moved.keys():
			if not alive.has(id):
				_moved.erase(id)


func _track_stuck(p: Passenger, tick: int) -> void:
	var before: int = _stuck[p.id]["reason"] if _stuck.has(p.id) else Passenger.Stuck.NONE
	if p.stuck != before:
		if p.stuck == Passenger.Stuck.NONE:
			_stuck.erase(p.id)
		else:
			_stuck[p.id] = {"reason": p.stuck, "since": tick, "flagged": false}
	if not _stuck.has(p.id) or _stuck[p.id]["flagged"]:
		return
	if tick - int(_stuck[p.id]["since"]) >= STUCK_TICKS:
		_stuck[p.id]["flagged"] = true
		_stuck_events += 1
		var line := (
			"seed=%d tick=%d id=%d stage=%s reason=%s cell=%s"
			% [
				_seed,
				tick,
				p.id,
				Passenger.Stage.keys()[p.stage],
				Passenger.Stuck.keys()[p.stuck],
				p.at,
			]
		)
		print("PROBE stuck_too_long %s" % line)
		if _first_stuck == "":
			_first_stuck = line


func _track_motion(p: Passenger, tick: int) -> void:
	var sig := [p.stage, p.at, p.seg_mm, p.odometer_mm]
	if not _moved.has(p.id) or _moved[p.id]["sig"] != sig:
		_moved[p.id] = {"sig": sig, "since": tick}


## Control: one passenger held at NO_ROUTE every tick, so the detector must fire.
func _force_stuck(p: Passenger) -> void:
	if _forced_id < 0 or _sim.get_passenger(_forced_id) == null:
		_forced_id = p.id
	if p.id == _forced_id:
		p.stuck = Passenger.Stuck.NO_ROUTE


func _hung_passengers() -> Array[String]:
	var found: Array[String] = []
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.is_done() or p.stuck != Passenger.Stuck.NONE or not _moved.has(id):
			continue
		var idle: int = _clock.tick - int(_moved[id]["since"])
		if idle >= HUNG_TICKS:
			found.append(
				(
					"id=%d stage=%s cell=%s idle_ticks=%d"
					% [id, Passenger.Stage.keys()[p.stage], p.at, idle]
				)
			)
	return found


func _day_end() -> void:
	_day_ends += 1
	var day_format := "PROBE day_end=%d tick=%d mem_mb=%.1f objects=%d nodes=%d orphans=%d "
	day_format += "resources=%d passengers=%d flights_made=%d"
	print(
		(
			day_format
			% [
				_day_ends,
				_clock.tick,
				OS.get_static_memory_usage() / 1048576.0,
				Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
				_sim.active_count(),
				_flights_made,
			]
		)
	)
	_day_snaps.append(_breakdown())


## One snapshot of what holds the tree's nodes and the sim's history, keyed by
## kind: "cls:<script or engine class>" is a node count by class, "sub:<path>"
## is the descendant count under each direct child of the world root (and of
## the children of the HUD/view containers one level down), "cont:<Node.prop>"
## is a script container's size.
func _breakdown() -> Dictionary:
	var snap := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script()
		var cls := String(script.get_global_name()) if script != null else ""
		if cls == "":
			cls = node.get_class()
		snap["cls:" + cls] = int(snap.get("cls:" + cls, 0)) + 1
		for child in node.get_children(true):
			stack.append(child)
	for child in _main.get_children(true):
		snap["sub:" + String(child.name)] = _descendants(child)
		for grand in child.get_children(true):
			if grand.get_child_count(true) > 0:
				snap["sub:%s/%s" % [child.name, grand.name]] = _descendants(grand)
	var views: Node = _main.get_node("PassengerViews")
	var pooled := 0
	for free: Array in views.get("_pool"):
		pooled += free.size()
	snap["pool:PassengerViews free nodes"] = pooled
	snap["pool:PassengerViews nodes in use"] = (views.get("_nodes") as Dictionary).size()
	snap["pool:PassengerViews direct children"] = views.get_child_count(true)
	var sizes := _container_sizes()
	for key in sizes:
		snap["cont:" + String(key)] = sizes[key]
	return snap


func _descendants(node: Node) -> int:
	var total := 0
	for child in node.get_children(true):
		total += 1 + _descendants(child)
	return total


## Prints the TOP kinds that grew most from the first day end to the last, with
## the value at day 1, the middle day and the last day (all days after).
func _print_breakdown() -> void:
	if _day_snaps.size() < 2:
		return
	var first: Dictionary = _day_snaps[0]
	var last: Dictionary = _day_snaps[_day_snaps.size() - 1]
	var rows: Array = []
	var keys := {}
	for key in first:
		keys[key] = true
	for key in last:
		keys[key] = true
	for key in keys:
		rows.append([int(last.get(key, 0)) - int(first.get(key, 0)), key])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var days := ""
	for i in _day_snaps.size():
		days += " d%d" % (i + 1)
	print("PROBE breakdown top %d net growers (values per day:%s)" % [TOP, days])
	_print_rows(rows, false)
	print("PROBE breakdown top %d never-shrinking growers (leak candidates if flat load)" % TOP)
	_print_rows(rows, true)
	print("PROBE breakdown watch list (the sim-side history holders and the view pool)")
	for key in WATCH:
		var series := ""
		for snap in _day_snaps:
			series += " %d" % int(snap.get(key, 0))
		print("PROBE   watch %s :%s" % [key, series])


## Prints up to TOP rows; with `steady` only those whose per-day series never
## drops, since a container that shrinks again is churn, not accumulation.
func _print_rows(rows: Array, steady: bool) -> void:
	var shown := 0
	for row in rows:
		var key: String = row[1]
		var series := ""
		var shrank := false
		var before := -1
		for snap in _day_snaps:
			var value := int(snap.get(key, 0))
			shrank = shrank or value < before
			before = value
			series += " %d" % value
		if steady and (shrank or row[0] <= 0):
			continue
		print("PROBE   grow %+d %s :%s" % [row[0], key, series])
		shown += 1
		if shown >= TOP:
			return


func _accept_offers() -> void:
	var day := GameCalendar.day_of(_clock.tick, _clock.epoch)
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
## under "label.prop[*]". A freed object held in a container is skipped.
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
					if is_instance_valid(item) and item is RefCounted:
						_measure(item, key + "[*]", sizes, depth - 1)
		elif depth > 0 and is_instance_valid(value) and value is RefCounted:
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
	_print_breakdown()
	var ticks := _clock.tick - _start_tick
	var hung := _hung_passengers()
	for entry in hung:
		print("PROBE hung %s" % entry)
	var peak := maxi(_peak_static, int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)))
	print("PROBE headless counts no GPU memory; peak_mem_mb is static (CPU heap) memory only")
	var done_format := "PROBE_SEED_DONE seed=%d days=%d ticks=%d stuck_events=%d hung=%d "
	done_format += "peak_mem_mb=%.1f max_passengers=%d flights_made=%d"
	print(
		(
			done_format
			% [
				_seed,
				_days,
				ticks,
				_stuck_events,
				hung.size(),
				peak / 1048576.0,
				_max_passengers,
				_flights_made,
			]
		)
	)
	if _control:
		_report_control()
		return
	if ticks < _days * GameCalendar.TICKS_PER_DAY or _max_passengers < 1 or _flights_made < 1:
		_fail("the soak did not run with passengers and flights")
		return
	if _stuck_events > 0 or hung.size() > 0:
		print("PROBE_FAIL first stuck: %s" % _first_stuck)
		_finish(1)
		return
	print("PROBE_DONE")
	_finish(0)


## The control passes only when the detector saw the forced passenger.
func _report_control() -> void:
	if _stuck_events < 1:
		_fail("detector dead: a forced stuck passenger raised no stuck_too_long")
		return
	print(
		"PROBE_CONTROL_OK the detector fired %d time(s); first: %s" % [_stuck_events, _first_stuck]
	)
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
