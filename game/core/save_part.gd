class_name SavePart
extends RefCounted
## One part of the whole-world save (SaveGame.parts()): the key it is saved
## under and three steps.
##
## - save() -> Dictionary: the live part's JSON-safe state. It only reads.
## - stage(data: Dictionary, staged: Dictionary) -> String: checks `data`
##   without touching the live part, by loading it into a staged copy, and
##   returns why it is refused or "". A part that other checks read keeps
##   its staged copy in `staged` (under its key, or "sim" for the bare
##   PassengerSim); SaveGame checks the links between parts on those copies
##   (SaveLinks) and frees staged nodes when the load ends.
## - install(data: Dictionary) -> bool: loads `data` into the live part.

var key: String
var save: Callable
var stage: Callable
var install: Callable


func _init(
	part_key: String, save_step: Callable, stage_step: Callable, install_step: Callable
) -> void:
	key = part_key
	save = save_step
	stage = stage_step
	install = install_step


## A stage step that loads the data into a fresh instance of `script`
## through `method` (from_snapshot by default). The copy is kept in `staged`
## under `keep_as` when one is given, otherwise freed at once. The part's own
## loader pushes the detailed reason.
static func scratch(script: Script, method := &"from_snapshot", keep_as := "") -> Callable:
	return func(data: Dictionary, staged: Dictionary) -> String:
		var copy: Object = script.new()
		var ok: bool = copy.call(method, data)
		if ok and keep_as != "":
			staged[keep_as] = copy
		elif copy is Node:
			copy.free()
		return "" if ok else "it was refused (see the error log)"


## A stage step for a part whose loader is a static check that returns
## {"error": reason} or the loaded state (FlightSnapshot.load, for example).
## The loaded state is kept in `staged` under `keep_as`.
static func checked(keep_as: String, load_step: Callable) -> Callable:
	return func(data: Dictionary, staged: Dictionary) -> String:
		var loaded: Dictionary = load_step.call(data)
		if loaded.has("error"):
			return str(loaded["error"])
		staged[keep_as] = loaded
		return ""
