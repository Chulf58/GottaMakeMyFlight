class_name SaveList
extends VBoxContainer
## The Load page's list (decision title-menu-with-continue-new-airport-load-and-
## quit-autosave), shared by the title screen and the game menu: one button per
## save that exists, newest first, each naming the slot and when it was saved.
## Pressing one emits chosen(path); the owner loads it.

signal chosen(path: String)

## The files to offer; fill() keeps the ones that exist.
var _paths: Array[String] = []


## Rebuilds the buttons for the files of `paths` that exist. `manual_path` is
## the one that is named as the manual save.
func fill(paths: Array[String], manual_path: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_paths = SaveSlots.existing(paths)
	for path in _paths:
		var button := Button.new()
		button.name = "Save%d" % get_child_count()
		var values := {"slot": _slot_name(path, manual_path), "time": _saved_at(path)}
		if SaveSlots.is_compatible(path):
			button.text = tr("{slot}, {time}").format(values)
		else:
			button.text = tr("{slot}, {time} (Older version)").format(values)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: chosen.emit(path))
		add_child(button)


## The listed files, newest first.
func paths() -> Array[String]:
	return _paths.duplicate()


## The button that loads `path`, or null when it is not listed.
func button_for(path: String) -> Button:
	var at := _paths.find(path)
	return get_child(at) as Button if at >= 0 else null


func _slot_name(path: String, manual_path: String) -> String:
	if path == manual_path:
		return tr("Manual save")
	var at := SaveSlots.autosave_paths().find(path)
	if at >= 0:
		return tr("Autosave {number}").format({"number": at + 1})
	return path.get_file()


## The file's modified time in the player's local time, as YYYY-MM-DD HH:MM.
static func _saved_at(path: String) -> String:
	var bias_seconds := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var unix := FileAccess.get_modified_time(path) + bias_seconds
	return Time.get_datetime_string_from_unix_time(unix, true).left(16)
