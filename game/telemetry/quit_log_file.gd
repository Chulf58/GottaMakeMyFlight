class_name QuitLogFile
extends RefCounted
## One quit-log .jsonl file with a size cap (decision quit-point-log-d7-opt-in-
## local-event-log-file-only-off-by-de). put() writes a record as one JSON line
## until the next line would pass max_bytes less NOTICE_ROOM; from then on the
## file is capped and put() drops every record. The owner writes one notice
## into the room kept for it with put_notice(). prune_sessions() keeps the
## newest sessions of the log folder. The writer is copied from the dev-only
## PlaytestJsonl on purpose: this log ships to players, and game/debug/ stays
## inert in a release build.

enum Put { WRITTEN, CAPPED_NOW, DROPPED }

const DEFAULT_MAX_BYTES := 1024 * 1024
## Kept free under the cap for the one notice line.
const NOTICE_ROOM := 512
const SUFFIX := ".jsonl"

var max_bytes := DEFAULT_MAX_BYTES
## The absolute path, or "" before open().
var path := ""
var bytes := 0
var capped := false
var _file: FileAccess
var _noticed := false


## The newest `keep` sessions in `dir` stay; the others are deleted. A session
## is a <stem>.jsonl file, ordered by modified time and then by name. Other
## files are left alone. Returns how many sessions went.
static func prune_sessions(dir: String, keep: int) -> int:
	var absolute := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(absolute):
		return 0
	var sessions: Array[Array] = []
	for name in DirAccess.get_files_at(absolute):
		if name.ends_with(SUFFIX):
			var file := "%s/%s" % [absolute, name]
			sessions.append([FileAccess.get_modified_time(file), name])
	sessions.sort()
	var gone := 0
	for i in maxi(0, sessions.size() - keep):
		var file := "%s/%s" % [absolute, sessions[i][1]]
		if DirAccess.remove_absolute(file) != OK:
			push_error("QuitLogFile: cannot delete %s" % file)
		else:
			gone += 1
	return gone


## Opens (truncates) the file at `file_path`, a user:// or absolute path, and
## makes its folder. Returns false with an error when it cannot be opened.
func open(file_path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(file_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	_file = FileAccess.open(absolute, FileAccess.WRITE)
	if _file == null:
		push_error("QuitLogFile: cannot open %s: %s" % [absolute, FileAccess.get_open_error()])
		return false
	path = absolute
	bytes = 0
	capped = false
	_noticed = false
	return true


## Writes `record` as one line. CAPPED_NOW the first time a record does not
## fit (the record is dropped), DROPPED after that or when no file is open.
func put(record: Dictionary) -> Put:
	if _file == null or capped:
		return Put.DROPPED
	var line := JSON.stringify(record)
	var size := line.to_utf8_buffer().size() + 1
	if bytes + size > max_bytes - NOTICE_ROOM:
		capped = true
		return Put.CAPPED_NOW
	_file.store_line(line)
	bytes += size
	return Put.WRITTEN


## Writes the one notice of a capped file into the room kept for it and
## flushes. Later calls write nothing.
func put_notice(record: Dictionary) -> void:
	if _file == null or _noticed:
		return
	_noticed = true
	put_tail(record)


## Writes `record` into the room kept under the cap, whether the file is capped
## or not, and flushes. The notice and the session end use it.
func put_tail(record: Dictionary) -> void:
	if _file == null:
		return
	var line := JSON.stringify(record)
	_file.store_line(line)
	bytes += line.to_utf8_buffer().size() + 1
	_file.flush()


func flush() -> void:
	if _file != null:
		_file.flush()


func is_open() -> bool:
	return _file != null


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
