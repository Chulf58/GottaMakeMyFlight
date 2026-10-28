class_name TestCarryOnKinds
extends GdUnitTestSuite
## Carry-on bag kinds (decision carry-on-bag-kinds-backpack-shoulder-or-tote-
## bag-small-rolle): which kind a bag is (a fixed hash of the passenger's id,
## no saved state), how each kind is carried (CarryOnProps' placement maths)
## and what each kind does in a cell closed on both sides (only the hard case
## turns to the front; worn and pulled bags keep their carry, inside the
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
## upright, its inner face outside the hip, under the elbow.
func test_a_shoulder_bag_hangs_from_the_shoulder_outside_the_hip() -> void:
	var base := Vector3(0.0, 0.05, 0.14)
	for side in 2:
		var joint := Vector3(-0.206 if side == 0 else 0.206, 1.644, -0.061)
		var hung := CarryOnProps.worn_shoulder(joint, Vector3.ZERO, 0.0, side, 1.0, base)
		var xf: Transform3D = hung[0]
		var length: float = hung[1]
		var bar := xf * (base + Vector3(0.0, 0.0, length))
		assert_float(bar.y).is_equal_approx(joint.y + CarryOnProps.STRAP_OVER_ARM_M, 0.0001)
		assert_float(absf(bar.x)).is_equal_approx(CarryOnProps.STRAP_OUT_M, 0.0001)
		assert_float(signf(bar.x)).is_equal(signf(joint.x))
		assert_vector(xf.basis.z.normalized()).is_equal_approx(Vector3.UP, Vector3.ONE * 0.0001)
		# The inner face (local y = 0) at 0.22 from the centre line, the bag's
		# top STRAP_M under the bar.
		var inner := xf * Vector3.ZERO
		assert_float(absf(inner.x)).is_equal_approx(0.22, 0.0001)
		var top := xf * Vector3(0.0, 0.0, base.z)
		assert_float(top.y).is_equal_approx(bar.y - CarryOnProps.STRAP_M, 0.0001)


## A worn backpack: its back panel BACK_FROM_SPINE_M behind the spine bone,
## its length along the bone, its top just above it.
func test_a_backpack_is_worn_behind_the_spine() -> void:
	var spine := Transform3D(Basis(Vector3.RIGHT, -0.1), Vector3(0.0, 1.544, -0.047))
	var xf := CarryOnProps.worn_back(spine, 0.0, 1.0)
	assert_vector(xf.basis.z.normalized()).is_equal_approx(
		spine.basis.y.normalized(), Vector3.ONE * 0.0001
	)
	var panel := xf.affine_inverse() * spine.origin
	assert_float(panel.y).is_equal_approx(-CarryOnProps.BACK_FROM_SPINE_M, 0.0001)
	# Behind the body (it faces +Z).
	assert_float((xf * Vector3(0.0, 0.1, 0.0)).z).is_less(spine.origin.z)
	var top := CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK).end.z
	assert_float(panel.z).is_equal_approx(top - CarryOnProps.BACK_TOP_OVER_SPINE_M, 0.0001)


## The roller's axle trails like a trailer: straight behind on a straight
## walk, and through a right-angle corner it cuts the corner on the inside
## and never swings out past either walked leg (a rigid tail would swing to
## the outside at once). Control: the axle moved on round the corner.
func test_a_trailing_axle_follows_the_walked_line() -> void:
	var hitch := Vector3.ZERO
	var axle := Vector3(0.0, 0.0, -CarryOnProps.TRAIL_M)
	for i in 30:
		hitch.z += 0.08
		axle = CarryOnProps.trail(axle, hitch)
	assert_float(axle.x).is_equal_approx(0.0, 0.0001)
	assert_float(hitch.z - axle.z).is_equal_approx(CarryOnProps.TRAIL_M, 0.0001)
	var corner := hitch
	var worst := 0.0
	for i in 30:
		hitch.x += 0.08
		axle = CarryOnProps.trail(axle, hitch)
		# Distance from the walked polyline (the leg along z up to the corner,
		# then the leg along x).
		var to_first := absf(axle.x) if axle.z <= corner.z else axle.distance_to(corner)
		var to_second := absf(axle.z - corner.z) if axle.x >= corner.x else INF
		worst = maxf(worst, minf(to_first, to_second))
		assert_float(axle.x).is_greater_equal(-0.0001)
		assert_float(axle.z).is_less_equal(corner.z + 0.0001)
	print("trailer through a right-angle corner: worst off the walked line %.3f m" % worst)
	assert_float(axle.x).is_greater(corner.x + 1.0)
	assert_float(worst).is_less(CarryOnProps.TRAIL_M * 0.5)


## The overhead route for a backpack: it starts and ends where asked, stays
## on the body's centre plane in the middle, and while it crosses over the
## head its lowest point is at OVERHEAD_M.
func test_the_overhead_route_crosses_above_the_head() -> void:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK)
	var on_floor := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.0, 0.0, 0.56))
	var worn := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 1.1, -0.21))
	var crossed := 0
	for step in 21:
		var k := step / 20.0
		var at := CarryOnProps.overhead(on_floor, worn, k, box)
		if k == 0.0:
			assert_vector(at.origin).is_equal_approx(on_floor.origin, Vector3.ONE * 0.0001)
		if k == 1.0:
			assert_vector(at.origin).is_equal_approx(worn.origin, Vector3.ONE * 0.0001)
		if k > 1.0 / 3.0 and k < 2.0 / 3.0:
			var lowest := INF
			for i in 8:
				lowest = minf(lowest, (at * box.get_endpoint(i)).y)
			assert_float(lowest).is_equal_approx(CarryOnProps.OVERHEAD_M, 0.0001)
			assert_float(at.origin.x).is_equal_approx(0.0, 0.0001)
			crossed += 1
	assert_int(crossed).is_greater(2)


## In a cell closed on both sides only a hard case comes to the front: in
## the alarm corridor the arm holding a hard case is in its front pose, a
## pulling arm is not, a shoulder bag's arm holds the strap and a backpack
## leaves both arms free; worn bags and a roller's axle stay inside the
## corridor (0.44 m either side of its centre). The hands' places are not
## checked here: a headless skeleton is not animated (the windowed probe
## checks them). Control: more than one kind is seen.
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
				SecurityLooks.Kind.ROLLER:
					var axle := bags[0].global_transform * CarryOnProps.ROLLER_AXLE
					var behind := body.global_transform.affine_inverse() * axle
					assert_float(behind.z).is_less(-0.6)
					widest = maxf(widest, absf(axle.x - centre.x) + 0.17)
		if ids.all(func(id: int) -> bool: return w.cleared.has(id)):
			break
	print(
		(
			"corridor arms [active, holds, front weight, half width] by kind: %s; widest %.3f m"
			% [seen, widest]
		)
	)
	assert_int(seen.size()).is_greater(1)
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
				assert_float(hand[2]).is_equal(0.0)
				assert_float(arms[1][2]).is_equal(0.0)
			SecurityLooks.Kind.SHOULDER:
				assert_bool(hand[1]).is_false()
				assert_float(hand[2]).is_equal(1.0)
				assert_float(hand[3]).is_equal(CarryOnProps.STRAP_OUT_M)
				assert_float(arms[1][2]).is_equal(0.0)
			SecurityLooks.Kind.BACKPACK:
				assert_bool(hand[0] or arms[1][0]).is_false()
