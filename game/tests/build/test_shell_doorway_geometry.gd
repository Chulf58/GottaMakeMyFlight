class_name TestShellDoorwayGeometry
extends GdUnitTestSuite
## ShellCutaway's doorway rules: when a side's doorways open, the hole over
## an opening and over a porch sign, and where the two jambs stand.

const NORTH := ShellCutaway.Side.NORTH
const SOUTH := ShellCutaway.Side.SOUTH
const EAST := ShellCutaway.Side.EAST
const WEST := ShellCutaway.Side.WEST

var _cut: ShellCutaway


func before_test() -> void:
	_cut = ShellCutaway.new()


func test_a_doorway_opens_once_its_side_is_half_cut() -> void:
	_cut.roof_level = 1.0
	_cut.side_levels = [0.0, 0.4, 0.5, 1.0]
	assert_bool(_cut.doorway_open(NORTH)).is_false()
	assert_bool(_cut.doorway_open(SOUTH)).is_false()
	assert_bool(_cut.doorway_open(EAST)).is_true()
	assert_bool(_cut.doorway_open(WEST)).is_true()
	# Behind the roof gate: a camera-side doorway stays shut while the roof is drawn.
	_cut.roof_level = 0.0
	assert_bool(_cut.doorway_open(WEST)).is_false()


## Doorway_3: on the north backdrop line, 2.30 m wide, facing -z.
func test_the_hole_spans_the_opening_and_nothing_beside_it() -> void:
	var hole := ShellCutaway.hole_box(Vector3(16.0, 0.3, -15.25), Vector3(0.0, 0.0, -1.0), 2.3)
	# The squashed lintel over the opening, and the full-height one.
	assert_bool(hole.has_point(Vector3(16.0, 0.55, -15.25))).is_true()
	assert_bool(hole.has_point(Vector3(17.1, 4.5, -15.45))).is_true()
	assert_bool(hole.has_point(Vector3(14.9, 0.55, -15.05))).is_true()
	# The kerb and the wall jamb faces just beside the opening stay.
	assert_bool(hole.has_point(Vector3(16.0 + 1.16, 0.5, -15.25))).is_false()
	assert_bool(hole.has_point(Vector3(16.0 - 1.16, 0.5, -15.25))).is_false()
	# The wall jamb faces at the opening edges (+-1.15) stay: the hole is inset.
	assert_bool(hole.has_point(Vector3(16.0 + 1.15, 0.5, -15.25))).is_false()
	assert_bool(hole.has_point(Vector3(16.0 - 1.15, 0.5, -15.25))).is_false()


func test_the_hole_turns_with_an_east_or_west_doorway() -> void:
	var hole := ShellCutaway.hole_box(Vector3(33.0, 0.3, 2.0), Vector3(1.0, 0.0, 0.0), 2.3)
	assert_bool(hole.has_point(Vector3(33.2, 0.55, 2.0 + 1.1))).is_true()
	assert_bool(hole.has_point(Vector3(33.0, 0.55, 2.0 + 1.16))).is_false()


## Porch_6's bounds; its letter sign is in Lot at x 15.6-16.4, y 4.08-5.0,
## z 19.0-19.2 (measured on tp_airport_shell.glb).
func test_the_sign_box_covers_the_porch_sign_and_not_the_ground() -> void:
	var porch := AABB(Vector3(14.85, 0.1, 15.6), Vector3(2.3, 4.73, 3.9))
	var sign_box := ShellCutaway.sign_box(porch)
	assert_bool(sign_box.has_point(Vector3(15.6, 4.08, 19.0))).is_true()
	assert_bool(sign_box.has_point(Vector3(16.4, 5.0, 19.2))).is_true()
	assert_bool(sign_box.has_point(Vector3(16.0, 0.3, 17.0))).is_false()
	assert_bool(sign_box.has_point(Vector3(16.0, 3.0, 17.0))).is_false()


func test_two_jambs_stand_at_the_opening_edges() -> void:
	var jambs := ShellCutaway.jamb_transforms(
		Vector3(16.0, 0.3, 15.65), Vector3(0.0, 0.0, 1.0), 2.3
	)
	assert_int(jambs.size()).is_equal(2)
	var xs: Array[float] = []
	for jamb in jambs:
		assert_float(jamb.origin.y).is_equal_approx(ShellCutaway.FLOOR_Y, 1e-5)
		assert_float(jamb.origin.z).is_equal_approx(15.65, 1e-5)
		# The kit wall is 1 m long on x and WALL_HEIGHT tall: the jamb is
		# JAMB_WIDTH along the facade and JAMB_HEIGHT tall.
		assert_float((jamb.basis * Vector3(1.0, 0.0, 0.0)).length()).is_equal_approx(
			ShellCutaway.JAMB_WIDTH, 1e-5
		)
		var top := jamb * Vector3(0.0, InteriorKit.WALL_HEIGHT, 0.0)
		assert_float(top.y).is_equal_approx(ShellCutaway.FLOOR_Y + ShellCutaway.JAMB_HEIGHT, 1e-5)
		xs.append(jamb.origin.x)
	xs.sort()
	var edge := 1.15 + ShellCutaway.JAMB_WIDTH * 0.5
	assert_float(xs[0]).is_equal_approx(16.0 - edge, 1e-5)
	assert_float(xs[1]).is_equal_approx(16.0 + edge, 1e-5)
	# A jamb is taller than the kerb, so the opening reads as a door frame.
	assert_float(ShellCutaway.JAMB_HEIGHT).is_greater(InteriorKit.STUB_HEIGHT)
