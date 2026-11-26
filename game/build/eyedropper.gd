class_name Eyedropper
extends RefCounted
## Alt+left-click or crisp middle-click Eyedropper for BuildMode (B3,
## decisions 45a81488 and 593876df). Picks the tool and facing of any built
## object, wall/door, room, floor, or landside spot under the pointer, opening
## the owning room's Contextual Room-Items tray for room-only furniture while
## still enforcing BuildUnlocks via BuildMode.set_tool().


## True when `event` is an Alt+left-click press.
static func is_alt_left_press(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	return mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.alt_pressed


## Maps catalog `def_id` to its BuildMode.Tool, or Tool.NONE if unmapped.
static func tool_for_object(def_id: StringName) -> BuildMode.Tool:
	var indexed := BuildUnlocks.tool_for_object(def_id)
	if indexed != BuildMode.Tool.NONE:
		return indexed
	if BuildCatalog.is_belt(def_id):
		return BuildMode.Tool.BELT
	for tool: BuildMode.Tool in ToolObjects.OBJECTS:
		if ToolObjects.OBJECTS[tool] == def_id:
			return tool
	for tool: BuildMode.Tool in FurnitureTools.OBJECTS:
		if FurnitureTools.OBJECTS[tool] == def_id:
			return tool
	return BuildMode.Tool.NONE


## Maps a BuildGrid.WallKind to its BuildMode.Tool.
static func tool_for_wall(kind: int) -> BuildMode.Tool:
	match kind:
		BuildGrid.WallKind.PLAIN:
			return BuildMode.Tool.WALL
		BuildGrid.WallKind.GLASS:
			return BuildMode.Tool.GLASS
		BuildGrid.WallKind.DOOR:
			return BuildMode.Tool.DOOR
	return BuildMode.Tool.NONE


## Inspects `mode.grid` (and landside when off-grid) at ground `point` and
## returns {"tool", "facing", "room_type", "room_id", "item_name"} or empty.
static func inspect_at(mode: BuildMode, point: Vector3) -> Dictionary:
	if mode == null or mode.grid == null:
		return {}
	var grid := mode.grid
	var cell := grid.world_to_cell(point)
	if not grid.in_bounds(cell):
		return _inspect_landside(mode, point)
	var camera := mode.get_viewport().get_camera_3d() if mode.is_inside_tree() else null
	var object_id := SightPick.seen_object(grid, mode._view, camera, point)
	var seen_wall := SightPick.seen_wall(grid, mode._view, camera, point)
	if object_id == 0 and seen_wall.z < 0:
		object_id = grid.object_at(cell)
	if object_id != 0:
		return _object_pick(grid, object_id, cell)
	var wall_tool := _picked_wall_tool(grid, seen_wall, point, cell)
	if wall_tool != BuildMode.Tool.NONE:
		return {
			"tool": wall_tool,
			"facing": mode.facing,
			"room_type": &"",
			"room_id": 0,
			"item_name": "",
		}
	var room_id := grid.room_at(cell)
	if room_id != 0:
		var room_type := StringName(grid.get_room(room_id)["type"])
		var room_tool := BuildMenuCatalog.room_tool_for(room_type)
		if room_tool != BuildMode.Tool.NONE:
			return {
				"tool": room_tool,
				"facing": mode.facing,
				"room_type": room_type,
				"room_id": room_id,
				"item_name": "",
			}
	if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
		return {
			"tool": BuildMode.Tool.FLOOR,
			"facing": mode.facing,
			"room_type": &"",
			"room_id": 0,
			"item_name": "",
		}
	return {}


static func _object_pick(grid: BuildGrid, object_id: int, cell: Vector2i) -> Dictionary:
	var record := grid.get_object(object_id)
	if record.is_empty():
		return {}
	var def_id := StringName(record["def"])
	var picked_tool := tool_for_object(def_id)
	if picked_tool == BuildMode.Tool.NONE:
		return {}
	var room_id := grid.room_at(record.get("anchor", cell))
	var room_type: StringName = &""
	if room_id != 0:
		room_type = StringName(grid.get_room(room_id).get("type", &""))
	var def := BuildCatalog.get_def(def_id)
	return {
		"tool": picked_tool,
		"facing": posmod(int(record.get("facing", 0)), 4),
		"room_type": room_type,
		"room_id": room_id,
		"item_name": def.display_name if def != null else "",
	}


static func _picked_wall_tool(
	grid: BuildGrid, seen_wall: Vector3i, point: Vector3, cell: Vector2i
) -> BuildMode.Tool:
	if seen_wall.z >= 0:
		var kind := grid.wall_kind(Vector2i(seen_wall.x, seen_wall.y), seen_wall.z)
		return tool_for_wall(kind)
	var side: int = grid.nearest_side(point)
	var offset := point - grid.cell_to_world(cell)
	var to_edge := 0.5 - maxf(absf(offset.x), absf(offset.z))
	if grid.has_wall(cell, side) and to_edge <= BuildMode.WALL_PICK_DISTANCE:
		return tool_for_wall(grid.wall_kind(cell, side))
	return BuildMode.Tool.NONE


static func _inspect_landside(mode: BuildMode, point: Vector3) -> Dictionary:
	var plan := mode.landside_placement().plan_remove(point)
	if plan == null:
		return {}
	for tool: BuildMode.Tool in BuildMode.LANDSIDE_BUILD_TOOLS:
		if BuildMode.LANDSIDE_BUILD_TOOLS[tool] == plan.kind:
			return {
				"tool": tool,
				"facing": mode.facing,
				"room_type": &"",
				"room_id": 0,
				"item_name": "",
			}
	return {}


## Applies the Eyedropper at ground `point` on `mode`. Returns true when an
## item was found and picked (or cleanly refused by BuildUnlocks).
static func pick_at(mode: BuildMode, point: Vector3) -> bool:
	var pick := inspect_at(mode, point)
	if pick.is_empty():
		return false
	var picked_tool: BuildMode.Tool = pick["tool"]
	var lock := BuildUnlocks.lock_text(mode.unlocks, mode.require_unlocks, picked_tool)
	if lock != "":
		# Route refusal through BuildMode.set_tool() so status/refusal signals fire identically.
		mode.set_tool(picked_tool)
		return true
	mode.templates.disarm()
	if mode.room_mover.active:
		mode.room_mover.cancel()
	if mode.object_mover.active:
		mode.object_mover.cancel()
	if mode.starter_kit != null and mode.starter_kit.is_active():
		mode.starter_kit.disarm()
	mode.set_tool(picked_tool)
	mode.facing = int(pick["facing"])
	mode._auto_facing = false
	mode._hover_key = ""
	mode._show_status(null)
	mode.eyedropper_picked.emit(pick)
	return true
