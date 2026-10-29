class_name ShopTestLayout
extends RefCounted
## The reference terminal with floor east of it, for the kiosk tests, laid out
## like ToiletTestLayout: floor at x 22-27, y 3-16, the security divider
## carried across it with a staff door near its east end (STAFF_DOOR), openings
## in the terminal's east wall, and kiosk rooms in
## its airside (x 22-27, y 3-8) and landside (x 22-27, y 10-15) halves. Each
## kiosk has its counter in its north-west corner and `displays` display
## stands at x 25, three rows apart, all facing south; a display's two browse
## slots are the cells south of it.

const AIRSIDE_ROOM := Rect2i(22, 3, 6, 6)
const LANDSIDE_ROOM := Rect2i(22, 10, 6, 6)
const FLOOR := Rect2i(22, 3, 6, 14)
## The door in the divider near its east end (decision a-door-wall-in-the-
## security-divider-is-allowed-security-is-e): shop staff, who never pass a
## scanner, reach the airside counter through it.
const STAFF_DOOR := Vector2i(26, ReferenceTerminal.DIVIDER_Y)
const COUNTER_X := 22
const DISPLAY_X := 25

## Free airside floor just west of the east wall's openings.
const AIRSIDE_CELL := Vector2i(19, 6)


## A grid holding the reference terminal, the floor east of it and a kiosk on
## each side named in `sides` ("air", "land"), and their ids: {"<side>_room",
## "<side>_counter", "<side>_displays" (object ids, north first)}. With no
## sides it is the floor alone, the control a kiosk is compared with.
static func build(grid: BuildGrid, sides: Array = ["air"], displays := 2) -> Dictionary:
	var built := ReferenceTerminal.build(grid)
	assert(built, "reference terminal refused")
	var edits: Array[BuildEdit] = []
	for y in range(FLOOR.position.y, FLOOR.end.y):
		for x in range(FLOOR.position.x, FLOOR.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(FLOOR.position.x, FLOOR.end.x):
		var cell := Vector2i(x, ReferenceTerminal.DIVIDER_Y)
		if cell != STAFF_DOOR:
			edits.append(BuildEdit.place_wall(cell, BuildGrid.Side.NORTH))
	# After the walls either side of it, which a door needs.
	edits.append(BuildEdit.place_wall(STAFF_DOOR, BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR))
	for y in [4, 5, 6, 7, 11, 12, 13, 14, 15]:
		edits.append(BuildEdit.remove_wall(Vector2i(21, y), BuildGrid.Side.EAST))
	for result in grid.apply_batch(edits):
		assert(result.ok, "shop layout edit refused: %s" % result.reason_text())
	var ids := {}
	for side: String in sides:
		var rect := AIRSIDE_ROOM if side == "air" else LANDSIDE_ROOM
		ids[side + "_room"] = _apply(grid, BuildEdit.place_room(rect, &"kiosk")).room_id
		ids[side + "_counter"] = _place(grid, &"kiosk_counter", rect.position)
		var stands: Array = []
		for i in displays:
			stands.append(
				_place(grid, &"kiosk_display", Vector2i(DISPLAY_X, rect.position.y + 3 * i))
			)
		ids[side + "_displays"] = stands
	return ids


## A calm cleared passenger with no bags heading for the gate from `cell`,
## `boredom` bored.
static func airside_guest(
	world: PassengerTestWorld, boredom: int, cell := AIRSIDE_CELL
) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = world.clock.tick
	p.at = cell
	p.clear_path()
	p.boredom = boredom
	p.shop_cooldown = 0
	return p


static func _place(grid: BuildGrid, def_id: StringName, anchor: Vector2i) -> int:
	return _apply(grid, BuildEdit.place_object(def_id, anchor, 0)).object_id


static func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert(result.ok, "shop layout edit refused: %s" % result.reason_text())
	return result
