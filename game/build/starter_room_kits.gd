class_name StarterRoomKits
extends RefCounted
## Pre-designed furnished Starter Room Kits for Contextual Room-Items Tray
## placement (B2 slice, decisions 593876df / c221025a). Each kit generates an
## atomic composite plan of missing floor, perimeter plain walls, a door wall,
## the room zone, and its mandatory furniture, rotatable with R.

const KITS := {
	&"toilet":
	{
		"name": "Starter Toilet",
		"room_type": &"toilet",
		"thumbnail": "toilet_room",
		"size": Vector2i(3, 3),
		"door": {"cell": Vector2i(1, 2), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"toilet_stall", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"toilet_sink", "anchor": Vector2i(2, 0), "facing": 0},
		],
	},
	&"cafe":
	{
		"name": "Starter Cafe",
		"room_type": &"cafe",
		"thumbnail": "cafe_room",
		"size": Vector2i(4, 4),
		"door": {"cell": Vector2i(1, 3), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"cafe_counter", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"cafe_table", "anchor": Vector2i(0, 2), "facing": 0},
		],
	},
	&"bar":
	{
		"name": "Starter Bar",
		"room_type": &"bar",
		"thumbnail": "bar_room",
		"size": Vector2i(4, 4),
		"door": {"cell": Vector2i(1, 3), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"bar_counter", "anchor": Vector2i(1, 0), "facing": 0},
		],
	},
	&"restaurant":
	{
		"name": "Starter Restaurant",
		"room_type": &"restaurant",
		"thumbnail": "restaurant_room",
		"size": Vector2i(5, 5),
		"door": {"cell": Vector2i(1, 4), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"cafe_counter", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"restaurant_table", "anchor": Vector2i(2, 1), "facing": 0},
		],
	},
	&"bag_room":
	{
		"name": "Starter Bag room",
		"room_type": &"bag_room",
		"thumbnail": "bag_room",
		"size": Vector2i(3, 3),
		"door": {"cell": Vector2i(1, 2), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"baggage_belt_end", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"baggage_cart", "anchor": Vector2i(2, 0), "facing": 0},
		],
	},
	&"kiosk":
	{
		"name": "Starter Kiosk",
		"room_type": &"kiosk",
		"thumbnail": "kiosk_room",
		"size": Vector2i(4, 3),
		"door": {"cell": Vector2i(1, 2), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"kiosk_counter", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"kiosk_display", "anchor": Vector2i(2, 0), "facing": 0},
		],
	},
	&"pharmacy":
	{
		"name": "Starter Pharmacy",
		"room_type": &"pharmacy",
		"thumbnail": "pharmacy_room",
		"size": Vector2i(4, 3),
		"door": {"cell": Vector2i(1, 2), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"pharmacy_counter", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"pharmacy_shelf", "anchor": Vector2i(2, 0), "facing": 0},
		],
	},
	&"duty_free":
	{
		"name": "Starter Duty free",
		"room_type": &"duty_free",
		"thumbnail": "duty_free_room",
		"size": Vector2i(4, 3),
		"door": {"cell": Vector2i(1, 2), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"duty_free_till", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"duty_free_shelf", "anchor": Vector2i(2, 0), "facing": 0},
		],
	},
	&"fashion":
	{
		"name": "Starter Fashion store",
		"room_type": &"fashion",
		"thumbnail": "fashion_room",
		"size": Vector2i(4, 3),
		"door": {"cell": Vector2i(1, 2), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"fashion_till", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"fashion_rail", "anchor": Vector2i(2, 0), "facing": 0},
		],
	},
	&"play_area":
	{
		"name": "Starter Play area",
		"room_type": &"play_area",
		"thumbnail": "play_slide",
		"size": Vector2i(4, 3),
		"door": {"cell": Vector2i(1, 2), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"play_slide", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"play_blocks", "anchor": Vector2i(2, 0), "facing": 0},
		],
	},
	&"lounge":
	{
		"name": "Starter Lounge",
		"room_type": &"lounge",
		"thumbnail": "lounge_sofa",
		"size": Vector2i(3, 3),
		"door": {"cell": Vector2i(1, 2), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"lounge_sofa", "anchor": Vector2i(0, 0), "facing": 0},
			{"def": &"lounge_armchair", "anchor": Vector2i(2, 0), "facing": 0},
		],
	},
	&"shower":
	{
		"name": "Starter Shower",
		"room_type": &"shower",
		"thumbnail": "shower_cubicle",
		"size": Vector2i(3, 2),
		"door": {"cell": Vector2i(1, 1), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"shower_cubicle", "anchor": Vector2i(0, 0), "facing": 0},
		],
	},
	&"break_room":
	{
		"name": "Starter Break Room",
		"room_type": &"break_room",
		"thumbnail": "bench_1a",
		"size": Vector2i(3, 3),
		"door": {"cell": Vector2i(1, 2), "side": BuildGrid.Side.SOUTH},
		"pieces":
		[
			{"def": &"bench_1a", "anchor": Vector2i(0, 0), "facing": 0},
		],
	},
}


static func has_kit(kit_id: StringName) -> bool:
	return KITS.has(kit_id)


static func get_kit(kit_id: StringName) -> Dictionary:
	return KITS.get(kit_id, {})


static func kit_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(KITS.keys())
	return out


static func display_name(kit_id: StringName) -> String:
	return str(KITS.get(kit_id, {}).get("name", ""))


static func thumbnail_id(kit_id: StringName) -> String:
	return str(KITS.get(kit_id, {}).get("thumbnail", ""))


static func kit_size(kit_id: StringName) -> Vector2i:
	return KITS.get(kit_id, {}).get("size", Vector2i.ZERO)


static func turned_size(kit_id: StringName, turns: int) -> Vector2i:
	var sz := kit_size(kit_id)
	return Vector2i(sz.y, sz.x) if posmod(turns, 2) == 1 else sz


static func rect_at(kit_id: StringName, centre: Vector2i, turns: int) -> Rect2i:
	var turned := turned_size(kit_id, turns)
	return Rect2i(centre - (turned - Vector2i.ONE) / 2, turned)


static func _turn_offset(sz: Vector2i, turns: int) -> Vector2i:
	var low := Vector2i(256, 256)
	var far := sz - Vector2i.ONE
	for corner in [Vector2i.ZERO, Vector2i(far.x, 0), Vector2i(0, far.y), far]:
		var turned := BuildObjectDef.rotate_offset(corner, turns)
		low = Vector2i(mini(low.x, turned.x), mini(low.y, turned.y))
	return -low


static func _edge_key(cell: Vector2i, side: int) -> Vector3i:
	match side:
		BuildGrid.Side.SOUTH:
			return Vector3i(cell.x, cell.y + 1, BuildGrid.Side.NORTH)
		BuildGrid.Side.EAST:
			return Vector3i(cell.x + 1, cell.y, BuildGrid.Side.WEST)
	return Vector3i(cell.x, cell.y, side)


## Returns the rotated doorway {"cell", "side", "outside"} for `kit_id`
## placed at `centre` rotated by `turns` quarter turns, or {} for unknown kits.
static func door_edge(kit_id: StringName, centre: Vector2i, turns: int) -> Dictionary:
	var kit := get_kit(kit_id)
	if kit.is_empty():
		return {}
	var sz: Vector2i = kit["size"]
	var rect := rect_at(kit_id, centre, turns)
	var shift := rect.position + _turn_offset(sz, turns)
	var door_info: Dictionary = kit["door"]
	var door_cell := shift + BuildObjectDef.rotate_offset(door_info["cell"], turns)
	var door_side := posmod(int(door_info["side"]) + turns, 4)
	return {
		"cell": door_cell,
		"side": door_side,
		"outside": door_cell + BuildGrid.SIDE_STEP[door_side],
	}


## Refusal when the doorway's outside threshold is out of bounds, lacks indoor
## floor (outer wall / outdoor ground), or holds a non-walk-through object;
## null when the doorway opens onto walkable indoor floor.
static func door_problem(
	grid: BuildGrid, kit_id: StringName, centre: Vector2i, turns: int
) -> BuildResult:
	if grid == null:
		return null
	var door := door_edge(kit_id, centre, turns)
	if door.is_empty():
		return null
	var outside: Vector2i = door["outside"]
	if not grid.in_bounds(outside):
		return BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS)
	if grid.floor_at(outside) == BuildGrid.FLOOR_NONE:
		return BuildResult.refused(BuildResult.Reason.NO_FLOOR)
	if not grid.is_walkable(outside):
		var oid := grid.object_at(outside)
		var result := BuildResult.refused(BuildResult.Reason.DOOR_FRONT_BLOCKED, oid)
		if oid != 0:
			var def := BuildCatalog.get_def(grid.get_object(oid).get("def", &""))
			if def != null and def.display_name != "":
				result.detail = def.display_name.to_lower()
		return result
	return null


## Extra composite validation rule enforcing door_problem() during staging
## and commit while keeping plan() usable for ghost rendering.
static func placement_rule(kit_id: StringName, centre: Vector2i, turns: int) -> Callable:
	return func(on: BuildGrid, edit: BuildEdit) -> BuildResult:
		if edit.kind == BuildEdit.Kind.PLACE_ROOM:
			return door_problem(on, kit_id, centre, turns)
		return null


## Builds the atomic composite edit list for placing `kit_id` centred at
## `centre` rotated by `turns` quarter turns: missing floors, missing perimeter
## plain walls, the rotated doorway, PLACE_ROOM, and all mandatory pieces.
static func plan(
	grid: BuildGrid, kit_id: StringName, centre: Vector2i, turns: int
) -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = []
	var kit := get_kit(kit_id)
	if kit.is_empty():
		return edits
	var sz: Vector2i = kit["size"]
	var rect := rect_at(kit_id, centre, turns)
	var shift := rect.position + _turn_offset(sz, turns)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if (
				grid == null
				or not grid.in_bounds(cell)
				or grid.floor_at(cell) == BuildGrid.FLOOR_NONE
			):
				edits.append(
					BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)
				)
	var door := door_edge(kit_id, centre, turns)
	var door_cell: Vector2i = door["cell"]
	var door_side: int = door["side"]
	var door_key := _edge_key(door_cell, door_side)
	for edge in RoomTool.perimeter_edges(rect):
		var cell: Vector2i = edge[0]
		var side: int = edge[1]
		if _edge_key(cell, side) == door_key:
			continue
		if grid != null and grid.wall_kind(cell, side) != BuildGrid.WallKind.NONE:
			continue
		if grid != null and DoorPlacement.on_a_way_out(grid, cell, side):
			continue
		edits.append(BuildEdit.place_wall(cell, side, BuildGrid.WallKind.PLAIN))
	if grid == null or grid.wall_kind(door_cell, door_side) != BuildGrid.WallKind.DOOR:
		edits.append(BuildEdit.place_wall(door_cell, door_side, BuildGrid.WallKind.DOOR))
	edits.append(BuildEdit.place_room(rect, kit["room_type"]))
	for piece: Dictionary in kit["pieces"]:
		var anchor := shift + BuildObjectDef.rotate_offset(piece["anchor"], turns)
		var facing := posmod(int(piece["facing"]) + turns, 4)
		edits.append(BuildEdit.place_object(piece["def"], anchor, facing))
	return edits


## Full bare-ground price of `kit_id` (floors + plain walls + door + pieces).
static func base_price(kit_id: StringName) -> int:
	var kit := get_kit(kit_id)
	if kit.is_empty():
		return 0
	var sz: Vector2i = kit["size"]
	var total := sz.x * sz.y * PriceTable.price_of_floor()
	var perimeter := 2 * (sz.x + sz.y)
	total += (perimeter - 1) * PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	total += PriceTable.price_of_wall(BuildGrid.WallKind.DOOR)
	for piece: Dictionary in kit["pieces"]:
		var each := BuildCatalog.object_price(piece["def"])
		if each == PriceTable.NO_PRICE:
			return PriceTable.NO_PRICE
		total += each
	return total


## Room and object edits of `kit_id` for BuildUnlocks gating checks.
static func unlock_edits(kit_id: StringName) -> Array[BuildEdit]:
	var kit := get_kit(kit_id)
	if kit.is_empty():
		return []
	var out: Array[BuildEdit] = [
		BuildEdit.place_room(Rect2i(Vector2i.ZERO, kit["size"]), kit["room_type"])
	]
	for piece: Dictionary in kit["pieces"]:
		out.append(BuildEdit.place_object(piece["def"], piece["anchor"], piece["facing"]))
	return out


## Highest unlock tier required by `kit_id`'s room or pieces.
static func max_tier(kit_id: StringName) -> int:
	var kit := get_kit(kit_id)
	if kit.is_empty():
		return 0
	var room_tool := BuildMenuCatalog.room_tool_for(kit["room_type"])
	var needed := BuildUnlocks.tier_of(room_tool) if room_tool != BuildMode.Tool.NONE else 0
	for piece: Dictionary in kit["pieces"]:
		var piece_tool := BuildUnlocks.tool_for_object(piece["def"])
		if piece_tool != BuildMode.Tool.NONE:
			needed = maxi(needed, BuildUnlocks.tier_of(piece_tool))
	return needed


static func lock_text(kit_id: StringName, unlocks: BuildUnlocks, require_unlocks: bool) -> String:
	return BuildUnlocks.edits_lock_text(unlocks, require_unlocks, unlock_edits(kit_id))


static func card_state(
	kit_id: StringName, unlocks: BuildUnlocks, require_unlocks: bool, demo: bool
) -> int:
	if not require_unlocks:
		return BuildMenuCatalog.CardState.OPEN
	var needed := max_tier(kit_id)
	if needed == 0:
		return BuildMenuCatalog.CardState.OPEN
	if unlocks == null:
		return BuildMenuCatalog.CardState.LOCKED
	var cap := mini(unlocks.tier(), DemoMode.MAX_PLAYABLE_TIER) if demo else unlocks.tier()
	if needed <= cap:
		return BuildMenuCatalog.CardState.OPEN
	if demo and unlocks.tier() >= DemoMode.MAX_PLAYABLE_TIER and needed == DemoMode.TEASER_TIER:
		return BuildMenuCatalog.CardState.TEASER
	return BuildMenuCatalog.CardState.HIDDEN


class Words:
	extends RefCounted

	func msgids() -> Array[String]:
		return [
			tr("Starter Toilet", "build menu"),
			tr("Starter Cafe", "build menu"),
			tr("Starter Bar", "build menu"),
			tr("Starter Restaurant", "build menu"),
			tr("Starter Bag room", "build menu"),
			tr("Starter Kiosk", "build menu"),
			tr("Starter Pharmacy", "build menu"),
			tr("Starter Duty free", "build menu"),
			tr("Starter Fashion store", "build menu"),
			tr("Starter Play area", "build menu"),
			tr("Starter Lounge", "build menu"),
			tr("Starter Shower", "build menu"),
			tr("Kit", "build menu"),
			tr("Placed {kit} for {cost}", "build status"),
			tr("{kit}: click to place", "build status"),
		]
