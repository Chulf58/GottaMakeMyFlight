class_name TestPullSideDoorLeaves
extends GdUnitTestSuite
## The open leaves of a sliding door are walls for a pulled roller (board
## babc77e0, user ruling open-sliding-door-leaves-count-as-obstacles-for-a-
## pulled-rol): PullSide.walls_near() gives each leaf of a door wall, and of an
## entrance or exit door's piece, as its own box, so tuck() and pick() keep the
## roller off it. The door's way through stays open. The game's doors never
## close (their leaves are always parked open beside the opening), so the
## control is the same wall run with a gap and no door: no leaf there.
##   DOOR_ROW: a plain wall on the north edge from X0 to X1, a door wall at DOOR_X.
##   GAP_ROW: the same run with no wall at all at DOOR_X.
## The exit door object is the reference terminal's, on its own grid.

const X0 := 4
const X1 := 16
const DOOR_X := 10
const DOOR_ROW := 10
const GAP_ROW := 30
## A leaf as wall_door.glb has it: 0.42 m long, 0.024 m thick, its middle
## 0.61 m along from the door's axis and 0.12 m off the wall's line.
const LEAF_HALF := Vector3(0.21, 1.105, 0.012)
const LEAF_ALONG_M := 0.61
const LEAF_OFF_M := 0.12

var _grid: BuildGrid
var _terminal: BuildGrid


func before() -> void:
	_grid = BuildGrid.new()
	var edits: Array[BuildEdit] = []
	for row in [DOOR_ROW, GAP_ROW]:
		for x in range(X0, X1):
			if row == GAP_ROW and x == DOOR_X:
				continue
			edits.append(BuildEdit.place_wall(Vector2i(x, row), BuildGrid.Side.NORTH))
	# A door goes in a wall with a plain wall on each side.
	var door := BuildGrid.WallKind.DOOR
	edits.append(BuildEdit.place_wall(Vector2i(DOOR_X, DOOR_ROW), BuildGrid.Side.NORTH, door))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	assert_int(_grid.wall_kind(Vector2i(DOOR_X, DOOR_ROW), BuildGrid.Side.NORTH)).is_equal(door)
	assert_bool(_grid.has_wall(Vector2i(DOOR_X, GAP_ROW), BuildGrid.Side.NORTH)).is_false()
	_terminal = BuildGrid.new()
	assert_bool(ReferenceTerminal.build(_terminal)).is_true()


func after() -> void:
	_grid = null
	_terminal = null


## The middle of the north edge of (DOOR_X, `row`) on `_grid`.
func _door_middle(row: int) -> Vector3:
	return BuildView.wall_transform(_grid, Vector2i(DOOR_X, row), BuildGrid.Side.NORTH).origin


## The boxes of `boxes` (walls_near()'s) shaped as a leaf.
static func _leaves(boxes: Array) -> Array:
	var out := []
	for box: Array in boxes:
		if (box[2] as Vector3).is_equal_approx(LEAF_HALF):
			out.append(box)
	return out


func test_a_door_wall_gives_its_two_open_leaves() -> void:
	var middle := _door_middle(DOOR_ROW)
	var leaves := _leaves(PullSide.walls_near(_grid, middle + Vector3(0.0, 0.0, 0.3)))
	assert_int(leaves.size()).is_equal(2)
	var along := []
	for leaf: Array in leaves:
		var centre: Vector3 = leaf[0]
		along.append(snappedf(centre.x - middle.x, 0.01))
		# Parked beside the opening, proud of the wall's face (0.07 m) on its south.
		assert_float(centre.z - middle.z).is_equal_approx(LEAF_OFF_M, 0.001)
		assert_float(centre.z - middle.z).is_greater(BuildView.WALL_THICKNESS / 2.0)
	along.sort()
	assert_array(along).is_equal([-LEAF_ALONG_M, LEAF_ALONG_M])


func test_a_gap_with_no_door_gives_no_leaf() -> void:
	var middle := _door_middle(GAP_ROW)
	var boxes := PullSide.walls_near(_grid, middle + Vector3(0.0, 0.0, 0.3))
	assert_int(_leaves(boxes).size()).is_equal(0)
	# The control has the same wall run beside the gap.
	assert_int(boxes.size()).is_greater(0)


func test_a_box_on_a_leaf_is_blocked_at_the_door_and_clear_at_the_gap() -> void:
	# A box over the east leaf only: south of the wall's face, east of the jamb.
	var box := AABB(Vector3(0.5, 0.0, 0.1), Vector3(0.2, 1.0, 0.05))
	assert_float(box.position.z).is_greater(BuildView.WALL_THICKNESS / 2.0)
	var at_door := Transform3D(Basis.IDENTITY, _door_middle(DOOR_ROW))
	var at_gap := Transform3D(Basis.IDENTITY, _door_middle(GAP_ROW))
	assert_bool(PullSide.blocked(_grid, [at_door], box, false)).is_true()
	assert_bool(PullSide.blocked(_grid, [at_gap], box, false)).is_false()


func test_the_way_through_the_door_stays_open() -> void:
	# A guest-sized box in the opening, either side of the wall's line.
	var box := AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 1.8, 0.6))
	var at_door := Transform3D(Basis.IDENTITY, _door_middle(DOOR_ROW))
	assert_bool(PullSide.blocked(_grid, [at_door], box, false)).is_false()


func test_an_exit_door_object_gives_its_leaves_inside_its_cell() -> void:
	var cell := ReferenceTerminal.EXIT_CELL + ReferenceTerminal.offset_on(_terminal)
	var id := _terminal.object_at(cell)
	assert_str(String(_terminal.get_object(id)["def"])).is_equal("exit_door")
	var centre := _terminal.cell_to_world(cell)
	var leaves := _leaves(PullSide.walls_near(_terminal, centre))
	assert_int(leaves.size()).is_equal(2)
	assert_int(PullSide.door_leaves(_terminal, id).size()).is_equal(2)
	# Its back edge is the cell's north edge (facing 0): the leaves stand on the
	# cell's side of it, 0.61 m either side of the cell's middle.
	var edge_z := centre.z - 0.5
	var along := []
	for leaf: Array in leaves:
		var at: Vector3 = leaf[0]
		assert_float(at.z - edge_z).is_equal_approx(LEAF_OFF_M, 0.001)
		along.append(snappedf(at.x - centre.x, 0.01))
	along.sort()
	assert_array(along).is_equal([-LEAF_ALONG_M, LEAF_ALONG_M])
	# No object (id 0) gives none.
	assert_int(PullSide.door_leaves(_terminal, 0).size()).is_equal(0)
