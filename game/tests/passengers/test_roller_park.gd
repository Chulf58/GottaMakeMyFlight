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
## Ticks a frame: a game at 1x (20 ticks a second at 60 frames), at 2x and at
## 3x.
const FRAME_TICKS := [1.0 / 3.0, 2.0 / 3.0, 1.0]
## Between two drawn frames 1/3 of a tick apart the bag and the hand's grip
## move less than SNAP_M (a snap to the move's start or end is 0.5 m or
## more; the fastest part of a move, the stand, about 0.15 m), and across a
## change of grip (the hand taking the bag off the floor, leaving it standing
## at the park and taking it again) less than GRASP_M: the bag still, the hand
## ending its way to the grip. Let go on the floor at the end, the bag settles
## less than DROP_M onto its place, the hand going back as fast as it likes.
## Each scales with the ticks a frame (a game at 3x draws three times as far
## between frames), but the drop, read at 1x only.
const SNAP_M := 0.3
const GRASP_M := 0.05
const DROP_M := 0.03
## How long a walker is followed after its move began.
const AFTER_TICKS := 22

var _world: PassengerTestWorld
var _views: PassengerViews
## Kept on time on every tick, after the sim and before the views (a late
## walker lifts its roller into the hand, a move of its own): the test
## walker's flight is close.
var _on_time: Passenger
## Made late instead (_route()'s late_in): kept late on every tick from then.
var _late := false
## Its home changed in the middle of the move (_route()'s flip_in): sitting
## down, its chair removed (_seat_goes()); standing up, sat down again at its
## chair the tick its stand-up ended (_resit, armed).
var _flipped := false
var _flip_to_floor := false
var _resit := false
## Sitting down, a wall built on the walker's right once its chair has gone and
## it has a route (_wall_on_its_right()), and what was seen as it went up.
var _wall_right := false
var _walled := {}


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
		var ticks := CarryOnProps.TRANSFER_TICKS
		if c[3]:
			ticks = RollerPark.TICKS_DOWN if c[2] == floor else RollerPark.TICKS_UP
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
	assert_float(RollerPark.TICKS_DOWN).is_greater(CarryOnProps.TRANSFER_TICKS)
	assert_float(RollerPark.TICKS_UP).is_greater(CarryOnProps.TRANSFER_TICKS)


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
		var ahead := RollerPark.PARK_AHEAD_M if down else RollerPark.UP_PARK_AHEAD_M
		var parked := RollerPark.park(bag["park_frame"], 0, 1.0, ahead)
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
			elif not down and k > RollerPark.up_ends(bag).x and k < RollerPark.up_ends(bag).y:
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
	_late = false
	_flipped = false
	_flip_to_floor = false
	_resit = false
	_wall_right = false
	_walled = {}
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
	if _on_time == null:
		return
	_on_time.late = _late
	if (
		_wall_right
		and _walled.is_empty()
		and _on_time.stage == Passenger.Stage.TO_GATE
		and _on_time.path.size() >= 2
	):
		_wall_on_its_right()
	if _resit and _on_time.stage == Passenger.Stage.TO_EXIT:
		# Up from the chair, it sits down at it again on the tick the stand-up
		# ended, from the chair's front where the stand-up left it, as one whose
		# facility visit was dropped before boarding does (PassengerSim: up, back
		# to the gate, the seat claimed again). Not forced into SEATED: that put
		# the body back on the seat in one frame, and its pose with it.
		var seat: Dictionary = _world.sim.layout.seats[0]
		_on_time.seat_object = seat["object_id"]
		_on_time.seat_cell = seat["cell"]
		_on_time.seat_front = seat["front"]
		_on_time.boarding_tick = _world.sim.tick + 100000
		_on_time.clear_path()
		_on_time.stage = Passenger.Stage.SITTING_DOWN
		_on_time.stage_tick = _world.sim.tick
		_resit = false
		_flipped = true


## The chair of the walker sitting down at it removed by a build edit: the sim
## rebuilds its layout and on its next tick (PassengerSim._reconcile()) frees
## the seat and sends the walker on to the gate, standing. Not seat_object
## cleared alone: a body left sitting down at no seat is no longer turn-locked
## (PassengerViews) and turned round to face its slide into the chair.
func _seat_goes() -> void:
	var seat: int = _world.sim.layout.seats[0]["object_id"]
	assert_bool(_world.sim.grid.apply(BuildEdit.remove_object(seat)).ok).is_true()


## Once the walker whose chair went has a route, a wall built on the right of
## its cell (its right for the way it goes), so the bag's hand for that way
## (SecurityLooks.hand_of()) is the left. Kept: the tick it went up, whether the
## park was in progress then, and the hand for the way after it.
func _wall_on_its_right() -> void:
	var p := _on_time
	var at := clampi(p.path_index, 0, p.path.size() - 2)
	var right := SecurityLooks.world_dir(p.path[at + 1] - p.path[at]).cross(Vector3.UP)
	var side := BuildGrid.SIDE_STEP.find(Vector2i(roundi(right.x), roundi(right.z)))
	assert_bool(_world.sim.grid.apply(BuildEdit.place_wall(p.at, side)).ok).is_true()
	var bag := _views.carry_on_props().bag_state(p.id, 0)
	var since := float(bag.get("since", -INF))
	_walled = {
		"tick": _world.sim.tick,
		"mid": bag.get("park", false) and _world.sim.tick - since < CarryLead.ticks_of(bag),
		"hand": SecurityLooks.hand_of(_world.sim, p, 0),
		"park_hand": CarryLead.hand_of(bag.get("place", 0)),
	}


## One frame `ticks` sim ticks on, as the game draws them.
func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## Follows `p`'s roller through its move `name` ("pull>floor" or "floor>pull",
## hands left out) at `ticks` a frame, until AFTER_TICKS after it began:
## {"frames", "held", "parked", "ticks": how long it took, "fails": lines}.
## With `late_in` ("lift" or "park", _late_now()) the walker turns late in
## that part of the move ("late_k", "-1" never), and every frame of the parking
## move after that must still draw it pulled (a fail line otherwise).
## With `flip_in` the walker's home changes instead, to the other one: sitting
## down ("lift" or "park", the same parts) its seat goes in that part, to the
## hand from the floor; standing up ("seat") it sits down again at its chair as
## the stand-up ends, to the floor from the hand. "flip_k" is the k it did,
## "flips" how many new moves were stamped after it, and the frame of each is
## checked for a jump of GRASP_M or more (a fail line otherwise). The walker is
## followed AFTER_TICKS after it.
func _route(p: Passenger, name: String, ticks: float, late_in := "", flip_in := "") -> Dictionary:
	var props := _views.carry_on_props()
	var out := {
		"frames": 0,
		"held": 0,
		"parked": 0,
		"ticks": -1.0,
		"fails": [],
		"worst": 0.0,
		"grasps": 0,
		"late_k": -1.0,
		"flip_k": -1.0,
		"flips": 0,
	}
	var flip_at := -1.0
	var last_since := -1.0
	var last_ticks := 0.0
	var began := -1.0
	var stamped := -1.0
	var last_xf := Transform3D()
	var last_grip := Vector3.INF
	var last_body := Vector3.INF
	var last_holder := -2
	var parked_xf := Transform3D()
	var parked_since := -1.0
	while _world.clock.tick < 3000:
		if not p.cleared:
			break
		await _tick(ticks)
		var move := FloatCheck.move_of(props, p.id, 0).replace(".R", "").replace(".L", "")
		var now := _world.clock.tick + _world.clock.alpha
		if move == name and began < 0.0:
			began = now
			# Timed from the tick it was stamped on: at 2x the first frame drawing it
			# can be a third of a tick later.
			stamped = float(props.bag_state(p.id, 0).get("since", now))
		if began < 0.0:
			continue
		if (
			(now - began > AFTER_TICKS and not _flipped)
			or (_flipped and flip_at >= 0.0 and now - flip_at > AFTER_TICKS)
		):
			break
		var body := _views.node_for(p.id)
		var node: Node3D = props.props_of(p.id)["bags"][0]
		var bag := props.bag_state(p.id, 0)
		var k := props.transfer_progress(p.id, 0)
		# Over once it is not the move drawn now (at its end, or a move stamped on
		# its last tick: a late walker's roller lifted into the hand then).
		if move != name and float(out["ticks"]) < 0.0:
			out["ticks"] = now - stamped
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
		# The parking move drawn now: the one it began as, else the one a change of
		# home stamped (if it parks at all).
		var cur := name
		if _flipped:
			cur = (
				"floor>pull"
				if bag.get("park", false) and CarryLead.start_of(bag)[0] == CarryLead.End.REST
				else "pull>floor"
			)
		var lead := CarryLead.hand_of(bag["home"] if cur == "floor>pull" else bag["was"])
		if flip_in == "seat" and began == now:
			_flip_to_floor = true
			_resit = true
		if (
			flip_in not in ["", "seat"]
			and not _flipped
			and move == name
			and _late_now(flip_in, name, k, bag, holder)
		):
			_flipped = true
			_seat_goes()
		if _flipped and flip_at < 0.0:
			flip_at = now
			out["flip_k"] = k
			print("%s home changes at k=%.3f holder %d" % [tag, k, holder])
		if (
			late_in != ""
			and not _late
			and move == name
			and _late_now(late_in, name, k, bag, holder)
		):
			_late = true
			p.late = true
			out["late_k"] = k
			print("%s turns late at k=%.3f holder %d" % [tag, k, holder])
		if (
			_late
			and k < 1.0
			and bag.get("park", false)
			and bag["carry"] != SecurityLooks.Carry.PULL
		):
			out["fails"].append("%s parking move no longer pulled" % tag)
		if holder >= 0:
			out["held"] += 1
			out["worst"] = maxf(out["worst"], on[0])
			if on[0] > on[1]:
				out["fails"].append("%s GRIP_ON gap %.3f > %.3f" % [tag, on[0], on[1]])
		elif move != "" and bag.get("park", false) and _in_park(cur, k, bag):
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
			# Still within one park: a second parking move (after a change of home)
			# parks somewhere else.
			if (
				int(out["parked"]) > 1
				and float(bag.get("since", -1.0)) == parked_since
				and node.global_transform.origin.distance_to(parked_xf.origin) > 0.001
			):
				out["fails"].append("%s parked bag moved" % tag)
			parked_xf = node.global_transform
			parked_since = float(bag.get("since", -1.0))
		var grip := props.grip_of(body, lead)
		if int(out["frames"]) > 1:
			var moved := node.global_transform.origin.distance_to(last_xf.origin)
			# The hand against the body (a walker walking off carries it 0.1 m a tick).
			var reached := (grip - body.global_position).distance_to(last_grip)
			var grasp := move != "" and holder != last_holder
			var let_go := grasp and holder < 0 and not _by_park(cur, k, bag)
			var step := (GRASP_M if grasp else SNAP_M) * ticks * 3.0
			# At 3x a frame holds a tick of the set-down before it: the drop is read
			# at 1x only.
			var drop := DROP_M if ticks < 0.5 else SNAP_M * ticks * 3.0
			if grasp and _by_park(cur, k, bag):
				out["grasps"] += 1
			if grasp:
				print(
					(
						"%s grasp %d>%d bag moved %.3f grip %.3f"
						% [tag, last_holder, holder, moved, reached]
					)
				)
			var since := float(bag.get("since", -1.0))
			if _flipped and since != last_since and out["flip_k"] >= 0.0:
				out["flips"] += 1
				# Stamped before the move before it had run its length: a restamp in
				# the middle of a park (one after its end is the next move, with the
				# ordinary tail of the hand coming back).
				var mid := float(_world.clock.tick) - last_since < last_ticks
				var allowed := GRASP_M * ticks * 3.0
				if mid and (moved > allowed or reached > allowed):
					out["fails"].append(
						(
							"%s home change: bag moved %.3f grip %.3f > %.3f"
							% [tag, moved, reached, allowed]
						)
					)
			if moved > (drop if let_go else step):
				out["fails"].append("%s bag jumped %.3f" % [tag, moved])
			if reached > (SNAP_M * ticks * 3.0 if let_go else step):
				out["fails"].append("%s grip jumped %.3f" % [tag, reached])
		last_xf = node.global_transform
		last_since = float(bag.get("since", -1.0))
		last_ticks = CarryLead.ticks_of(bag)
		last_grip = grip - body.global_position
		last_holder = holder if move != "" else -2
		if move != "" and int(out["frames"]) % 3 == 0:
			var side: String = [".R", ".L"][lead] if holder >= 0 else ""
			var points := CarryContact.body_points(body, [side] if side != "" else [])
			var inside := CarryContact.inside_meshes(points, node)
			if inside > 0:
				out["fails"].append("%s %d body points inside the bag" % [tag, inside])
	assert_float(began).is_greater(0.0)
	return out


## Whether `k` of a parking move `name` (its record `bag`) is at its park: in
## its parked share or within a frame of it.
static func _by_park(name: String, k: float, bag: Dictionary) -> bool:
	if name == "pull>floor":
		return k > RollerPark.STAND_END - 0.06 and k < RollerPark.PARK_END + 0.06
	var ends := RollerPark.up_ends(bag)
	return k > ends.x - 0.06 and k < ends.y + 0.06


## Whether a walker in parking move `name` (its record `bag`) at `k`, the bag
## held by `holder`, is in its part `part`: "lift" the bag in the hand on its
## way to the park (pull>floor standing up by the bar, floor>pull lifted off the
## floor by the handle), "park" the bag standing alone at the park.
static func _late_now(part: String, name: String, k: float, bag: Dictionary, holder: int) -> bool:
	if part == "park":
		return _in_park(name, k, bag)
	if holder < 0:
		return false
	if name == "pull>floor":
		return k > 0.15 and k < RollerPark.STAND_END - 0.05
	var took: float = bag.get("park_took", 2.0)
	return k > took + 0.03 and k < RollerPark.up_ends(bag).x - 0.03


## Whether `k` of a parking move `name` (its record `bag`) is inside its parked
## share.
static func _in_park(name: String, k: float, bag: Dictionary) -> bool:
	if name == "pull>floor":
		return k > RollerPark.STAND_END + 0.01 and k < RollerPark.PARK_END - 0.01
	var ends := RollerPark.up_ends(bag)
	return k > ends.x + 0.01 and k < ends.y - 0.01


## Sitting down by a gate chair with a pulled roller, and standing up from it
## to walk off, at 1x and 3x: every held frame on the bar or the handle
## (GRIP_ON), no FLOAT, every parked frame on the floor and still, no jump
## between frames, no body point inside the bag, and the move over in
## its RollerPark.TICKS_DOWN or TICKS_UP. Control: held and parked frames were seen.
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
			var ticks_of_move := RollerPark.TICKS_DOWN if down else RollerPark.TICKS_UP
			assert_float(float(seen["ticks"])).is_between(
				ticks_of_move - 0.01, ticks_of_move + 1.01
			)
			assert_int(fails.size()).is_equal(0)


## A walker turning late while its roller parks (in the lift to the park, or
## parked alone) keeps the park to its end (RollerPark.holds_lift()): at 1x and
## 3x, every change of grip under GRASP_M a third of a tick, no FLOAT, GRIP_ON or
## jump, and the parking move drawn pulled to its end. Controls: the walker
## turned late in that part and the park's two changes of grip were seen; once
## the move is over a roller standing up goes into the hand (carried by hand),
## and one laid on the floor stays as it lies (pulled, its lift kept).
func test_a_walker_turning_late_mid_park_keeps_the_park_sitting_down() -> void:
	await _late_mid_park(true)


## As above, standing up to walk off (floor>pull).
func test_a_walker_turning_late_mid_park_keeps_the_park_standing_up() -> void:
	await _late_mid_park(false)


## A walker turning late in a parking move, sitting down (`down`) or standing
## up, at each part and frame rate (the tests above).
func _late_mid_park(down: bool) -> void:
	for part: String in ["lift", "park"]:
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
			var seen := await _route(p, name, ticks, part)
			var fails: Array = seen["fails"]
			var bag := _views.carry_on_props().bag_state(p.id, 0)
			var line_of := "late in %s, %s %.2f ticks/frame: late at k=%.3f, held %d parked %d"
			line_of += " grasps %d took %.2f ticks, worst grip %.3f, carry now %d, fails %d"
			print(
				(
					line_of
					% [
						part,
						name,
						ticks,
						seen["late_k"],
						seen["held"],
						seen["parked"],
						seen["grasps"],
						seen["ticks"],
						seen["worst"],
						bag["carry"],
						fails.size()
					]
				)
			)
			for line: String in fails.slice(0, 12):
				print("  ", line)
			assert_float(float(seen["late_k"])).is_greater_equal(0.0)
			assert_bool(p.late).is_true()
			assert_int(int(seen["grasps"])).is_greater_equal(2)
			var ticks_of_move := RollerPark.TICKS_DOWN if down else RollerPark.TICKS_UP
			assert_float(float(seen["ticks"])).is_between(
				ticks_of_move - 0.01, ticks_of_move + 1.01
			)
			var carry := SecurityLooks.Carry.PULL if down else SecurityLooks.Carry.HAND
			assert_int(bag["carry"]).is_equal(carry)
			assert_int(fails.size()).is_equal(0)


## A walker's home changing in the middle of a parking move: sitting down, its
## chair is removed (_seat_goes(), in the lift or in the park), to the hand;
## standing up, it sits down again at its chair as the stand-up ends (in the
## park), to the floor. At each frame rate no new move stamped before the park
## ended jumps GRASP_M or more in the bag or the grip, and no FLOAT, GRIP_ON or
## jump follows. Controls: the home changed and a new move was stamped after it.
func test_a_walker_changing_home_mid_park_does_not_jump_sitting_down() -> void:
	await _home_mid_park(true)


## As above, standing up (floor>pull) and sitting again.
func test_a_walker_changing_home_mid_park_does_not_jump_standing_up() -> void:
	await _home_mid_park(false)


## A walker sitting down whose chair is removed early in the park, and then has
## a wall built on its right as it sets off (a new route, SecurityLooks.hand_of()
## gives its bag the other hand), keeps the park's hand as well as its home to
## the park's end (RollerPark.hold_park()): the same checks as above. Controls:
## the wall went up during the park, and the hand for the way changed.
func test_a_walker_changing_hand_mid_park_does_not_jump() -> void:
	await _home_mid_park(true, true)


## A walker changing home in a parking move, sitting down (`down`) or standing
## up, at each part and frame rate (the tests above); with `wall`, the hand
## changes after it (_wall_on_its_right()), in the lift only.
func _home_mid_park(down: bool, wall := false) -> void:
	# Standing up, the home can go back to the floor only once the stand-up has
	# ended (SecurityLooks: in the hand from UP_LEAD_TICKS before its end): never
	# in the lift.
	var parts := ["lift", "park"] if down else ["seat"]
	for part: String in ["lift"] if wall else parts:
		for ticks: float in FRAME_TICKS:
			var p := _roller_walker(not down)
			_wall_right = wall
			if down:
				for n in 4:
					await _tick(0.5)
				var seat: Dictionary = _world.sim.layout.seats[0]
				p.seat_object = seat["object_id"]
				p.stage = Passenger.Stage.SITTING_DOWN
				p.clear_path()
				p.stage_tick = _world.sim.tick
			var name := "pull>floor" if down else "floor>pull"
			var seen := await _route(p, name, ticks, "", part)
			var fails: Array = seen["fails"]
			print(
				(
					"home change in %s, %s %.2f ticks/frame: at k=%.3f, held %d parked %d new moves %d fails %d"
					% [
						part,
						name,
						ticks,
						seen["flip_k"],
						seen["held"],
						seen["parked"],
						seen["flips"],
						fails.size()
					]
				)
			)
			for line: String in fails.slice(0, 12):
				print("  ", line)
			assert_float(float(seen["flip_k"])).is_greater_equal(0.0)
			assert_int(int(seen["flips"])).is_greater_equal(1)
			if wall:
				print("  wall: %s" % _walled)
				assert_bool(_walled.get("mid", false)).is_true()
				assert_int(int(_walled.get("hand", -1))).is_not_equal(_walled.get("park_hand", -1))
			assert_int(fails.size()).is_equal(0)


## A parking move keeps its home to its end whatever the walker's home turns
## to (RollerPark.held_home()), marked held only while the two differ, and a
## held park to the floor lays the bag in the frame the park was stamped in
## (lay_frame()), not the body's; once the move's ticks are over the walker's
## home is drawn. Both read the record and the sim tick only, and the plan of
## the held move is the same for two hand heights drawn (CarryLead.plan()).
func test_a_parking_move_keeps_its_home_to_its_end() -> void:
	var hand := SecurityLooks.Home.HAND
	var floor := SecurityLooks.Home.FLOOR
	var roller := SecurityLooks.Kind.ROLLER
	var pull := SecurityLooks.Carry.PULL
	var body := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3.0, 0.0, -2.0))
	var turned := Transform3D(Basis(Vector3.UP, 2.3), Vector3(3.5, 0.0, -1.0))
	var bag := _move(_place(hand, 0), pull, _place(floor, 0), pull)
	bag["since"] = 100.0
	CarryLead.stamp_move(bag, false, floor, body)
	assert_bool(bag.get("park", false)).is_true()
	var mid := 100.0 + RollerPark.TICKS_DOWN * 0.5
	assert_int(RollerPark.held_home(bag, roller, floor, mid)).is_equal(floor)
	assert_bool(bag.has("home_held")).is_false()
	assert_bool(RollerPark.lay_frame(bag, turned).is_equal_approx(turned)).is_true()
	assert_int(RollerPark.held_home(bag, roller, hand, mid)).is_equal(floor)
	assert_bool(bag.get("home_held", false)).is_true()
	var frame: Transform3D = bag["park_frame"]
	assert_bool(RollerPark.lay_frame(bag, turned).is_equal_approx(frame)).is_true()
	var after := 100.0 + RollerPark.TICKS_DOWN
	assert_int(RollerPark.held_home(bag, roller, hand, after)).is_equal(hand)
	assert_bool(bag.has("home_held")).is_false()
	assert_int(RollerPark.held_home(bag, SecurityLooks.Kind.CASE, hand, mid)).is_equal(hand)
	bag["home"] = bag["place"]
	var flags := {"to_floor": true, "yaw": 0.0, "hand": 0}
	var want := frame * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.6))
	var start := CarryOnProps.pulled(Vector3(-0.25, 0.85, 0.05), Vector3(-0.35, 0.03, -0.95), 1.0)
	for k: float in [0.2, 0.5, 0.7, 0.9]:
		var plans := []
		for grip_y: float in [0.3, 1.0]:
			var grip := Vector3(0.0, grip_y, 0.0)
			var drawn := {"hand": 0, "bar_z": 0.4, "scale": 1.0, "grips": [grip, grip]}
			plans.append(CarryLead.plan(bag, k, body * start, want, body, flags, drawn))
		var xf: Transform3D = plans[0]["xf"]
		var target: Vector3 = plans[0]["targets"][0]
		assert_bool(xf.is_equal_approx(plans[1]["xf"])).is_true()
		assert_bool(target.is_equal_approx(plans[1]["targets"][0])).is_true()
