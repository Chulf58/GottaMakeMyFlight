class_name RoomTemplates
extends RefCounted
## The room templates of one airport (decision room-templates-store-rooms-
## with-their-pieces-kept-in-each-sa, point 2): kept in its save as the
## "templates" part (SaveGame), so a new game starts with none. Newest last.

## Emitted when a template is added or the list is replaced by a load.
signal changed

## 2: each template holds its room's floor; version 1 is refused (no
## migration before a release).
const SAVE_VERSION := 2

var _templates: Array[RoomTemplate] = []


func size() -> int:
	return _templates.size()


func get_template(index: int) -> RoomTemplate:
	return _templates[index]


func add(template: RoomTemplate) -> void:
	_templates.append(template)
	changed.emit()


func to_snapshot() -> Dictionary:
	var saved: Array = []
	for template in _templates:
		saved.append(template.to_dict())
	return {"save_version": SAVE_VERSION, "templates": saved}


## Replaces the list from a to_snapshot() dictionary, including one that went
## through JSON. Pushes an error and returns false, leaving the list as it was,
## when any template is refused.
func from_snapshot(data: Dictionary) -> bool:
	var problem := ""
	if data.size() != 2 or not data.has("save_version") or not data.has("templates"):
		problem = "a templates part holds save_version and templates"
	elif (
		not WholeNumber.is_whole(data["save_version"]) or int(data["save_version"]) != SAVE_VERSION
	):
		problem = "save_version must be %d" % SAVE_VERSION
	elif typeof(data["templates"]) != TYPE_ARRAY:
		problem = "templates must be a list"
	var loaded: Array[RoomTemplate] = []
	if problem == "":
		for entry in data["templates"]:
			var read := RoomTemplate.from_dict(entry)
			if read.has("error"):
				problem = read["error"]
				break
			loaded.append(read["template"])
	if problem != "":
		push_error("RoomTemplates.from_snapshot: %s" % problem)
		return false
	_templates = loaded
	changed.emit()
	return true
