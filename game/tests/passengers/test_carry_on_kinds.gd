class_name TestCarryOnKinds
extends GdUnitTestSuite
## Carry-on bag kinds (decision carry-on-bag-kinds-backpack-shoulder-or-tote-
## bag-small-rolle): which kind a bag is (a fixed hash of the passenger's id,
## no saved state), how each kind is worn or pulled (CarryOnProps' static
## transforms: the pull, the shoulder, the back, a trailing axle; the moves
## between homes are tested in TestCarryLead) and what each kind does in a
## cell closed on both sides (only the hard case turns to the front, a roller
## lifted at security included; worn bags keep their carry, inside the
## corridor).

const CORRIDOR := Vector2i(4, 6)
const IDS := 2000

var _worlds: Array[SecurityTestWorld] = []
var _views: Array[PassengerViews] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for v in _views:
		v.free()
	_views.clear()
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


func _passenger(id: int) -> Passenger:
	var p := Passenger.new()
	p.id = id
	return p


## The kind is the same every time for the same passenger, whatever else the
## passenger holds, and the four kinds come up in about equal shares.
func test_the_kind_is_a_fixed_hash_of_the_id() -> void:
	var counts := [0, 0, 0, 0]
	for id in range(1, IDS + 1):
		var p := _passenger(id)
		var kind := SecurityLooks.bag_kind(p, 0)
		counts[kind] += 1
		p.carry_on = 2
		p.variant = 1
		p.stage = Passenger.Stage.SEATED
		assert_int(SecurityLooks.bag_kind(p, 0)).is_equal(kind)
		assert_int(SecurityLooks.bag_kind(_passenger(id), 0)).is_equal(kind)
	print("first-bag kinds over %d ids (case, backpack, shoulder, roller): %s" % [IDS, counts])
	for count: int in counts:
		assert_int(count).is_between(IDS * 18 / 100, IDS * 32 / 100)


## A second bag never repeats a backpack or a roller; a second shoulder bag
## or hard case is allowed, and every kind still comes up as a second bag.
func test_a_second_bag_never_repeats_a_backpack_or_a_roller() -> void:
	var seconds := [0, 0, 0, 0]
	var repeats := 0
	for id in range(1, IDS + 1):
		var p := _passenger(id)
		var first := SecurityLooks.bag_kind(p, 0)
		var second := SecurityLooks.bag_kind(p, 1)
		seconds[second] += 1
		if first == second:
			repeats += 1
			assert_int(first).is_not_equal(SecurityLooks.Kind.BACKPACK)
			assert_int(first).is_not_equal(SecurityLooks.Kind.ROLLER)
	print("second-bag kinds: %s, same kind twice: %d" % [seconds, repeats])
	assert_int(repeats).is_greater(0)
	for count: int in seconds:
		assert_int(count).is_greater(IDS / 10)


## Each kind is carried its natural way, and its piece exists in the kit.
func test_each_kind_has_its_carry_and_its_piece() -> void:
	var want := {
		SecurityLooks.Kind.CASE: SecurityLooks.Carry.HAND,
		SecurityLooks.Kind.BACKPACK: SecurityLooks.Carry.BACK,
		SecurityLooks.Kind.SHOULDER: SecurityLooks.Carry.SHOULDER,
		SecurityLooks.Kind.ROLLER: SecurityLooks.Carry.PULL,
	}
	assert_dict(SecurityLooks.KIND_CARRY).is_equal(want)
	for kind in SecurityLooks.Kind.values():
		var size := CarryOnProps.bag_size(kind)
		print("kind %d %s size %s" % [kind, SecurityLooks.KIND_PIECES[kind], size])
		# Fits a tray (inner 0.41 x 0.57 m) lying flat, and two end to end at 0.55.
		assert_float(size.x).is_less(0.41)
		assert_float(size.z).is_less(0.57)
		assert_float(size.z * SecurityLooks.TWO_BAG_SCALE).is_less(0.285)
	assert_int(SecurityLooks.worn_side(0)).is_equal(0)
	assert_int(SecurityLooks.worn_side(1)).is_equal(1)


## A pulled roller: its axle where asked (the wheels on the floor), the grip
## on the line through the axle along its length, its back panel down toward
## the walker, and the rods long enough for the grip bar to reach the hand.
func test_a_pulled_roller_runs_from_the_floor_to_the_hand() -> void:
	for scale_by in [1.0, SecurityLooks.TWO_BAG_SCALE]:
		var grip := Vector3(0.3, 1.0, -0.1)
		var axle := Vector3(0.05, 0.03 * scale_by, -0.85)
		var xf := CarryOnProps.pulled(grip, axle, scale_by)
		assert_vector(xf * CarryOnProps.ROLLER_AXLE).is_equal_approx(axle, Vector3.ONE * 0.0001)
		var local := xf.affine_inverse() * grip
		assert_float(local.x).is_equal_approx(0.0, 0.0001)
		assert_float(local.y).is_equal_approx(CarryOnProps.ROLLER_AXLE.y, 0.0001)
		assert_float(local.z).is_greater(0.0)
		# The front panel (+y) faces up and away from the walker.
		var front := xf.basis.y.normalized()
		var toward := grip - axle
		toward.y = 0.0
		assert_float(front.y).is_greater(0.0)
		assert_float(front.dot(toward)).is_less(0.0)
		var length := CarryOnProps._pull_length(grip, axle, scale_by, 0.22)
		var reached := 0.22 + length + CarryOnProps.ROLLER_GRIP_PAST_TOP_M
		assert_float(reached).is_equal_approx(local.z, 0.0001)


## A worn shoulder bag hangs from its strap's bar over the shoulder joint,
## upright, its inner face outside the hip (0.196 m), under the elbow.
func test_a_shoulder_bag_hangs_from_the_shoulder_outside_the_hip() -> void:
	var base := Vector3(0.0, 0.05, 0.14)
	for side in 2:
		var joint := Vector3(-0.206 if side == 0 else 0.206, 1.644, -0.061)
		var hung := CarryWorn.shoulder(joint, Vector3.ZERO, 0.0, side, 1.0, base)
		var xf: Transform3D = hung[0]
		var length: float = hung[1]
		var bar := xf * (base + Vector3(0.0, 0.0, length))
		assert_float(bar.y).is_equal_approx(joint.y + CarryOnProps.STRAP_OVER_ARM_M, 0.0001)
		assert_float(absf(bar.x)).is_equal_approx(CarryOnProps.STRAP_OUT_M, 0.0001)
		assert_float(signf(bar.x)).is_equal(signf(joint.x))
		assert_vector(xf.basis.z.normalized()).is_equal_approx(Vector3.UP, Vector3.ONE * 0.0001)
		# The inner face (local y = 0) the strips' depth in from the strap, the
		# bag's top STRAP_M under the bar.
		var inner := xf * Vector3.ZERO
		assert_float(absf(inner.x)).is_equal_approx(CarryOnProps.STRAP_OUT_M - base.y, 0.0001)
		assert_float(absf(inner.x)).is_greater(0.21)
		var top := xf * Vector3(0.0, 0.0, base.z)
		assert_float(top.y).is_equal_approx(bar.y - CarryOnProps.STRAP_M, 0.0001)


## A worn backpack: the top of its back panel BACK_FROM_SPINE_M behind the
## spine bone and just above it, its length along the bone leaning in at the
## top by BACK_LEAN_DEGREES (so its bottom stands further out, clear of the
## hips), behind the body.
func test_a_backpack_is_worn_behind_the_spine() -> void:
	var spine := Transform3D(Basis(Vector3.RIGHT, -0.1), Vector3(0.0, 1.544, -0.047))
	var xf := CarryOnProps.worn_back(spine, 0.0, 1.0)
	var along := xf.basis.z.normalized()
	var lean := rad_to_deg(along.angle_to(spine.basis.y.normalized()))
	assert_float(lean).is_equal_approx(CarryOnProps.BACK_LEAN_DEGREES, 0.01)
	var top := CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK).end.z
	var top_inner := xf * Vector3(0.0, 0.0, top)
	var bottom_inner := (
		xf * Vector3(0.0, 0.0, CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK).position.z)
	)
	var up := spine.basis.y.normalized()
	var out := (top_inner - spine.origin) - up * (top_inner - spine.origin).dot(up)
	assert_float(out.length()).is_equal_approx(CarryOnProps.BACK_FROM_SPINE_M, 0.0001)
	assert_float((top_inner - spine.origin).dot(up)).is_equal_approx(
		CarryOnProps.BACK_TOP_OVER_SPINE_M, 0.0001
	)
	# Behind the body (it faces +Z), the bottom further back than the top.
	assert_float(top_inner.z).is_less(spine.origin.z)
	assert_float(bottom_inner.z).is_less(top_inner.z)


## The roller's axle is TRAIL_M back along the line the body walked: on a
## straight walk straight behind, and round a right-angle corner on the walked
## line itself (never cutting the corner, where a lane part may stand). Before
## any step it is TRAIL_M along `back`. Control: it moves round the corner.
func test_a_trailing_axle_follows_the_walked_line() -> void:
	var back := Vector3(0.0, 0.0, -1.0)
	var start := CarryOnProps.trail([Vector3.ZERO], back)
	assert_vector(start).is_equal_approx(back * CarryOnProps.TRAIL_M, Vector3.ONE * 0.0001)
	var walked: Array = [Vector3.ZERO]
	for i in 30:
		walked.append(walked[-1] + Vector3(0.0, 0.0, 0.08))
	var axle := CarryOnProps.trail(walked, back)
	assert_vector(axle).is_equal_approx(
		walked[-1] - Vector3(0.0, 0.0, CarryOnProps.TRAIL_M), Vector3.ONE * 0.0001
	)
	var corner: Vector3 = walked[-1]
	var worst := 0.0
	for i in 30:
		walked.append(walked[-1] + Vector3(0.08, 0.0, 0.0))
		axle = CarryOnProps.trail(walked, back)
		# Off the walked polyline: the leg along z, then the leg along x.
		var off := absf(axle.x) if axle.z < corner.z - 0.0001 else absf(axle.z - corner.z)
		worst = maxf(worst, off)
	print("trailing axle round a right-angle corner: worst off the walked line %.4f m" % worst)
	assert_float(worst).is_less(0.0001)
	assert_float(axle.x).is_greater(corner.x + 1.0)


## A pulled roller whose walker turns right round (its axle was 1 m behind,
## now it is 1 m ahead): the drawn axle swings back behind the body round the
## pulling hand's side, one tick at a time, moving at most 0.6 m a tick and
## never nearer the body's centre than SWING_RADIUS_M (the legs keep within
## about 0.45 m). It does not move while no tick passes. Control: it gets to
## where the trail puts it within 12 ticks, from a real half turn away.
func test_a_roller_swings_round_after_a_half_turn() -> void:
	for hand in 2:
		var out := -1.0 if hand == 0 else 1.0
		var to := Vector3(out * 0.3, 0.03, -CarryOnProps.TRAIL_M)
		var from := Vector3(-out * 0.3, 0.03, CarryOnProps.TRAIL_M)
		assert_vector(CarryOnProps.follow(from, to, 0.0, hand)).is_equal_approx(
			from, Vector3.ONE * 0.0001
		)
		var at := from
		var worst := 0.0
		var ticks := 0
		while at.distance_to(to) > 0.001 and ticks < 30:
			var next := CarryOnProps.follow(at, to, 1.0, hand)
			worst = maxf(worst, next.distance_to(at))
			at = next
			ticks += 1
			assert_float(Vector2(at.x, at.z).length()).is_greater_equal(
				CarryOnProps.SWING_RADIUS_M - 0.0001
			)
		print(
			"half-turn swing, hand %d: %d ticks, worst move per tick %.3f m" % [hand, ticks, worst]
		)
		assert_float(worst).is_less(0.6)
		assert_int(ticks).is_less_equal(12)
		assert_float(from.distance_to(to)).is_greater(1.9)


## In a cell closed on both sides only a hand-carried bag comes to the front:
## in the alarm corridor the arm holding a hard case, or a roller (lifted by
## its handle at security), is in its front pose, a shoulder bag's arm holds
## the strap and a backpack leaves both arms free; worn bags stay inside the
## corridor (0.44 m either side of its centre). The hands' places are not
## checked here: a headless skeleton is not animated (the windowed probe
## checks them). Control: every kind is seen, and a worn bag was measured.
func test_in_the_corridor_only_the_hard_case_turns_to_the_front() -> void:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	var wall := BuildEdit.place_wall(CORRIDOR, BuildGrid.Side.WEST)
	assert_bool(w.world.sim.grid.apply(wall).ok).is_true()
	var views := PassengerViews.new()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	var props := views.carry_on_props()
	var sent: Array = []
	for i in 8:
		sent.append([1, false, true])
	var ids := w.send_all(sent)
	var seen := {}
	var widest := 0.0
	var centre := w.world.sim.grid.cell_to_world(CORRIDOR)
	for i in 6000:
		w.world.step()
		views.draw()
		for id in ids:
			var p := w.world.passenger(id)
			var bags: Array[Node3D] = props.props_of(id)["bags"]
			if p.at != CORRIDOR or p.security_phase != SecurityRuntime.Phase.RETURN:
				continue
			if bags.is_empty() or props.transfer_progress(id, 0) < 1.0:
				continue
			if props.front_weight_of(id) < 1.0:
				continue
			var kind := SecurityLooks.bag_kind(p, 0)
			var body := views.node_for(id)
			var arms := [
				body.find_child("CarryArm0", true, false), body.find_child("CarryArm1", true, false)
			]
			seen[kind] = arms.map(
				func(a: CarryArm) -> Array:
					return [a.active, a.holds, a.front_weight, a.front_half_width]
			)
			var box := bags[0].global_transform * CarryOnProps.bag_box(kind)
			match kind:
				SecurityLooks.Kind.BACKPACK, SecurityLooks.Kind.SHOULDER:
					widest = maxf(
						widest, maxf(absf(box.position.x - centre.x), absf(box.end.x - centre.x))
					)
		if ids.all(func(id: int) -> bool: return w.cleared.has(id)):
			break
	print(
		(
			"corridor arms [active, holds, front weight, half width] by kind: %s; widest %.3f m"
			% [seen, widest]
		)
	)
	assert_int(seen.size()).is_equal(SecurityLooks.Kind.size())
	assert_float(widest).is_greater(0.2)
	assert_float(widest).is_less(0.44)
	for kind: int in seen:
		var arms: Array = seen[kind]
		var hand: Array = arms[0]
		match kind:
			SecurityLooks.Kind.CASE:
				assert_bool(hand[1]).is_true()
				assert_float(hand[2]).is_equal(1.0)
			SecurityLooks.Kind.ROLLER:
				assert_bool(hand[1]).is_true()
				assert_float(hand[2]).is_equal(1.0)
			SecurityLooks.Kind.SHOULDER:
				assert_bool(hand[1]).is_false()
				assert_float(hand[2]).is_equal(1.0)
				assert_float(hand[3]).is_equal(CarryOnProps.STRAP_HAND_M)
				assert_float(arms[1][2]).is_equal(0.0)
			SecurityLooks.Kind.BACKPACK:
				assert_bool(hand[0] or arms[1][0]).is_false()
