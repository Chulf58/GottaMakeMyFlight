class_name QuitLog
extends RefCounted
## The quit-point log (decision quit-point-log-d7-opt-in-local-event-log-file-
## only-off-by-de): an opt-in event log that records where a player stopped
## playing, written to <dir>/<session>.jsonl on the player's computer and
## nowhere else. Off by default; the Esc menu holds the switch. No network
## code, and no raw mouse or key input: only game events.
##
## A record is {"i", "wall", "tick", "type", "data"}: a running index from 0,
## the Unix time in seconds, the sim tick of the last tick the recorder saw and
## the event type with its data. Every record is flushed as it is written, so a
## killed game still leaves its file; a file without a session_end record means
## a crash or a kill.
##
## While a session is open, QuitLog.current is it and QuitLog.note() writes to
## it. With none open note() does nothing, so an event site is one line and
## costs nothing while the log is off.

const DIR := "user://telemetry"
const KEEP_SESSIONS := 10
## The settings file the switch is saved in: the player's shared one, which a
## script-driven run never reads or writes (HudFlagSetting.is_shielded).
const SETTINGS_PATH := HudFlagSetting.PATH
const SETTING_KEY := "quit_log"
const WHO := "QuitLog"

## The open session, or null while the log is off.
static var current: QuitLog

## The sim tick stamped on each record; the recorder keeps it current.
var tick := 0
var max_bytes := QuitLogFile.DEFAULT_MAX_BYTES
## The absolute path of the open file, or "".
var path := ""
var _file := QuitLogFile.new()
var _next := 0


## Writes one event to the open session, if there is one.
static func note(type: String, data := {}) -> void:
	if current != null:
		current.add(type, data)


## A passenger counted missed: the stage it was in and what held it up.
static func note_missed(stage: int, stuck: int) -> void:
	if current != null:
		(
			current
			. add(
				"passenger_missed",
				{
					"stage": Passenger.Stage.keys()[stage].to_lower(),
					"cause": Passenger.Stuck.keys()[stuck].to_lower(),
				}
			)
		)


static func is_enabled(settings_path := SETTINGS_PATH) -> bool:
	return HudFlagSetting.load_flag(settings_path, SETTING_KEY, false, WHO)


static func save_enabled(on: bool, settings_path := SETTINGS_PATH) -> void:
	HudFlagSetting.save_flag(settings_path, SETTING_KEY, on, WHO)


## The log folder as an absolute path, for the Open log folder button.
static func folder(dir := DIR) -> String:
	return ProjectSettings.globalize_path(dir)


## A session file stem: the local time, then the process id. Two sessions that
## share it are told apart by open().
static func new_session_name() -> String:
	var stamp := Time.get_datetime_string_from_system(false, true)
	stamp = stamp.replace("-", "").replace(":", "").replace(" ", "-")
	return "%s-%d" % [stamp, OS.get_process_id()]


## Makes the folder, keeps the newest sessions (KEEP_SESSIONS with this one),
## opens <dir>/quitlog_<session>.jsonl and makes this the current session. A
## session name already used in `dir` gets -2, -3 and so on, so a new session
## never truncates an earlier file. False, with an error pushed by the writer,
## when the file cannot be opened.
func open(dir: String, session: String) -> bool:
	QuitLogFile.prune_sessions(dir, KEEP_SESSIONS - 1)
	_file.max_bytes = max_bytes
	var file_path := _free_path(dir, session)
	if not _file.open(file_path):
		return false
	path = _file.path
	_next = 0
	current = self
	return true


func is_open() -> bool:
	return _file.is_open()


## Writes one record. `data` must be JSON-safe (no vectors). Past the cap the
## file takes one last record, a log_capped notice, and no more.
func add(type: String, data := {}) -> void:
	var record := _record(type, data)
	if _file.put(record) == QuitLogFile.Put.CAPPED_NOW:
		_file.put_notice(_record("log_capped", {"max_bytes": max_bytes}))
	_file.flush()


## Writes session_end with `reason`, closes the file and, when this was the
## current session, leaves none.
func end(reason: String) -> void:
	if not _file.is_open():
		return
	_file.put_tail(_record("session_end", {"reason": reason}))
	_file.close()
	if current == self:
		current = null


func _free_path(dir: String, session: String) -> String:
	var n := 1
	var stem := session
	var file_path := "%s/%s%s%s" % [dir, QuitLogFile.PREFIX, stem, QuitLogFile.SUFFIX]
	while FileAccess.file_exists(file_path):
		n += 1
		stem = "%s-%d" % [session, n]
		file_path = "%s/%s%s%s" % [dir, QuitLogFile.PREFIX, stem, QuitLogFile.SUFFIX]
	return file_path


func _record(type: String, data: Dictionary) -> Dictionary:
	var record := {
		"i": _next,
		"wall": snappedf(Time.get_unix_time_from_system(), 0.001),
		"tick": tick,
		"type": type,
		"data": data,
	}
	_next += 1
	return record
