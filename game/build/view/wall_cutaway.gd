class_name WallCutaway
extends RefCounted
## Which walls the build view cuts down to a stub, so that a wall facing the
## camera never hides a room (decision
## camera-tilt-follows-zoom-wall-cutaway-wide-zoom-view-jumps). View only: it
## reads the grid and the camera's yaw and changes neither.
##
## The rule: every wall edge runs along x or z. For each axis the cutaway keeps
## the side the camera looks from (+1 or -1, or 0 before the camera has looked
## clearly along it). A wall drops when the cell on its far side, away from the
## camera, has floor: the near wall of a room drops, its far wall (with outside
## behind it) stays full, and so does a wall standing on bare ground. The side
## of an axis only changes once the camera's heading is more than DEADBAND off
## edge-on, so a wall seen side-on does not flicker as the camera turns.
##
## It does not find rooms: a partition with floor behind it drops whatever room
## the camera is looking at.

## Below this share of the horizontal view direction an axis keeps its side.
const DEADBAND := 0.1
## Vertex directions, as bits.
const EAST := 1
const WEST := 2
const SOUTH := 4
const NORTH := 8

var side_x := 0
var side_z := 0


## Takes the camera's direction toward the eye (its basis z) and updates the
## sides. Returns true when a side changed.
func update(toward_eye: Vector3) -> bool:
	var flat := Vector2(toward_eye.x, toward_eye.z)
	if flat.length() < 0.001:
		return false
	flat = flat.normalized()
	var before := Vector2i(side_x, side_z)
	if absf(flat.x) >= DEADBAND:
		side_x = 1 if flat.x > 0.0 else -1
	if absf(flat.y) >= DEADBAND:
		side_z = 1 if flat.y > 0.0 else -1
	return before != Vector2i(side_x, side_z)


func reset() -> void:
	side_x = 0
	side_z = 0


## Whether the wall on `side` of `cell` drops. Either form of an edge (from
## the cell on each side of it) gives the same answer.
func is_cut(grid: BuildGrid, cell: Vector2i, side: int) -> bool:
	var step := BuildGrid.SIDE_STEP[side]
	var toward_camera := side_x * step.x + side_z * step.y
	if toward_camera == 0:
		return false
	var far := cell if toward_camera > 0 else cell + step
	return grid.in_bounds(far) and grid.floor_at(far) != BuildGrid.FLOOR_NONE


## Every walled edge once, as Vector3i(x, y, side): the north and west edge of
## each cell, plus the south edge of the last row and the east edge of the last
## column.
static func wall_edges(grid: BuildGrid) -> Array[Vector3i]:
	var edges: Array[Vector3i] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			var sides := [BuildGrid.Side.NORTH, BuildGrid.Side.WEST]
			if y == grid.size.y - 1:
				sides.append(BuildGrid.Side.SOUTH)
			if x == grid.size.x - 1:
				sides.append(BuildGrid.Side.EAST)
			for side in sides:
				if grid.has_wall(cell, side):
					edges.append(Vector3i(x, y, side))
	return edges


## The two edges in line with `edge`, one either end, in wall_edges form.
static func inline_neighbours(edge: Vector3i) -> Array[Vector3i]:
	var along := Vector3i(1, 0, 0)
	if edge.z == BuildGrid.Side.EAST or edge.z == BuildGrid.Side.WEST:
		along = Vector3i(0, 1, 0)
	return [edge - along, edge + along]


## Posts for the walls: vertex (in grid corner coordinates) -> true for a
## full-height post, false for a stub. A vertex gets a post unless it joins
## exactly two walls in a straight line; the post is full when any wall at it
## is drawn full. `full` maps an edge (wall_edges form) to whether it is full.
static func posts(edges: Array[Vector3i], full: Dictionary) -> Dictionary:
	var masks := {}
	var tall := {}
	for edge in edges:
		var ends := _edge_ends(edge)
		var horizontal := edge.z == BuildGrid.Side.NORTH or edge.z == BuildGrid.Side.SOUTH
		var bits := [EAST, WEST] if horizontal else [SOUTH, NORTH]
		for i in 2:
			var vertex: Vector2i = ends[i]
			masks[vertex] = masks.get(vertex, 0) | bits[i]
			tall[vertex] = tall.get(vertex, false) or full.get(edge, true)
	var result := {}
	for vertex in masks:
		var mask: int = masks[vertex]
		if mask != EAST | WEST and mask != NORTH | SOUTH:
			result[vertex] = tall[vertex]
	return result


## The start and end vertex of an edge: west then east, or north then south.
static func _edge_ends(edge: Vector3i) -> Array[Vector2i]:
	var x := edge.x
	var y := edge.y
	match edge.z:
		BuildGrid.Side.NORTH:
			return [Vector2i(x, y), Vector2i(x + 1, y)]
		BuildGrid.Side.SOUTH:
			return [Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]
		BuildGrid.Side.WEST:
			return [Vector2i(x, y), Vector2i(x, y + 1)]
	return [Vector2i(x + 1, y), Vector2i(x + 1, y + 1)]
