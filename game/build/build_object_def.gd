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


static func rotate_offset(offset: Vector2i, facing: int) -> Vector2i:
	match posmod(facing, 4):
		1:
			return Vector2i(-offset.y, offset.x)
		2:
			return Vector2i(-offset.x, -offset.y)
		3:
			return Vector2i(offset.y, -offset.x)
	return offset


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


## The grid direction a passenger may walk through the object in (and its
## negative). Only meaningful for walk-through objects.
func through_axis(facing: int) -> Vector2i:
	return rotate_offset(Vector2i(0, 1), facing)
