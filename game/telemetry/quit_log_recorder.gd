class_name QuitLogRecorder
extends Node
## Runs the quit log for the main scene (decision quit-point-log-d7-opt-in-
## local-event-log-file-only-off-by-de). While the player's switch is off it
## does nothing: no file, no signal connected, no per-frame work. While it is
## on it opens a QuitLog session, listens to the sim's own signals for the
## events they carry (day edges, build edits, missed passengers), watches the
## clock for speed and pause changes, and ends the session with the reason the
## game closed. The event sites that have no signal write through
## QuitLog.note() (offers accepted, flight results, alerts, the menu opening).
##
## No raw input is read: not one mouse or key event reaches this node.
##
## The Esc menu owns the switch: set_enabled() saves it and starts or stops the
## session at once. A test points settings_path and log_dir at files of its own
## before the node enters the tree (anti-pattern a-test-that-builds-passengerhud-
## or-main-tscn-on-the-default); a script run never reads the player's file.

## The game closed through the window's close button or the system.
const REASON_WINDOW_CLOSE := "window_close"
## The player left through the menu.
const REASON_QUIT_MENU := "quit_menu"
## The player switched the log off.
const REASON_SWITCHED_OFF := "switched_off"
## The scene left the tree (back to the title screen or a load) with no other reason.
const REASON_LEFT_GAME := "left_game"

@export var clock: SimClock
@export var finances: Finances
@export var rating: AirportRating
@export var passengers: PassengerSim
@export var build_mode: BuildMode

var settings_path := QuitLog.SETTINGS_PATH
var log_dir := QuitLog.DIR

var _log: QuitLog
var _speed := 0
var _paused := false
var _grid: BuildGrid


func _ready() -> void:
	name = "QuitLogRecorder"
	set_process(false)
	if QuitLog.is_enabled(settings_path):
		start()


func _exit_tree() -> void:
	stop(REASON_LEFT_GAME)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop(REASON_WINDOW_CLOSE)


## Speed and pause have no signal; they are read each frame and a change is one
## record.
func _process(_delta: float) -> void:
	if clock == null:
		return
	if clock.speed != _speed:
		_speed = clock.speed
		QuitLog.note("speed_changed", {"speed": _speed})
	if clock.player_paused != _paused:
		_paused = clock.player_paused
		QuitLog.note("pause_changed", {"paused": _paused})


## The player's saved switch.
func is_enabled() -> bool:
	return QuitLog.is_enabled(settings_path)


func is_recording() -> bool:
	return _log != null


## The absolute path of the open file, or "".
func log_path() -> String:
	return _log.path if _log != null else ""


## Saves the switch and starts or stops the session now.
func set_enabled(on: bool) -> void:
	QuitLog.save_enabled(on, settings_path)
	if on:
		start()
	else:
		stop(REASON_SWITCHED_OFF)


## Opens a session and writes session_start. False when one is already open or
## the file cannot be opened.
func start() -> bool:
	if _log != null:
		return false
	var session := QuitLog.new()
	if not session.open(log_dir, QuitLog.new_session_name()):
		return false
	_log = session
	_connect_parts()
	var start_data := {"version": ProjectSettings.get_setting("application/config/version", "")}
	if clock != null:
		start_data["seed"] = str(clock.rng.seed)
		session.tick = clock.tick
		_speed = clock.speed
		_paused = clock.player_paused
		set_process(true)
	QuitLog.note("session_start", start_data)
	return true


## Writes session_end with `reason` and closes the file. Nothing when no
## session is open.
func stop(reason: String) -> void:
	if _log == null:
		return
	_disconnect_parts()
	set_process(false)
	_log.end(reason)
	_log = null


## The data of a missed passenger: where it was and what held it up.
static func miss_data(p: Passenger) -> Dictionary:
	return {
		"stage": Passenger.Stage.keys()[p.missed_stage].to_lower(),
		"cause": Passenger.Stuck.keys()[p.missed_stuck].to_lower(),
	}


## The data of a build edit: its kind only, no cell and no object.
static func edit_data(edit: BuildEdit) -> Dictionary:
	return {"kind": BuildEdit.Kind.keys()[edit.kind].to_lower()}


func _connect_parts() -> void:
	if clock != null:
		clock.ticked.connect(_on_ticked)
	if passengers != null:
		passengers.outcome.connect(_on_outcome)
	_grid = build_mode.grid if build_mode != null else null
	if _grid != null:
		_grid.edit_applied.connect(_on_edit_applied)


func _disconnect_parts() -> void:
	if is_instance_valid(clock) and clock.ticked.is_connected(_on_ticked):
		clock.ticked.disconnect(_on_ticked)
	if is_instance_valid(passengers) and passengers.outcome.is_connected(_on_outcome):
		passengers.outcome.disconnect(_on_outcome)
	if is_instance_valid(_grid) and _grid.edit_applied.is_connected(_on_edit_applied):
		_grid.edit_applied.disconnect(_on_edit_applied)
	_grid = null


func _on_ticked(tick: int) -> void:
	_log.tick = tick
	if GameCalendar.is_last_tick_of_day(tick):
		QuitLog.note("day_end", _day_data(GameCalendar.day_of(tick)))
	elif GameCalendar.tick_of_day(tick) == 0:
		QuitLog.note("day_start", _day_data(GameCalendar.day_of(tick)))


func _day_data(day: int) -> Dictionary:
	var data := {"day": day}
	if finances != null:
		data["money"] = finances.wallet.balance
	if rating != null:
		data["stars"] = rating.stars()
	return data


## A made passenger is counted in flight_result; a missed one is logged with
## its cause.
func _on_outcome(id: int, made: bool) -> void:
	if made:
		return
	var p := passengers.get_passenger(id)
	if p != null:
		QuitLog.note("passenger_missed", miss_data(p))


func _on_edit_applied(edit: BuildEdit, _result: BuildResult) -> void:
	QuitLog.note("build_edit", edit_data(edit))
