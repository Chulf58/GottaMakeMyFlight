class_name GhostReason
extends PanelContainer
## A short refusal reason beside the build ghost (decision hud-steal-list-self-
## clearing-alert-cards-money-hover-departu, item 6): while the pointer is over
## the grid and the edit under it is refused, a small card right of the drawn
## ghost's on-screen bounds (left of them when the window ends first), level
## with the ghost's middle, says why in a few words. The status line above the
## tray still gives the whole reason.
##
## It reads BuildMode's public hover, hover_edit() and check(), and the ghost's
## place on screen through GhostBounds over BuildMode's Ghost node. The Belt
## and the landside tools have no hover edit, so their reasons stay on the
## status line alone, as do a dragged rectangle's
## and a wall row's: while BuildMode.is_dragging() the drag owns the hover. A
## held button with no drag (pressing on a refused desk) keeps the card.
##
## The answer is cached per hover edit and balance, and forgotten whenever the
## grid changes (BuildGrid.graph_changed and edit_applied, which also catch an
## edit written straight to the grid, such as the starter terminal), BuildMode
## redraws after its own edit, or BuildMode's status line changes.

## The gap between the ghost's bounds and the card.
const GAP := 10.0
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
## The grid whose change signals _forget() is connected to.
var _watched: BuildGrid


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
	refresh()


## The text on the card ("" while it is hidden).
func text() -> String:
	return _label.text if visible else ""


## The refusal of the edit under the pointer, or null when the card has none to show.
func refusal() -> BuildResult:
	if build_mode == null or build_mode.tool == BuildMode.Tool.NONE:
		return null
	if not build_mode.pointer_on_grid() or build_mode.is_dragging():
		return null
	var edit := build_mode.hover_edit()
	if edit == null:
		return null
	_watch(build_mode.grid)
	var key := _edit_key(edit)
	if key != _key:
		_key = key
		_result = build_mode.check(edit)
	return null if _result.ok else _result


## Shows the card beside the drawn ghost while the edit under the pointer is
## refused, kept inside the window; hides it otherwise, and while no part of
## the ghost is on screen.
func refresh() -> void:
	var result := refusal()
	var screen := get_viewport().get_visible_rect()
	var ghost := ghost_rect() if result != null else Rect2()
	visible = result != null and ghost.has_area() and screen.intersects(ghost)
	if not visible:
		return
	_label.text = short_text(result)
	reset_size()
	var at := Vector2(ghost.end.x + GAP, ghost.get_center().y - size.y / 2.0)
	if at.x + size.x > screen.end.x - EDGE:
		at.x = ghost.position.x - GAP - size.x
	at.x = clampf(at.x, EDGE, maxf(EDGE, screen.end.x - size.x - EDGE))
	at.y = clampf(at.y, EDGE, maxf(EDGE, screen.end.y - size.y - EDGE))
	position = at


## The drawn ghost's bounds on screen (GhostBounds), or an empty Rect2.
func ghost_rect() -> Rect2:
	return GhostBounds.screen_rect(GhostBounds.ghost_of(build_mode), get_viewport().get_camera_3d())


## A placed or removed piece can change the answer for the same edit.
func _forget() -> void:
	_key = ""


## Forgets the cached answer on every change of `grid`, including an edit
## written straight to it without BuildMode.
func _watch(grid: BuildGrid) -> void:
	if grid == _watched:
		return
	if _watched != null:
		_watched.graph_changed.disconnect(_on_graph_changed)
		_watched.edit_applied.disconnect(_on_edit_applied)
	_watched = grid
	_key = ""
	if grid != null:
		grid.graph_changed.connect(_on_graph_changed)
		grid.edit_applied.connect(_on_edit_applied)


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_forget()


func _on_edit_applied(_edit: BuildEdit, _applied: BuildResult) -> void:
	_forget()


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
