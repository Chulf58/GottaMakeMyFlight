class_name ShellDefinition
extends Resource
## The Toon terminal shell as the game's rules see it, authored in
## build/toon_terminal_shell.tres against tp_airport_shell.glb: the build grid's
## frame (the buildable ground floor) and one ShellDoorConnection per Toon
## doorway. BuildMode takes its grid frame from it and snaps the Entrance and
## Exit tools to its doors, PassengerSim walks its outside routes, and a saved
## grid is restored only when it fits it (snapshot_problem()). Facade segments
## are not here yet: nothing reads them until the shell walls become
## removable.

## How far from a door's cell, in metres, the Entrance and Exit tools snap to it.
const SNAP_RADIUS_M := 3.0
const ORIGIN_TOLERANCE_M := 0.001

## World position of grid cell (0, 0)'s north-west corner; y is the floor.
## In the Toon shell the floor is 2 cm above the shell's ground slab (y 0.3),
## because the kit's floor tiles have their top at the grid floor and would
## z-fight with the slab at the same height.
@export var grid_origin := Vector3.ZERO
@export var grid_size := Vector2i.ONE
@export var connections: Array[ShellDoorConnection] = []


## The middle of the buildable floor, at floor height.
func centre() -> Vector3:
	return grid_origin + Vector3(grid_size.x / 2.0, 0.0, grid_size.y / 2.0)


## The connection a door object of `def_id` at `cell` and `facing` stands on,
## or null when it is not on a Toon door of its kind.
func connection_for(def_id: StringName, cell: Vector2i, facing: int) -> ShellDoorConnection:
	var kind := ShellDoorConnection.kind_for(def_id)
	for c in connections:
		if c.kind == kind and c.cell == cell and c.facing == posmod(facing, 4):
			return c
	return null


## The connection of the kind `def_id` needs whose cell centre is nearest
## `point` and within SNAP_RADIUS_M of it, or null.
func nearest(grid: BuildGrid, def_id: StringName, point: Vector3) -> ShellDoorConnection:
	var kind := ShellDoorConnection.kind_for(def_id)
	var best: ShellDoorConnection = null
	var best_m := SNAP_RADIUS_M
	for c in connections:
		var centre_at := grid.cell_to_world(c.cell)
		var m := Vector2(point.x - centre_at.x, point.z - centre_at.z).length()
		if c.kind == kind and m <= best_m:
			best = c
			best_m = m
	return best


## Why a BuildGrid snapshot cannot be restored into this shell, or "" when it
## can: it must be well formed, have this frame (a save from before the shell
## has none, or the forecourt's) and load, and every entrance and exit must
## stand on a Toon door of its kind with nothing on its way out. Nothing is
## changed.
func snapshot_problem(data: Dictionary) -> String:
	var problem := BuildGridSnapshot.problem(data)
	if problem != "":
		return problem
	var size := Vector2i(int(data["width"]), int(data["height"]))
	if not data.has("origin") or size != grid_size or not _origin_matches(data["origin"]):
		return "the grid was saved in another frame than the terminal shell's"
	var grid := BuildGrid.new(grid_size, grid_origin)
	if not grid.from_snapshot(data):
		return "the grid snapshot was refused"
	for object_id in grid.object_ids():
		var record := grid.get_object(object_id)
		if not BuildCatalog.is_door(record["def"]):
			continue
		var anchor: Vector2i = record["anchor"]
		if connection_for(record["def"], anchor, record["facing"]) == null:
			return "%s at %s is not on a Toon door of its kind" % [record["def"], anchor]
		var side := BuildGrid.SIDE_STEP.find(DoorPlacement.back_step(record["facing"]))
		if grid.wall_kind(anchor, side) != BuildGrid.WallKind.NONE:
			return "%s at %s has a wall on its way out" % [record["def"], anchor]
	return ""


## `saved` is an origin BuildGridSnapshot.problem() accepted.
func _origin_matches(saved: Array) -> bool:
	var at := Vector3(saved[0], saved[1], saved[2])
	return at.distance_to(grid_origin) <= ORIGIN_TOLERANCE_M
