class_name PlaytestLog
extends RefCounted
## The playtest event log: every event is one JSON line in a .jsonl file and
## the last `ring_size` events stay in memory. An event is
## {"i", "tick", "wall", "type", "data"}: a running index from 0, the sim
## tick, the Unix time in seconds and the event type with its data. The file
## is flushed by flush() and on close(), so a reader may trail by up to one
## flush. Past max_bytes the file takes one last event, a "session" event with
## state "capped", and no more; the ring and the counts go on.

const DEFAULT_RING_SIZE := 200

var ring_size := DEFAULT_RING_SIZE
var max_bytes := PlaytestJsonl.DEFAULT_MAX_BYTES
## The absolute path of the file, or "" when nothing is written.
var path := ""
var _file := PlaytestJsonl.new()
var _ring: Array[Dictionary] = []
var _next := 0
var _counts: Dictionary = {}


## Opens (truncates) the file at `file_path`, a user:// or absolute path, and
## makes its folder. Returns false with an error when it cannot be opened.
func open(file_path: String) -> bool:
	_file.max_bytes = max_bytes
	if not _file.open(file_path):
		return false
	path = _file.path
	return true


## Records one event and returns it. `data` must be JSON-safe (no vectors).
func add(tick: int, type: String, data: Dictionary) -> Dictionary:
	var event := _remember(tick, type, data)
	if _file.put(event) == PlaytestJsonl.Put.CAPPED_NOW:
		var notice := {"state": "capped", "file": "events", "max_bytes": max_bytes}
		_file.put_notice(_remember(tick, "session", notice))
	return event


## The events still in memory with an index of `index` or more, oldest first.
## An index older than the ring returns from the oldest kept; the file has all.
func since(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in _ring:
		if event["i"] >= index:
			out.append(event)
	return out


## The last `count` events, oldest first.
func last(count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_ring.slice(maxi(0, _ring.size() - count)))
	return out


## How many events were logged in all.
func total() -> int:
	return _next


## Event count by type, for every type logged.
func counts() -> Dictionary:
	return _counts.duplicate()


func flush() -> void:
	_file.flush()


func close() -> void:
	_file.close()


func _remember(tick: int, type: String, data: Dictionary) -> Dictionary:
	var event := {
		"i": _next,
		"tick": tick,
		"wall": snappedf(Time.get_unix_time_from_system(), 0.001),
		"type": type,
		"data": data,
	}
	_next += 1
	_counts[type] = _counts.get(type, 0) + 1
	_ring.append(event)
	if _ring.size() > ring_size:
		_ring.pop_front()
	return event
