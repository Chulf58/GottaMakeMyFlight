class_name TestRollerTipTurn
extends GdUnitTestSuite
## A queue-stood roller's tip waits while its walker turns toward its way
## (RollerPark.tip_wait(), TIP_TURN_RAD, board 4b9d1a4e): tipped during the
## turn, the pull swung round the body at its trail on top of the tip's own
## step, and a gate stander walking off with a turn of 0.202 rad a frame stepped
## its bag 0.218 m against the body, over test_roller_queue_stand's TIP_JUMP_M.

const Q := preload("res://tests/passengers/test_roller_queue_stand.gd")
const ROLLER := SecurityLooks.Kind.ROLLER
## Boarding opens here in the gate world, long after the guest is on its spot
## (test_roller_file_gate_stand).
const GATE_BOARDING := 240
const GATE_STANDERS := 4
## A body turned more than this between two frames is turning.
const TURN_RAD := 0.01
## The sharp turn the case is about: the gate stander's turn measured 0.202 rad
## a frame. Some frame of a tip must turn the body at least this much, or the
## check below never met the case.
const SHARP_RAD := 0.15

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


## Facing its way, or not walking, the tip goes at once; facing more than
## TIP_TURN_RAD away it waits the turn's TURN_TICKS.
func test_the_tip_waits_only_for_a_turn() -> void:
	var way := Vector2(0.0, 1.0)
	var faces := atan2(way.x, way.y)
	assert_float(RollerPark.tip_wait(faces, way)).is_equal(0.0)
	assert_float(RollerPark.tip_wait(faces + RollerPark.TIP_TURN_RAD - 0.01, way)).is_equal(0.0)
	assert_float(RollerPark.tip_wait(faces + 2.4, Vector2.ZERO)).is_equal(0.0)
	var turns := float(PassengerTurns.TURN_TICKS)
	assert_float(RollerPark.tip_wait(faces + RollerPark.TIP_TURN_RAD + 0.01, way)).is_equal(turns)
	assert_float(RollerPark.tip_wait(faces - 2.4, way)).is_equal(turns)


## Walking off with a turn, the move marks its tip at once (it no longer stands)
## but the roller stays stood until the turn is over, then tips over
## QUEUE_TIP_TICKS, the move ending with the tip.
func test_a_turning_walker_tips_after_the_turn() -> void:
	var bag: Dictionary = Q._pulled()
	var now := 100.0
	for t in RollerPark.STILL_TICKS + 1:
		RollerPark.queue_stand(bag, ROLLER, true, now)
		now += 1.0
	bag["led"] = true
	bag["was"] = bag["home"]
	bag["carry_from"] = SecurityLooks.Carry.PULL
	bag["since"] = bag["changed"]
	CarryLead.stamp_move(bag, false, SecurityLooks.Home.HAND, Transform3D.IDENTITY)
	for t in 20:
		RollerPark.queue_stand(bag, ROLLER, true, now)
		now += 1.0
	var turn := float(PassengerTurns.TURN_TICKS)
	RollerPark.queue_stand(bag, ROLLER, false, now, RollerPark.STILL_TICKS, turn)
	var at := now - float(bag["since"])
	var ticks := CarryLead.ticks_of(bag)
	assert_float(float(bag["queue_tip"])).is_equal(at + turn)
	assert_float(ticks).is_equal_approx(at + turn + RollerPark.QUEUE_TIP_TICKS, 0.001)
	assert_float(RollerPark.queue_share(bag, at / ticks)).is_equal(1.0)
	assert_float(RollerPark.queue_share(bag, (at + turn) / ticks)).is_equal(1.0)
	assert_float(RollerPark.queue_share(bag, (at + turn + 1.0) / ticks)).is_less(1.0)
	assert_float(RollerPark.queue_share(bag, 1.0)).is_equal(0.0)


## GATE_STANDERS seatless guests stand their rollers up at the gate; at
## boarding each walks off, some turning sharply. On every frame of a tip (the
## stand marked to tip) in which the body turns TURN_RAD or more, the bag steps
## at most TIP_JUMP_M against the body. Control: some such frame turns the body
## SHARP_RAD or more. On 37872d0 with the gate branch's spots, stander 22
## stepped 0.218 m on a 0.202 rad frame.
func test_a_turning_tip_keeps_the_bag_with_the_body() -> void:
	_world = TestStandingSpotClaims.seatless_world(
		PassengerTestWorld.starts_with(GATE_BOARDING, 4000)
	)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	_world.clock.ticked.connect(_keep_on_time)
	for i in GATE_STANDERS:
		var p := _roller_guest()
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
		p.stage_tick = _world.clock.tick + 1
		p.at = TestStandingSpotClaims.SCANNER_EXIT
		p.clear_path()
		p.apron = []
		p.apron_mm = 0
		_followed.append(p)
	var props := _views.carry_on_props()
	var last := {}
	var frames := 0
	var sharpest := 0.0
	var fails: Array[String] = []
	var stop := _world.clock.tick + GATE_BOARDING + 300
	while _world.clock.tick < stop and not _followed.all(_gone):
		await _tick(1.0 / 3.0)
		for p in _followed:
			var body := _views.node_for(p.id)
			if _gone(p) or body == null or props.props_of(p.id).get("bags", []).is_empty():
				continue
			var node: Node3D = props.props_of(p.id)["bags"][0]
			var now := [body.global_rotation.y, node.global_position - body.global_position]
			var was: Array = last.get(p.id, now)
			last[p.id] = now
			var bag := props.bag_state(p.id, 0)
			var turn := absf(wrapf(float(now[0]) - float(was[0]), -PI, PI))
			if not RollerPark.queued(bag) or not bag.has("queue_tip") or turn < TURN_RAD:
				continue
			frames += 1
			sharpest = maxf(sharpest, turn)
			var step := (now[1] as Vector3).distance_to(was[1])
			if step > Q.TIP_JUMP_M:
				fails.append(
					(
						"id %d tick %.2f turning %.3f rad: bag stepped %.3f m"
						% [p.id, _world.clock.tick + _world.clock.alpha, turn, step]
					)
				)
	print("turning tip frames %d, sharpest turn %.3f rad" % [frames, sharpest])
	for line in fails.slice(0, 5):
		print(line)
	assert_array(fails).is_empty()
	assert_float(sharpest).is_greater_equal(SHARP_RAD)


## GATE_STANDERS seatless guests stand their rollers up at the gate; at
## boarding each walks off. Each stander's tip is marked on a tick its way is
## known (PassengerViews.walk_heading() not zero), so tip_wait() can wait for
## its turn, and the wait is 0 or PassengerTurns.TURN_TICKS. Before board
## 34a0d0aa every stander's tip was marked on the boarding tick, turned to the
## exit with no path yet: no way, so no wait.
func test_a_gate_stander_tips_once_its_way_is_known() -> void:
	_world = TestStandingSpotClaims.seatless_world(
		PassengerTestWorld.starts_with(GATE_BOARDING, 4000)
	)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	_world.clock.ticked.connect(_keep_on_time)
	for i in GATE_STANDERS:
		var p := _roller_guest()
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
		p.stage_tick = _world.clock.tick + 1
		p.at = TestStandingSpotClaims.SCANNER_EXIT
		p.clear_path()
		p.apron = []
		p.apron_mm = 0
		_followed.append(p)
	var props := _views.carry_on_props()
	var marks := {}
	var stop := _world.clock.tick + GATE_BOARDING + 300
	while _world.clock.tick < stop and not _followed.all(_gone):
		await _tick(1.0 / 3.0)
		for p in _followed:
			if marks.has(p.id) or props.props_of(p.id).get("bags", []).is_empty():
				continue
			var bag := props.bag_state(p.id, 0)
			if not RollerPark.queued(bag) or not bag.has("queue_tip"):
				continue
			var at := float(_world.clock.tick) - float(bag["since"])
			marks[p.id] = {
				"tick": _world.clock.tick,
				"heading": _views.walk_heading(p),
				"wait": float(bag["queue_tip"]) - at,
				"stage": p.stage,
			}
	print("tip marks by stander: %s" % marks)
	assert_int(marks.size()).is_equal(GATE_STANDERS)
	for id: int in marks:
		var mark: Dictionary = marks[id]
		assert_vector(mark["heading"]).is_not_equal(Vector2.ZERO)
		assert_array([0.0, float(PassengerTurns.TURN_TICKS)]).contains([mark["wait"]])


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


func _gone(p: Passenger) -> bool:
	return p.is_done() or p.stage == Passenger.Stage.APRON


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
