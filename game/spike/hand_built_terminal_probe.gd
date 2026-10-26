extends SceneTree
## Headless end-to-end check: boots main.tscn, builds a terminal with the
## BuildMode tools only (floor, wall, glass, door, desk, scanner, seats,
## entrance, exit; the HUD's starter terminal is never pressed), then runs the
## sim and prints how many passengers spawned at the entrance, walked through
## the door wall, reached a desk and reached the gate.
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path game -s res://spike/hand_built_terminal_probe.gd
## A guard thread prints PROBE_INVALID and calls OS.crash() when the main
## thread stops beating or a stage overruns, since a frozen main thread never
## reaches a check in _process.

const FLOOR_MIN := HandBuiltTerminal.FLOOR_MIN
const FLOOR_MAX := HandBuiltTerminal.FLOOR_MAX
const LOBBY_Y := HandBuiltTerminal.LOBBY_Y
const DOOR_X := HandBuiltTerminal.DOOR_X
const ENTRANCE_CELL := HandBuiltTerminal.ENTRANCE_CELL
## Ticks run per frame on top of the clock's own frame time.
const PROBE_STEP_SECONDS := 0.5
const END_TICK := 2000
## The sim runs this far with no terminal first; nobody may spawn meanwhile.
const CONTROL_TICK := 200
const HANG_MS := 30000
const STAGE_LIMIT_MS := {"boot": 60000, "build": 60000, "run": 240000}

var _main: Node
var _mode: BuildMode
var _sim: PassengerSim
var _clock: SimClock
var _frame := 0
var _stage := "boot"
var _built := false
var _applied := 0
var _refused: Array[String] = []
var _spawned := 0
var _spawned_at_entrance := 0
var _spawns_before_entrance := -1
var _pending_before_entrance := -1
var _build_tick := -1
var _first_spawn_tick := -1
## Passenger ids seen at a desk or later, and at the gate or later (missed
## passengers not counted), and whose committed path went through the door.
var _reached_desk: Dictionary = {}
var _reached_gate: Dictionary = {}
var _door_in_path: Dictionary = {}

var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage_ms := 0
var _stop := false


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	var seed := randi()
	print("PROBE seed=", seed)
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(seed)
	root.add_child(_main)
	_mode = _main.get_node("BuildMode") as BuildMode
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_sim.passenger_spawned.connect(_on_spawned)


func _process(_delta: float) -> bool:
	_frame += 1
	_beat(_stage)
	if _frame < 3:
		return false
	if not _built and _clock.tick < CONTROL_TICK:
		_clock.advance(PROBE_STEP_SECONDS)
		return false
	if not _built:
		_spawns_before_entrance = _spawned
		_pending_before_entrance = _sim.pending_spawns()
		_build_tick = _clock.tick
		_beat("build")
		_build_terminal()
		_built = true
		_beat("run")
		return false
	_clock.advance(PROBE_STEP_SECONDS)
	_observe()
	if _clock.tick >= END_TICK:
		return _report()
	return false


func _build_terminal() -> void:
	print(
		(
			"PROBE before build: tick=%d spawned=%d entrances=%d"
			% [_clock.tick, _spawned, _sim.layout.entrances.size()]
		)
	)
	var builder := HandBuiltTerminal.new(_mode)
	builder.on_edit = func() -> void: _beat(_stage)
	builder.build()
	_applied = builder.applied
	_refused = builder.refused
	var grid := _mode.grid
	var kinds := {}
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 2):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 2):
			for side in [BuildGrid.Side.NORTH, BuildGrid.Side.WEST]:
				var kind := grid.wall_kind(Vector2i(x, y), side)
				kinds[kind] = kinds.get(kind, 0) + 1
	print(
		(
			"PROBE built with tools: applied=%d refused=%d wall_kinds=%s"
			% [_applied, _refused.size(), kinds]
		)
	)
	for line in _refused:
		print("PROBE refused ", line)
	print(
		(
			"PROBE layout: entrances=%d open_exits=%d desks=%d scanners=%d seats=%d"
			% [
				_sim.layout.entrances.size(),
				_sim.layout.open_exits(grid).size(),
				_sim.layout.desks.size(),
				_sim.layout.scanners.size(),
				_sim.layout.seats.size(),
			]
		)
	)


func _on_spawned(id: int) -> void:
	_spawned += 1
	if _first_spawn_tick < 0:
		_first_spawn_tick = _clock.tick
	var p := _sim.get_passenger(id)
	if p.at == ENTRANCE_CELL:
		_spawned_at_entrance += 1


func _observe() -> void:
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.stage != Passenger.Stage.MISSED:
			if p.stage >= Passenger.Stage.CHECKIN:
				_reached_desk[id] = true
			if p.stage >= Passenger.Stage.SITTING_DOWN:
				_reached_gate[id] = true
		if not _door_in_path.has(id) and _crosses_door(p.path):
			_door_in_path[id] = true


func _crosses_door(path: Array[Vector2i]) -> bool:
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		if a.x == DOOR_X and b.x == DOOR_X and mini(a.y, b.y) == LOBBY_Y - 1:
			return true
	return false


func _report() -> bool:
	var at_desk := _reached_desk.size()
	var at_gate := _reached_gate.size()
	print(
		(
			"PROBE control: no terminal until tick %d: spawned=%d pending=%d"
			% [_build_tick, _spawns_before_entrance, _pending_before_entrance]
		)
	)
	print("PROBE first spawn tick=%d" % _first_spawn_tick)
	print(
		(
			"PROBE spawned=%d spawned_at_entrance=%d door_in_path=%d"
			% [_spawned, _spawned_at_entrance, _door_in_path.size()]
		)
	)
	print(
		(
			"PROBE reached_desk=%d reached_gate=%d made=%d missed=%d tick=%d"
			% [at_desk, at_gate, _sim.made_count(), _sim.missed_count(), _clock.tick]
		)
	)
	var ok := (
		_refused.is_empty()
		and _spawns_before_entrance == 0
		and _pending_before_entrance > 0
		and _spawned > 0
		and _spawned_at_entrance == _spawned
		and _door_in_path.size() > 0
		and at_desk > 0
		and at_gate > 0
	)
	print("PROBE result: ", "pass" if ok else "FAIL")
	_finish()
	quit(0 if ok else 1)
	return true


func _beat(stage: String) -> void:
	_lock.lock()
	var now := Time.get_ticks_msec()
	if stage != _stage or _stage_ms == 0:
		_stage_ms = now
	_stage = stage
	_beat_ms = now
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var now := Time.get_ticks_msec()
		var silent := now - _beat_ms
		var in_stage := now - _stage_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS or in_stage > STAGE_LIMIT_MS.get(stage, HANG_MS):
			print(
				"PROBE_INVALID hang: stage=%s silent_ms=%d stage_ms=%d" % [stage, silent, in_stage]
			)
			OS.crash("hand_built_terminal_probe: main thread stalled in %s" % stage)
