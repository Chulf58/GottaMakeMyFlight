# gdlint:disable = max-public-methods
# BuildMode is the one player build surface; undo (undo, undo_history) took it
# past the 20-method cap.
class_name BuildMode
extends Node3D
## The player's build tools over a BuildGrid. Keys 1 to 9 and 0 (or
## BuildMenu's cards) pick floor, wall, desk, scanner, seats, remove, glass,
## door, entrance and exit; Esc picks none; R turns the object;
## left-click applies, a drag with Wall or Glass shows a straight row and
## lays it on release (WallRowDrag), and a drag with Floor or Remove fills or
## clears a rectangle (AreaDrag). Esc or right-click cancels either drag, and
## a single click acts as it always did. A
## ghost shows the edit under the mouse, tinted by check(), so the preview and
## the click use the same rules. Entrances and exits turn themselves to face
## in from the edge under the mouse until R is pressed (DoorPlacement.auto_facing()).
## Inside a terminal shell they snap to its Toon doors instead (ShellDefinition).
## The Cafe tool drags a rectangle that marks floor as a cafe room (RoomTool);
## the counter and table tools furnish it, and RoomView shows what it needs.
## The Bag room tool does the same for a baggage room, and the Toilet room tool
## for a toilet, which the stall and sink tools furnish. The Belt tool lays belt
## cells: press, drag and release lays an L-shaped line (BeltShaper.path()),
## a click lays one cell, and Esc or right-click cancels. Every belt cell takes
## its piece from its neighbours (BeltShaper), so a line that dead-ends in a
## bag room ends in the belt end the room needs; after every other edit the
## belts next to it are reshaped too (_reshape_belts()).
## Every edit is paid from `finances` through BuildTransaction; a belt cell
## costs the plain belt price whatever shape it takes, and a reshape is free.
## Ctrl+Z (build_undo) undoes the last build action and its money (UndoStack,
## BuildUndo); a refused undo changes nothing and says why on the status line.

signal grid_changed
## Emitted by every set_tool(), NONE included, so the menu can follow it.
signal tool_changed(new_tool: Tool)
## Emitted when the status line's text changes.
signal status_changed(text: String)
## Emitted when the room under the pointer changes, 0 for none
## (update_room_focus()).
signal room_focus_changed(room_id: int)

enum Tool {
	NONE,
	FLOOR,
	WALL,
	DESK,
	SCANNER,
	SEATS,
	REMOVE,
	GLASS,
	DOOR,
	ENTRANCE,
	EXIT,
	CAFE_ROOM,
	COUNTER,
	TABLE,
	BAG_ROOM,
	BELT,
	CART,
	TRAY_TABLE,
	XRAY_BELT,
	ARCH,
	PICKUP_TABLE,
	TOILET_ROOM,
	TOILET_STALL,
	TOILET_SINK,
	KIOSK_ROOM,
	KIOSK_COUNTER,
	KIOSK_DISPLAY,
	SCREEN,
	CURB,
	SURFACE_LOT,
	MULTI_STOREY,
	LOT_GATE,
	BENCH,
	TREE_BENCH,
	BUSH,
	FOUNTAIN,
	POST,
	CHAIN,
	PLANTER,
	PLANT_POT,
	STATUE,
	BIN,
	TREE,
	BAR_COUNTER,
	GRAB_STALL,
	DINING_TABLE,
	BOOTH,
	INFO_DESK,
	INFO_SCREEN,
	EXCHANGE,
	ATM,
	PHARMACY_COUNTER,
	PHARMACY_SHELF,
	SHOWER,
	NAP_POD,
	PLAY_BLOCKS,
	PLAY_SLIDE,
	SOFA,
	ARMCHAIR,
	WORK_DESK,
	PRIZE_PODIUM,
	PHARMACY_ROOM,
	DUTY_FREE_ROOM,
	DUTY_FREE_TILL,
	DUTY_FREE_SHELF,
	FASHION_ROOM,
	FASHION_TILL,
	FASHION_RAIL,
}

## The landside build tools (LandsidePlacement), by the kind each builds. They
## work on the ground outside the grid; LOT_GATE opens or closes a car park.
const LANDSIDE_BUILD_TOOLS := {
	Tool.CURB: LandsidePlacement.Kind.CURB,
	Tool.SURFACE_LOT: LandsidePlacement.Kind.SURFACE_LOT,
	Tool.MULTI_STOREY: LandsidePlacement.Kind.MULTI_STOREY,
}

const TOOL_ACTIONS := {
	&"build_tool_floor": Tool.FLOOR,
	&"build_tool_wall": Tool.WALL,
	&"build_tool_desk": Tool.DESK,
	&"build_tool_scanner": Tool.SCANNER,
	&"build_tool_seats": Tool.SEATS,
	&"build_tool_remove": Tool.REMOVE,
	&"build_tool_glass": Tool.GLASS,
	&"build_tool_door": Tool.DOOR,
	&"build_tool_entrance": Tool.ENTRANCE,
	&"build_tool_exit": Tool.EXIT,
	&"build_tool_none": Tool.NONE,
}
const TOOL_OBJECTS := {
	Tool.DESK: &"checkin_desk",
	Tool.SCANNER: &"security_scanner",
	Tool.SEATS: &"seat_row",
	Tool.ENTRANCE: &"entrance_door",
	Tool.EXIT: &"exit_door",
	Tool.COUNTER: &"cafe_counter",
	Tool.TABLE: &"cafe_table",
	Tool.CART: &"baggage_cart",
	Tool.TRAY_TABLE: SecurityLanes.TRAY_TABLE,
	Tool.XRAY_BELT: SecurityLanes.XRAY_BELT,
	Tool.ARCH: SecurityLanes.ARCH,
	Tool.PICKUP_TABLE: SecurityLanes.PICKUP_TABLE,
	Tool.TOILET_STALL: &"toilet_stall",
	Tool.TOILET_SINK: &"toilet_sink",
	Tool.KIOSK_COUNTER: &"kiosk_counter",
	Tool.KIOSK_DISPLAY: &"kiosk_display",
	Tool.SCREEN: ScreenCoverage.SCREEN_ID,
	Tool.DUTY_FREE_TILL: &"duty_free_till",
	Tool.DUTY_FREE_SHELF: &"duty_free_shelf",
	Tool.FASHION_TILL: &"fashion_till",
	Tool.FASHION_RAIL: &"fashion_rail",
}
## The security lane part tools, in flow order.
const LANE_TOOLS: Array[Tool] = [Tool.TRAY_TABLE, Tool.XRAY_BELT, Tool.ARCH, Tool.PICKUP_TABLE]
## What one belt cell costs, whatever piece it becomes.
const BELT_PRICE_ID := &"baggage_belt"
const BELT_HINT := "Drag to lay a belt"
## The status line over a lane part that belongs to no arch.
const NOT_IN_LANE := "Not part of a lane"
## The status line over an item placed inside a room whose front cell falls
## outside it: the room does not count the item (FacilitySlots.piece_inside).
const FRONT_OUTSIDE_ROOM := "Its front is outside the room, so it will not count. R turns it"
## The status line while a rectangle drag is held by the pointer being over the
## HUD: the rectangle keeps its last size and a release applies that one.
const DRAG_OVER_UI := "Drag stops over the menu. Move back onto the floor to keep sizing"
## Tools that mark a dragged rectangle as a room of a RoomTypes id.
const TOOL_ROOMS := {
	Tool.CAFE_ROOM: &"cafe",
	Tool.BAG_ROOM: &"bag_room",
	Tool.TOILET_ROOM: &"toilet",
	Tool.KIOSK_ROOM: &"kiosk",
	Tool.PHARMACY_ROOM: &"pharmacy",
	Tool.DUTY_FREE_ROOM: &"duty_free",
	Tool.FASHION_ROOM: &"fashion",
}
## Tools under which the room under the pointer is followed for its panel.
const ROOM_FOCUS_TOOLS := [
	Tool.NONE,
	Tool.CAFE_ROOM,
	Tool.COUNTER,
	Tool.TABLE,
	Tool.BAG_ROOM,
	Tool.BELT,
	Tool.CART,
	Tool.TOILET_ROOM,
	Tool.TOILET_STALL,
	Tool.TOILET_SINK,
	Tool.KIOSK_ROOM,
	Tool.KIOSK_COUNTER,
	Tool.KIOSK_DISPLAY,
	Tool.PHARMACY_ROOM,
	Tool.PHARMACY_COUNTER,
	Tool.PHARMACY_SHELF,
	Tool.DUTY_FREE_ROOM,
	Tool.DUTY_FREE_TILL,
	Tool.DUTY_FREE_SHELF,
	Tool.FASHION_ROOM,
	Tool.FASHION_TILL,
	Tool.FASHION_RAIL,
]
const TOOL_WALL_KINDS := {
	Tool.WALL: BuildGrid.WallKind.PLAIN,
	Tool.GLASS: BuildGrid.WallKind.GLASS,
	Tool.DOOR: BuildGrid.WallKind.DOOR,
}
## The door tools by the name the status line uses for them.
const DOOR_NAMES := {Tool.ENTRANCE: "entrance", Tool.EXIT: "exit"}
## What the status line tells the player to do when a door tool is refused.
const DOOR_HINTS := {
	BuildResult.Reason.NO_FLOOR: "Put the %s on a floor tile at the outside edge",
	BuildResult.Reason.DOOR_NOT_ON_EDGE: "Put the %s on the outside edge of the floor",
	BuildResult.Reason.INTERACTION_BLOCKED: "Clear the floor in front of the %s",
	BuildResult.Reason.DOOR_WALLED: "Take down the glass or door wall behind the %s",
	BuildResult.Reason.WALL_HOLDS_DOOR: "The wall behind the %s holds a door; pick another spot",
}
## The status line for a door tool refused with DOOR_NOT_AT_SHELL_DOOR.
const SHELL_DOOR_HINTS := {
	Tool.ENTRANCE: "Put the entrance on one of the building's landside doors",
	Tool.EXIT: "Put the exit on one of the building's gate doors",
}
## Tools whose drag lays a straight row of edges, applied on release.
const DRAG_TOOLS := [Tool.WALL, Tool.GLASS]
## Tools whose drag is applied on release: a rectangle, or the Belt's line.
const AREA_TOOLS := [
	Tool.FLOOR,
	Tool.REMOVE,
	Tool.CAFE_ROOM,
	Tool.BAG_ROOM,
	Tool.TOILET_ROOM,
	Tool.KIOSK_ROOM,
	Tool.PHARMACY_ROOM,
	Tool.DUTY_FREE_ROOM,
	Tool.FASHION_ROOM,
	Tool.BELT,
]
## Zone id painted floors get. One terminal zone until zones become a tool.
const TERMINAL_ZONE := 1
## How close to an edge (in metres) the remove tool targets the wall there
## rather than the floor, once the line of sight found no wall (WallPick).
const WALL_PICK_DISTANCE := 0.4
## How far (screen pixels) the pointer may drift after a press before the press
## becomes a drag: a click that slips across a cell border is still a click.
const CLICK_SLOP_PX := 6.0
## How far past the pointer's ground point an object box still counts as seen
## (a box's floor face lies on the ground plane itself).
const SIGHT_SLACK_M := 0.001
const VALID_TINT := Color(0.35, 0.9, 0.45, 0.5)
const INVALID_TINT := Color(0.95, 0.3, 0.25, 0.5)
const MARKER_TINT := Color(1.0, 0.85, 0.3, 0.7)
const AREA_REMOVE_TINT := Color(0.95, 0.55, 0.2, 0.5)
## The cells a screen stand being placed would cover (ScreenCoverage; decision
## boredom-screens-are-floor-standing-screen-stands-placed-like).
const COVERAGE_TINT := Color(0.35, 0.65, 1.0, 0.35)

@export var grid_size := BuildGrid.DEFAULT_SIZE
## When true the grid is centred on the world origin at height 0 and
## grid_origin is not used.
@export var grid_centred := true
## World position of the grid's north-west corner, its floor height included.
@export var grid_origin := Vector3.ZERO
## The terminal shell the player builds inside. When set, the grid takes its
## frame (grid_size, grid_centred and grid_origin are not used), the Entrance
## and Exit tools snap to its doors and load_snapshot() checks a save fits it.
@export var shell: ShellDefinition
## The terminal shell's cutaway, drawn over the same shell. Remove does not
## pick an object the shell hides from the camera (ShellSight). main.tscn
## sets it; without it nothing hides an object but the grid's own walls.
@export var shell_view: ShellView
## Where building is paid from (BuildTransaction): a click or door costs its
## price, a Floor rectangle is all or nothing, a wall row stops when the
## money runs out, and removals refund a share of the saved price. main.tscn
## sets it. Without it the tools build for free and save no prices, the
## non-spending path tests and probes use.
@export var finances: Finances
## The landside the curb, car park and Close tools build on (Landside 3/4). main.tscn
## sets it; without it those tools do nothing.
@export var landside: LandsideSim

## The tool BuildMode starts on. main.tscn sets None, so a new game has no tool
## and a stray click on the world builds nothing; the Floor default keeps a bare
## BuildMode ready to paint for tests and probes.
@export var initial_tool := Tool.FLOOR:
	set(value):
		initial_tool = value
		tool = value

var grid: BuildGrid
var tool := Tool.FLOOR
var facing := 0
## Probe hook: a viewport point read in place of the real mouse by the hover
## and ghost. (-1, -1), the default, reads the mouse; nothing in the game sets it.
var pointer_override := Vector2(-1.0, -1.0)
## How many times the lane hint under the pointer was worked out afresh rather
## than reused; for the tests.
var lane_hint_scans := 0

## False once R is pressed, until a tool is picked again. While true, the
## door tools ignore `facing` and use DoorPlacement.auto_facing().
var _auto_facing := true
var _view := BuildView.new()
var _room_view := RoomView.new()
var _focus_room := 0
var _ghost := Node3D.new()
var _valid_material := _ghost_material(VALID_TINT)
var _invalid_material := _ghost_material(INVALID_TINT)
var _marker_material := _ghost_material(MARKER_TINT)
var _area_remove_material := _ghost_material(AREA_REMOVE_TINT)
var _coverage_material := _ghost_material(COVERAGE_TINT)
var _status := ""
var _hover_key := ""
var _hover_edit: BuildEdit
## What the status line adds for the lane part under the pointer ("" for none).
var _lane_hint := ""
## The hint last worked out and its cell; any grid edit drops it, so a pointer
## resting on a cell does not recognise the lanes again every frame.
var _hint_cell := Vector2i.ZERO
var _hint_cached := false
var _hint_cache := ""
## True while the pointer maps to a cell inside the grid, whether or not the
## picked tool makes an edit there (a room tool makes none before a drag).
var _pointer_on_grid := false
## True while a rectangle drag is on and the pointer is over a HUD Control.
var _area_over_ui := false
## What the status line adds for the item under the pointer when its front falls
## outside the room it stands in ("" for none).
var _front_warning := ""
var _area := AreaDrag.new()
## The Wall or Glass row being dragged, and the status line text it shows.
var _row := WallRowDrag.new()
var _row_label := ""
## Where the pointer was at the press that began a drag, and whether it has
## since moved CLICK_SLOP_PX away.
var _press_screen := Vector2.ZERO
var _drag_moved := false
## What the last rectangle or undo did, shown until the pointer leaves its cell.
var _status_note := ""
var _note_cell := Vector2i.ZERO
## The Belt line the ghost shows (the drag, or the cell under the pointer).
var _belt_plan: BeltShaper.Plan
## True while the grid holds a change the view has not drawn: an edit made
## straight on the grid (the debug starter, a playtest script) rather than
## through these tools, which redraw at once.
var _view_stale := false
var _history := UndoStack.new()
var _landside_placement := LandsidePlacement.new()
## What the landside tool under the pointer would do, or null (BuildMenu prices it).
var _landside_plan: LandsidePlacement.Plan


## Where a ray meets the level plane y = `height`, or null when it never does.
static func ground_point(from: Vector3, direction: Vector3, height := 0.0) -> Variant:
	return Plane(Vector3.UP, height).intersects_ray(from, direction)


static func _ghost_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _ready() -> void:
	if shell != null:
		grid = BuildGrid.new(shell.grid_size, shell.grid_origin)
	else:
		grid = BuildGrid.new(grid_size, null if grid_centred else grid_origin)
	grid.graph_changed.connect(_on_lane_graph_changed)
	grid.graph_changed.connect(_on_grid_drawn_cells_changed)
	_view.name = "BuildView"
	add_child(_view)
	_redraw()
	_room_view.name = "RoomView"
	add_child(_room_view)
	_room_view.watch(grid)
	_ghost.name = "Ghost"
	add_child(_ghost)
	if finances != null:
		finances.wallet.changed.connect(_on_balance_changed)
	_history.watch(grid, wallet())
	set_tool(tool)


func _process(_delta: float) -> void:
	var point: Variant = _mouse_ground()
	# Over a HUD Control the pointer is not over the world: no ghost, no hover.
	# A rectangle in progress stays, hidden, until the pointer is back.
	var over_ui := _pointer_over_ui()
	_area_over_ui = over_ui and _drag_active()
	if not over_ui:
		_update_ghost(point)
	elif _drag_active():
		_hide_area_ghost()
	else:
		_update_ghost(null)
	update_room_focus(point)


## A rectangle in progress is dropped when the window loses focus, because
## the release will not reach it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_area()


## A drag's release is caught here, ahead of the HUD: a Control under the
## pointer takes the release before _unhandled_input sees it, which would leave
## the drag open with nothing applied.
func _input(event: InputEvent) -> void:
	if _drag_active() and event.is_action_released("build_apply"):
		finish_area()
		finish_row()


func _unhandled_input(event: InputEvent) -> void:
	if _drag_active() and _cancels_area(event):
		cancel_area()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_undo"):
		undo()
		get_viewport().set_input_as_handled()
		return
	for action in TOOL_ACTIONS:
		if event.is_action_pressed(action):
			set_tool(TOOL_ACTIONS[action])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("build_rotate"):
		rotate_facing()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_apply"):
		var point: Variant = _mouse_ground()
		_press_screen = _pointer_position()
		_drag_moved = false
		if point != null and AREA_TOOLS.has(tool):
			begin_area(point)
		elif point != null and DRAG_TOOLS.has(tool):
			begin_row(point)
		elif point != null:
			apply_at(point)
	elif event.is_action_released("build_apply"):
		finish_area()
		finish_row()
	elif event is InputEventMouseMotion and _drag_active():
		var point: Variant = _mouse_ground()
		if point == null or _pointer_over_ui():
			return
		if not _drag_moved:
			if _pointer_position().distance_to(_press_screen) < CLICK_SLOP_PX:
				return
			_drag_moved = true
		if _area.active:
			move_area(point)
		else:
			move_row(point)


## Picks a tool.
func set_tool(new_tool: Tool) -> void:
	cancel_area()
	tool = new_tool
	_auto_facing = true
	_hover_key = ""
	_hover_edit = null
	_show_status(null)
	tool_changed.emit(tool)


func rotate_facing() -> void:
	cancel_area()
	_auto_facing = false
	facing = (facing + 1) % 4
	_hover_key = ""
	_show_status(null)


## Where a ray meets this grid's floor (its origin's height), or null.
func grid_point(from: Vector3, direction: Vector3) -> Variant:
	return ground_point(from, direction, grid.origin.y)


## The catalog id a tool places: TOOL_OBJECTS, or FurnitureTools.OBJECTS for the
## furniture tools. &"" for a tool that places no object.
static func tool_object(for_tool: Tool) -> StringName:
	return TOOL_OBJECTS.get(for_tool, FurnitureTools.OBJECTS.get(for_tool, &""))


## The edit the current tool would make at a ground point, or null for none.
func edit_at(point: Vector3) -> BuildEdit:
	var cell := grid.world_to_cell(point)
	var side: int = grid.nearest_side(point)
	match tool:
		Tool.FLOOR:
			return BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, TERMINAL_ZONE)
		Tool.REMOVE:
			return _removal_at(point, cell, side)
	if TOOL_WALL_KINDS.has(tool):
		return BuildEdit.place_wall(cell, side, TOOL_WALL_KINDS[tool])
	var def_id := tool_object(tool)
	if def_id != &"":
		if shell != null and DOOR_NAMES.has(tool):
			var door := shell.nearest(grid, def_id, point)
			if door != null:
				return BuildEdit.place_object(def_id, door.cell, door.facing)
		var turn := facing
		if _facing_is_auto():
			turn = DoorPlacement.auto_facing(grid, def_id, point, facing)
		return BuildEdit.place_object(def_id, cell, turn)
	return null


## Applies the current tool at a ground point, paid through BuildTransaction,
## and redraws on success. Returns null when nothing was attempted. One undo
## step.
func apply_at(point: Vector3) -> BuildResult:
	# A landside action is not a grid action: it keeps its own undo record.
	var landside_plan := landside_plan_at(point)
	if landside_plan != null or _is_landside_tool():
		return _apply_landside(landside_plan)
	_history.begin_action()
	var result := _apply_at(point)
	_history.end_action()
	return result


func _apply_at(point: Vector3) -> BuildResult:
	var edit := edit_at(point)
	if edit == null:
		return null
	var warning := front_warning(grid, edit)
	var result := check(edit)
	var refused_by_check := not result.ok
	if result.ok:
		# A removed room's cells, read before it is gone: its dead ends change.
		var touched: Array[Vector2i] = []
		if edit.kind == BuildEdit.Kind.REMOVE_ROOM:
			touched = _rect_cells(grid.get_room(edit.room_id).get("rect", Rect2i()))
		# The edit and the reshape it causes reach listeners as one change.
		grid.hold_signals()
		result = BuildTransaction.commit_plan(grid, DoorPlacement.edits_for(grid, edit), wallet())
		if result.ok:
			touched.append_array(result.dirty_cells)
			_reshape_belts(touched)
		grid.release_signals()
	if result.ok:
		_redraw()
		_hover_key = ""
		grid_changed.emit()
		if warning != "":
			_status_note = warning
			_note_cell = edit.cell
	_show_status(result)
	# A refusal from the grid or the transaction (inside commit_plan()) was
	# emitted there.
	if refused_by_check:
		grid.edit_refused.emit(edit, result)
	return result


## Starts a Floor or Remove rectangle on the cell under a ground point. A press
## outside the grid is a plain click, which the grid refuses with its reason.
func begin_area(point: Vector3) -> void:
	var cell := grid.world_to_cell(point)
	if not grid.in_bounds(cell):
		if tool == Tool.BELT:
			_show_status(BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS))
			return
		apply_at(point)
		return
	_status_note = ""
	_area.begin(cell, point, grid.size)
	_hover_key = ""


## Starts a Wall or Glass row on the cell under a ground point, on the edge side
## nearest the point. A press outside the grid is a plain click, which the grid
## refuses with its reason.
func begin_row(point: Vector3) -> void:
	if not DRAG_TOOLS.has(tool):
		return
	var cell := grid.world_to_cell(point)
	if not grid.in_bounds(cell):
		apply_at(point)
		return
	_status_note = ""
	_row.begin(cell, grid.nearest_side(point), grid.size)
	_hover_key = ""


## Stretches the row to the cell under a ground point.
func move_row(point: Vector3) -> void:
	if _row.active:
		_row.move(grid.world_to_cell(point))


## Lays the row (WallRowDrag.apply()): every edge the rules accept, stopping
## where the money runs out, as one undo step. A drag that never left its cell
## lays the one edge, as a click. Returns what the row did, or null with no
## row. The status line says how many edges were placed, what they cost and
## why any was skipped.
func finish_row() -> AreaDrag.Outcome:
	if not _row.active:
		return null
	_history.begin_action()
	_row.cancel()
	_hover_key = ""
	var dirty: Array[Vector2i] = []
	var outcome := WallRowDrag.apply(grid, _row_edits(), check, wallet(), dirty)
	if outcome.placed > 0:
		_reshape_belts(dirty)
		_redraw()
		grid_changed.emit()
	_history.end_action()
	_status_note = outcome.message()
	_note_cell = _row.end_cell()
	_show_status(null)
	return outcome


func _row_edits() -> Array[BuildEdit]:
	return _row.edits(TOOL_WALL_KINDS[tool])


## True while a rectangle or a wall row is being dragged.
func _drag_active() -> bool:
	return _area.active or _row.active


## The edit under the pointer, or null (BuildMenu prices it for the cost line).
func hover_edit() -> BuildEdit:
	return _hover_edit


## True while the pointer is over a cell of the grid (BuildMenu shows its status
## line only then); false with no hover yet, over the HUD or outside the grid.
## A landside tool works on the ground outside the grid, so for it this is true
## while the pointer is over the ground.
func pointer_on_grid() -> bool:
	return _pointer_on_grid


## True while a rectangle drag is on and the pointer is over the HUD, where the
## rectangle stops growing (BuildMenu keeps the status line, which says why,
## visible).
func drag_held_by_ui() -> bool:
	return _area_over_ui and _drag_active()


## The rectangle being dragged, or an empty Rect2i when no rectangle drag is on
## (BuildMenu prices it for the cost line).
func dragged_area() -> Rect2i:
	return _area.rect() if _area.active else Rect2i()


## Stretches the rectangle to the cell under a ground point.
func move_area(point: Vector3) -> void:
	if _area.active:
		_area.move(grid.world_to_cell(point))


## Applies the rectangle. A drag that never left its cell is applied as the
## single click it is, at the press point (which marks no room). Returns what
## a Floor or Remove rectangle did, or null when there was no rectangle, it
## was a click or it marked a room. One undo step.
func finish_area() -> AreaDrag.Outcome:
	_history.begin_action()
	var outcome := _finish_area()
	_history.end_action()
	return outcome


func _finish_area() -> AreaDrag.Outcome:
	if not _area.active:
		return null
	_area.cancel()
	_hover_key = ""
	if tool == Tool.BELT:
		lay_belt(_area.start_cell(), _area.end_cell())
		return null
	if _area.is_single_cell():
		apply_at(_area.press_point)
		return null
	if TOOL_ROOMS.has(tool):
		_finish_room()
		return null
	var outcome: AreaDrag.Outcome
	if tool == Tool.REMOVE:
		var touched := _cells_a_clear_touches(_area.rect())
		grid.hold_signals()
		outcome = AreaDrag.clear(grid, _area.rect(), wallet())
		if outcome.placed > 0:
			_reshape_belts(touched)
		grid.release_signals()
	else:
		outcome = AreaDrag.fill_floor(grid, _area.rect(), TERMINAL_ZONE, wallet())
	if outcome.placed > 0:
		_redraw()
		grid_changed.emit()
	_status_note = outcome.message()
	_note_cell = _area.end_cell()
	_show_status(null)
	return outcome


## Marks the released rectangle as a room of the current room tool's type.
func _finish_room() -> void:
	var type: StringName = TOOL_ROOMS[tool]
	grid.hold_signals()
	var result := RoomTool.mark(grid, _area.rect(), type, wallet())
	if result.ok:
		_reshape_belts(_rect_cells(_area.rect()))
	grid.release_signals()
	if result.ok:
		grid_changed.emit()
	_status_note = RoomTool.message(grid, result, type)
	_note_cell = _area.end_cell()
	_show_status(null)


## Lays a belt line from cell `from` to cell `to` (BeltShaper.path()): buys a
## plain belt on each path cell that has none, at the belt price, and shapes
## them and the belts next to them, all in one plan. Refused whole when a cell
## cannot take a belt, a wall crosses the line, a belt would get a fourth link
## or the wallet cannot pay. A line over belt only does nothing. One undo step.
func lay_belt(from: Vector2i, to: Vector2i) -> BuildResult:
	_history.begin_action()
	var result := _lay_belt(from, to)
	_history.end_action()
	return result


func _lay_belt(from: Vector2i, to: Vector2i) -> BuildResult:
	var plan := BeltShaper.plan_line(grid, from, to, facing)
	var result := plan.result
	if result.ok and not plan.edits.is_empty():
		result = BuildTransaction.commit_plan(grid, plan.edits, wallet())
	if result.ok and not plan.edits.is_empty():
		_redraw()
		grid_changed.emit()
	_belt_plan = null
	_hover_key = ""
	_show_status(result)
	if not plan.result.ok:
		grid.edit_refused.emit(BuildEdit.place_object(BELT_PRICE_ID, to, facing), result)
	return result


## Undoes the last build action and its money (UndoStack.undo()), dropping a
## rectangle or row in progress first. The status line says it was undone,
## why it was refused (nothing changed) or that there is nothing to undo, until
## the pointer leaves its cell. Returns the result, or null with no history.
func undo() -> BuildResult:
	cancel_area()
	var landside_first := landside_placement().has_undo_for(_history.peek())
	var result := _landside_placement.undo() if landside_first else _history.undo(shell)
	if result == null:
		_status_note = UndoStack.NOTHING_TO_UNDO
	elif result.ok:
		_status_note = UndoStack.UNDONE
		_redraw()
		grid_changed.emit()
	else:
		_status_note = UndoStack.CANT_UNDO
		if result.reason_text() != "":
			_status_note += ": " + result.reason_text()
	var point: Variant = _mouse_ground()
	if point != null:
		_note_cell = grid.world_to_cell(point)
	_hover_key = ""
	if landside_first:
		# The landside hover keeps this note until the pointer meets another plan.
		_hover_key = _landside_key(landside_plan_at(point))
	_show_status(null)
	return result


## Forgets every action that could be undone, the grid's and the landside's
## (BuildSession calls it when build mode ends).
func clear_undo() -> void:
	_history.clear()
	_landside_placement.clear_undo()


## The undo history, newest action on top (read it, never change it).
func undo_history() -> UndoStack:
	return _history


## How many belt cells the line under the pointer (or being dragged) would buy;
## 0 when it is refused or no Belt line is shown (BuildMenu prices it).
func belt_cells_to_buy() -> int:
	if tool != Tool.BELT or _belt_plan == null or not _belt_plan.result.ok:
		return 0
	return _belt_plan.new_cells.size()


## Reshapes the belts on and next to `cells` to fit their links (BeltShaper):
## free RESHAPE_BELT edits, committed through BuildTransaction so they reach
## listeners like any edit.
func _reshape_belts(cells: Array[Vector2i]) -> void:
	var edits := BeltShaper.reshape_edits(grid, BeltShaper.around(cells))
	if edits.is_empty():
		return
	BuildTransaction.commit_plan(grid, edits, wallet())
	_redraw()


## The cells a Remove rectangle over `area` can change the belts next to, read
## before it clears: the rectangle, the whole footprint of each object reaching
## into it (a desk's outlet sits beside its far cell) and every bag room that
## reaches into or touches it.
func _cells_a_clear_touches(area: Rect2i) -> Array[Vector2i]:
	var cells := _rect_cells(area)
	var seen := {}
	for cell in _rect_cells(area):
		var object_id := grid.object_at(cell) if grid.in_bounds(cell) else 0
		if object_id == 0 or seen.has(object_id):
			continue
		seen[object_id] = true
		var record := grid.get_object(object_id)
		var def := BuildCatalog.get_def(record["def"])
		cells.append_array(def.footprint(record["anchor"], record["facing"]))
	for room_id in grid.room_ids():
		var room := grid.get_room(room_id)
		if room["type"] == &"bag_room" and (room["rect"] as Rect2i).intersects(area.grow(1)):
			cells.append_array(_rect_cells(room["rect"]))
	return cells


static func _rect_cells(area: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			cells.append(Vector2i(x, y))
	return cells


## Follows the room under a ground point (null for none) while a room-focus
## tool is picked; any other tool follows no room. Emits room_focus_changed
## when the room changes, including when the followed room is removed.
func update_room_focus(point: Variant) -> void:
	var room_id := 0
	if point != null and ROOM_FOCUS_TOOLS.has(tool) and not _pointer_over_ui():
		room_id = grid.room_at(grid.world_to_cell(point))
	if room_id != _focus_room:
		_focus_room = room_id
		room_focus_changed.emit(room_id)


## The room the info panel shows, 0 for none.
func focused_room() -> int:
	return _focus_room


## Drops the rectangle or row being dragged with nothing applied.
func cancel_area() -> void:
	if not _drag_active():
		return
	_area.cancel()
	_row.cancel()
	_hover_key = ""
	_show_status(null)


## The text on the status line.
func status_text() -> String:
	return _status


## The wallet building is paid from, or null when the tools build for free.
func wallet() -> Wallet:
	return finances.wallet if finances != null else null


## BuildGrid.validate() plus the entrance and exit rules (DoorPlacement.check()),
## no belt crossing and no lane part across a wall (LaneWall), then whether the
## wallet can pay for the edits it takes (BuildTransaction.check(), CANT_AFFORD).
func check(edit: BuildEdit) -> BuildResult:
	var result := DoorPlacement.check(grid, edit, shell)
	if not result.ok:
		return result
	var crossing := BeltShaper.crossing_problem(grid, edit)
	if crossing != null:
		return crossing
	var lane_wall := LaneWall.problem(grid, edit)
	if lane_wall != null:
		return lane_wall
	return BuildTransaction.check(grid, DoorPlacement.edits_for(grid, edit), wallet())


## Restores a BuildGrid.to_snapshot() dictionary into the grid and redraws.
## With a shell, a save that does not fit it is refused first
## (ShellDefinition.snapshot_problem()). Pushes an error and returns false,
## leaving the grid as it was, on any refusal. A load never spends or
## credits: it bypasses BuildTransaction and keeps the saved purchase prices.
## It clears the undo history.
func load_snapshot(data: Dictionary) -> bool:
	var problem := shell.snapshot_problem(data) if shell != null else ""
	if problem != "":
		push_error("BuildMode.load_snapshot: %s" % problem)
		return false
	if not grid.from_snapshot(data):
		return false
	clear_undo()
	_redraw()
	_hover_key = ""
	grid_changed.emit()
	return true


## A changed balance can change whether the ghost's edit is affordable, so the
## ghost is checked again.
func _on_balance_changed(_balance: int) -> void:
	_hover_key = ""


func _cancels_area(event: InputEvent) -> bool:
	if event.is_action_pressed("build_tool_none"):
		return true
	var click := event as InputEventMouseButton
	return click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT


## A door tool picks its own facing until R is pressed; inside a shell, always.
func _facing_is_auto() -> bool:
	return (_auto_facing or shell != null) and DOOR_NAMES.has(tool)


## What Remove takes at a ground point: the object the pointer is on (seen
## from the camera, or on the point's cell unless the terminal shell hides the
## point, see ShellSight), then the wall the line of sight to the point meets
## (WallPick), then a wall edge within WALL_PICK_DISTANCE of the point, then the
## room, then the floor. A wall in the way hides the object by cell behind it.
func _removal_at(point: Vector3, cell: Vector2i, side: int) -> BuildEdit:
	var object_id := _object_in_sight(point)
	var camera := get_viewport().get_camera_3d()
	var seen_wall := _wall_in_line_of_sight(camera, point)
	if object_id == 0 and seen_wall.z < 0:
		if not ShellSight.hides_point(shell_view, grid, camera, point):
			object_id = grid.object_at(cell)
	if object_id != 0:
		return BuildEdit.remove_object(object_id)
	if seen_wall.z >= 0:
		return BuildEdit.remove_wall(Vector2i(seen_wall.x, seen_wall.y), seen_wall.z)
	var offset := point - grid.cell_to_world(cell)
	var to_edge := 0.5 - maxf(absf(offset.x), absf(offset.z))
	if grid.has_wall(cell, side) and to_edge <= WALL_PICK_DISTANCE:
		return BuildEdit.remove_wall(cell, side)
	if grid.room_at(cell) != 0:
		return BuildEdit.remove_room(grid.room_at(cell))
	return BuildEdit.remove_floor(cell)


## The wall edge (WallCutaway.wall_edges form) the camera's line of sight to a
## ground point meets first (WallPick), or an edge whose z is -1 for none, also
## with no camera or the point behind it.
func _wall_in_line_of_sight(camera: Camera3D, point: Vector3) -> Vector3i:
	if camera == null or camera.is_position_behind(point):
		return WallPick.NO_EDGE
	var from := camera.project_ray_origin(camera.unproject_position(point))
	return WallPick.first_wall(grid, _view, from, point)


## The object the camera's line of sight to a ground point meets first, or 0
## (also 0 with no camera, or the point behind it). Each object is a box over
## its footprint as tall as it is drawn (BuildView.pick_height). A tall object
## hides the ground behind it on screen, so a click on it picks a ground point
## beyond it, maybe beside a wall edge; the object the player sees under the
## pointer wins. An object behind a wall the view draws opaque
## (_wall_in_sight) or behind the terminal shell (ShellSight) is not seen.
func _object_in_sight(point: Vector3) -> int:
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(point):
		return 0
	var from := camera.project_ray_origin(camera.unproject_position(point))
	var reach := from.distance_to(point)
	if reach <= 0.0:
		return 0
	var direction := (point - from) / reach
	var nearest := reach + SIGHT_SLACK_M
	var seen := 0
	for object_id in grid.object_ids():
		var hit: Variant = _object_box(object_id).intersects_ray(from, direction)
		if hit == null:
			continue
		var distance := from.distance_to(hit)
		if distance < nearest:
			nearest = distance
			seen = object_id
	if seen != 0 and nearest >= _wall_in_sight(from, point) - SIGHT_SLACK_M:
		return 0
	if seen != 0 and ShellSight.in_sight(shell_view, grid, from, point):
		return 0
	return seen


## A placed object's footprint, from the floor up to its drawn height.
func _object_box(object_id: int) -> AABB:
	var record := grid.get_object(object_id)
	var def := BuildCatalog.get_def(record["def"])
	var cells := def.footprint(record["anchor"], record["facing"])
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for at in cells:
		low = Vector2i(mini(low.x, at.x), mini(low.y, at.y))
		high = Vector2i(maxi(high.x, at.x), maxi(high.y, at.y))
	var corner := grid.origin + Vector3(low.x, 0.0, low.y)
	var extent := Vector3(high.x - low.x + 1, BuildView.pick_height(def), high.y - low.y + 1)
	return AABB(corner, extent)


## How far from `from`, on the straight line to `to`, the first wall edge the
## view draws opaque (BuildView.sight_blocked) stands in the way, or INF. The
## line is walked across the grid lines it crosses, so the cost grows with the
## grid's width, not with the number of walls.
func _wall_in_sight(from: Vector3, to: Vector3) -> float:
	var start := from - grid.origin
	var span := to - from
	var nearest := INF
	for axis in [0, 2]:
		if absf(span[axis]) < 0.000001:
			continue
		var cells := grid.size.x if axis == 0 else grid.size.y
		var low := maxi(0, ceili(minf(start[axis], start[axis] + span[axis])))
		var high := mini(cells, floori(maxf(start[axis], start[axis] + span[axis])))
		for line in range(low, high + 1):
			var t := (line - start[axis]) / span[axis]
			var at := start + span * t
			var edge := WallPick.edge_on_line(grid, axis, line, at)
			if edge.z >= 0 and _view.sight_blocked(edge, fposmod(at[2 - axis], 1.0) - 0.5, at.y):
				nearest = minf(nearest, t * span.length())
	return nearest


## Whether the pointer is over a HUD control, which hides the world under it.
func _pointer_over_ui() -> bool:
	if pointer_override.x >= 0.0:
		return false
	return get_viewport().gui_get_hovered_control() != null


## Where the pointer is, in viewport coordinates: pointer_override when set.
func _pointer_position() -> Vector2:
	return pointer_override if pointer_override.x >= 0.0 else get_viewport().get_mouse_position()


func _mouse_ground() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := _pointer_position()
	var from := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if _is_landside_tool():
		return LandsidePlacement.ground_point(from, direction)
	var point: Variant = grid_point(from, direction)
	# Remove also takes a built landside spot, which stands off the grid, on the
	# ground plane.
	if tool == Tool.REMOVE and point != null and not grid.in_bounds(grid.world_to_cell(point)):
		return LandsidePlacement.ground_point(from, direction)
	return point


func _update_ghost(point: Variant) -> void:
	_pointer_on_grid = point != null and grid.in_bounds(grid.world_to_cell(point))
	_landside_plan = null if _drag_active() else landside_plan_at(point)
	if _landside_plan != null or _is_landside_tool():
		_pointer_on_grid = point != null
		_hover_landside(_landside_plan)
		return
	if _area.active:
		_draw_area()
		return
	if _row.active:
		_draw_row()
		return
	if _status_note != "" and (point == null or grid.world_to_cell(point) != _note_cell):
		_status_note = ""
		_hover_key = ""
		_show_status(null)
	if tool == Tool.BELT:
		_hover_belt(point)
		return
	var edit: BuildEdit = null if point == null else edit_at(point)
	_hover_edit = edit
	var hint := "" if point == null else _lane_hint_at(grid.world_to_cell(point))
	if edit == null:
		_ghost.visible = false
		_front_warning = ""
		var idle_key := "" if hint == "" else "lane:" + hint
		if _hover_key != idle_key:
			_hover_key = idle_key
			_lane_hint = hint
			_show_status(null)
		return
	var warning := front_warning(grid, edit)
	var key := _edit_key(edit) + "|" + hint + "|" + warning
	if key == _hover_key:
		return
	_hover_key = key
	_lane_hint = hint
	var result := check(edit)
	_front_warning = warning if result.ok else ""
	var valid := _area_remove_material if tool == Tool.REMOVE else _valid_material
	_draw_ghost(edit, valid if result.ok else _invalid_material)
	_show_status(result)


## The landside tools' rules (LandsidePlacement) for the sim, shell and wallet
## BuildMode has now.
func landside_placement() -> LandsidePlacement:
	_landside_placement.sim = landside
	_landside_placement.shell = shell
	_landside_placement.wallet = wallet()
	return _landside_placement


## What the current tool would do on the landside at a ground point (picked on
## the y = 0 plane): a curb or car park tool snaps to the nearest free spot of
## its kind or says why not, the Close tool finds the car park under it, and
## Remove, off the grid, finds the built spot under it. Null for any other
## tool or point, and for a spot-less pointer.
func landside_plan_at(point: Variant) -> LandsidePlacement.Plan:
	if point == null:
		return null
	var placement := landside_placement()
	if LANDSIDE_BUILD_TOOLS.has(tool):
		return placement.plan_build(LANDSIDE_BUILD_TOOLS[tool], point)
	if tool == Tool.LOT_GATE:
		return placement.plan_toggle(point)
	if tool == Tool.REMOVE and not grid.in_bounds(grid.world_to_cell(point)):
		return placement.plan_remove(point)
	return null


## (cost, money the wallet must hold) of the landside build under the pointer,
## zero for anything else (BuildMenu's cost line).
func landside_preview_price() -> Vector2i:
	if _landside_plan == null or _landside_plan.action != LandsidePlacement.Action.BUILD:
		return Vector2i.ZERO
	return Vector2i(_landside_plan.price, _landside_plan.price)


func _is_landside_tool() -> bool:
	return LANDSIDE_BUILD_TOOLS.has(tool) or tool == Tool.LOT_GATE


## Ghosts and describes a landside plan: the free spots of the tool's kind in
## the marker tint, the spot under the pointer valid or invalid, and its
## capacity, walk and price on the status line.
func _hover_landside(plan: LandsidePlacement.Plan) -> void:
	var key := _landside_key(plan)
	if key == _hover_key:
		return
	_hover_key = key
	_status_note = ""
	_clear_ghost()
	if plan == null:
		_ghost.visible = false
		_set_status("")
		return
	var spots: Array[LandsidePlacement.Plan] = []
	if LANDSIDE_BUILD_TOOLS.has(tool):
		spots = landside_placement().free_spot_plans(LANDSIDE_BUILD_TOOLS[tool])
	var valid := _area_remove_material if tool == Tool.REMOVE else _valid_material
	LandsidePlacement.draw(_ghost, spots, plan, valid, _invalid_material, _marker_material)
	_set_status(plan.text)


func _landside_key(plan: LandsidePlacement.Plan) -> String:
	return "landside:%d:%s" % [tool, "none" if plan == null else plan.text]


## Applies a landside plan (null when the tool has no landside to build on).
## Landside actions keep their own undo records (LandsidePlacement.apply()).
func _apply_landside(plan: LandsidePlacement.Plan) -> BuildResult:
	var result := landside_placement().apply(plan, _history.peek())
	_hover_key = ""
	_status_note = ""
	return result


## Hides the rectangle's slab and size while the pointer is over the HUD; the
## cleared hover key makes _draw_area() draw both again on the way back.
func _hide_area_ghost() -> void:
	_pointer_on_grid = false
	_ghost.visible = false
	_hover_key = ""
	_set_status(DRAG_OVER_UI)


## The Belt ghost for the one cell under the pointer, or none off the grid.
func _hover_belt(point: Variant) -> void:
	_hover_edit = null
	if not _pointer_on_grid:
		_belt_plan = null
		_ghost.visible = false
		if _hover_key != "":
			_hover_key = ""
			_show_status(null)
		return
	var cell := grid.world_to_cell(point)
	_draw_belt(cell, cell)


## The shaped pieces a Belt line from `from` to `to` would lay or reshape,
## tinted by whether it can be laid; a refused line tints its cells instead.
func _draw_belt(from: Vector2i, to: Vector2i) -> void:
	var key := "belt:%s:%s:%d" % [from, to, facing]
	if key == _hover_key:
		return
	_hover_key = key
	_belt_plan = BeltShaper.plan_line(grid, from, to, facing)
	var result := _belt_plan.result
	if result.ok:
		result = BuildTransaction.check(grid, _belt_plan.edits, wallet())
	_clear_ghost()
	var material := _valid_material if result.ok else _invalid_material
	if _belt_plan.result.ok:
		for piece in _belt_plan.shapes:
			_ghost_object(piece[0], piece[1], piece[2], material)
	else:
		for cell in _belt_plan.cells:
			if grid.in_bounds(cell):
				_ghost_tile(cell, material)
	_show_status(result)


## The whole row a Wall or Glass drag would lay, one box per edge tinted by
## whether it would be placed, with its length and cost on the status line.
func _draw_row() -> void:
	var cells := _row.cells()
	var purse := wallet()
	var key := "row:%s:%s:%d:%d" % [cells.front(), cells.back(), _row.side, tool]
	if purse != null:
		key += ":%d" % purse.balance
	if key == _hover_key:
		return
	_hover_key = key
	_hover_edit = null
	var plan := WallRowDrag.preview(grid, _row_edits(), check, purse)
	_clear_ghost()
	for i in plan.edits.size():
		var material := _valid_material if plan.valid[i] else _invalid_material
		_ghost_wall(plan.edits[i].cell, plan.edits[i].side, material)
	_row_label = "%s row of %d" % ["Glass" if tool == Tool.GLASS else "Wall", cells.size()]
	_row_label += ", cost %d" % plan.cost
	if plan.blocked > 0:
		_row_label += ", %d blocked: %s" % [plan.blocked, plan.first_reason]
	_show_status(null)


## One tinted slab over the whole rectangle, with its size on the status line.
func _draw_area() -> void:
	if tool == Tool.BELT:
		_draw_belt(_area.start_cell(), _area.end_cell())
		return
	var area := _area.rect()
	var purse := wallet()
	var key := "area:%s" % area
	if tool == Tool.FLOOR and purse != null:
		key += ":%d" % purse.balance
	if key == _hover_key:
		return
	_hover_key = key
	_clear_ghost()
	var material := _area_remove_material if tool == Tool.REMOVE else _valid_material
	if TOOL_ROOMS.has(tool) and not RoomTool.check(grid, area, TOOL_ROOMS[tool]).ok:
		material = _invalid_material
	# A floor rectangle the wallet cannot pay for lays nothing (CANT_AFFORD).
	if tool == Tool.FLOOR and purse != null and AreaDrag.floor_cost(grid, area) > purse.balance:
		material = _invalid_material
	_ghost_slab(area, material)
	_show_status(null)


func _clear_ghost() -> void:
	for child in _ghost.get_children():
		child.queue_free()
	_ghost.visible = true


func _draw_ghost(edit: BuildEdit, material: Material) -> void:
	_clear_ghost()
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR, BuildEdit.Kind.REMOVE_FLOOR:
			_ghost_tile(edit.cell, material)
		BuildEdit.Kind.PLACE_WALL, BuildEdit.Kind.REMOVE_WALL:
			# A wall about to be removed is drawn bigger, so it reads at range.
			_ghost_wall(edit.cell, edit.side, material, 2.0 if tool == Tool.REMOVE else 1.0)
		BuildEdit.Kind.PLACE_OBJECT:
			_ghost_object(edit.def_id, edit.cell, edit.facing, material)
			for cell in coverage_preview(edit):
				_ghost_tile(cell, _coverage_material).name = "Coverage"
		BuildEdit.Kind.REMOVE_OBJECT:
			var record := grid.get_object(edit.object_id)
			_ghost_object(record["def"], record["anchor"], record["facing"], material)
		BuildEdit.Kind.REMOVE_ROOM:
			_ghost_slab(grid.get_room(edit.room_id)["rect"], material)


## A tinted box over the wall edge of `cell` on `side`; `grow` thickens it.
func _ghost_wall(cell: Vector2i, side: int, material: Material, grow := 1.0) -> void:
	var extent := Vector3(1.0, BuildView.WALL_HEIGHT, BuildView.WALL_THICKNESS * 1.5 * grow)
	if grow > 1.0:
		extent += Vector3(0.04, 0.1, 0.0)
	var wall := _ghost_box(extent, material)
	wall.transform = BuildView.wall_transform(grid, cell, side).translated_local(
		Vector3(0.0, extent.y / 2.0, 0.0)
	)


func _ghost_object(def_id: StringName, anchor: Vector2i, turn: int, material: Material) -> void:
	var def := BuildCatalog.get_def(def_id)
	var node := BuildView.make_object_node(def, material)
	node.transform = BuildView.object_transform(grid, def.footprint(anchor, turn), turn)
	node.scale = Vector3.ONE * 1.02
	_ghost.add_child(node)
	var spot := def.interaction_cell(anchor, turn)
	if spot != BuildObjectDef.NO_CELL:
		_ghost_tile(spot, _marker_material)


## The cells the ghost tints as covered while `edit` places a screen stand:
## ScreenCoverage.covered_cells() where it would stand; empty for any other edit.
func coverage_preview(edit: BuildEdit) -> Array[Vector2i]:
	if edit.kind != BuildEdit.Kind.PLACE_OBJECT or edit.def_id != ScreenCoverage.SCREEN_ID:
		return []
	return ScreenCoverage.covered_cells(grid, edit.cell, edit.facing)


func _ghost_tile(cell: Vector2i, material: Material) -> MeshInstance3D:
	var tile := _ghost_box(Vector3(0.96, 0.08, 0.96), material)
	tile.position = grid.cell_to_world(cell) + Vector3(0.0, 0.06, 0.0)
	return tile


## One tinted slab over a rectangle of cells.
func _ghost_slab(area: Rect2i, material: Material) -> void:
	var slab := _ghost_box(Vector3(area.size.x - 0.04, 0.08, area.size.y - 0.04), material)
	slab.position = (
		grid.cell_to_world(area.position)
		+ Vector3((area.size.x - 1) / 2.0, 0.06, (area.size.y - 1) / 2.0)
	)


func _ghost_box(extent: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = extent
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = material
	_ghost.add_child(box)
	return box


func _edit_key(edit: BuildEdit) -> String:
	return (
		"%d:%s:%d:%d:%d:%s:%s"
		% [
			edit.kind,
			edit.cell,
			edit.side,
			edit.wall_kind,
			edit.facing,
			edit.object_id,
			edit.room_id
		]
	)


func _show_status(result: BuildResult) -> void:
	if _row.active:
		_set_status(_row_label)
		return
	if _area.active and TOOL_ROOMS.has(tool):
		_set_status(RoomTool.drag_label(grid, _area.rect(), TOOL_ROOMS[tool]))
		return
	# An undo's note shows under the Belt tool too.
	if _status_note != "" and not _area.active:
		_set_status(_status_note)
		return
	if tool == Tool.BELT:
		var text := BELT_HINT
		if _area.active and _belt_plan != null:
			text = "Belt %d cells" % _belt_plan.cells.size()
		if result != null and not result.ok:
			text += "  " + result.reason_text()
		_set_status(text)
		return
	if _area.active:
		_set_status(_area.size_label())
		return
	var text := RoomTool.hint(TOOL_ROOMS[tool]) if TOOL_ROOMS.has(tool) else ""
	var refused := result != null and not result.ok
	# The facing is for an item that can be placed; a refusal shows its reason alone.
	if tool_object(tool) != &"" and not refused:
		text = "Facing auto" if _facing_is_auto() else "Facing %d" % facing
	if refused:
		var reason := result.reason_text()
		if DOOR_NAMES.has(tool) and result.reason == BuildResult.Reason.DOOR_NOT_AT_SHELL_DOOR:
			reason = SHELL_DOOR_HINTS[tool]
		elif DOOR_NAMES.has(tool) and DOOR_HINTS.has(result.reason):
			reason = DOOR_HINTS[result.reason] % DOOR_NAMES[tool]
		text += ("  " if text != "" else "") + reason
	if _front_warning != "" and not refused:
		text += ("  " if text != "" else "") + _front_warning
	if _lane_hint != "":
		text += ("  " if text != "" else "") + _lane_hint
	_set_status(text)


## What the status line says about the lane part at `cell`: the first thing
## the arch lacks
## (SecurityLanes.status_text) for an incomplete arch or a part of an
## incomplete lane, NOT_IN_LANE for a part no arch counts, and "" for a whole
## lane, any other object and empty floor. The lanes are recognised afresh
## from the grid, and only when the cell holds a lane part.
static func lane_hint(on_grid: BuildGrid, cell: Vector2i) -> String:
	if not on_grid.in_bounds(cell):
		return ""
	var id := on_grid.object_at(cell)
	if id == 0 or not SecurityLanes.is_part(StringName(on_grid.get_object(id)["def"])):
		return ""
	var lanes := SecurityLanes.new()
	lanes.rebuild(on_grid)
	if lanes.is_complete(id) or lanes.lane_of_piece(id) != 0:
		return ""
	if lanes.arches.has(id):
		return lanes.status_text(id)
	for arch in lanes.arches:
		if (lanes.candidate(arch)["parts"] as Dictionary).values().has(id):
			return lanes.status_text(arch)
	return NOT_IN_LANE


## FRONT_OUTSIDE_ROOM for an object edit whose footprint lies wholly in a room
## but whose interaction (front) cell does not: the room would not count it
## (FacilitySlots.piece_inside), so a toilet stall placed so reads "Needs a
## toilet stall". "" for any other edit.
static func front_warning(on_grid: BuildGrid, edit: BuildEdit) -> String:
	if edit == null or edit.kind != BuildEdit.Kind.PLACE_OBJECT:
		return ""
	var def := BuildCatalog.get_def(edit.def_id)
	if def == null or not def.has_interaction:
		return ""
	var room_id := on_grid.room_at(edit.cell)
	if room_id == 0:
		return ""
	var area: Rect2i = on_grid.get_room(room_id)["rect"]
	for cell in def.footprint(edit.cell, edit.facing):
		if not area.has_point(cell):
			return ""
	if area.has_point(def.interaction_cell(edit.cell, edit.facing)):
		return ""
	return FRONT_OUTSIDE_ROOM


## lane_hint() for the cell under the pointer, kept until the pointer moves to
## another cell or the grid changes.
func _lane_hint_at(cell: Vector2i) -> String:
	if not _hint_cached or cell != _hint_cell:
		lane_hint_scans += 1
		_hint_cell = cell
		_hint_cache = lane_hint(grid, cell)
		_hint_cached = true
	return _hint_cache


func _on_lane_graph_changed(_cells: Array[Vector2i]) -> void:
	_hint_cached = false


## Every grid change reaches the view: one not drawn yet by the tool that made
## it is drawn once at the end of the frame, however many edits came before.
func _on_grid_drawn_cells_changed(_cells: Array[Vector2i]) -> void:
	if _view_stale:
		return
	_view_stale = true
	_redraw_if_stale.call_deferred()


func _redraw_if_stale() -> void:
	if _view_stale:
		_redraw()


func _redraw() -> void:
	_view_stale = false
	_view.refresh(grid)


func _set_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	status_changed.emit(text)
