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
## The Cafe tool drags a rectangle that marks floor as a cafe room (RoomTool);
## the counter and table tools furnish it, and RoomView shows what it needs.
## The Bag room tool does the same for a baggage room, and the Toilet room tool
## for a toilet, which the stall and sink tools furnish. The Belt tool lays belt
## cells: press, drag and release lays an L-shaped line (BeltShaper.path()),
## a click lays one cell, and Esc or right-click cancels. Every belt cell takes
## its piece from its neighbours (BeltShaper), so a line that dead-ends in a
## bag room ends in the belt end the room needs; after every other edit the
## belts next to it are reshaped too (BuildDrags.reshape_belts()).
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
	EXCHANGE_ROOM,
	ATM_ROOM,
	BAR_ROOM,
	RESTAURANT_ROOM,
	STALL_ROOM,
	PLAY_AREA_ROOM,
	LOUNGE_ROOM,
	SHOWER_ROOM,
	NAP_POD_ROOM,
	BUY_LAND,
	GATE_DESK,
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
## The catalog id each object tool places (ToolObjects).
const TOOL_OBJECTS := ToolObjects.OBJECTS
## The security lane part tools, in flow order.
const LANE_TOOLS: Array[Tool] = [Tool.TRAY_TABLE, Tool.XRAY_BELT, Tool.ARCH, Tool.PICKUP_TABLE]
## What one belt cell costs, whatever piece it becomes.
const BELT_PRICE_ID := &"baggage_belt"
const BELT_HINT := "Drag to lay a belt"
## The status line over a lane part that belongs to no arch.
const NOT_IN_LANE := "Not part of a lane"
## The status line over an item placed inside a room whose front cell falls
## outside it: the room does not count the item (FacilitySlots.piece_inside).
const FRONT_OUTSIDE_ROOM := "Its front is outside the room, so it will not count"
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
	Tool.EXCHANGE_ROOM: &"exchange",
	Tool.ATM_ROOM: &"atm",
	Tool.BAR_ROOM: &"bar",
	Tool.RESTAURANT_ROOM: &"restaurant",
	Tool.STALL_ROOM: &"stall",
	Tool.PLAY_AREA_ROOM: &"play_area",
	Tool.LOUNGE_ROOM: &"lounge",
	Tool.SHOWER_ROOM: &"shower",
	Tool.NAP_POD_ROOM: &"nap_pod",
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
	Tool.EXCHANGE_ROOM,
	Tool.EXCHANGE,
	Tool.ATM_ROOM,
	Tool.ATM,
	Tool.BAR_ROOM,
	Tool.RESTAURANT_ROOM,
	Tool.STALL_ROOM,
	Tool.PLAY_AREA_ROOM,
	Tool.LOUNGE_ROOM,
	Tool.SHOWER_ROOM,
	Tool.NAP_POD_ROOM,
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
	Tool.EXCHANGE_ROOM,
	Tool.ATM_ROOM,
	Tool.BAR_ROOM,
	Tool.RESTAURANT_ROOM,
	Tool.STALL_ROOM,
	Tool.PLAY_AREA_ROOM,
	Tool.LOUNGE_ROOM,
	Tool.SHOWER_ROOM,
	Tool.NAP_POD_ROOM,
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
## The airport site the player builds the terminal on. When set, the grid
## takes its frame (grid_size, grid_centred and grid_origin are not used) and
## load_snapshot() checks a save fits it (SiteDefinition.snapshot_problem()).
@export var site: SiteDefinition
## Where building is paid from (BuildTransaction): a click or door costs its
## price, a Floor rectangle is all or nothing, a wall row stops when the
## money runs out, and removals refund a share of the saved price. main.tscn
## sets it. Without it the tools build for free and save no prices, the
## non-spending path tests and probes use.
@export var finances: Finances
## The landside the curb, car park and Close tools build on (Landside 3/4). main.tscn
## sets it; without it those tools do nothing.
@export var landside: LandsideSim
## The tier gate set_tool() and the template paste ask (BuildUnlocks). main.tscn sets both;
## without `require_unlocks` (a test world or probe) every tool can be picked.
@export var unlocks: BuildUnlocks
@export var require_unlocks := false
## Starts the grid with the player-owned starter shell (StarterShell) when the
## node enters the tree. main.tscn sets it; a load replaces the grid, so a
## loaded game never gets a second shell. A bare BuildMode starts empty.
@export var starter_shell := false

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
## Saved room templates and their paste (TemplatePaste), made a child in _ready().
var templates := TemplatePaste.new()
## The picked-up room and its set-down (RoomMoveTool), made a child in _ready().
var room_mover := RoomMoveTool.new()
## The Buy land tool and the site's land plots (LandTool), made in _ready(); no land without a site.
var land_tool: LandTool = null

## False once R is pressed, until a tool is picked again. While true, the
## door tools ignore `facing` and use DoorPlacement.auto_facing().
var _auto_facing := true
var _view := BuildView.new()
var _room_view := RoomView.new()
var _focus_room := 0
var _ghost := Node3D.new()
var _valid_material := BuildGhost.material(VALID_TINT)
var _invalid_material := BuildGhost.material(INVALID_TINT)
var _marker_material := BuildGhost.material(MARKER_TINT)
var _area_remove_material := BuildGhost.material(AREA_REMOVE_TINT)
var _coverage_material := BuildGhost.material(COVERAGE_TINT)
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
## The room edge being dragged to resize a room (RoomResize).
var _resize := RoomResize.new()
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


func _ready() -> void:
	if site != null:
		grid = SiteGrid.new(site)
	else:
		grid = BuildGrid.new(grid_size, null if grid_centred else grid_origin)
	land_tool = LandTool.attach(self)
	tool = BuildUnlocks.start_tool(unlocks, require_unlocks, tool)
	if starter_shell and not StarterShell.place(grid):
		push_error("BuildMode: the starter shell does not fit this grid; it starts empty")
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
	add_child(templates)
	add_child(room_mover)
	set_tool(tool)


func _process(_delta: float) -> void:
	var point: Variant = _mouse_ground()
	# Over a HUD Control the pointer is not over the world: no ghost, no hover.
	# A rectangle in progress stays, hidden, until the pointer is back.
	var over_ui := _pointer_over_ui()
	_area_over_ui = over_ui and is_dragging()
	if not over_ui:
		_update_ghost(point)
	elif is_dragging():
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
	if is_dragging() and event.is_action_released("build_apply"):
		finish_area()
		finish_row()


func _unhandled_input(event: InputEvent) -> void:
	if is_dragging() and _cancels_area(event):
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
	elif event is InputEventMouseMotion and is_dragging():
		var point: Variant = _mouse_ground()
		if point == null or _pointer_over_ui():
			return
		if not _drag_moved:
			if _pointer_position().distance_to(_press_screen) < CLICK_SLOP_PX:
				return
			_drag_moved = true
		if _row.active:
			move_row(point)
		else:
			move_area(point)


## Picks a tool.
func set_tool(new_tool: Tool) -> void:
	var locked := BuildUnlocks.lock_text(unlocks, require_unlocks, new_tool)
	if locked != "":
		_status_note = locked
		_show_status(null)
		return
	_enter_tool(new_tool)


## Picks a tool to move something already built: the tier lock gates picking a
## new thing to build, not lifting what stands (BuildUnlocks, "only picking the
## tool is gated"). A fresh pick from the menu still goes through set_tool().
func set_tool_for_move(new_tool: Tool) -> void:
	_enter_tool(new_tool)


func _enter_tool(new_tool: Tool) -> void:
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
		var turn := facing
		if _facing_is_auto():
			turn = DoorPlacement.auto_facing(grid, def_id, point, facing)
		return BuildEdit.place_object(def_id, DoorPlacement.cell_under(grid, point), turn)
	return null


## Applies the current tool at a ground point, paid through BuildTransaction,
## and redraws on success. Returns null when nothing was attempted. One undo
## step.
func apply_at(point: Vector3) -> BuildResult:
	# A landside action is not a grid action: it keeps its own undo record.
	if tool == Tool.BUY_LAND:
		return land_tool.buy_at(point) if land_tool.land != null else null
	var landside_plan := landside_plan_at(point)
	if landside_plan != null or BuildModeLandside.is_landside_tool(self):
		return BuildModeLandside.apply(self, landside_plan)
	_history.begin_action()
	var result := _apply_at(point)
	_history.end_action()
	return result


## Applies one prepared grid edit exactly as a click would: checked, paid
## through BuildTransaction, redrawn, and one undo step. For a caller that holds
## an edit already (the inspect window's Delete), not a ground point. The active
## tool is ignored. The status note, left only by a placement, stays on
## edit.cell, which is not always the cell a click was on (object and room
## removals leave it at zero, and a door placement may shift it).
func apply_edit(edit: BuildEdit) -> BuildResult:
	_history.begin_action()
	var result := _commit_edit(edit, edit.cell)
	_history.end_action()
	return result


func _apply_at(point: Vector3) -> BuildResult:
	var edit := edit_at(point)
	if edit == null:
		return null
	return _commit_edit(edit, grid.world_to_cell(point))


## The check, payment, redraw and status of one edit; `note_cell` is the cell
## the status note stays on until the pointer leaves it.
func _commit_edit(edit: BuildEdit, note_cell: Vector2i) -> BuildResult:
	# An earlier action's note must not hide this one's result.
	_status_note = ""
	var warning := front_warning(grid, edit)
	var result := check(edit)
	var refused_by_check := not result.ok
	if result.ok:
		# A removed room's cells, read before it is gone: its dead ends change.
		var touched: Array[Vector2i] = []
		if edit.kind == BuildEdit.Kind.REMOVE_ROOM:
			touched = BuildDrags.rect_cells(grid.get_room(edit.room_id).get("rect", Rect2i()))
		# The edit and the reshape it causes reach listeners as one change.
		grid.hold_signals()
		result = BuildTransaction.commit_plan(grid, DoorPlacement.edits_for(grid, edit), wallet())
		if result.ok:
			touched.append_array(result.dirty_cells)
			BuildDrags.reshape_belts(self, touched)
		grid.release_signals()
	if result.ok:
		_redraw()
		_hover_key = ""
		grid_changed.emit()
		if warning != "":
			_status_note = warning
			_note_cell = note_cell
		elif edit.kind == BuildEdit.Kind.PLACE_OBJECT:
			# The ghost now re-checks the piece it just placed, which overlaps
			# itself: say what was placed until the pointer leaves the cell.
			_status_note = "%s placed" % BuildCatalog.get_def(edit.def_id).display_name
			_note_cell = note_cell
	_show_status(result)
	# A refusal from the grid or the transaction (inside commit_plan()) was
	# emitted there.
	if refused_by_check:
		grid.edit_refused.emit(edit, result)
	return result


## Starts a Floor or Remove rectangle on the cell under a ground point. A press
## outside the grid is a plain click, which the grid refuses with its reason.
func begin_area(point: Vector3) -> void:
	BuildDrags.begin_area(self, point)


## Starts a Wall or Glass row on the cell under a ground point, on the edge side
## nearest the point. A press outside the grid is a plain click, which the grid
## refuses with its reason.
func begin_row(point: Vector3) -> void:
	BuildDrags.begin_row(self, point)


## Stretches the row to the cell under a ground point.
func move_row(point: Vector3) -> void:
	BuildDrags.move_row(self, point)


## Lays the row (WallRowDrag.apply()): every edge the rules accept, stopping
## where the money runs out, as one undo step. A drag that never left its cell
## lays the one edge, as a click. Returns what the row did, or null with no
## row. The status line says how many edges were placed, what they cost and
## why any was skipped.
func finish_row() -> AreaDrag.Outcome:
	if not _row.active:
		return null
	_history.begin_action()
	var outcome := BuildDrags.lay_row(self)
	_history.end_action()
	BuildDrags.report_row(self, outcome)
	return outcome


## True while a rectangle or a wall row is being dragged; the drag then owns
## the hover (BuildMenu's refusal card, GhostReason, hides).
func is_dragging() -> bool:
	return _area.active or _row.active or _resize.active


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
	return _area_over_ui and is_dragging()


## The rectangle being dragged, or an empty Rect2i when no rectangle drag is on
## (BuildMenu prices it for the cost line).
func dragged_area() -> Rect2i:
	return _area.rect() if _area.active else Rect2i()


## Stretches the rectangle to the cell under a ground point, or moves the grabbed
## room edge to the nearest grid line (RoomResize).
func move_area(point: Vector3) -> void:
	BuildDrags.move_area(self, point)


## Applies the rectangle. A drag that never left its cell is applied as the
## single click it is, at the press point (which marks no room). Returns what
## a Floor or Remove rectangle did, or null when there was no rectangle, it
## was a click or it marked a room. One undo step.
func finish_area() -> AreaDrag.Outcome:
	_history.begin_action()
	var outcome := BuildDrags.finish_area(self)
	_history.end_action()
	return outcome


## Lays a belt line from cell `from` to cell `to` (BeltShaper.path()): buys a
## plain belt on each path cell that has none, at the belt price, and shapes
## them and the belts next to them, all in one plan. Refused whole when a cell
## cannot take a belt, a wall crosses the line, a belt would get a fourth link
## or the wallet cannot pay. A line over belt only does nothing. One undo step.
func lay_belt(from: Vector2i, to: Vector2i) -> BuildResult:
	_history.begin_action()
	var result := BuildDrags.lay_belt(self, from, to)
	_history.end_action()
	return result


## Undoes the last build action and its money (UndoStack.undo()), dropping a
## rectangle or row in progress first. The status line says it was undone,
## why it was refused (nothing changed) or that there is nothing to undo, until
## the pointer leaves its cell. Returns the result, or null with no history.
func undo() -> BuildResult:
	cancel_area()
	var landside_first := landside_placement().has_undo_for(_history.peek())
	var result := _landside_placement.undo() if landside_first else _history.undo()
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
		_hover_key = BuildModeLandside.hover_key(self, landside_plan_at(point))
	_show_status(null)
	return result


## Forgets every action that could be undone, the grid's and the landside's
## (BuildSession calls it when build mode ends).
func clear_undo() -> void:
	_history.clear()
	_landside_placement.clear_undo()


## The drawn node of object `object_id`, or null (RoomMoveTool dims them).
func object_node(object_id: int) -> Node3D:
	return _view.object_node(object_id)


## The undo history, newest action on top (read it, never change it).
func undo_history() -> UndoStack:
	return _history


## How many belt cells the line under the pointer (or being dragged) would buy;
## 0 when it is refused or no Belt line is shown (BuildMenu prices it).
func belt_cells_to_buy() -> int:
	if tool != Tool.BELT or _belt_plan == null or not _belt_plan.result.ok:
		return 0
	return _belt_plan.new_cells.size()


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
	if not is_dragging():
		return
	_area.cancel()
	_row.cancel()
	_resize.cancel()
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
	var result := DoorPlacement.check(grid, edit)
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
## With a site, a save in another frame than the site's is refused first
## (SiteDefinition.snapshot_problem()). Pushes an error and returns false,
## leaving the grid as it was, on any refusal. A load never spends or
## credits: it bypasses BuildTransaction and keeps the saved purchase prices.
## It clears the undo history.
func load_snapshot(data: Dictionary) -> bool:
	var problem := site.snapshot_problem(data) if site != null else ""
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


## A door tool picks its own facing until R is pressed.
func _facing_is_auto() -> bool:
	return _auto_facing and DOOR_NAMES.has(tool)


## What Remove takes at a ground point: the object the pointer is on (seen
## from the camera, or on the point's cell), then the wall the line of sight
## to the point meets (WallPick), then a wall edge within WALL_PICK_DISTANCE of
## the point, then the room, then the floor. A wall in the way hides the object by cell behind it.
func _removal_at(point: Vector3, cell: Vector2i, side: int) -> BuildEdit:
	var camera := get_viewport().get_camera_3d()
	var object_id := SightPick.seen_object(grid, _view, camera, point)
	var seen_wall := SightPick.seen_wall(grid, _view, camera, point)
	if object_id == 0 and seen_wall.z < 0:
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
	if BuildModeLandside.is_landside_tool(self):
		return LandsidePlacement.ground_point(from, direction)
	var point: Variant = grid_point(from, direction)
	# Remove also takes a built landside spot, which stands off the grid, on the
	# ground plane.
	if tool == Tool.REMOVE and point != null and not grid.in_bounds(grid.world_to_cell(point)):
		return LandsidePlacement.ground_point(from, direction)
	return point


## True for a ground point over the grid's whole area, its far east and south
## edge lines included (world_to_cell() puts those in a cell outside the grid).
func _over_grid_area(point: Vector3) -> bool:
	var local := point - grid.origin
	return local.x >= 0.0 and local.z >= 0.0 and local.x <= grid.size.x and local.z <= grid.size.y


func _update_ghost(point: Variant) -> void:
	_pointer_on_grid = point != null and _over_grid_area(point)
	_landside_plan = null if is_dragging() else landside_plan_at(point)
	if _landside_plan != null or BuildModeLandside.is_landside_tool(self) or tool == Tool.BUY_LAND:
		BuildModeLandside.hover_off_grid_tool(self, point)
		return
	if _area.active or _resize.active:
		_draw_area()
		return
	if _row.active:
		BuildGhost.draw_row(self)
		return
	if _status_note != "" and (point == null or grid.world_to_cell(point) != _note_cell):
		_status_note = ""
		_hover_key = ""
		_show_status(null)
	if tool == Tool.BELT:
		BuildGhost.hover_belt(self, point)
		return
	var edit: BuildEdit = null if point == null else edit_at(point)
	_hover_edit = edit
	var hint := "" if point == null else BuildStatus.lane_hint_at(self, grid.world_to_cell(point))
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
	var key := BuildStatus.edit_key(edit) + "|" + hint + "|" + warning
	if key == _hover_key:
		return
	_hover_key = key
	_lane_hint = hint
	var result := check(edit)
	_front_warning = warning if result.ok else ""
	var valid := _area_remove_material if tool == Tool.REMOVE else _valid_material
	BuildGhost.draw(self, edit, valid if result.ok else _invalid_material)
	_show_status(result)


## The landside tools' rules (LandsidePlacement) for the sim, grid and wallet
## BuildMode has now.
func landside_placement() -> LandsidePlacement:
	return BuildModeLandside.placement(self)


## What the current tool would do on the landside at a ground point (picked on
## the y = 0 plane): a curb or car park tool snaps to the nearest free spot of
## its kind or says why not, the Close tool finds the car park under it, and
## Remove, off the grid, finds the built spot under it. Null for any other
## tool or point, and for a spot-less pointer.
func landside_plan_at(point: Variant) -> LandsidePlacement.Plan:
	return BuildModeLandside.plan_at(self, point)


## (cost, money the wallet must hold) of the landside build under the pointer,
## zero for anything else (BuildMenu's cost line).
func landside_preview_price() -> Vector2i:
	return BuildModeLandside.preview_price(self)


## Hides the rectangle's slab and size while the pointer is over the HUD; the
## cleared hover key makes _draw_area() draw both again on the way back.
func _hide_area_ghost() -> void:
	BuildGhost.hide_area(self)


func _draw_area() -> void:
	BuildGhost.draw_area(self)


## The cells the ghost tints as covered while `edit` places a screen stand:
## ScreenCoverage.covered_cells() where it would stand; empty for any other edit.
func coverage_preview(edit: BuildEdit) -> Array[Vector2i]:
	return BuildGhost.coverage_preview(grid, edit)


func _show_status(result: BuildResult) -> void:
	BuildStatus.show_status(self, result)


## What the status line says about the lane part at `cell`: the first thing
## the arch lacks
## (SecurityLanes.status_text) for an incomplete arch or a part of an
## incomplete lane, NOT_IN_LANE for a part no arch counts, and "" for a whole
## lane, any other object and empty floor. The lanes are recognised afresh
## from the grid, and only when the cell holds a lane part.
static func lane_hint(on_grid: BuildGrid, cell: Vector2i) -> String:
	return BuildStatus.lane_hint(on_grid, cell)


## FRONT_OUTSIDE_ROOM for an object edit whose footprint lies wholly in a room
## but whose interaction (front) cell does not: the room would not count it
## (FacilitySlots.piece_inside), so a toilet stall placed so reads "Needs a
## toilet stall". "" for any other edit.
static func front_warning(on_grid: BuildGrid, edit: BuildEdit) -> String:
	return BuildStatus.front_warning(on_grid, edit)


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
