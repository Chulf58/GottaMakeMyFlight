extends GdUnitTestSuite
## A bag set down on the floor at a seat lies still while its guest sits down
## (board 0dd2c787 item c): CarryPlace lays it from the body drawn between its
## two tick positions less the sit offset of the tick (SitHold.offset()), and
## the two do not go together, so a floor bag wobbled up to 0.087 m while the
## drawn body eased into the seat. The two-bag gate case lies in the chair
## front's frame (test_gate_two_bag_floor.gd); these cases are a one-bag guest at
## a gate chair and a cafe guest with a roller and one other bag, and one with a
## single bag. Drawn through the views and stepped half a tick at a time, so
## frames between ticks are drawn too.

## How far (m, flat) a settled floor bag may be drawn from where it settled.
const STILL_M := 0.001
## Half ticks stepped from the first tick of the sit-down.
const HALF_TICKS := 120

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
	if _world != null:
		_world.free_all()
	_views = null
	_world = null


func _tick() -> void:
	_world.clock.advance(SimClock.STEP)
	await get_tree().process_frame


func _attach_views() -> void:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


## A one-bag guest (not a roller) sitting down at the reference terminal's first
## gate chair: its bag lies still on every settled frame.
func test_one_bag_at_a_gate_chair_lies_still() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_attach_views()
	var p := _spawn(func(kinds: Array) -> bool: return kinds[0] != SecurityLooks.Kind.ROLLER, 1)
	var seat: Dictionary = _world.sim.layout.seats[0]
	p.stage = Passenger.Stage.TO_GATE
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.boarding_tick = _world.sim.tick + 100000
	for n in 4:
		await _tick()
	p.seat_object = seat["object_id"]
	p.seat_piece = Relocation.placement(_world.grid, p.seat_object)
	p.stage = Passenger.Stage.SITTING_DOWN
	p.stage_tick = _world.sim.tick
	p.clear_path()
	var got := await _watch(p, 0)
	_check("gate one bag", got, 1)


## A cafe guest with a roller and one other bag, sitting down at the airside
## cafe: the bag that is not the roller lies still on every settled frame,
## while the drawn body eases off the sit offset (SitHold.offset()).
func test_cafe_bag_beside_a_roller_lies_still() -> void:
	var p := await _cafe_guest(
		func(kinds: Array) -> bool:
			return SecurityLooks.Kind.ROLLER in kinds and kinds[0] != kinds[1],
		2
	)
	var other := 0 if SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER else 1
	var got := await _watch(p, other)
	_check("cafe bag beside a roller", got, 4)


## A cafe guest with a single bag that is not a roller: it lies still too.
func test_cafe_one_bag_lies_still() -> void:
	var p := await _cafe_guest(
		func(kinds: Array) -> bool: return kinds[0] != SecurityLooks.Kind.ROLLER, 1
	)
	var got := await _watch(p, 0)
	_check("cafe one bag", got, 1)


## A guest spawned with `count` bags whose kinds pass `want`, calmed.
func _spawn(want: Callable, count: int) -> Passenger:
	var p: Passenger = null
	for attempt in 400:
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.carry_on = count
		var kinds := []
		for i in count:
			kinds.append(SecurityLooks.bag_kind(p, i))
		if want.call(kinds):
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.liquids = false
	p.alarm = false
	p.cleared = true
	return p


## A guest with `count` bags passing `want` at the first tick of its sit-down at
## CafeTestLayout's airside cafe, the views drawing it.
func _cafe_guest(want: Callable, count: int) -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_attach_views()
	var p := _spawn(want, count)
	p.cafe_cooldown = 1000000
	p.hunger = 30
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 1500:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	while p.stage != Passenger.Stage.CAFE_SITTING_DOWN and _world.clock.tick < 3000:
		await _tick()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	return p


## Steps `p` half a tick a frame and watches bag `index`: on every frame it is on
## the floor with its move over, how far (flat) it is from where it was first
## seen settled, how many such frames, and on how many the drawn body moved.
func _watch(p: Passenger, index: int) -> Dictionary:
	var props := _views.carry_on_props()
	var body := _views.node_for(p.id)
	var drawn_was := body.global_position
	var first := Vector3.INF
	var off := 0.0
	var frames := 0
	var moving := 0
	var body_moved := 0.0
	for n in HALF_TICKS:
		_world.clock.advance(SimClock.STEP * 0.5)
		await get_tree().process_frame
		var bag := props.bag_state(p.id, index)
		var stepped := body.global_position.distance_to(drawn_was)
		drawn_was = body.global_position
		if int(bag.get("place", -1)) / 4 != SecurityLooks.Home.FLOOR:
			continue
		if props.transfer_progress(p.id, index) < 1.0:
			continue
		var at := (bag["node"] as Node3D).global_position
		if not first.is_finite():
			first = at
			continue
		frames += 1
		moving += int(stepped > 0.0001)
		body_moved += stepped
		off = maxf(off, Vector2(at.x - first.x, at.z - first.z).length())
	# Seated by now: the frame the bags lie in is where the body is drawn.
	var seated: Variant = CarryPlace.seat_frame(_world.sim, p)
	assert_object(seated).is_not_null()
	var frame: Transform3D = seated if seated != null else Transform3D()
	var drawn := body.global_position
	return {
		"pose": StageKinds.Pose.keys()[StageKinds.pose(p.stage)],
		"seat_off": Vector2(frame.origin.x - drawn.x, frame.origin.z - drawn.z).length(),
		"yaw_off": absf(angle_difference(frame.basis.get_euler().y, body.rotation.y)),
		"kind": SecurityLooks.Kind.keys()[SecurityLooks.bag_kind(p, index)],
		"frames": frames,
		"moving": moving,
		"body_moved": body_moved,
		"off": off,
	}


## Prints `got` and checks the bag stayed within STILL_M while the drawn body
## moved on more than `moving_min` of its settled frames (the control), and
## that the seat frame it lies in (CarryPlace.seat_frame()) is where the body is
## drawn seated, so the bag rests where the body's own frame put it before.
func _check(label: String, got: Dictionary, moving_min: int) -> void:
	print(
		(
			(
				"%s: %s settled on the floor %d frames (%d with the drawn body moving, %.3f m),"
				+ " most off its first spot %.5f m (< %.3f); %s, seat frame off the drawn body"
				+ " %.5f m, %.4f rad"
			)
			% [
				label,
				got["kind"],
				got["frames"],
				got["moving"],
				got["body_moved"],
				got["off"],
				STILL_M,
				got["pose"],
				got["seat_off"],
				got["yaw_off"]
			]
		)
	)
	assert_int(got["frames"]).is_greater(10)
	assert_int(got["moving"]).is_greater(moving_min)
	assert_float(got["off"]).is_less(STILL_M)
	assert_str(got["pose"]).is_equal("SEATED")
	assert_float(got["seat_off"]).is_less(STILL_M)
	assert_float(got["yaw_off"]).is_less(0.01)
