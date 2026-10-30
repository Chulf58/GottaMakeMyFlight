class_name GhostReason
extends PanelContainer
## A short refusal reason beside the build ghost (decision hud-steal-list-self-
## clearing-alert-cards-money-hover-departu, item 6): while the pointer is over
## the grid and the edit under it is refused, a small card just below and to
## the right of the pointer, where the ghost is, says why in a few words. The
## status line above the tray still gives the whole reason.
##
## It reads BuildMode's public hover: hover_edit() and check(). The Belt and
## the landside tools have no hover edit, so their reasons stay on the status
## line alone, as do a dragged rectangle's and a wall row's: while the left
## button is held a drag may own the hover, and the card hides.

## Where the card's top-left corner sits from the pointer.
const OFFSET := Vector2(22.0, 18.0)
## The card keeps this far inside the window edges.
const EDGE := 8.0
## Short forms of the longer BuildResult.REASON_TEXT lines; a reason missing
## here (already short, such as "Needs floor") shows its full text.
const SHORT_TEXT := {
	BuildResult.Reason.OUT_OF_BOUNDS: "Outside the building",
	BuildResult.Reason.OVERLAP: "Overlaps an object",
	BuildResult.Reason.WALL_IN_FOOTPRINT: "A wall is in the way",
	BuildResult.Reason.INTERACTION_BLOCKED: "Front spot blocked",
	BuildResult.Reason.INTERACTION_RESERVED: "Blocks a front spot",
	BuildResult.Reason.WALL_EXISTS: "Wall already here",
	BuildResult.Reason.DOOR_NEEDS_WALLS: "Needs wall on both sides",
	BuildResult.Reason.WALL_HOLDS_DOOR: "A door is beside it",
	BuildResult.Reason.DOOR_NOT_ON_EDGE: "Needs the outside edge",
	BuildResult.Reason.DOOR_WALLED: "Keep the edge open",
	BuildResult.Reason.DOOR_NOT_AT_SHELL_DOOR: "Not a door spot",
	BuildResult.Reason.ROOM_OVERLAP: "Overlaps a room",
	BuildResult.Reason.IN_ROOM: "Remove the room first",
	BuildResult.Reason.WALLET_FULL: "Money at its limit",
	BuildResult.Reason.BELT_CROSSING: "Belts cannot cross",
	BuildResult.Reason.BELT_WALL: "A wall is in the way",
	BuildResult.Reason.STAFF_SPOT: "Keep the staff spot free",
	BuildResult.Reason.LANE_WALL: "A wall is in the lane",
}

var build_mode: BuildMode

var _label := Label.new()
## The hover edit and balance last checked, and what check() said.
var _key := ""
var _result: BuildResult


## The few words the card shows for a refusal.
static func short_text(result: BuildResult) -> String:
	return SHORT_TEXT.get(result.reason, result.reason_text())


func _ready() -> void:
	name = "GhostReason"
	theme = BuildMenu.HUD_THEME
	theme_type_variation = &"HudSubCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_label.name = "ReasonText"
	_label.theme_type_variation = &"HudProblemText"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	if build_mode != null:
		build_mode.grid_changed.connect(_forget)
		# BuildMode checks the hover afresh after an undo or a load too, and
		# then its status line changes.
		build_mode.status_changed.connect(_forget.unbind(1))


func _process(_delta: float) -> void:
	refresh(_pointer())


## The text on the card ("" while it is hidden).
func text() -> String:
	return _label.text if visible else ""


## The refusal of the edit under the pointer, or null when the card has none to show.
func refusal() -> BuildResult:
	if build_mode == null or build_mode.tool == BuildMode.Tool.NONE:
		return null
	if not build_mode.pointer_on_grid() or build_mode.dragged_area().has_area():
		return null
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return null
	var edit := build_mode.hover_edit()
	if edit == null:
		return null
	var key := _edit_key(edit)
	if key != _key:
		_key = key
		_result = build_mode.check(edit)
	return null if _result.ok else _result


## Shows the card beside `pointer` (viewport coordinates) while the edit there is
## refused, kept inside the window; hides it otherwise.
func refresh(pointer: Vector2) -> void:
	var result := refusal()
	visible = result != null
	if result == null:
		return
	_label.text = short_text(result)
	reset_size()
	var screen := get_viewport().get_visible_rect().size
	var at := pointer + OFFSET
	at.x = clampf(at.x, EDGE, maxf(EDGE, screen.x - size.x - EDGE))
	at.y = clampf(at.y, EDGE, maxf(EDGE, screen.y - size.y - EDGE))
	position = at


## A placed or removed piece can change the answer for the same edit.
func _forget() -> void:
	_key = ""


func _pointer() -> Vector2:
	if build_mode != null and build_mode.pointer_override.x >= 0.0:
		return build_mode.pointer_override
	return get_viewport().get_mouse_position()


## The edit's fields and the wallet balance: what check() depends on, beside the grid.
func _edit_key(edit: BuildEdit) -> String:
	var wallet := build_mode.wallet()
	return (
		"%d:%d:%s:%d:%d:%s:%d:%d:%s:%s:%d:%d"
		% [
			build_mode.tool,
			edit.kind,
			edit.cell,
			edit.side,
			edit.wall_kind,
			edit.def_id,
			edit.facing,
			edit.object_id,
			edit.room_type,
			edit.room_size,
			edit.room_id,
			wallet.balance if wallet != null else 0,
		]
	)
