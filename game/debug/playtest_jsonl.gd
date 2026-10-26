class_name PlaytestJsonl
extends RefCounted
## One playtest .jsonl file with a size cap. put() writes a record as one JSON
## line until the next line would pass max_bytes less NOTICE_ROOM; from then on
## the file is capped and put() drops every record. The owner writes one
## notice into the room kept for it with put_notice(). prune_sessions() keeps
## the newest sessions of a playtest folder.

enum Put { WRITTEN, CAPPED_NOW, DROPPED }

const DEFAULT_MAX_BYTES := 20 * 1024 * 1024
## Kept free under the cap for the one notice line.
const NOTICE_ROOM := 512
const EVENTS_SUFFIX := ".jsonl"
const INPUT_SUFFIX := ".input.jsonl"

var max_bytes := DEFAULT_MAX_BYTES
## The absolute path, or "" before open().
var path := ""
var bytes := 0
var capped := false
var _file: FileAccess
var _noticed := false


## The newest `keep` sessions in `dir` stay; the events and input files of the
## others are deleted. A session is a <stem>.jsonl file, ordered by modified
## time and then by name. Other files are left alone. Returns how many
## sessions went.
static func prune_sessions(dir: String, keep: int) -> int:
	var absolute := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(absolute):
		return 0
	var sessions: Array[Array] = []
	for name in DirAccess.get_files_at(absolute):
		if name.ends_with(EVENTS_SUFFIX) and not name.ends_with(INPUT_SUFFIX):
			var stem := name.trim_suffix(EVENTS_SUFFIX)
			var file := "%s/%s" % [absolute, name]
			sessions.append([FileAccess.get_modified_time(file), stem])
	sessions.sort()
	var gone := 0
	for i in maxi(0, sessions.size() - keep):
		var stem: String = sessions[i][1]
		for suffix in [EVENTS_SUFFIX, INPUT_SUFFIX]:
			var file := "%s/%s%s" % [absolute, stem, suffix]
			if FileAccess.file_exists(file) and DirAccess.remove_absolute(file) != OK:
				push_error("PlaytestJsonl: cannot delete %s" % file)
		gone += 1
	return gone


## Opens (truncates) the file at `file_path`, a user:// or absolute path, and
## makes its folder. Returns false with an error when it cannot be opened.
func open(file_path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(file_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	_file = FileAccess.open(absolute, FileAccess.WRITE)
	if _file == null:
		push_error("PlaytestJsonl: cannot open %s: %s" % [absolute, FileAccess.get_open_error()])
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
	var line := JSON.stringify(record)
	_file.store_line(line)
	bytes += line.to_utf8_buffer().size() + 1
	_file.flush()


func flush() -> void:
	if _file != null:
		_file.flush()


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
