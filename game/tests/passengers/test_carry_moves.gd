class_name TestCarryMoves
extends GdUnitTestSuite
## The bag paths that keep clear of the walker's own body (CarryMoves; board
## item pre-existing-carry-self-clips-found-by-game-spike-basic-scan): a roller
## held in the hand joins the overhead route through a gate ahead of the body,
## whichever side of the body's centre its origin is; a bag picked up from the
## floor ahead stays ahead of the knees and comes back outside the thigh. Body
## frame: x across (the right hand at -x), +z ahead, the floor at y 0.

## Where the thighs reach (body points the crossing probe found inside bags:
## x within 0.2 m of the centre line, y 0.6-0.87 m, up to 0.27 m ahead), and
## below them the knees and shins of a stride (the leading foot 0.3-0.35 m
## ahead, CarryOnProps.PICK_AHEAD_M).
const THIGHS := AABB(Vector3(-0.2, 0.5, -0.15), Vector3(0.4, 0.45, 0.45))
const SHINS := AABB(Vector3(-0.2, 0.05, -0.15), Vector3(0.4, 0.5, 0.51))
## The head and shoulders, from the shoulders to the top of the head.
const UPPER := AABB(Vector3(-0.25, 1.3, -0.2), Vector3(0.5, 0.6, 0.4))


## A roller lifted by its handle in the right hand at `grip`.
func _roller_in_hand(grip: Vector3) -> Transform3D:
	return CarryOnProps.carried(grip, Vector3.ZERO, 0.0, 1.0, SecurityLooks.Kind.ROLLER)


## A pulled roller behind the walker on the right hand's side.
func _roller_pulled() -> Transform3D:
	return CarryOnProps.pulled(Vector3(-0.34, 0.9, -0.1), Vector3(-0.3, 0.03, -1.0), 1.0)


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


## A roller lowered from the hand to the pull, or lifted from the pull to the
## hand, never has its box in the legs, the head or the shoulders, with the
## hand's swing putting the grip ahead of or behind the body's centre. Control:
## the old route (no gate) puts the box in the head when the grip is behind.
func test_a_roller_in_hand_joins_the_route_through_a_gate_ahead() -> void:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var pulled := _roller_pulled()
	var checked := 0
	for grip_z in [-0.1, -0.02, 0.05, 0.15]:
		var held := _roller_in_hand(Vector3(-0.36, 0.9, grip_z))
		for step in 61:
			var k := step / 60.0
			var lowering := CarryOnProps.overhead(
				held, pulled, k, box, CarryOnProps.ROLLER_LAND, true, false
			)
			var lifting := CarryOnProps.overhead(pulled, held, k, box, 1.0, false, true)
			for xf: Transform3D in [lowering, lifting]:
				var b := _bounds(xf, box)
				(
					assert_bool(b.intersects(THIGHS) or b.intersects(SHINS))
					. override_failure_message(
						"grip z %.2f k %.3f: bag %s in the legs" % [grip_z, k, b]
					)
					. is_false()
				)
				(
					assert_bool(b.intersects(_forearm(held)))
					. override_failure_message(
						"grip z %.2f k %.3f: bag %s in the forearm" % [grip_z, k, b]
					)
					. is_false()
				)
				(
					assert_bool(b.intersects(UPPER))
					. override_failure_message(
						"grip z %.2f k %.3f: bag %s in the head or shoulders" % [grip_z, k, b]
					)
					. is_false()
				)
				checked += 1
		# Lands in the hand at the end of the move, not at ROLLER_LAND.
		var early := CarryOnProps.overhead(
			pulled, held, CarryOnProps.ROLLER_LAND, box, 1.0, false, true
		)
		assert_float(early.origin.distance_to(held.origin)).is_greater(0.05)
		var landed := CarryOnProps.overhead(pulled, held, 1.0, box, 1.0, false, true)
		assert_vector(landed.origin).is_equal_approx(held.origin, Vector3.ONE * 0.0001)
	assert_int(checked).is_equal(4 * 61 * 2)
	var behind := _roller_in_hand(Vector3(-0.36, 0.9, -0.1))
	var hit := false
	for step in 61:
		var old := CarryOnProps.overhead(behind, pulled, step / 60.0, box, CarryOnProps.ROLLER_LAND)
		hit = hit or _bounds(old, box).intersects(UPPER)
	assert_bool(hit).override_failure_message("control: the old route never met the head").is_true()


## The gate puts the bag's nearest face FRONT_CLEAR_M ahead, at the end's own
## side and height, and leaves an end already further ahead where it is.
func test_the_gate_is_ahead_at_the_ends_side_and_height() -> void:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var held := _roller_in_hand(Vector3(-0.36, 0.9, 0.0))
	var gate := CarryMoves.gate(held, box)
	assert_float(gate.x).is_equal_approx(held.origin.x, 0.0001)
	assert_float(gate.y).is_equal_approx(held.origin.y, 0.0001)
	var at_gate := Transform3D(held.basis, gate)
	var nearest := INF
	for c in _corners(at_gate, box):
		nearest = minf(nearest, c.z)
	assert_float(nearest).is_equal_approx(CarryMoves.FRONT_CLEAR_M, 0.0001)
	var far := Transform3D(held.basis, held.origin + Vector3(0.0, 0.0, 2.0))
	assert_vector(CarryMoves.gate(far, box)).is_equal_approx(far.origin, Vector3.ONE * 0.0001)


## Without a hand end the route is the old one, written out here as it was
## before the gates (rise to the centre plane ROUTE_FRONT_M ahead or
## ROUTE_BACK_M behind, cross at the height that puts the lowest point at
## OVERHEAD_M, come down), so a change to the helper cannot move it unseen.
func test_without_a_hand_end_the_route_is_unchanged() -> void:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK)
	var on_floor := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.0, 0.0, 0.56))
	var worn := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 1.1, -0.21))
	for step in 13:
		var k := step / 12.0
		var a := CarryOnProps.overhead(on_floor, worn, k, box)
		assert_vector(a.origin).is_equal_approx(
			_old_route(on_floor, worn, k, box), Vector3.ONE * 0.0001
		)


## The overhead route's origin as built before the gates (carry-on-bag-kinds-as-
## built), land 1.
func _old_route(from: Transform3D, to: Transform3D, k: float, box: AABB) -> Vector3:
	var turned := clampf(k * 3.0 - 1.0, 0.0, 1.0)
	var turn := from.basis.get_rotation_quaternion().slerp(
		to.basis.get_rotation_quaternion(), turned
	)
	var basis := Basis(turn).scaled(from.basis.get_scale().lerp(to.basis.get_scale(), turned))
	var lowest := INF
	for i in 8:
		lowest = minf(lowest, (basis * box.get_endpoint(i)).y)
	var high := CarryOnProps.OVERHEAD_M - lowest
	var ends: Array[Vector3] = []
	for at: Vector3 in [from.origin, to.origin]:
		var z := (
			maxf(at.z, CarryOnProps.ROUTE_FRONT_M)
			if at.z >= 0.0
			else minf(at.z, -CarryOnProps.ROUTE_BACK_M)
		)
		ends.append(Vector3(0.0, high, z))
	if k < 1.0 / 3.0:
		return from.origin.lerp(ends[0], k * 3.0)
	if k < 2.0 / 3.0:
		return ends[0].lerp(ends[1], k * 3.0 - 1.0)
	return ends[1].lerp(to.origin, k * 3.0 - 2.0)


## Where the holding forearm is above a roller held at the side by `held`'s
## grip (the crossing probe's forearm points inside a lifted or lowered
## roller: 0.02-0.04 m inside the grip across, 0.12-0.45 m above it).
func _forearm(held: Transform3D) -> AABB:
	var grip := held * CarryOnProps.ROLLER_HANDLE
	var inward := signf(-grip.x)
	var near := grip + Vector3(inward * 0.02, 0.12, -0.1)
	var far := grip + Vector3(inward * 0.15, 0.45, 0.05)
	return AABB(near.min(far), (far - near).abs())


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
