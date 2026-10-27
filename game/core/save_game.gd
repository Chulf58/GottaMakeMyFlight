class_name SaveGame
extends Node
## The whole-world save (decision flights-and-economy-design-tick-derived-
## calendar-timetable-o, point 8, under standing sim-architecture-fixed-tick-
## data-records-snapshot-saves-grid-astar: "Saves are a JSON snapshot at a tick
## boundary with save_version"). One JSON dictionary with one save_version
## holds every part of the world that is state, one key per entry of parts().
## Views, UI and caches are not saved; they are rebuilt from the parts.
##
## Saving happens only between ticks. The pre-save step, save_problem(), runs
## before any part is read: it refuses inside a tick (SimClock.is_in_tick())
## and between a grid edit and the next tick (CafeSim.deadlines_stale), because
## only that tick's reconcile may settle the cafe; settling it at save time
## would run it a tick early. Each part's to_snapshot() only reads, so a
## game saved and played on plays exactly like one never saved. The staff are
## saved as they stand, a leaving member whose service just ended included;
## the next tick's staff step lets it go, loaded or not.
## The bags wait for the same tick (BaggageSim.routes_stale): their route
## field is rebuilt from the grid on the tick after an edit, never at save
## time. request_save() keeps a refused save waiting, with its message kept
## on screen while it waits (a paused game can wait a long time), and
## retries it after each frame's clock advance (process_priority puts this
## node after SimClock).
##
## Loading checks everything before it changes anything. Each part is loaded
## into a staged copy built from the save alone (a grid, then a bare
## PassengerSim on that grid for the passengers and the staff, a fresh
## instance for the rest), then the parts are checked against each other: one
## tick for all, and every id one part saves that names something in another
## (SaveLinks). Only when every check passes are the live parts installed,
## in parts() order. A refused load leaves the world as it was.
##
## Files go to user://saves/ as JSON, written to a .tmp file and renamed over
## the old save. F5 quick-saves and F8 quick-loads (F9 is left unbound; the
## playtest hook tests press it as a key bound to nothing). Every failure is
## pushed as an error and shown on screen.

## A save or load finished; `ok` false when it was refused or failed.
signal saved(path: String, ok: bool)
signal loaded(ok: bool)

## 2: the bags (part "baggage"); version 1 saves are refused.
const SAVE_VERSION := 2
const SAVE_DIR := "user://saves"
const QUICK_SAVE_PATH := "user://saves/quicksave.json"
const QUICK_SAVE_KEY := KEY_F5
const QUICK_LOAD_KEY := KEY_F8
## How long a message stays on screen.
const MESSAGE_SECONDS := 4.0

@export var clock: SimClock
@export var build_mode: BuildMode
@export var flights: FlightSim
@export var passengers: PassengerSim
@export var staff: StaffSim
@export var finances: Finances
@export var settlement: Settlement
@export var rescue_grant: RescueGrant
@export var offer_desk: OfferDesk
@export var rating: AirportRating
@export var baggage: BaggageSim
## Where F5 and F8 save and load. Tests point it at their own file.
@export var quick_save_path := QUICK_SAVE_PATH

## The file a refused request_save() is waiting to write, or "".
var pending_path := ""

var _message := ""
var _message_left := 0.0
## The on-screen message, made when the node enters the tree.
var _label: Label


func _ready() -> void:
	process_priority = 100
	var layer := CanvasLayer.new()
	layer.layer = 3
	layer.name = "SaveMessage"
	_label = Label.new()
	_label.name = "Message"
	_label.position = Vector2(16.0, 56.0)
	_label.visible = false
	layer.add_child(_label)
	add_child(layer)


## The save's parts in install order. The grid comes first (the passengers
## are checked against it), the passengers before the staff, then the rest. A
## new part is one more entry here.
func parts() -> Array[SavePart]:
	var list: Array[SavePart] = [
		SavePart.new("grid", build_mode.grid.to_snapshot, _stage_grid, build_mode.load_snapshot),
		SavePart.new("clock", clock.to_snapshot, SavePart.scratch(SimClock), clock.from_snapshot),
		SavePart.new(
			"flights",
			flights.to_snapshot,
			SavePart.checked(
				"flights", func(data: Dictionary) -> Dictionary: return FlightSnapshot.load(data)
			),
			flights.from_snapshot
		),
		SavePart.new(
			"passengers", passengers.to_snapshot, _stage_passengers, passengers.from_snapshot
		),
		SavePart.new("staff", staff.to_snapshot, _stage_staff, staff.from_snapshot),
		SavePart.new(
			"baggage",
			baggage.to_snapshot,
			SavePart.checked(
				"baggage", func(data: Dictionary) -> Dictionary: return BaggageSnapshot.load(data)
			),
			baggage.from_snapshot
		),
		# Finances.restore(), never start_new_game(): a load is not a new game.
		SavePart.new(
			"wallet",
			finances.wallet.to_snapshot,
			SavePart.scratch(Finances, &"restore"),
			finances.restore
		),
		SavePart.new(
			"settlement",
			settlement.to_snapshot,
			SavePart.scratch(Settlement),
			settlement.from_snapshot
		),
		SavePart.new(
			"rescue_grant",
			rescue_grant.to_snapshot,
			SavePart.scratch(RescueGrant),
			rescue_grant.from_snapshot
		),
		# The board holds no RNG: the next day's draw continues from the clock's.
		SavePart.new(
			"offers",
			offer_desk.board.to_snapshot,
			SavePart.scratch(OfferBoard, &"from_snapshot", "offers"),
			offer_desk.board.from_snapshot
		),
		SavePart.new(
			"rating",
			rating.to_snapshot,
			SavePart.checked(
				"rating", func(data: Dictionary) -> Dictionary: return RatingSnapshot.load(data)
			),
			_install_rating
		),
	]
	return list


## Why no save may be taken now, or "" when one may. Checked before any part
## is read.
func save_problem() -> String:
	if clock.is_in_tick():
		return "the game is in the middle of a tick"
	if passengers.cafes.deadlines_stale or baggage.routes_stale:
		return "the last build change settles on the next tick"
	return ""


## The whole world as one JSON-safe dictionary, or {} (with an error shown)
## when save_problem() refuses.
func snapshot() -> Dictionary:
	var problem := save_problem()
	if problem != "":
		_fail("Save", problem)
		return {}
	var data := {"save_version": SAVE_VERSION}
	for part in parts():
		data[part.key] = part.save.call()
	return data


## Loads a snapshot() dictionary, including one that went through JSON. Every
## part is checked before any is installed; on a refusal the world is left as
## it was, the reason is shown and false returned.
func load_world(data: Variant) -> bool:
	var problem := "the game is in the middle of a tick" if clock.is_in_tick() else ""
	if problem == "":
		problem = _shape_problem(data)
	if problem == "":
		var staged := {}
		problem = _stage_all(data, staged)
		for value in staged.values():
			if value is Node:
				value.free()
	if problem != "":
		_fail("Load", problem)
		loaded.emit(false)
		return false
	pending_path = ""
	for part in parts():
		if not part.install.call(data[part.key]):
			# Unreachable while each install repeats its own stage check; said
			# loudly, because the world is then partly loaded.
			_fail("Load", "the %s part was refused after it was checked" % part.key)
			loaded.emit(false)
			return false
	_say("Loaded", false)
	loaded.emit(true)
	return true


## Saves the world to `path`: written to `path`.tmp, then renamed over `path`.
## False (with the reason shown) when the save is refused or the file cannot
## be written; an old save at `path` is then left as it was.
func save_to_file(path: String) -> bool:
	var data := snapshot()
	if data.is_empty():
		saved.emit(path, false)
		return false
	var problem := _write_replacing(path, JSON.stringify(data, "", true, true))
	if problem != "":
		_fail("Save", problem)
		saved.emit(path, false)
		return false
	_say("Saved to %s" % path, false)
	saved.emit(path, true)
	return true


## Loads the save at `path`. False (with the reason shown) when the file is
## missing, unreadable, not JSON or refused by load_world().
func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		_fail("Load", "there is no save at %s" % path)
		loaded.emit(false)
		return false
	var text := FileAccess.get_file_as_string(path)
	var open_error := FileAccess.get_open_error()
	if open_error != OK:
		_fail("Load", "cannot read %s (%s)" % [path, error_string(open_error)])
		loaded.emit(false)
		return false
	var json := JSON.new()
	if json.parse(text) != OK:
		_fail(
			"Load",
			(
				"%s is not a save (line %d: %s)"
				% [path, json.get_error_line(), json.get_error_message()]
			)
		)
		loaded.emit(false)
		return false
	return load_world(json.data)


## Saves to `path` now, or, when save_problem() refuses for now, waits and
## saves after the first frame's clock advance that allows it. True when it
## saved now.
func request_save(path := quick_save_path) -> bool:
	var problem := save_problem()
	if problem == "":
		pending_path = ""
		return save_to_file(path)
	pending_path = path
	_say("Saving after the next tick: %s" % problem, false)
	return false


## Writes the waiting save if save_problem() now allows it. True when it did.
func retry_pending() -> bool:
	if pending_path == "" or save_problem() != "":
		return false
	var path := pending_path
	pending_path = ""
	return save_to_file(path)


func quick_save() -> bool:
	return request_save(quick_save_path)


## Drops a waiting save: the loaded world replaces the one it was for.
func quick_load() -> bool:
	pending_path = ""
	return load_from_file(quick_save_path)


## The last message shown, "" when none.
func message_text() -> String:
	return _message


func _process(delta: float) -> void:
	retry_pending()
	if pending_path != "":
		_message_left = MESSAGE_SECONDS
	elif _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0 and _label != null:
			_label.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.ctrl_pressed or key.alt_pressed or key.shift_pressed or key.meta_pressed:
		return
	if key.keycode == QUICK_SAVE_KEY:
		get_viewport().set_input_as_handled()
		quick_save()
	elif key.keycode == QUICK_LOAD_KEY:
		get_viewport().set_input_as_handled()
		quick_load()


func _shape_problem(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "the save is not a dictionary"
	var keys := ["save_version"]
	for part in parts():
		keys.append(part.key)
	for key in (data as Dictionary).keys():
		if not keys.has(key):
			return "unknown key '%s'" % key
	for key in keys:
		if not (data as Dictionary).has(key):
			return "missing key '%s'" % key
	if not WholeNumber.is_whole(data["save_version"]) or int(data["save_version"]) != SAVE_VERSION:
		return "save_version must be %d" % SAVE_VERSION
	for key in keys.slice(1):
		if typeof(data[key]) != TYPE_DICTIONARY:
			return "part '%s' is not a dictionary" % key
	return ""


func _stage_all(data: Dictionary, staged: Dictionary) -> String:
	for part in parts():
		var problem: String = part.stage.call(data[part.key], staged)
		if problem != "":
			return "%s: %s" % [part.key, problem]
	var across := _ticks_problem(data)
	if across == "":
		across = SaveLinks.problem(data, staged)
	return across


## Every part that keeps the tick was saved on the same one.
func _ticks_problem(data: Dictionary) -> String:
	var tick := str(data["clock"]["tick"]).to_int()
	for key in ["flights", "passengers", "rating", "baggage"]:
		var value: Variant = data[key]["tick"]
		var other := str(value).to_int() if typeof(value) == TYPE_STRING else int(value)
		if other != tick:
			return "%s was saved on tick %d, the clock on tick %d" % [key, other, tick]
	return ""


## The terminal shell's check, then the grid's own, on a staged grid.
func _stage_grid(data: Dictionary, staged: Dictionary) -> String:
	if build_mode.shell != null:
		var problem := build_mode.shell.snapshot_problem(data)
		if problem != "":
			return problem
	var grid := BuildGrid.new()
	if not grid.from_snapshot(data):
		return "it was refused (see the error log)"
	staged["grid"] = grid
	return ""


## Checked against the staged grid. Keeps the loaded passenger state and a
## bare PassengerSim on that grid, with its layout built, for the staff check
## and the links (SaveLinks).
func _stage_passengers(data: Dictionary, staged: Dictionary) -> String:
	var grid: BuildGrid = staged["grid"]
	var loaded := PassengerSnapshot.load(data, grid)
	if loaded.has("error"):
		return str(loaded["error"])
	staged["passengers"] = loaded
	var sim := PassengerSim.new()
	sim.grid = grid
	sim.layout.rebuild(grid)
	staged["sim"] = sim
	return ""


func _stage_staff(data: Dictionary, staged: Dictionary) -> String:
	return str(StaffSnapshot.load(data, staged["sim"]).get("error", ""))


## AirportRating.from_snapshot() then bind (a no-op when already bound to
## these three).
func _install_rating(data: Dictionary) -> bool:
	if not rating.from_snapshot(data):
		return false
	rating.bind(clock, flights, passengers)
	return true


## "" or why the file could not be written. The old file is replaced only
## once the new one is fully written.
func _write_replacing(path: String, text: String) -> String:
	var dir := path.get_base_dir()
	var made := DirAccess.make_dir_recursive_absolute(dir)
	if made != OK:
		return "cannot make the folder %s (%s)" % [dir, error_string(made)]
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (%s)" % [temp, error_string(FileAccess.get_open_error())]
	file.store_string(text)
	var written := file.get_error()
	file.close()
	if written != OK:
		DirAccess.remove_absolute(temp)
		return "cannot write %s (%s)" % [temp, error_string(written)]
	var renamed := DirAccess.rename_absolute(temp, path)
	if renamed != OK:
		return "cannot replace %s (%s)" % [path, error_string(renamed)]
	return ""


func _fail(action: String, problem: String) -> void:
	push_error("SaveGame: %s failed: %s" % [action, problem])
	_say("%s failed: %s" % [action, problem], true)


func _say(text: String, is_error: bool) -> void:
	_message = text
	_message_left = MESSAGE_SECONDS
	if _label == null:
		return
	_label.text = text
	_label.modulate = Color(1.0, 0.45, 0.4) if is_error else Color.WHITE
	_label.visible = true
