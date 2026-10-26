class_name HandBuiltTerminal
extends RefCounted
## A terminal built only through BuildMode's tools, the way a player paints
## one, for the spike probes. Cells x 10-21, y 2-17 on the default grid, laid
## out like ReferenceTerminal (desks, a security divider with two scanners,
## seats, the entrance on the south edge and the exit on the north edge) plus
## a landside wall across row LOBBY_Y with a door, and three glass walls in
## the west side.

const FLOOR_MIN := Vector2i(10, 2)
const FLOOR_MAX := Vector2i(21, 17)
const DIVIDER_Y := 9
## The landside wall runs along the north edge of this row, with a door at
## DOOR_X.
const LOBBY_Y := 15
const DOOR_X := 18
const GLASS_YS: Array[int] = [11, 12, 13]
const SCANNER_XS: Array[int] = [17, 19]
const ENTRANCE_CELL := Vector2i(18, 17)
const EXIT_CELL := Vector2i(20, 2)

var mode: BuildMode
var applied := 0
## One line per refused or empty tool use.
var refused: Array[String] = []
## Called after every tool use (a probe's heartbeat).
var on_edit := Callable()


func _init(with_mode: BuildMode) -> void:
	mode = with_mode


func build() -> void:
	_use(BuildMode.Tool.FLOOR, 0)
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
			_at_cell(Vector2i(x, y))
	_use(BuildMode.Tool.WALL, 0)
	for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
		if x != EXIT_CELL.x:
			_at_edge(Vector2i(x, FLOOR_MIN.y), BuildGrid.Side.NORTH)
		if x != ENTRANCE_CELL.x:
			_at_edge(Vector2i(x, FLOOR_MAX.y), BuildGrid.Side.SOUTH)
		if not SCANNER_XS.has(x):
			_at_edge(Vector2i(x, DIVIDER_Y), BuildGrid.Side.NORTH)
		_at_edge(Vector2i(x, LOBBY_Y), BuildGrid.Side.NORTH)
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		_at_edge(Vector2i(FLOOR_MIN.x, y), BuildGrid.Side.WEST)
		_at_edge(Vector2i(FLOOR_MAX.x, y), BuildGrid.Side.EAST)
	_use(BuildMode.Tool.GLASS, 0)
	for y in GLASS_YS:
		_at_edge(Vector2i(FLOOR_MIN.x, y), BuildGrid.Side.WEST)
	_use(BuildMode.Tool.DOOR, 0)
	_at_edge(Vector2i(DOOR_X, LOBBY_Y), BuildGrid.Side.NORTH)
	_use(BuildMode.Tool.DESK, 0)
	_at_cell(Vector2i(11, 11))
	_at_cell(Vector2i(14, 11))
	_use(BuildMode.Tool.SCANNER, 0)
	for x in SCANNER_XS:
		_at_cell(Vector2i(x, DIVIDER_Y - 1))
	_use(BuildMode.Tool.SEATS, 0)
	for anchor in [Vector2i(11, 3), Vector2i(14, 3), Vector2i(11, 6), Vector2i(14, 6)]:
		_at_cell(anchor)
	_use(BuildMode.Tool.ENTRANCE, 2)
	_at_cell(ENTRANCE_CELL)
	_use(BuildMode.Tool.EXIT, 0)
	_at_cell(EXIT_CELL)
	mode.set_tool(BuildMode.Tool.NONE)


func _use(tool: BuildMode.Tool, turns: int) -> void:
	mode.set_tool(tool)
	while mode.facing != turns:
		mode.rotate_facing()


func _at_cell(cell: Vector2i) -> void:
	_record(mode.apply_at(mode.grid.cell_to_world(cell)), "%s at %s" % [mode.tool, cell])


func _at_edge(cell: Vector2i, side: int) -> void:
	var step := BuildGrid.SIDE_STEP[side]
	var point := mode.grid.cell_to_world(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)
	_record(mode.apply_at(point), "%s at %s side %d" % [mode.tool, cell, side])


func _record(result: BuildResult, what: String) -> void:
	if on_edit.is_valid():
		on_edit.call()
	if result != null and result.ok:
		applied += 1
	else:
		refused.append("%s: %s" % [what, "no edit" if result == null else result.reason_text()])
