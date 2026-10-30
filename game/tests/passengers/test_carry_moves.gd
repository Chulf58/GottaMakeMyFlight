class_name TestCarryMoves
extends GdUnitTestSuite
## The bag paths that keep clear of the walker's own body (CarryMoves; board
## item pre-existing-carry-self-clips-found-by-game-spike-basic-scan): a bag
## picked up from the floor ahead stays ahead of the knees and comes back
## outside the thigh. Body frame: x across (the right hand at -x), +z ahead,
## the floor at y 0.

## Where the thighs reach (body points the crossing probe found inside bags:
## x within 0.2 m of the centre line, y 0.6-0.87 m, up to 0.27 m ahead), and
## below them the knees and shins of a stride (the leading foot 0.3-0.35 m
## ahead, CarryOnProps.PICK_AHEAD_M).
const THIGHS := AABB(Vector3(-0.2, 0.5, -0.15), Vector3(0.4, 0.45, 0.45))
const SHINS := AABB(Vector3(-0.2, 0.05, -0.15), Vector3(0.4, 0.5, 0.51))


## The bag's corners at `xf`.
func _corners(xf: Transform3D, box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(xf * box.get_endpoint(i))
	return out


## The bag's box at `xf` (its corners' bounds).
func _bounds(xf: Transform3D, box: AABB) -> AABB:
	var corners := _corners(xf, box)
	var out := AABB(corners[0], Vector3.ZERO)
	for c in corners:
		out = out.expand(c)
	return out


## A hard case picked up from the floor spot ahead of the walker (lying across,
## FLOOR_AHEAD_M ahead) to the right hand never has its box in the legs, and
## starts and ends where asked. Control: the spot counts as ahead.
func test_a_case_picked_up_ahead_stays_out_of_the_legs() -> void:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.CASE)
	var spot := Transform3D(
		Basis(Vector3.UP, PI / 2.0), Vector3(0.0, 0.0, SecurityLooks.FLOOR_AHEAD_M)
	)
	assert_bool(CarryMoves.picks_up_ahead(spot)).is_true()
	for grip_z in [-0.1, 0.0, 0.15]:
		var held := CarryOnProps.carried(Vector3(-0.38, 0.93, grip_z), Vector3.ZERO, 0.0, 1.0)
		for step in 61:
			var k := step / 60.0
			var xf := CarryMoves.pick_up(spot, held, k)
			var b := _bounds(xf, box)
			(
				assert_bool(b.intersects(THIGHS) or b.intersects(SHINS))
				. override_failure_message(
					"grip z %.2f k %.3f: case %s in the legs" % [grip_z, k, b]
				)
				. is_false()
			)
		assert_vector(CarryMoves.pick_up(spot, held, 0.0).origin).is_equal_approx(
			spot.origin, Vector3.ONE * 0.0001
		)
		assert_vector(CarryMoves.pick_up(spot, held, 1.0).origin).is_equal_approx(
			held.origin, Vector3.ONE * 0.0001
		)
	(
		assert_bool(
			CarryMoves.picks_up_ahead(Transform3D(Basis.IDENTITY, Vector3(-0.45, 0.0, 0.0)))
		)
		. is_false()
	)
