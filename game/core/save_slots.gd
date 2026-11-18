class_name SaveSlots
extends RefCounted
## The save files the title screen and the game menu offer (decision
## title-menu-with-continue-new-airport-load-and-quit-autosave): the manual save
## (F5 and the menu's Save) and two autosaves, written in turn at each day
## rollover so a broken file still leaves the day before. Continue loads the
## newest of the three.
##
## Every path is under `dir`. Tests and probes point it at a folder of their own
## (SaveTestKit.run_dir) and put it back. A script run (a test, probe or spike)
## that leaves it on the player's folder is shielded: SaveGame writes no
## autosave there.

const DIR := "user://saves"
const MANUAL_FILE := "quicksave.json"
const AUTOSAVE_FILES: Array[String] = ["autosave_1.json", "autosave_2.json"]

static var dir := DIR


static func manual_path() -> String:
	return dir.path_join(MANUAL_FILE)


static func autosave_paths() -> Array[String]:
	var paths: Array[String] = []
	for file in AUTOSAVE_FILES:
		paths.append(dir.path_join(file))
	return paths


## The manual save first, then the autosaves.
static func all_paths() -> Array[String]:
	var paths: Array[String] = [manual_path()]
	paths.append_array(autosave_paths())
	return paths


## The files of `paths` that exist, newest first.
static func existing(paths: Array[String] = all_paths()) -> Array[String]:
	var times := {}
	var found: Array[String] = []
	for path in paths:
		if FileAccess.file_exists(path):
			found.append(path)
			times[path] = FileAccess.get_modified_time(path)
	return newest_first(found, times)


## The newest save, or "" when there is none.
static func latest() -> String:
	var found := existing()
	return found[0] if not found.is_empty() else ""


## `paths` sorted by `times` (path to modified time), newest first. Paths with
## the same time keep their order in `paths`.
static func newest_first(paths: Array, times: Dictionary) -> Array[String]:
	var order: Array[String] = []
	order.assign(paths)
	var rank := {}
	for i in order.size():
		rank[order[i]] = i
	order.sort_custom(
		func(a: String, b: String) -> bool:
			if times[a] != times[b]:
				return times[a] > times[b]
			return rank[a] < rank[b]
	)
	return order


## The autosave to write next: a missing one first, then the one that was not
## written last. With no last write known (a new session), the older file; on a
## tie, the first.
static func next_autosave(last_written: String) -> String:
	var paths := autosave_paths()
	for path in paths:
		if not FileAccess.file_exists(path):
			return path
	var at := paths.find(last_written)
	if at >= 0:
		return paths[(at + 1) % paths.size()]
	var oldest := paths[0]
	for path in paths:
		if FileAccess.get_modified_time(path) < FileAccess.get_modified_time(oldest):
			oldest = path
	return oldest


## True when this process is a script run and `dir` is the player's folder.
static func is_shielded() -> bool:
	return dir == DIR and Hints.launched_by_script(OS.get_cmdline_args())
