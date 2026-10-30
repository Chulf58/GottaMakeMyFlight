class_name TestRollerPark
extends GdUnitTestSuite
## A roller laid on the floor from the pull, and taken off the floor into the
## pull, parks on its wheels while the hand changes grip (RollerPark, decision
## roller-laid-on-the-floor-stand-it-up-by-the-bar-park-it-upri, board
## 5b0fa979). The plan itself (stamped, timed, continuous at each change of
## grip, parked still on its wheels), and the two routes by a gate chair as
## the game draws them: sitting down with a pulled roller (pull>floor) and
## standing up to walk off (floor>pull), every drawn frame checked with the
## probes' FLOAT and GRIP_ON checks (spike/carry_float_check.gd), the parked
## frames for floor support and stillness, each frame against the last for a
## jump, and the body against the bag (spike/carry_contact.gd).

const FloatCheck := preload("res://spike/carry_float_check.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
## Ticks a frame: a game at 1x (20 ticks a second at 60 frames) and at 3x.
const FRAME_TICKS := [1.0 / 3.0, 1.0]
## Between two drawn frames 1/3 of a tick apart the bag and the hand's grip
## move less than SNAP_M (a snap to the move's start or end is 0.5 m or
## more; the fastest part of a move, the stand, about 0.15 m), and across a
## change of grip at the park (the frame the hand leaves the bag standing, and
## the frame it takes it again) less than GRASP_M: the bag still, the hand
## ending its way to the grip.
const SNAP_M := 0.3
const GRASP_M := 0.05
## How long a walker is followed after its move began.
const AFTER_TICKS := 22

var _world: PassengerTestWorld
var _views: PassengerViews
## Kept on time on every tick, after the sim and before the views (a late
## walker lifts its roller into the hand, a move of its own): the test
## walker's flight is close.
var _on_time: Passenger


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_free_world()


func _free_world() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null


## A move record as CarryOnProps stamps it: from `was` carried `carry_from` to
## `place` carried `carry`.
static func _move(was: int, carry_from: int, place: int, carry: int) -> Dictionary:
	return {
		"kind": SecurityLooks.Kind.ROLLER,
		"led": true,
		"from": Transform3D(),
		"was": was,
		"carry_from": carry_from,
		"place": place,
		"carry": carry,
	}


## (home * 2 + hand) * 2 + lifted, as CarryOnProps' place.
static func _place(home: int, hand: int, lifted := 0) -> int:
	return (home * 2 + hand) * 2 + lifted


## Only a roller between the pull and the floor outside a stall parks, and only
## its move is longer; every other move keeps TRANSFER_TICKS.
func test_only_a_roller_between_the_pull_and_the_floor_parks() -> void:
	var hand := SecurityLooks.Home.HAND
	var floor := SecurityLooks.Home.FLOOR
	var pull := SecurityLooks.Carry.PULL
	var by_hand := SecurityLooks.Carry.HAND
	var body := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3.0, 0.0, -2.0))
	var cases := [
		[_move(_place(hand, 0), pull, _place(floor, 0), pull), false, floor, true],
		[_move(_place(floor, 1), pull, _place(hand, 1), pull), false, hand, true],
		[_move(_place(hand, 0), pull, _place(floor, 0), pull), true, floor, false],
		[_move(_place(hand, 0, 1), by_hand, _place(floor, 0), pull), false, floor, false],
		[_move(_place(floor, 0), pull, _place(hand, 0, 1), by_hand), false, hand, false],
		[_move(_place(hand, 0), pull, _place(hand, 1), pull), false, hand, false],
	]
	for c: Array in cases:
		var bag: Dictionary = c[0]
		CarryLead.stamp_move(bag, c[1], c[2], body)
		assert_bool(bag.get("park", false)).is_equal(c[3])
		var ticks := RollerPark.TICKS if c[3] else CarryOnProps.TRANSFER_TICKS
		assert_float(CarryLead.ticks_of(bag)).is_equal(ticks)
	var case := _move(_place(hand, 0), pull, _place(floor, 0), pull)
	case["kind"] = SecurityLooks.Kind.CASE
	CarryLead.stamp_move(case, false, floor, body)
	assert_bool(case.has("park")).is_false()
	# A parking move stamped again as another move loses its length.
	var again := _move(_place(hand, 0), pull, _place(floor, 0), pull)
	CarryLead.stamp_move(again, false, floor, body)
	again["carry"] = SecurityLooks.Carry.HAND
	again["was"] = _place(floor, 0)
	CarryLead.stamp_move(again, false, hand, body)
	assert_float(CarryLead.ticks_of(again)).is_equal(CarryOnProps.TRANSFER_TICKS)
	assert_float(RollerPark.TICKS).is_greater(CarryOnProps.TRANSFER_TICKS)


## Parked, the roller stands upright on its wheels, its axle the wheels'
## radius up, out on the hand's side, its meshes' lowest point on the floor
## (as the probes' rest check reads it); at full size and at the two-bag scale.
func test_the_park_stands_upright_on_its_wheels() -> void:
	var frame := Transform3D(Basis(Vector3.UP, -1.1), Vector3(1.0, 0.25, 4.0))
	for scale_by: float in [1.0, SecurityLooks.TWO_BAG_SCALE]:
		for hand in 2:
			var parked := RollerPark.park(frame, hand, scale_by)
			var r := CarryOnProps.ROLLER_AXLE.y * scale_by
			var axle := parked * CarryOnProps.ROLLER_AXLE
			assert_float(axle.y - frame.origin.y).is_equal_approx(r, 0.0001)
			# The wheel's lowest point is the radius under the axle when its own x is level.
			assert_float(parked.basis.x.normalized().y).is_equal_approx(0.0, 0.0001)
			assert_float(parked.basis.z.normalized().y).is_equal_approx(1.0, 0.0001)
			var local := frame.affine_inverse() * axle
			assert_float(local.x * (-1.0 if hand == 0 else 1.0)).is_equal_approx(
				RollerPark.PARK_SIDE_M, 0.0001
			)
			# Every point of its meshes is on or over the floor.
			var node := InteriorKit.instantiate("carry_roller")
			add_child(node)
			node.global_transform = parked
			var lowest := INF
			for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
				lowest = minf(lowest, (mi.global_transform * mi.get_aabb()).position.y)
			node.free()
			assert_float(lowest - frame.origin.y).is_between(-0.003, 0.003)


## A plan of a parking move (CarryLead.plan() handing it to RollerPark), with
## the hand on its target: [k, holder, bag, held point (world), target, held
## point (own frame), the bar (own frame)].
func _plans(bag: Dictionary, start: Transform3D, want: Transform3D, frame: Transform3D) -> Array:
	var out := []
	var flags := {"to_floor": bag["place"] / 4 == SecurityLooks.Home.FLOOR, "yaw": 0.0, "hand": 0}
	for n in 401:
		var k := n / 400.0
		var rods := CarryLead.carry_t(k, bag)
		var bar_z: float = lerpf(0.7, 0.255, rods)
		if bag["place"] / 4 == SecurityLooks.Home.HAND:
			bar_z = lerpf(0.255, 0.7, rods)
		var body := {"hand": 0, "bar_z": bar_z, "scale": 1.0, "grips": [Vector3.ZERO, Vector3.ZERO]}
		var plan := CarryLead.plan(bag, k, start, want, frame, flags, body)
		var xf: Transform3D = plan["xf"]
		var at: Vector3 = plan["anchor"]
		var bar := Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, bar_z)
		out.append([k, plan["holder"], xf, xf * at, plan["targets"][0], at, bar])
	return out


## Both moves, planned: every held step has the hand's target on the point
## held, the bar or the carry handle; the bag never jumps between two steps
## (the changes of grip included); the parked steps keep the bag still at the
## park, the hand aimed at it all the while; there are held, parked and
## (pull>floor) let-go steps.
func test_a_parking_plan_holds_a_grip_point_and_never_jumps() -> void:
	var frame := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var pulled := CarryOnProps.pulled(Vector3(-0.25, 0.85, 0.05), Vector3(-0.35, 0.03, -0.95), 1.0)
	var lying := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.0, 0.0, 0.56))
	var hand := SecurityLooks.Home.HAND
	var floor := SecurityLooks.Home.FLOOR
	var pull := SecurityLooks.Carry.PULL
	for down in [true, false]:
		var bag := (
			_move(_place(hand, 0), pull, _place(floor, 0), pull)
			if down
			else _move(_place(floor, 0), pull, _place(hand, 0), pull)
		)
		CarryLead.stamp_move(bag, false, floor if down else hand, frame)
		bag["home"] = bag["place"]
		var parked := RollerPark.park(bag["park_frame"], 0, 1.0)
		var plans := _plans(bag, pulled if down else lying, lying if down else pulled, frame)
		var held := 0
		var still := 0
		var was: Array = plans[0]
		for step: Array in plans:
			var xf: Transform3D = step[2]
			var k: float = step[0]
			if step[1] == 0:
				held += 1
				assert_float((step[3] as Vector3).distance_to(step[4])).is_less(0.0005)
				# The point held is the bar as drawn or the carry handle, nothing between.
				var at: Vector3 = step[5]
				var on_bar := at.distance_to(step[6]) < 0.0001
				assert_bool(on_bar or at.distance_to(CarryOnProps.ROLLER_HANDLE) < 0.0001).is_true()
			elif k > RollerPark.STAND_END and k < RollerPark.LAY_END and down:
				still += 1
				assert_float(xf.origin.distance_to(parked.origin)).is_less(0.0001)
			elif k > RollerPark.LIFT_END and k < RollerPark.UP_PARK_END and not down:
				still += 1
				assert_float(xf.origin.distance_to(parked.origin)).is_less(0.0001)
			var moved := xf.origin.distance_to((was[2] as Transform3D).origin)
			var aimed := (step[4] as Vector3).distance_to(was[4])
			if moved > 0.03 or aimed > 0.03:
				print("step k=%.4f holder=%d moved=%.3f aimed=%.3f" % [k, step[1], moved, aimed])
			assert_float(moved).is_less(0.03)
			assert_float(aimed).is_less(0.03)
			was = step
		print("parking plan down=%s held=%d still=%d" % [down, held, still])
		assert_int(held).is_greater(150)
		assert_int(still).is_greater(60)


## A walker with one roller by a gate chair in a new reference terminal with
## the views drawing: `seated` sitting (its boarding a few ticks off), else
## standing at the chair's front about to sit.
func _roller_walker(seated: bool) -> Passenger:
	_free_world()
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_on_time = null
	_world.clock.ticked.connect(_keep_on_time)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.cleared = true
	var seat: Dictionary = _world.sim.layout.seats[0]
	p.stage = Passenger.Stage.SEATED if seated else Passenger.Stage.TO_GATE
	p.stage_tick = _world.sim.tick
	p.seat_object = seat["object_id"] if seated else 0
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.boarding_tick = _world.sim.tick + (8 if seated else 100000)
	_on_time = p
	return p


func _keep_on_time(_tick_now: int) -> void:
	if _on_time != null:
		_on_time.late = false


## One frame `ticks` sim ticks on, as the game draws them.
func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## Follows `p`'s roller through its move `name` ("pull>floor" or "floor>pull",
## hands left out) at `ticks` a frame, until AFTER_TICKS after it began:
## {"frames", "held", "parked", "ticks": how long it took, "fails": lines}.
func _route(p: Passenger, name: String, ticks: float) -> Dictionary:
	var props := _views.carry_on_props()
	var out := {
		"frames": 0, "held": 0, "parked": 0, "ticks": -1.0, "fails": [], "worst": 0.0, "grasps": 0
	}
	var began := -1.0
	var last_xf := Transform3D()
	var last_grip := Vector3.INF
	var last_body := Vector3.INF
	var last_holder := -2
	var parked_xf := Transform3D()
	while _world.clock.tick < 3000:
		if not p.cleared:
			break
		await _tick(ticks)
		var move := FloatCheck.move_of(props, p.id, 0).replace(".R", "").replace(".L", "")
		var now := _world.clock.tick + _world.clock.alpha
		if move == name and began < 0.0:
			began = now
		if began < 0.0:
			continue
		if now - began > AFTER_TICKS:
			break
		var body := _views.node_for(p.id)
		var node: Node3D = props.props_of(p.id)["bags"][0]
		var bag := props.bag_state(p.id, 0)
		var k := props.transfer_progress(p.id, 0)
		if k >= 1.0 and float(out["ticks"]) < 0.0:
			out["ticks"] = now - began
		var tag := (
			"%s %.2f ticks/frame k=%.3f now %s body moved %.3f"
			% [name, ticks, k, move, body.global_position.distance_to(last_body)]
		)
		last_body = body.global_position
		out["frames"] += 1
		var state := FloatCheck.float_state(_world.sim, _views, p.id, 0)
		if state[0] == "float":
			out["fails"].append("%s FLOAT %s" % [tag, state])
		var on := FloatCheck.grip_on_gap(props, p.id, 0, body)
		var holder: int = bag.get("held_by", -1)
		var lead := CarryLead.hand_of(bag["home"] if name == "floor>pull" else bag["was"])
		if holder >= 0:
			out["held"] += 1
			out["worst"] = maxf(out["worst"], on[0])
			if on[0] > on[1]:
				out["fails"].append("%s GRIP_ON gap %.3f > %.3f" % [tag, on[0], on[1]])
		elif move != "" and bag.get("park", false) and _in_park(name, k):
			out["parked"] += 1
			var rest := FloatCheck.rest_gap(_world.sim, null, node)
			if rest > FloatCheck.RESTING_M:
				var low := INF
				for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
					low = minf(low, (mi.global_transform * mi.get_aabb()).position.y)
				out["fails"].append(
					(
						"%s parked off the floor by %.3f (lowest %.3f, floor %.3f, body y %.3f)"
						% [tag, rest, low, _world.sim.grid.origin.y, body.global_position.y]
					)
				)
			if (
				int(out["parked"]) > 1
				and node.global_transform.origin.distance_to(parked_xf.origin) > 0.001
			):
				out["fails"].append("%s parked bag moved" % tag)
			parked_xf = node.global_transform
		var grip := props.grip_of(body, lead)
		if int(out["frames"]) > 1:
			var moved := node.global_transform.origin.distance_to(last_xf.origin)
			var reached := grip.distance_to(last_grip)
			var grasp := move != "" and holder != last_holder
			# At the park the bag stands still and the hand slows onto and off it;
			# taking the bag first and leaving it last the hand may come and go fast
			# (each printed with what it moved).
			var at_park := grasp and _by_park(name, k)
			var step := (GRASP_M if at_park else SNAP_M) * ticks * 3.0
			if at_park:
				out["grasps"] += 1
			if grasp:
				print(
					(
						"%s grasp %d>%d bag moved %.3f grip %.3f"
						% [tag, last_holder, holder, moved, reached]
					)
				)
			if moved > step:
				out["fails"].append("%s bag jumped %.3f" % [tag, moved])
			if reached > step:
				out["fails"].append("%s grip jumped %.3f" % [tag, reached])
		last_xf = node.global_transform
		last_grip = grip
		last_holder = holder if move != "" else -2
		if move != "" and int(out["frames"]) % 3 == 0:
			var side: String = [".R", ".L"][lead] if holder >= 0 else ""
			var points := CarryContact.body_points(body, [side] if side != "" else [])
			var inside := CarryContact.inside_meshes(points, node)
			if inside > 0:
				out["fails"].append("%s %d body points inside the bag" % [tag, inside])
	assert_float(began).is_greater(0.0)
	return out


## Whether `k` of a parking move `name` is at its park: in its parked share or
## within a frame of it.
static func _by_park(name: String, k: float) -> bool:
	if name == "pull>floor":
		return k > RollerPark.STAND_END - 0.06 and k < RollerPark.PARK_END + 0.06
	return k > RollerPark.LIFT_END - 0.06 and k < RollerPark.UP_PARK_END + 0.06


## Whether `k` of a parking move `name` is inside its parked share.
static func _in_park(name: String, k: float) -> bool:
	if name == "pull>floor":
		return k > RollerPark.STAND_END + 0.01 and k < RollerPark.PARK_END - 0.01
	return k > RollerPark.LIFT_END + 0.01 and k < RollerPark.UP_PARK_END - 0.01


## Sitting down by a gate chair with a pulled roller, and standing up from it
## to walk off, at 1x and 3x: every held frame on the bar or the handle
## (GRIP_ON), no FLOAT, every parked frame on the floor and still, no jump
## between frames, no body point inside the bag, and the move over in
## RollerPark.TICKS. Control: held and parked frames were seen.
func test_a_roller_by_a_gate_chair_parks_to_change_grip_on_every_frame() -> void:
	for down in [true, false]:
		for ticks: float in FRAME_TICKS:
			var p := _roller_walker(not down)
			if down:
				for n in 4:
					await _tick(0.5)
				var seat: Dictionary = _world.sim.layout.seats[0]
				p.seat_object = seat["object_id"]
				p.stage = Passenger.Stage.SITTING_DOWN
				p.clear_path()
				p.stage_tick = _world.sim.tick
			var name := "pull>floor" if down else "floor>pull"
			var seen := await _route(p, name, ticks)
			var fails: Array = seen["fails"]
			print(
				(
					"%s %.2f ticks a frame: frames %d held %d parked %d took %.2f ticks, worst grip %.3f, fails %d"
					% [
						name,
						ticks,
						seen["frames"],
						seen["held"],
						seen["parked"],
						seen["ticks"],
						seen["worst"],
						fails.size()
					]
				)
			)
			for line: String in fails.slice(0, 12):
				print("  ", line)
			assert_int(int(seen["held"])).is_greater(0)
			assert_int(int(seen["parked"])).is_greater(0)
			# Both changes of grip at the park seen: onto it and off it.
			assert_int(int(seen["grasps"])).is_greater_equal(2)
			assert_float(float(seen["ticks"])).is_between(
				RollerPark.TICKS - 0.01, RollerPark.TICKS + 1.01
			)
			assert_int(fails.size()).is_equal(0)
