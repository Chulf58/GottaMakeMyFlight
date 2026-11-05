class_name TestRollerFileGateStand
extends GdUnitTestSuite
## The roller queue stand (RollerPark.queue_stand(), test_roller_queue_stand)
## for a walker waiting in a boarding file and one standing at the gate for want
## of a seat (board 44b974cc): the roller stood upright beside it, held by the
## bar, and tipped back into the pull when it walks on, drawn every third of a
## tick as the game draws it. No frame draws the bag floating
## (spike/carry_float_check.gd), none on a queue stand jumps more than JUMP_M
## against the body (TIP_JUMP_M on a tip, test_roller_queue_stand), and the
## hips holding it stay at least IDLE_SHARE of the same guest's standing still
## before the stand (anti-pattern a-crouch-check-for-a-still-held-pose-must-
## compare-hip-height).

const FloatCheck := preload("res://spike/carry_float_check.gd")
const Q := preload("res://tests/passengers/test_roller_queue_stand.gd")
const ROLLER := SecurityLooks.Kind.ROLLER
## The cell the file walkers start on together: they set off one at a time, a
## full BoardingFiles.GAP_MM apart, so each waits longer than the one before.
const FILE_CELL := Vector2i(19, 6)
const FILE_WALKERS := 5
## Boarding opens here in the gate world, long after the guest is on its spot.
const GATE_BOARDING := 240
## Frames that count as stood: this many ticks past the stand's start.
const STOOD_AFTER := RollerPark.QUEUE_STAND_TICKS + 2.0

var _world: PassengerTestWorld
var _views: PassengerViews
var _followed: Array[Passenger] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null
	_world = null
	_followed = []


## FILE_WALKERS walkers with a roller each on one cell as boarding opens: the
## later ones wait in their file (pending, then held), still with the path
## open. Each held still RollerPark.FILE_STILL_TICKS plus the stand stands its
## roller up; a wait shorter than FILE_STILL_TICKS stands none (a file moves up
## in ripples); and each stood roller tips back into the pull as its walker
## walks on.
func test_a_file_waiter_stands_its_roller_and_tips_it_on_walking() -> void:
	_world = TestBoardingFiles.boarding_world()
	_world.run_to(TestBoardingFiles.BOARDING + 5)
	_open_views()
	while _followed.size() < FILE_WALKERS:
		var p := _roller_guest()
		TestBoardingFiles.turn_out(_world, p, FILE_CELL)
		p.carry_on = 1
		_followed.append(p)
	var seen := await _follow(
		func() -> bool: return _followed.all(func(p: Passenger) -> bool: return _gone(p)), 600
	)
	var stood := 0
	var short_seen := 0
	for p in _followed:
		var mine: Dictionary = seen[p.id]
		print("walker %d: %s" % [p.id, _line(mine)])
		var longest: int = mine["longest_still"]
		if longest >= RollerPark.FILE_STILL_TICKS + STOOD_AFTER + 1.0:
			stood += 1
			assert_int(mine["stood"]).is_greater(0)
			assert_int(mine["repulled"]).is_greater(0)
			# A file waiter plays the walk clip on the spot while held (PassengerViews
			# _pose() takes is_moving(), and its path is open), so there is no idle
			# to measure the hips against: the share printed is the walk's bob.
			# Only the stoop is held to (board 44b974cc report).
			_print_posture(mine)
			assert_float(float(mine["stood_stoop"])).is_less_equal(Q.STOOP_EPS)
		elif longest < RollerPark.FILE_STILL_TICKS:
			# A ripple's wait: no stand, though STILL_TICKS would have asked for one.
			short_seen += int(longest > RollerPark.STILL_TICKS)
			assert_int(mine["queued"]).is_equal(0)
	_assert_clean(seen)
	# Controls: some waiter held long enough to stand, one too short to.
	assert_int(stood).is_greater(0)
	assert_int(short_seen).is_greater(0)


## A seatless guest with a roller walks to a standing spot at the gate (pulled,
## control), stands its roller up beside it there and holds it, and once
## boarding opens tips it back into the pull and walks out.
func test_a_gate_stander_stands_its_roller_and_tips_it_on_walking() -> void:
	_world = TestStandingSpotClaims.seatless_world(
		PassengerTestWorld.starts_with(GATE_BOARDING, 4000)
	)
	_open_views()
	# As TestStandingSpotClaims.cleared() makes one, with its roller.
	var p := _roller_guest()
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick + 1
	p.at = TestStandingSpotClaims.SCANNER_EXIT
	p.clear_path()
	p.apron = []
	p.apron_mm = 0
	_followed.append(p)
	var seen := await _follow(func() -> bool: return _gone(p), GATE_BOARDING + 200)
	var mine: Dictionary = seen[p.id]
	print("gate stander %d: %s" % [p.id, _line(mine)])
	_assert_clean(seen)
	assert_int(mine["walk_pulled"]).is_greater(0)
	assert_int(mine["standing_frames"]).is_greater(int(STOOD_AFTER + RollerPark.STILL_TICKS) * 3)
	assert_int(mine["stood"]).is_greater(0)
	assert_int(mine["stood_standing"]).is_greater(0)
	assert_int(mine["repulled"]).is_greater(0)
	_assert_posture(mine)


## The still test (RollerPark.queue_still()): a walker waiting to join its file
## is still with its path open, the walker it waits for (room to step) is not,
## and the wait in a file is FILE_STILL_TICKS. A gate stander with no path left
## is still, and waits STILL_TICKS.
func test_a_file_waiter_and_a_gate_stander_count_as_still() -> void:
	_world = TestBoardingFiles.boarding_world()
	_world.run_to(TestBoardingFiles.BOARDING + 5)
	var first := TestBoardingFiles.walker(_world, FILE_CELL)
	var second := TestBoardingFiles.walker(_world, FILE_CELL)
	_world.step()
	var sim := _world.sim
	print(
		(
			"first moving %s allowed %d; second moving %s pending %s allowed %d"
			% [
				first.is_moving(),
				sim.files.allowed(sim, first, PassengerSim.WALK_MM),
				second.is_moving(),
				sim.files.is_pending(second.id),
				sim.files.allowed(sim, second, PassengerSim.WALK_MM),
			]
		)
	)
	assert_bool(second.is_moving()).is_true()
	assert_bool(RollerPark.queue_still(sim, second)).is_true()
	assert_int(RollerPark.still_wait(second)).is_equal(RollerPark.FILE_STILL_TICKS)
	assert_bool(RollerPark.queue_still(sim, first)).is_false()
	# Not in a file stage: held in no file, still only with no path left.
	second.stage = Passenger.Stage.TO_GATE
	assert_bool(RollerPark.queue_still(sim, second)).is_false()
	second.stage = Passenger.Stage.STANDING
	assert_bool(RollerPark.queue_still(sim, second)).is_false()
	second.clear_path()
	assert_bool(RollerPark.queue_still(sim, second)).is_true()
	assert_int(RollerPark.still_wait(second)).is_equal(RollerPark.STILL_TICKS)
	assert_int(RollerPark.FILE_STILL_TICKS).is_greater(RollerPark.STILL_TICKS)


func _open_views() -> void:
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	_world.clock.ticked.connect(_keep_on_time)


## A calm passenger with one roller, its liquids and alarm off.
func _roller_guest() -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != ROLLER:
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	return p


## Out of the terminal: on the apron or done.
func _gone(p: Passenger) -> bool:
	return p.is_done() or p.stage == Passenger.Stage.APRON


## Draws every third of a tick until `done` or `limit` ticks, and returns per
## followed walker: frames, FLOAT and jump lines, its longest still spell (ticks
## with the drawn position unchanged), queued frames, stood frames (upright,
## beside the feet, held, STOOD_AFTER into the stand), the hips standing still
## before the stand and holding it, the stoop, and repulled frames (settled in
## the pull again, trailing, QUEUE_TIP_TICKS + 2 after it walked on).
func _follow(done: Callable, limit: int) -> Dictionary:
	var props := _views.carry_on_props()
	var seen := {}
	var stop := _world.clock.tick + limit
	while _world.clock.tick < stop and not done.call():
		await _tick(1.0 / 3.0)
		for p in _followed:
			if _gone(p):
				continue
			var mine: Dictionary = seen.get_or_add(p.id, _fresh())
			_sample(p, props, mine)
	return seen


static func _fresh() -> Dictionary:
	return {
		"frames": 0,
		"fails": [],
		"still": 0,
		"longest_still": 0,
		"queued": 0,
		"stood": 0,
		"stood_standing": 0,
		"standing_frames": 0,
		"walk_pulled": 0,
		"repulled": 0,
		"idle_hips": -1.0,
		"stood_hips": INF,
		"stood_stoop": 0.0,
		"walked_at": -1.0,
		"clips": {},
	}


func _sample(p: Passenger, props: CarryOnProps, mine: Dictionary) -> void:
	var body := _views.node_for(p.id)
	if body == null or props.props_of(p.id).get("bags", []).is_empty():
		return
	var now := _world.clock.tick + _world.clock.alpha
	mine["frames"] += 1
	var node: Node3D = props.props_of(p.id)["bags"][0]
	var bag := props.bag_state(p.id, 0)
	var tag := (
		"id %d tick %.2f stage %d move %s"
		% [p.id, now, p.stage, FloatCheck.move_of(props, p.id, 0)]
	)
	var state := FloatCheck.float_state(_world.sim, _views, p.id, 0)
	if state[0] == "float":
		mine["fails"].append("%s FLOAT %s" % [tag, state])
	var rel := node.global_position - body.global_position
	var queued := RollerPark.queued(bag)
	if (queued or mine.get("was_queued", false)) and mine.has("rel"):
		var step := rel.distance_to(mine["rel"])
		var tipping := bag.has("queue_tip") or not queued
		var key := "worst_tip_step" if tipping else "worst_step"
		mine[key] = maxf(mine.get(key, 0.0), step)
		if step > (Q.TIP_JUMP_M if tipping else Q.JUMP_M):
			mine["fails"].append("%s bag jumped %.3f against the body" % [tag, step])
	mine["rel"] = rel
	mine["was_queued"] = queued
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	mine["clips"][player.current_animation] = (
		int(mine["clips"].get(player.current_animation, 0)) + 1
	)
	# Still: the drawn position the same on this tick as on the last.
	var still := (
		_views.tick_position(p.id, true).distance_to(_views.tick_position(p.id, false)) < 0.001
	)
	var tick_now := _world.clock.tick
	if still and int(mine.get("still_tick", -1)) != tick_now:
		mine["still_tick"] = tick_now
		mine["run"] = (
			int(mine.get("run", 0)) + 1 if int(mine.get("last_tick", -9)) == tick_now - 1 else 1
		)
		mine["last_tick"] = tick_now
		mine["longest_still"] = maxi(mine["longest_still"], mine["run"])
	var up := node.global_transform.basis.z.normalized().dot(Vector3.UP)
	var axle := node.global_transform * CarryOnProps.ROLLER_AXLE
	var flat := Vector2(axle.x - body.global_position.x, axle.z - body.global_position.z)
	var settled := props.transfer_progress(p.id, 0) >= 1.0
	var pulled := settled and up < 0.8 and flat.length() > Q.TRAILS_M
	var held := int(bag.get("held_by", -1)) >= 0
	var hips := Q._hips(body)
	mine["still"] += int(still)
	if p.stage == Passenger.Stage.TO_GATE and pulled:
		mine["walk_pulled"] += 1
	if p.stage == Passenger.Stage.STANDING:
		mine["standing_frames"] += 1
	# Standing still before the stand: the roller settled in the pull.
	var idle_clip := player.current_animation == &"idle"
	if still and idle_clip and not queued and FloatCheck.move_of(props, p.id, 0) == "" and pulled:
		mine["idle_hips"] = maxf(mine["idle_hips"], hips)
	if queued:
		mine["queued"] += 1
		var into := now - float(bag.get("since", now))
		if into >= STOOD_AFTER and not bag.has("queue_tip"):
			mine["stood_hips"] = minf(mine["stood_hips"], hips)
			mine["stood_stoop"] = maxf(mine["stood_stoop"], Q._stoop(body))
			if up >= Q.UPRIGHT_DOT and flat.length() <= Q.BESIDE_M and held:
				mine["stood"] += 1
				mine["stood_standing"] += int(p.stage == Passenger.Stage.STANDING)
			else:
				mine["fails"].append(
					(
						"%s stood %.1f ticks: up %.3f beside %.3f held %s"
						% [tag, into, up, flat.length(), held]
					)
				)
		if bag.has("queue_tip") and float(mine["walked_at"]) < 0.0:
			mine["walked_at"] = now
	if (
		float(mine["walked_at"]) >= 0.0
		and now - float(mine["walked_at"]) > RollerPark.QUEUE_TIP_TICKS + 2.0
	):
		mine["repulled"] += int(pulled)


func _line(mine: Dictionary) -> String:
	var keep := mine.duplicate()
	keep.erase("fails")
	keep.erase("rel")
	return "%s, %d fails" % [keep, (mine["fails"] as Array).size()]


func _assert_clean(seen: Dictionary) -> void:
	var fails: Array = []
	for id: int in seen:
		assert_int(seen[id]["frames"]).is_greater(0)
		fails.append_array(seen[id]["fails"])
	for line: String in fails.slice(0, 10):
		print(line)
	assert_array(fails).is_empty()


## Holding the stood roller the hips stay at least IDLE_SHARE of the same guest
## standing still before the stand, and no stoop is drawn.
func _assert_posture(mine: Dictionary) -> void:
	var idle: float = mine["idle_hips"]
	var low: float = mine["stood_hips"]
	_print_posture(mine)
	assert_float(idle).is_greater(0.5)
	assert_float(low / idle).is_greater_equal(Q.IDLE_SHARE)
	assert_float(float(mine["stood_stoop"])).is_less_equal(Q.STOOP_EPS)


func _print_posture(mine: Dictionary) -> void:
	var idle: float = mine["idle_hips"]
	var low: float = mine["stood_hips"]
	print(
		(
			"POSTURE idle hips %.3f m, lowest stood %.3f m, share %.3f (>= %.2f), stoop %.3f (<= %.2f)"
			% [idle, low, low / maxf(idle, 0.001), Q.IDLE_SHARE, mine["stood_stoop"], Q.STOOP_EPS]
		)
	)


func _keep_on_time(_tick_now: int) -> void:
	for p in _followed:
		p.late = false


## One frame `ticks` sim ticks on, the followed walkers' clips played by the
## same sim time (test_roller_queue_stand's _tick()).
func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	for p in _followed:
		var body := _views.node_for(p.id)
		if body == null:
			continue
		var player := body.get_node("AnimationPlayer") as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()
