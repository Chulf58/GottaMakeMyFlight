extends SceneTree
## Headless probe of the PlaytestHook autoload on the real main scene.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://tests/debug/playtest_hook_probe.gd -- --playtest
##
## --playtest switches the autoload on (it is off in a debug build without it).
##
## Boots main.tscn with a new random world seed (printed) as the current scene,
## waits for the autoload to attach, builds the starter terminal with the HUD
## button, drags a Floor rectangle over the cell behind the entrance (one cell
## refused), takes both check-in desks away for 30 sim seconds (passengers get
## stuck and the stuck_too_long anomaly is raised, then cleared once the desks
## are back), and runs the flight to DEPARTED at up to 40 ticks a frame. Then it
## prints the snapshot, the log path and the log's line counts by type, read
## back from the file. Every type but error must have grown from zero, or the
## probe prints PROBE_INVALID and exits 1. A guard thread ends a hang with
## OS.crash() (anti-pattern a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const MAIN := "res://main/main.tscn"
const TICKS_PER_FRAME := 40
const DESKS_GONE_TICK := 300
const DESKS_BACK_TICK := 900
const AFTER_DEPARTED_TICKS := 40
const HANG_LIMIT_MS := 30000
const TOTAL_LIMIT_MS := 300000
## Types that must appear in the log file. error is reported, not required.
const REQUIRED := [
	"session",
	"build_edit",
	"build_refused",
	"passenger_stage",
	"passenger_stuck",
	"passenger_made",
	"flight_state",
	"anomaly",
]

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _hook: Node
var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _sim: PassengerSim
var _mode: BuildMode
var _desks: Array[Dictionary] = []
var _phase := 0
var _departed_at := -1
var _waited := 0


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	_hook = root.get_node_or_null("PlaytestHook")
	if _hook == null:
		_invalid("no PlaytestHook autoload under root")
		return
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	_mode = _main.get_node("BuildMode")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)


func _process(_delta: float) -> bool:
	_beat(_stage)
	if _done:
		return true
	match _phase:
		0:
			return _wait_attach()
		1:
			_build()
		2:
			_run_flight()
		3:
			_report()
			return true
	return false


func _wait_attach() -> bool:
	_waited += 1
	if _hook.is_attached():
		print("PROBE hook attached after %d frames, log=%s" % [_waited, _hook.log_path()])
		_phase = 1
	elif _waited > 30:
		_invalid("hook did not attach in 30 frames (enabled=%s)" % _hook.enabled)
		return true
	return false


func _build() -> void:
	_beat("build")
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var grid := _mode.grid
	_mode.set_tool(BuildMode.Tool.FLOOR)
	var behind := ReferenceTerminal.ENTRANCE_CELL + Vector2i(0, 1)
	_mode.begin_area(grid.cell_to_world(behind + Vector2i(-1, 0)))
	_mode.move_area(grid.cell_to_world(behind + Vector2i(1, 0)))
	var outcome := _mode.finish_area()
	print("PROBE floor rectangle placed=%d skipped=%d" % [outcome.placed, outcome.skipped])
	_mode.set_tool(BuildMode.Tool.NONE)
	_phase = 2


func _run_flight() -> void:
	_beat("flight tick %d" % _clock.tick)
	# Views were drawn at the end of the last frame and the sim has not moved
	# since, so the checks compare like with like.
	_hook.run_checks()
	_clock.set_paused(false)
	var target := _clock.tick + TICKS_PER_FRAME
	while _clock.tick < target:
		_clock.advance(SimClock.STEP)
		if _clock.tick == DESKS_GONE_TICK:
			_take_desks()
		elif _clock.tick == DESKS_BACK_TICK:
			_return_desks()
	_clock.set_paused(true)
	var state := _flights.state_of(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
	if state == FlightSim.State.DEPARTED and _departed_at < 0:
		_departed_at = _clock.tick
	if _departed_at >= 0 and _clock.tick >= _departed_at + AFTER_DEPARTED_TICKS:
		_hook.run_checks()
		_phase = 3


func _take_desks() -> void:
	var grid := _mode.grid
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if record["def"] == &"checkin_desk":
			_desks.append(record)
			grid.apply(BuildEdit.remove_object(object_id))
	(_mode.get_node("BuildView") as BuildView).refresh(grid)
	print("PROBE tick %d took %d check-in desks away" % [_clock.tick, _desks.size()])


func _return_desks() -> void:
	var grid := _mode.grid
	for record in _desks:
		grid.apply(BuildEdit.place_object(record["def"], record["anchor"], record["facing"]))
	(_mode.get_node("BuildView") as BuildView).refresh(grid)
	print("PROBE tick %d put %d check-in desks back" % [_clock.tick, _desks.size()])


func _report() -> void:
	_beat("report")
	var snap: Dictionary = _hook.snapshot(5)
	print("PROBE snapshot=%s" % JSON.stringify(snap))
	var path: String = _hook.log_path()
	var counts := {}
	var lines := 0
	var raised := 0
	var cleared := 0
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var event: Dictionary = JSON.parse_string(line)
		lines += 1
		counts[event["type"]] = counts.get(event["type"], 0) + 1
		if event["type"] == "anomaly":
			if event["data"]["state"] == "raised":
				raised += 1
			else:
				cleared += 1
	print("PROBE log=%s lines=%d" % [path, lines])
	print("PROBE input_log=%s" % _hook.input_log_path())
	var types := counts.keys()
	types.sort()
	for type in types:
		print("PROBE count %s=%d" % [type, counts[type]])
	print(
		(
			"PROBE anomalies raised=%d cleared=%d open_now=%d"
			% [raised, cleared, snap["anomalies"].size()]
		)
	)
	print(
		(
			"PROBE passengers made=%d missed=%d flight=%s tick=%d"
			% [
				snap["passengers"]["made"],
				snap["passengers"]["missed"],
				snap["flight_state"],
				snap["tick"]
			]
		)
	)
	var missing: Array[String] = []
	for type in REQUIRED:
		if counts.get(type, 0) <= 0:
			missing.append(type)
	if missing.is_empty() and raised > 0 and cleared > 0:
		print("PROBE_DONE every required type logged")
		_finish(0)
	else:
		_invalid("missing types %s, anomalies raised %d cleared %d" % [missing, raised, cleared])


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
			OS.crash("playtest hook probe hung")
