class_name PlaytestErrorLogger
extends Logger
## Catches engine and script errors for the playtest hook. Godot calls a
## Logger added with OS.add_logger() for push_error(), push_warning(), engine
## errors and GDScript runtime errors, from any thread, so the errors queue
## under a mutex and the hook drains them on the main thread. Plain print()
## output is not kept.

var _mutex := Mutex.new()
var _pending: Array[Dictionary] = []


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	var kinds := ["error", "warning", "script", "shader"]
	var entry := {
		"kind": kinds[error_type] if error_type >= 0 and error_type < kinds.size() else "error",
		"message": rationale if rationale != "" else code,
		"code": code,
		"function": function,
		"file": file,
		"line": line,
	}
	_mutex.lock()
	_pending.append(entry)
	_mutex.unlock()


## The errors caught since the last call, oldest first.
func drain() -> Array[Dictionary]:
	_mutex.lock()
	var out := _pending.duplicate()
	_pending.clear()
	_mutex.unlock()
	return out
