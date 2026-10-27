class_name BuildObjectDef
extends Resource
## A placeable object type. Cells are in the object's own frame at facing 0:
## the footprint is size.x by size.y cells from the anchor, and the front is
## +y (south, towards the default camera). Each facing turns the frame a
## quarter turn about the anchor cell: (x, y) -> (-y, x).

const NO_CELL := Vector2i(-1, -1)

@export var id: StringName = &""
@export var display_name := ""
@export var size := Vector2i.ONE
## Walk-through objects (a scanner) keep their cells walkable, but only along
## their own y axis: their long sides block sideways steps.
@export var walk_through := false
@export var has_interaction := false
## The cell a passenger stands on to use the object, in the object's frame.
## It must lie outside the footprint and next to it.
@export var interaction_offset := Vector2i.ZERO
@export var height := 1.0
@export var color := Color.WHITE
## Seats in the object's frame at facing 0, in seat-id order: each
## {"cell": Vector2i, "approach": Vector2i, "root": Vector2, "facing": Vector2i}.
## "cell" is the chair's footprint cell, "approach" the free cell next to it a
## guest walks to before sitting, "root" where the seated guest's feet are,
## in cells from the chair cell's centre, and "facing" the way the guest looks.
@export var seats: Array[Dictionary] = []


static func rotate_offset(offset: Vector2i, facing: int) -> Vector2i:
	match posmod(facing, 4):
		1:
			return Vector2i(-offset.y, offset.x)
		2:
			return Vector2i(-offset.x, -offset.y)
		3:
			return Vector2i(offset.y, -offset.x)
	return offset


## rotate_offset() for a point that need not be on a cell.
static func rotate_point(point: Vector2, facing: int) -> Vector2:
	match posmod(facing, 4):
		1:
			return Vector2(-point.y, point.x)
		2:
			return Vector2(-point.x, -point.y)
		3:
			return Vector2(point.y, -point.x)
	return point


## Where a seat_descriptors() entry's seated guest stands, in world space.
static func seat_root_world(grid: BuildGrid, seat: Dictionary) -> Vector3:
	var root: Vector2 = seat["root"]
	return grid.cell_to_world(seat["cell"]) + Vector3(root.x, 0.0, root.y)


func footprint(anchor: Vector2i, facing: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(anchor + rotate_offset(Vector2i(x, y), facing))
	return cells


## The interaction cell on the grid, or NO_CELL when the object has none.
func interaction_cell(anchor: Vector2i, facing: int) -> Vector2i:
	if not has_interaction:
		return NO_CELL
	return anchor + rotate_offset(interaction_offset, facing)


## The seats on the grid, turned with the object: each seat's "index" (its
## seat id within the object), "cell", "approach", "root" and "facing".
func seat_descriptors(anchor: Vector2i, facing: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in seats.size():
		var seat: Dictionary = seats[i]
		(
			out
			. append(
				{
					"index": i,
					"cell": anchor + rotate_offset(seat["cell"], facing),
					"approach": anchor + rotate_offset(seat["approach"], facing),
					"root": rotate_point(seat["root"], facing),
					"facing": rotate_offset(seat["facing"], facing),
				}
			)
		)
	return out


## The grid direction a passenger may walk through the object in (and its
## negative). Only meaningful for walk-through objects.
func through_axis(facing: int) -> Vector2i:
	return rotate_offset(Vector2i(0, 1), facing)
