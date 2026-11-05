class_name TestSitHold
extends GdUnitTestSuite
## A passenger sitting down at a gate chair with a pulled roller stays
## standing (idle) until the roller's pull>floor park has ended and its hand
## has let go, then sits (SitHold; user ruling sitting-down-with-a-roller-set-
## the-bag-down-standing-then-sit, board 76cb23c0). A headless run cannot show
## the seated pose (clips advance by real frame time), so this checks the clip
## PassengerViews chooses on every tick; the windowed park_recovery_plates_probe
## checks the pose (SEAT_LOW).

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null


## A walker with one bag, a roller or not, at the first gate chair's front,
## drawn a few ticks, then sitting down there.
func _sitting_walker(roller: bool) -> Passenger:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while (SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER) != roller:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.cleared = true
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
	return p


func _tick() -> void:
	_world.clock.advance(SimClock.STEP)
	await get_tree().process_frame


## The clip drawn on each tick of the sit-down, and the tick the roller's park
## ended (or -1).
func _follow(p: Passenger) -> Dictionary:
	var clips: Array[String] = []
	var park_end := -1.0
	while p.stage == Passenger.Stage.SITTING_DOWN:
		await _tick()
		if p.stage != Passenger.Stage.SITTING_DOWN:
			break
		var bag := _views.carry_on_props().bag_state(p.id, 0)
		if bag.get("park", false):
			park_end = float(bag["since"]) + CarryLead.ticks_of(bag) - p.stage_tick
		clips.append(_views.node_for(p.id).get_meta(&"clip", ""))
	print("sit-down clips %s, park ends %.1f ticks in" % [clips, park_end])
	return {"clips": clips, "park_end": park_end}


## With a roller: idle on every tick until the park has ended and the hand let
## go (SitHold.LET_GO_TICKS), sit_down on every tick after. Control: the park
## was stamped and ran its 13 ticks, and sit_down was drawn.
func test_a_walker_sitting_down_with_a_roller_stands_until_the_park_ends() -> void:
	var p := await _sitting_walker(true)
	var seen := await _follow(p)
	var clips: Array[String] = seen["clips"]
	var held := ceili(float(seen["park_end"]) + SitHold.LET_GO_TICKS)
	assert_float(seen["park_end"]).is_greater_equal(RollerPark.TICKS_DOWN)
	assert_int(clips.size()).is_greater(held)
	# The clip of tick n (counted from 1) drawn after the stage started.
	for n in clips.size():
		var want := "idle" if n + 1 < held else "sit_down"
		(
			assert_str(clips[n])
			. override_failure_message(
				"tick %d of the sit-down drew %s, not %s" % [n + 1, clips[n], want]
			)
			. is_equal(want)
		)


## A load during the roller hold (PassengerViews.snap(): the views start every
## record over) draws the body at the chair front, not at the sim's
## already-shuffled place: the front is rebuilt from the chair, so a gate
## passenger never jumps back up to 0.55 m into the seat. Control: the sim
## itself had shuffled the body off the chair front by then, and the load
## fell inside the hold.
func test_a_load_during_the_roller_hold_keeps_the_body_at_the_chair_front() -> void:
	var p := await _sitting_walker(true)
	var front := _world.sim.grid.cell_to_world(p.seat_front)
	for n in 5:
		await _tick()
	var shuffled := _world.sim.world_position(p).distance_to(front)
	assert_float(shuffled).is_greater(0.1)
	assert_int(SitHold.held_ticks(_views.carry_on_props(), _world.sim, p)).is_greater(0)
	_views.snap()
	var worst := _front_gap(p, front)
	var frames := 1
	var hold := ceili(RollerPark.TICKS_DOWN + SitHold.LET_GO_TICKS)
	while _world.sim.tick - p.stage_tick < hold - 1:
		await _tick()
		frames += 1
		worst = maxf(worst, _front_gap(p, front))
	print(
		"shuffled %.3f m off the front, drawn worst %.3f m, %d frames" % [shuffled, worst, frames]
	)
	assert_int(frames).is_greater(4)
	assert_float(worst).is_less(0.02)


## How far the drawn body of `p` stands from `front`, along the ground.
func _front_gap(p: Passenger, front: Vector3) -> float:
	var at := _views.node_for(p.id).global_position
	return Vector2(at.x - front.x, at.z - front.z).length()


## With no roller it sits at once: sit_down from the first tick.
func test_a_walker_sitting_down_with_no_roller_sits_at_once() -> void:
	var p := await _sitting_walker(false)
	var seen := await _follow(p)
	var clips: Array[String] = seen["clips"]
	assert_int(clips.size()).is_greater(0)
	for clip in clips:
		assert_str(clip).is_equal("sit_down")


## On the lounge sofa and in the nap pod a roller visitor sets the roller down
## standing at its slot cell (ActivityPoses.seat_door()): the park and the
## let-go end before the pose turns to SITTING_DOWN, the body draws idle until
## then, and its drawn step onto the seat has not begun. Control: the park
## was stamped, and the sit-down was reached.
func test_a_sofa_or_pod_visitor_sets_its_roller_down_before_it_sits() -> void:
	for type: StringName in [&"lounge", &"nap_pod"]:
		var grid := BuildGrid.new()
		ActivityTestLayout.build(grid, type)
		_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
		_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
		_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
		_world.run_to(10)
		_views = PassengerTestWorld.views()
		_views.clock = _world.clock
		_views.sim = _world.sim
		add_child(_views)
		var p := ShopTestLayout.airside_guest(_world, 0)
		while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
			p = ShopTestLayout.airside_guest(_world, 0)
		p.boredom = 80
		p.carry_on = 1
		assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
		while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 3000:
			await _tick()
		assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
		var park_end := -1.0
		var sat := -1
		var clips: Array[String] = []
		while sat < 0 and _world.clock.tick - p.stage_tick < 60:
			await _tick()
			var bag := _views.carry_on_props().bag_state(p.id, 0)
			if bag.get("park", false):
				park_end = float(bag["since"]) + CarryLead.ticks_of(bag) - p.stage_tick
			var spent := _world.clock.tick - p.stage_tick
			if ActivityPoses.pose(_world.sim, p) == StageKinds.Pose.SITTING_DOWN:
				sat = spent
			else:
				clips.append(_views.node_for(p.id).get_meta(&"clip", ""))
				assert_float(ActivityPoses.share(_world.sim, p)).is_equal(0.0)
		print("%s: park ends %.1f ticks in, sits at %d, clips %s" % [type, park_end, sat, clips])
		assert_float(park_end).is_greater_equal(RollerPark.TICKS_DOWN)
		assert_int(sat).is_greater_equal(ceili(park_end + SitHold.LET_GO_TICKS))
		for clip in clips:
			assert_str(clip).is_equal("idle")
		_views.free()
		_world.free_all()
		_views = null


## A late walker sets its roller down from the hand with no park
## (CarryOnProps._lifted()), so a save and load on the first tick of its
## sit-down, before ParkRecovery.note_sitting() notes sat_late a tick on, must
## not hold the body standing for a park that never ran (board 5cdf7605).
## Control: the same save and load of an on-time walker holds it for the
## park's whole length.
func test_a_late_walker_loaded_on_the_first_tick_of_its_sit_down_is_not_held() -> void:
	for late in [true, false]:
		var p := await _sitting_walker(true)
		p.late = late
		var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
		assert_bool(_world.sim.from_snapshot(saved)).is_true()
		var loaded := _world.passenger(p.id)
		_views.snap()
		var held := SitHold.held_ticks(_views.carry_on_props(), _world.sim, loaded)
		print(
			(
				"late %s: tick %d stage_tick %d held %d"
				% [late, _world.sim.tick, loaded.stage_tick, held]
			)
		)
		assert_int(_world.sim.tick - loaded.stage_tick).is_equal(0)
		assert_bool(loaded.late).is_equal(late)
		assert_bool(loaded.sat_late).is_false()
		if late:
			assert_int(held).is_equal(0)
		else:
			assert_int(held).is_equal(ceili(RollerPark.TICKS_DOWN + SitHold.LET_GO_TICKS))
		_views.free()
		_world.free_all()
		_views = null


## A cafe guest with a roller loaded during its hold is drawn at the seat's
## approach anchor, the chair front SitHold.chair_front() reads from the
## visit's seat each time (never kept per passenger), and not at the sim's
## already-shuffled place. Control: the sim had moved the body off the anchor
## by the load, and the roller is still held.
func test_a_load_in_the_hold_of_a_cafe_sit_down_puts_the_body_at_the_approach() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = 1
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	while p.stage != Passenger.Stage.CAFE_SITTING_DOWN and _world.clock.tick < 1400:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	for n in 5:
		_world.step()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	assert_bool(_world.sim.from_snapshot(saved)).is_true()
	var loaded := _world.passenger(p.id)
	_views.snap()
	var approach := _world.grid.cell_to_world(_world.sim.cafes.visit_of(p.id).seat["approach"])
	var held := SitHold.held_ticks(_views.carry_on_props(), _world.sim, loaded)
	var chair_front := SitHold.chair_front(_world.sim, loaded) as Vector3
	var drawn := _front_gap(loaded, approach)
	var at := _world.sim.world_position(loaded)
	var shuffled := Vector2(at.x - approach.x, at.z - approach.z).length()
	print(
		"cafe load: held %d, drawn %.3f m, sim %.3f m from the approach" % [held, drawn, shuffled]
	)
	assert_float(shuffled).is_greater(0.1)
	assert_int(held).is_greater(0)
	assert_vector(chair_front).is_equal_approx(approach, Vector3.ONE * 0.001)
	assert_float(drawn).is_less(0.02)


## At a gate chair the start of the roller's set-down from the pull stays in
## the body's frame, as on main: no fixed start and no wall faces
## (BoothRoller.fix_start() is for a booth seat only). Control: the park was
## stamped.
func test_a_gate_chair_set_down_starts_in_the_body_frame() -> void:
	var p := await _sitting_walker(true)
	for n in 3:
		await _tick()
	var bag := _views.carry_on_props().bag_state(p.id, 0)
	print("gate chair set-down: park %s, fixed start %s" % [bag.get("park"), bag.has("from_world")])
	assert_bool(bag.get("park", false)).is_true()
	assert_bool(bag.has("from_world")).is_false()
	assert_bool(bag.has("wall_faces")).is_false()
