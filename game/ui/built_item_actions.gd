class_name BuiltItemActions
extends VBoxContainer
## Move and Delete for the built item the inspect window shows (decision
## built-items-selectable-reuse-the-selection-window-move-delete-close-open:
## both live here and stay on the bar). PassengerInspect puts this under the
## item's info rows.
##
## Move picks up the room the item is, or stands in, with that room's tool
## (RoomMoveTool.pick_up(), so the ghost, the turn and the set-down are the bar's
## own). It is disabled, with the reason on its own line, for a room that can
## never move (RoomMoveTool.never_moves_refusal()), for check-in desks, scanners
## and lane parts, for a single piece outside a room and for a car park.
##
## Delete enters build mode, which pauses the game and keeps the undo history
## (decision select-placed-items-design-click-order-gold-footprint-highli), then
## removes the item or room through BuildMode.apply_edit(): paid back and one
## undo step. A refused delete leaves build mode alone and says why.

const MOVE := "Move"
const MOVE_ROOM := "Move room"
const DELETE := "Delete"
const DELETE_ROOM := "Delete room"
const NO_LOOSE_PIECE := "Single pieces outside a room can't be moved yet"
const GONE := "It is no longer there"
const NO_ROOM_TOOL := "This kind of room can't be moved yet"
const NO_LANDSIDE_MOVE := "Car parks and curbs can't be moved yet"
const NO_LANDSIDE_DELETE := "Take car parks and curbs back with the Remove tool"
const DELETE_REFUSED := "Can't delete: %s"

## The window's item card, which holds the selection, the build mode and the sim.
var card: BuiltItemCard
## Build mode as the player lives it; Delete starts it and refuses without one
## (PassengerHud wires it from the BuildMenu).
var session: BuildSession

var _move_button := Button.new()
var _delete_button := Button.new()
var _reason := Label.new()
## What Move and Delete can do for the selection: "ok", "label", "reason", and
## when ok, for Move "room", "type" and "tool", for Delete "edit".
var _move := {}
var _delete := {}
var _note := ""
var _key := ""
var _stale := true
var _watched: BuildGrid


func _init() -> void:
	name = "BuiltItemActions"
	visible = false
	add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	add_child(row)
	_move_button.name = "MoveButton"
	_move_button.focus_mode = Control.FOCUS_NONE
	_move_button.theme_type_variation = &"HudButtonTeal"
	_move_button.pressed.connect(press_move)
	row.add_child(_move_button)
	_delete_button.name = "DeleteButton"
	_delete_button.focus_mode = Control.FOCUS_NONE
	_delete_button.theme_type_variation = &"HudButtonCoral"
	_delete_button.pressed.connect(press_delete)
	row.add_child(_delete_button)
	_reason.name = "ActionReason"
	_reason.theme_type_variation = &"HudHint"
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_reason)


## Shows the buttons for the selected item, or hides them with none.
func refresh() -> void:
	if card == null or not card.visible or card.build_mode == null or card.selection == null:
		visible = false
		return
	_watch()
	var key := card.selection.key()
	if key != _key or _stale:
		_move = _move_state()
		_delete = _delete_state()
		_key = key
		_stale = false
		_note = ""
	visible = true
	_move_button.text = _move["label"]
	_move_button.disabled = not _move["ok"]
	_move_button.tooltip_text = "Pick it up and set it down elsewhere" if _move["ok"] else ""
	_delete_button.text = _delete["label"]
	_delete_button.disabled = not _delete["ok"]
	var lines := PackedStringArray()
	for text in [_move["reason"], _delete["reason"], _note]:
		if text != "":
			lines.append(text)
	_reason.text = "\n".join(lines)
	_reason.visible = not lines.is_empty()


## Picks the room tool and lifts the room the item is or stands in. False when
## Move is disabled or the room refuses to be lifted.
func press_move() -> bool:
	if card == null or card.build_mode == null or not _move.get("ok", false):
		return false
	var mode := card.build_mode
	var rect: Rect2i = mode.grid.get_room(_move["room"])["rect"]
	var point := mode.grid.cell_to_world(rect.position + (rect.size - Vector2i.ONE) / 2)
	mode.set_tool_for_move(_move["tool"])
	if mode.room_mover.pick_up(point, _move["type"]):
		return true
	mode.set_tool(BuildMode.Tool.NONE)
	return false


## Removes the selected item or room as one refunded undo step, inside build
## mode. Returns the result, or null when nothing is selected that can be deleted
## or no session is wired (an error).
func press_delete() -> BuildResult:
	if card == null or card.build_mode == null or not _delete.get("ok", false):
		return null
	if session == null:
		push_error("BuiltItemActions: no build session wired, so Delete cannot start build mode")
		return null
	var mode := card.build_mode
	var edit: BuildEdit = _delete["edit"]
	if mode.check(edit).ok:
		session.set_building(true)
	var result := mode.apply_edit(edit)
	if not result.ok:
		_note = DELETE_REFUSED % result.reason_text()
		refresh()
	return result


## The room tool that builds, and so moves, rooms of `type`; NONE for a type
## with no tool.
static func tool_for_room(type: StringName) -> BuildMode.Tool:
	for tool in BuildMode.TOOL_ROOMS:
		if BuildMode.TOOL_ROOMS[tool] == type:
			return tool
	return BuildMode.Tool.NONE


func move_text() -> String:
	return _move_button.text


func move_disabled() -> bool:
	return _move_button.disabled


func delete_text() -> String:
	return _delete_button.text


func delete_disabled() -> bool:
	return _delete_button.disabled


## The lines under the buttons: why an action is disabled, or why a delete failed.
func reason_text() -> String:
	return _reason.text if _reason.visible else ""


func _watch() -> void:
	var grid := card.sim.grid
	if grid == _watched:
		return
	_watched = grid
	grid.graph_changed.connect(_mark_stale)
	grid.edit_applied.connect(_mark_stale_edit)
	_stale = true


func _mark_stale(_cells: Array[Vector2i]) -> void:
	_stale = true


func _mark_stale_edit(_edit: BuildEdit, _result: BuildResult) -> void:
	_stale = true


func _move_state() -> Dictionary:
	var grid := card.sim.grid
	var found := _room_to_move()
	if found["reason"] != "":
		return _off(MOVE, found["reason"])
	var room: int = found["room"]
	var type := StringName(grid.get_room(room)["type"])
	var tool := tool_for_room(type)
	if tool == BuildMode.Tool.NONE:
		return _off(MOVE_ROOM, NO_ROOM_TOOL)
	var refusal := RoomMoveTool.never_moves_refusal(grid, room)
	if refusal != null:
		return _off(MOVE_ROOM, refusal.reason_text())
	return {"ok": true, "label": MOVE_ROOM, "reason": "", "room": room, "type": type, "tool": tool}


## The room the selection moves with: {"room": id} for a room or a piece in one,
## else {"reason": why not}.
func _room_to_move() -> Dictionary:
	var grid := card.sim.grid
	var selection := card.selection
	match selection.kind:
		BuiltSelection.Kind.ROOM:
			return {"room": selection.id, "reason": ""}
		BuiltSelection.Kind.OBJECT:
			var record := grid.get_object(selection.id)
			if record.is_empty():
				return {"room": 0, "reason": GONE}
			var room := grid.room_at(record["anchor"])
			if _is_lane_piece(StringName(record["def"])):
				return {"room": 0, "reason": _lane_piece_reason(room)}
			return {"room": room, "reason": "" if room != 0 else NO_LOOSE_PIECE}
	return {"room": 0, "reason": NO_LANDSIDE_MOVE}


func _delete_state() -> Dictionary:
	match card.selection.kind:
		BuiltSelection.Kind.OBJECT:
			var edit := BuildEdit.remove_object(card.selection.id)
			return {"ok": true, "label": DELETE, "reason": "", "edit": edit}
		BuiltSelection.Kind.ROOM:
			var edit := BuildEdit.remove_room(card.selection.id)
			return {"ok": true, "label": DELETE_ROOM, "reason": "", "edit": edit}
	return _off(DELETE, NO_LANDSIDE_DELETE)


## Why a check-in desk, scanner or lane part cannot move: what RoomMove refuses
## its room with, or the base text of that refusal for a piece outside any room.
func _lane_piece_reason(room: int) -> String:
	if room != 0:
		var refusal := RoomMoveTool.never_moves_refusal(card.sim.grid, room)
		if refusal != null:
			return refusal.reason_text()
	return BuildResult.REASON_TEXT[BuildResult.Reason.MOVE_UNMOVABLE]


static func _is_lane_piece(def_id: StringName) -> bool:
	var kind: Variant = BuiltItemCard.KIND_OF_DEF.get(def_id)
	return (
		kind == BuiltItemCard.Kind.DESK
		or kind == BuiltItemCard.Kind.SCANNER
		or kind == BuiltItemCard.Kind.ARCH
		or SecurityLanes.is_part(def_id)
	)


static func _off(label: String, reason: String) -> Dictionary:
	return {"ok": false, "label": label, "reason": reason}
