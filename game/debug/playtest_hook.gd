extends Node
## The PlaytestHook autoload: a dev-only window into the running game for an
## AI playtester. It is on in debug builds, or in any build run with the
## --playtest user argument (after `--`) or the debug/playtest/enabled project
## setting, and inert otherwise: no file, no signal, no per-frame work.
##
## When the current scene has a SimClock, FlightSim, PassengerSim and
## BuildMode as children (main.tscn), the hook attaches to it and
##   - writes every event to user://playtest/<session>.jsonl (PlaytestLog) and
##     keeps the last ones in memory: build_edit, build_refused, passenger_stage,
##     passenger_stuck, passenger_made, passenger_missed, flight_state, anomaly,
##     error, plus a session line with the world seed at the start and end;
##   - records mouse and key input with its tick and frame to
##     user://playtest/<session>.input.jsonl;
##   - every CHECK_INTERVAL_S of real time checks for anomalies (PlaytestAnomalies):
##     stuck_too_long, no_route, off_grid, view_drift, view_missing, frame_time;
##   - answers snapshot() and events_since() for the Godot MCP's run_script.
## --playtest-seed=<n> seeds the scene's SimClock before anything draws from
## it, so a logged seed can be played again.

const SETTING := "debug/playtest/enabled"
const ARG := "--playtest"
const SEED_ARG := "--playtest-seed="
const LOG_DIR := "user://playtest"
const EVENT_TYPES: Array[String] = [
	"session",
	"build_edit",
	"build_refused",
	"passenger_stage",
	"passenger_stuck",
	"passenger_made",
	"passenger_missed",
	"flight_state",
	"anomaly",
	"error",
]
const CHECK_INTERVAL_S := 0.5
## A passenger stuck this long in sim seconds is an anomaly.
const STUCK_LIMIT_S := 10.0
## A passenger node this far from its sim position is an anomaly. A node sits
## between its last two tick positions, at most one step (0.18 m) apart.
const VIEW_DRIFT_M := 1.5
## An object node this far from its footprint centre is an anomaly.
const OBJECT_DRIFT_M := 0.5
## A rolling average frame time over this is an anomaly (under 20 fps).
const FRAME_MS_LIMIT := 50.0
const FRAME_WINDOW := 30

static var _sessions_opened := 0

var enabled := false
## Attach to the current scene on its own. Tests call configure() and attach().
var auto_attach := true
var log_dir := LOG_DIR
## The file name stem; a dated one is made at attach when it is empty.
var session := ""
var stuck_limit_s := STUCK_LIMIT_S
var frame_ms_limit := FRAME_MS_LIMIT
var world_seed := 0

var clock: SimClock
var flights: FlightSim
var passengers: PassengerSim
var views: PassengerViews
var build_mode: BuildMode
var grid: BuildGrid

var _configured := false
var _scene: Node
## The instance id of the last current scene tried, so each is tried once.
var _tried_scene_id := 0
var _log := PlaytestLog.new()
var _anomalies := PlaytestAnomalies.new()
var _errors := PlaytestErrorLogger.new()
var _logger_added := false
## "file:line:message" -> the error with a "count" of how often it came.
var _error_counts: Dictionary = {}
## Passenger id -> {"reason": Passenger.Stuck, "since": tick}.
var _stuck: Dictionary = {}
var _input_file: FileAccess
var _input_path := ""
var _input_count := 0
var _since_check := 0.0
var _frame_ms := PackedFloat32Array()


static func wants_enabled(debug_build: bool, user_args: PackedStringArray, setting: bool) -> bool:
	return debug_build or setting or user_args.has(ARG)


## The seed given with --playtest-seed=<n>, or null.
static func seed_arg(user_args: PackedStringArray) -> Variant:
	for arg in user_args:
		if arg.begins_with(SEED_ARG) and arg.substr(SEED_ARG.length()).is_valid_int():
			return arg.substr(SEED_ARG.length()).to_int()
	return null


## Sets the switch by hand instead of from the build, arguments and setting.
## Call before the node enters the tree.
func configure(on: bool, dir := LOG_DIR, attach_automatically := false) -> void:
	_configured = true
	enabled = on
	log_dir = dir
	auto_attach = attach_automatically


func _ready() -> void:
	# After every default-priority node, so the views are drawn for this frame
	# before they are compared with the sim.
	process_priority = 1000
	if not _configured:
		enabled = wants_enabled(
			OS.is_debug_build(),
			OS.get_cmdline_user_args(),
			ProjectSettings.get_setting(SETTING, false)
		)
	set_process(enabled)
	set_process_input(enabled)
	if enabled and auto_attach:
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	detach()


func _process(delta: float) -> void:
	if auto_attach and _scene == null:
		var current := get_tree().current_scene
		if current != null and current.get_instance_id() != _tried_scene_id:
			_tried_scene_id = current.get_instance_id()
			attach(current)
	if _scene == null:
		return
	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > FRAME_WINDOW:
		_frame_ms.remove_at(0)
	_drain_errors()
	_since_check += delta
	if _since_check >= CHECK_INTERVAL_S:
		_since_check = 0.0
		run_checks()


func _input(event: InputEvent) -> void:
	if _input_file == null:
		return
	if not (
		event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventKey
	):
		return
	var line := {
		"i": _input_count,
		"tick": clock.tick,
		"frame": Engine.get_process_frames(),
		"ms": Time.get_ticks_msec(),
		"type": event.get_class(),
		"text": event.as_text(),
	}
	var with_mods := event as InputEventWithModifiers
	line["mods"] = [with_mods.shift_pressed, with_mods.ctrl_pressed, with_mods.alt_pressed]
	if event is InputEventMouse:
		var mouse := event as InputEventMouse
		line["position"] = [mouse.position.x, mouse.position.y]
		line["button_mask"] = mouse.button_mask
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		line["button"] = button.button_index
		line["pressed"] = button.pressed
		line["double_click"] = button.double_click
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		line["relative"] = [motion.relative.x, motion.relative.y]
	elif event is InputEventKey:
		var key := event as InputEventKey
		line["keycode"] = key.keycode
		line["physical_keycode"] = key.physical_keycode
		line["unicode"] = key.unicode
		line["pressed"] = key.pressed
		line["echo"] = key.echo
	_input_file.store_line(JSON.stringify(line))
	_input_count += 1


## Attaches to a scene with a SimClock, FlightSim, PassengerSim and BuildMode
## among its children, opens the log files and starts logging. Returns false
## when the hook is off, the scene lacks a part, or a file cannot be opened.
func attach(scene: Node) -> bool:
	if not enabled:
		return false
	detach()
	if not _find_parts(scene):
		return false
	if session == "":
		session = _new_session_name()
	if not _log.open("%s/%s.jsonl" % [log_dir, session]):
		return false
	_input_path = ProjectSettings.globalize_path("%s/%s.input.jsonl" % [log_dir, session])
	_input_file = FileAccess.open(_input_path, FileAccess.WRITE)
	if _input_file == null:
		push_error("PlaytestHook: cannot open %s" % _input_path)
		_log.close()
		return false
	_scene = scene
	world_seed = clock.rng.seed
	grid.edit_applied.connect(_on_edit_applied)
	grid.edit_refused.connect(_on_edit_refused)
	clock.ticked.connect(_on_ticked)
	flights.state_changed.connect(_on_flight_state)
	passengers.passenger_spawned.connect(_on_spawned)
	passengers.stage_changed.connect(_on_stage)
	passengers.outcome.connect(_on_outcome)
	scene.tree_exiting.connect(detach)
	OS.add_logger(_errors)
	_logger_added = true
	var start := {
		"state": "start",
		"seed": str(world_seed),
		"scene": scene.scene_file_path,
		"log_path": _log.path,
		"input_path": _input_path,
		"args": Array(OS.get_cmdline_user_args()),
	}
	_log.add(clock.tick, "session", start)
	_log.flush()
	print("PLAYTEST log=%s input=%s seed=%d" % [_log.path, _input_path, world_seed])
	return true


## Stops logging, closes the files and lets go of the scene.
func detach() -> void:
	if _scene == null:
		return
	_log.add(clock.tick, "session", {"state": "end", "events": _log.total()})
	for pair in [
		[grid.edit_applied, _on_edit_applied],
		[grid.edit_refused, _on_edit_refused],
		[clock.ticked, _on_ticked],
		[flights.state_changed, _on_flight_state],
		[passengers.passenger_spawned, _on_spawned],
		[passengers.stage_changed, _on_stage],
		[passengers.outcome, _on_outcome],
		[_scene.tree_exiting, detach],
	]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if _logger_added:
		OS.remove_logger(_errors)
		_logger_added = false
	_log.close()
	if _input_file != null:
		_input_file.close()
		_input_file = null
	_scene = null


func is_attached() -> bool:
	return _scene != null


func log_path() -> String:
	return _log.path


func input_log_path() -> String:
	return _input_path


## Event count by type so far.
func event_counts() -> Dictionary:
	return _log.counts()


## The events still in memory from index `index` on (each has its "i").
func events_since(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in _log.since(index):
		out.append(event.duplicate(true))
	return out


## The state an AI playtester reads: tick, flights, passenger counts by stage,
## the stuck list, a grid summary, the last `event_count` events, the open
## anomalies and the errors caught. JSON-safe. When the hook is off or has no
## scene, only "enabled" and "attached".
func snapshot(event_count := 20) -> Dictionary:
	if _scene == null:
		return {"enabled": enabled, "attached": false}
	_drain_errors()
	var flight_list := PlaytestState.flights_summary(flights)
	var events: Array[Dictionary] = []
	for event in _log.last(event_count):
		events.append(event.duplicate(true))
	return {
		"enabled": enabled,
		"attached": true,
		"session": session,
		"log_path": _log.path,
		"input_log_path": _input_path,
		"seed": str(world_seed),
		"tick": clock.tick,
		"paused": clock.paused,
		"speed": clock.speed,
		"flight_state": flight_list[0]["state"] if not flight_list.is_empty() else "",
		"flights": flight_list,
		"passengers": PlaytestState.passenger_summary(passengers),
		"stuck": stuck_list(),
		"grid": PlaytestState.grid_summary(grid),
		"events": events,
		"event_total": _log.total(),
		"event_counts": _log.counts(),
		"anomalies": _anomalies.open(),
		"errors": _error_counts.values(),
		"input_events": _input_count,
		"debug_batch_seed": passengers.last_batch_seed,
	}


## snapshot() as a JSON string, for a caller that wants text.
func snapshot_json(event_count := 20) -> String:
	return JSON.stringify(snapshot(event_count))


## The passengers stuck now, by id: reason, stage, cell, since which tick and
## for how many sim seconds.
func stuck_list() -> Array[Dictionary]:
	var ids := _stuck.keys()
	ids.sort()
	var out: Array[Dictionary] = []
	for id in ids:
		var p := passengers.get_passenger(id)
		if p == null:
			continue
		var since: int = _stuck[id]["since"]
		var entry := {
			"id": id,
			"reason": PlaytestState.enum_name(Passenger.Stuck.keys(), p.stuck),
			"stage": PlaytestState.enum_name(Passenger.Stage.keys(), p.stage),
			"cell": PlaytestState.cell(p.at),
			"since_tick": since,
			"seconds": (clock.tick - since) / float(SimClock.TICK_RATE),
		}
		out.append(entry)
	return out


## The open anomalies.
func anomalies() -> Array[Dictionary]:
	return _anomalies.open()


## Runs every anomaly check now and logs what was raised or cleared. _process
## calls it every CHECK_INTERVAL_S.
func run_checks() -> void:
	if _scene == null:
		return
	_drain_errors()
	var found := {}
	_check_passengers(found)
	_check_objects(found)
	_check_frame(found)
	var change := _anomalies.update(found, clock.tick)
	for record in change["raised"]:
		record["state"] = "raised"
		_log.add(clock.tick, "anomaly", record)
	for record in change["cleared"]:
		record["state"] = "cleared"
		_log.add(clock.tick, "anomaly", record)
	_log.flush()
	if _input_file != null:
		_input_file.flush()


func _find_parts(scene: Node) -> bool:
	clock = null
	flights = null
	passengers = null
	views = null
	build_mode = null
	for child in scene.get_children():
		if child is SimClock:
			clock = child
		elif child is FlightSim:
			flights = child
		elif child is PassengerSim:
			passengers = child
		elif child is PassengerViews:
			views = child
		elif child is BuildMode:
			build_mode = child
	grid = build_mode.grid if build_mode != null else null
	return clock != null and flights != null and passengers != null and grid != null


func _new_session_name() -> String:
	var stamp := Time.get_datetime_string_from_system(false, true)
	stamp = stamp.replace("-", "").replace(":", "").replace(" ", "-")
	_sessions_opened += 1
	var name := "%s-%d" % [stamp, OS.get_process_id()]
	if _sessions_opened > 1:
		name += "-%d" % _sessions_opened
	return name


func _on_node_added(node: Node) -> void:
	if not node is SimClock or node.get_parent() == null:
		return
	if node.get_parent().get_parent() != get_tree().root:
		return
	var given: Variant = seed_arg(OS.get_cmdline_user_args())
	if given != null:
		(node as SimClock).seed_rng(given)
		print("PLAYTEST seeded SimClock with %d" % given)


func _on_edit_applied(edit: BuildEdit, result: BuildResult) -> void:
	var data := PlaytestState.edit_data(edit)
	data["object_id"] = result.object_id
	_log.add(clock.tick, "build_edit", data)


func _on_edit_refused(edit: BuildEdit, result: BuildResult) -> void:
	var data := PlaytestState.edit_data(edit)
	data["reason"] = PlaytestState.enum_name(BuildResult.Reason.keys(), result.reason)
	data["reason_text"] = result.reason_text()
	data["blocking_object_id"] = result.blocking_object_id
	_log.add(clock.tick, "build_refused", data)


func _on_ticked(_tick: int) -> void:
	_poll_stuck()


func _on_flight_state(flight_id: String, new_state: int) -> void:
	var state := PlaytestState.enum_name(FlightSim.State.keys(), new_state)
	_log.add(clock.tick, "flight_state", {"flight": flight_id, "state": state})


func _on_spawned(id: int) -> void:
	_log_stage(passengers.get_passenger(id))


func _on_stage(id: int, _stage: Passenger.Stage) -> void:
	_log_stage(passengers.get_passenger(id))


func _on_outcome(id: int, made: bool) -> void:
	var p := passengers.get_passenger(id)
	var data := {"id": id, "flight": p.flight_id, "mood": p.mood, "spawn_tick": p.spawn_tick}
	_log.add(clock.tick, "passenger_made" if made else "passenger_missed", data)


func _log_stage(p: Passenger) -> void:
	var data := {
		"id": p.id,
		"flight": p.flight_id,
		"stage": PlaytestState.enum_name(Passenger.Stage.keys(), p.stage),
		"cell": PlaytestState.cell(p.at),
	}
	_log.add(clock.tick, "passenger_stage", data)


## Logs each change of a passenger's stuck reason. Runs after PassengerSim on
## every tick, because the hook connects to the clock after it.
func _poll_stuck() -> void:
	for id in passengers.passenger_ids():
		var p := passengers.get_passenger(id)
		var now: int = Passenger.Stuck.NONE if p.is_done() else p.stuck
		var before: int = _stuck[id]["reason"] if _stuck.has(id) else Passenger.Stuck.NONE
		if now == before:
			continue
		var data := {
			"id": id,
			"reason": PlaytestState.enum_name(Passenger.Stuck.keys(), now),
			"stage": PlaytestState.enum_name(Passenger.Stage.keys(), p.stage),
			"cell": PlaytestState.cell(p.at),
		}
		if now == Passenger.Stuck.NONE:
			data["cleared"] = true
			data["seconds"] = (clock.tick - int(_stuck[id]["since"])) / float(SimClock.TICK_RATE)
			_stuck.erase(id)
		else:
			_stuck[id] = {"reason": now, "since": clock.tick}
		_log.add(clock.tick, "passenger_stuck", data)


func _check_passengers(found: Dictionary) -> void:
	for id in passengers.passenger_ids():
		var p := passengers.get_passenger(id)
		if p.is_done():
			continue
		var subject := "passenger:%d" % id
		var stage := PlaytestState.enum_name(Passenger.Stage.keys(), p.stage)
		var base := {"id": id, "stage": stage, "cell": PlaytestState.cell(p.at)}
		if _stuck.has(id):
			var seconds: float = (clock.tick - int(_stuck[id]["since"])) / float(SimClock.TICK_RATE)
			if seconds >= stuck_limit_s:
				var data := base.duplicate()
				data["reason"] = PlaytestState.enum_name(Passenger.Stuck.keys(), p.stuck)
				data["limit_s"] = stuck_limit_s
				_found(found, "stuck_too_long", subject, data)
		if p.stuck == Passenger.Stuck.NO_ROUTE:
			_found(found, "no_route", subject, base)
		if p.stage < Passenger.Stage.APRON and not grid.in_bounds(p.at):
			_found(found, "off_grid", subject, base)
		var node: Node3D = views.node_for(id) if views != null else null
		if node != null and node.is_inside_tree():
			var sim_at := passengers.world_position(p)
			var drift := node.global_position.distance_to(sim_at)
			if drift > VIEW_DRIFT_M:
				var data := base.duplicate()
				data["drift_m"] = snappedf(drift, 0.01)
				data["view"] = PlaytestState.point(node.global_position)
				data["sim"] = PlaytestState.point(sim_at)
				_found(found, "view_drift", subject, data)


func _check_objects(found: Dictionary) -> void:
	var view := build_mode.get_node_or_null("BuildView") as BuildView
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		var def := BuildCatalog.get_def(record["def"])
		var subject := "object:%d" % object_id
		var data := {
			"object_id": object_id,
			"def": String(record["def"]),
			"cell": PlaytestState.cell(record["anchor"])
		}
		var cells := def.footprint(record["anchor"], record["facing"])
		for at in cells:
			if not grid.in_bounds(at):
				_found(found, "off_grid", subject, data)
				break
		if view == null:
			continue
		var node := view.object_node(object_id)
		if node == null:
			_found(found, "view_missing", subject, data)
			continue
		var centre := (
			view.global_transform * BuildView.object_transform(grid, cells, record["facing"]).origin
		)
		var drift := node.global_position.distance_to(centre)
		if drift > OBJECT_DRIFT_M:
			var drifted := data.duplicate()
			drifted["drift_m"] = snappedf(drift, 0.01)
			_found(found, "view_drift", subject, drifted)


func _check_frame(found: Dictionary) -> void:
	if _frame_ms.size() < FRAME_WINDOW:
		return
	var total := 0.0
	for ms in _frame_ms:
		total += ms
	var average := total / _frame_ms.size()
	if average > frame_ms_limit:
		var data := {
			"average_ms": snappedf(average, 0.1), "limit_ms": frame_ms_limit, "frames": FRAME_WINDOW
		}
		_found(found, "frame_time", "frame", data)


func _found(found: Dictionary, kind: String, subject: String, data: Dictionary) -> void:
	found[PlaytestAnomalies.key_of(kind, subject)] = {
		"kind": kind, "subject": subject, "detail": data
	}


func _drain_errors() -> void:
	for entry in _errors.drain():
		var key := "%s:%d:%s" % [entry["file"], entry["line"], entry["message"]]
		if _error_counts.has(key):
			_error_counts[key]["count"] += 1
			continue
		var kept: Dictionary = entry.duplicate()
		kept["count"] = 1
		kept["first_tick"] = clock.tick if clock != null else 0
		_error_counts[key] = kept
		_log.add(kept["first_tick"], "error", entry)
		_log.flush()
