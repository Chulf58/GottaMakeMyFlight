class_name TestCarryStallBarTurn
extends GdUnitTestSuite
## The holding arm's out turn in the side carry (board a791eb90, Sol re-check
## of d4490aa): every hand carry turns out CarrySwap.HAND_OUT_DEGREES (12),
## which keeps a case clear of the hip and thigh, and only a hand holding a
## roller by its bar beside the stalls (StallCarry.beside_row()) turns out
## StallCarry.BAR_OUT_DEGREES (6), so the roller clears the stall front as it
## passes the side partition. The turn eases between the two, and the swap to
## the pull starts from it, so the arm never jumps between frames.

## Sim ticks between frames in the unit cases (a frame falls between ticks).
const STEP_TICKS := 0.25
## The most the turn may move in one STEP_TICKS: the ease is a smoothstep over
## TRANSFER_TICKS (slope at most 1.5), and in a swap it and the swap's own
## smoothstep add, twice that. A switch without the ease moves 6 at once.
const STEP_MAX_DEGREES := 0.8
## Sim ticks per frame through the real views, and the most the holding arm's
## turn may move in one of them (the same bound at this frame length).
const FRAME_TICKS := 0.75
const FRAME_MAX_DEGREES := 2.3
## The case is checked on its walk at least this far from the stall (mm).
const WALK_MIN_MM := 3000
const AFTER_M := 4.0

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	_free_world()
	PassengerTestWorld.tracker = null


## A hand-held case, near the stalls or not, and the free hand beside it keep
## the wide turn; with a roller held by its bar in the other hand beside the
## stalls only that hand narrows. Control: the same roller away from the
## stalls keeps the wide turn.
func test_only_a_bar_roller_beside_the_stalls_narrows() -> void:
	var case := {"by_bar": false}
	var held := {"bags": [case], "homes": [SecurityLooks.Home.HAND], "hands": [0]}
	for near in [false, true]:
		for tick in [100.0, 110.0, 120.0]:
			StallCarry.stamp_bar_turn(held, near, tick)
			var outs := StallCarry.hand_out_degrees(held, tick + 0.5)
			assert_float(outs[0]).is_equal(CarrySwap.HAND_OUT_DEGREES)
			assert_float(outs[1]).is_equal(CarrySwap.HAND_OUT_DEGREES)
	var roller := {"by_bar": true}
	var two := {
		"bags": [case, roller],
		"homes": [SecurityLooks.Home.HAND, SecurityLooks.Home.HAND],
		"hands": [0, 1],
	}
	StallCarry.stamp_bar_turn(two, false, 200.0)
	var away := StallCarry.hand_out_degrees(two, 210.0)
	StallCarry.stamp_bar_turn(two, true, 210.0)
	var beside := StallCarry.hand_out_degrees(two, 220.0)
	print("away %s, beside %s" % [away, beside])
	assert_float(away[1]).is_equal(CarrySwap.HAND_OUT_DEGREES)
	assert_float(beside[0]).is_equal(CarrySwap.HAND_OUT_DEGREES)
	assert_float(beside[1]).is_equal_approx(StallCarry.BAR_OUT_DEGREES, 0.0001)
	assert_float(StallCarry.BAR_OUT_DEGREES).is_less(CarrySwap.HAND_OUT_DEGREES)


## A roller held by its bar comes beside the stalls, turns back half way, comes
## beside them again and then swaps to the pull (the hand carry's turn there
## going to CarryOnProps.PULL_OUT_DEGREES, CarrySwap.pose_arm): the arm's turn
## at each STEP_TICKS moves at most STEP_MAX_DEGREES, the first step after each
## change is where the last one was, and it reaches both ends. Control: the
## turn did narrow by the whole gap and come back.
func test_the_turn_eases_through_each_change_and_the_swap() -> void:
	var roller := {"by_bar": true}
	var held := {"bags": [roller], "homes": [SecurityLooks.Home.HAND], "hands": [0]}
	var arm: CarryArm = auto_free(CarryArm.new())
	StallCarry.stamp_bar_turn(held, false, 100.0)
	# Changes on these sync ticks: beside, away, beside, then the swap.
	var changes := {104.0: true, 107.0: false, 109.0: true, 120.0: false}
	var swap_at := 120.0
	var last := NAN
	var worst := 0.0
	var narrowest := INF
	var tick := 100.0
	while tick <= 132.0:
		if changes.has(tick):
			if tick == swap_at:
				roller["by_bar"] = false
			StallCarry.stamp_bar_turn(held, changes[tick], tick)
		var out: float = StallCarry.hand_out_degrees(held, tick)[0]
		arm.angle_degrees = out
		if tick >= swap_at:
			var k := clampf((tick - swap_at) / CarryOnProps.TRANSFER_TICKS, 0.0, 1.0)
			CarrySwap.pose_arm(arm, CarrySwap.pull_share(true, k), 0.0, out)
		if not is_nan(last):
			worst = maxf(worst, absf(arm.angle_degrees - last))
		last = arm.angle_degrees
		narrowest = minf(narrowest, arm.angle_degrees)
		tick += STEP_TICKS
	print("largest step %.3f deg, narrowest %.3f, last %.3f" % [worst, narrowest, last])
	assert_float(worst).is_less_equal(STEP_MAX_DEGREES)
	assert_float(narrowest).is_equal_approx(StallCarry.BAR_OUT_DEGREES, 0.0001)
	assert_float(last).is_equal_approx(CarryOnProps.PULL_OUT_DEGREES, 0.0001)


## Through the real views: a hard case on its walk to a stall, side-carried
## WALK_MIN_MM or more from it, hangs from an arm turned out 12 degrees; a
## roller leaving a stall is held by its bar beside the row from an arm turned
## out 6, and both arms' turns move at most FRAME_MAX_DEGREES a frame from the
## stall's door until the walker is AFTER_M away, the roller pulled again.
## Controls: frames of each were seen, and the roller's arm went the whole way
## from 6 back to the pull's 12.
func test_the_real_arms_turn_wide_away_and_narrow_beside_the_stalls() -> void:
	var case_p := _visitor(SecurityLooks.Kind.CASE)
	var case_run := await _run(case_p)
	print("case: walk frames %d, turns %s" % [case_run["walk"], case_run["walk_turns"]])
	assert_int(case_run["walk"]).is_greater(0)
	for turn: float in case_run["walk_turns"]:
		assert_float(turn).is_equal(CarrySwap.HAND_OUT_DEGREES)
	var roller_p := _visitor(SecurityLooks.Kind.ROLLER)
	var run := await _run(roller_p)
	print(
		(
			"roller: narrow side frames %d, largest step %.3f deg, narrowest %.3f, last %.3f"
			% [run["narrow"], run["worst"], run["narrowest"], run["last"]]
		)
	)
	assert_int(run["narrow"]).is_greater(0)
	assert_float(run["narrowest"]).is_equal_approx(StallCarry.BAR_OUT_DEGREES, 0.0001)
	assert_float(run["last"]).is_equal_approx(CarryOnProps.PULL_OUT_DEGREES, 0.0001)
	assert_float(run["worst"]).is_less_equal(FRAME_MAX_DEGREES)


func _free_world() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null


## A visitor carrying one bag of `kind`, sent to a stall (as
## test_carry_stall_front_margin.gd does).
func _visitor(kind: SecurityLooks.Kind) -> Passenger:
	_free_world()
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != kind:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.at = Vector2i(20, 14)
	p.clear_path()
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	return p


func _frame() -> void:
	_world.clock.advance(SimClock.STEP * FRAME_TICKS)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## Runs `p`'s visit and the walk AFTER_M beyond it, frame by frame. Returns
## {"walk": side-carried frames on the walk WALK_MIN_MM or more from the
## stall, "walk_turns": the holding arm's turn on each, "narrow": frames after
## the visit with the bag held by its bar at the side beside the stalls,
## "narrowest" and "last": the holding arm's least turn after the visit and
## its turn on the last frame, "worst": the most either arm's turn moved
## between two frames after the visit}.
func _run(p: Passenger) -> Dictionary:
	var props := _views.carry_on_props()
	var approach := _world.sim.grid.cell_to_world(
		_world.sim.toilets.visit_of(p.id).stall["approach"]
	)
	var out := {"walk": 0, "walk_turns": [], "narrow": 0, "narrowest": INF, "last": NAN}
	out["worst"] = 0.0
	var last := []
	var visited := false
	while _world.clock.tick < 20000:
		var sat := _world.clock.tick - p.stage_tick
		if p.stage == Passenger.Stage.TOILET_USE and sat < ToiletSim.USE_TICKS - 4:
			_world.step()
			continue
		await _frame()
		var body := _views.node_for(p.id)
		var held: Dictionary = props._held.get(p.id, {})
		if body == null or held.is_empty() or (held["bags"] as Array).is_empty():
			continue
		var arms: Array = props._rig(body)["arms"]
		var hand: int = held["hands"][0]
		var turn: float = (arms[hand] as CarryArm).angle_degrees
		var bag: Dictionary = held["bags"][0]
		var side := props.front_weight_of(p.id) == 0.0
		if p.stage == Passenger.Stage.TOILET_WALK and p.remaining_mm() >= WALK_MIN_MM and side:
			out["walk"] += 1
			out["walk_turns"].append(turn)
		visited = visited or p.stage == Passenger.Stage.TOILET_EXIT
		if not visited:
			continue
		var turns := [(arms[0] as CarryArm).angle_degrees, (arms[1] as CarryArm).angle_degrees]
		if not last.is_empty():
			for s in 2:
				out["worst"] = maxf(out["worst"], absf(turns[s] - last[s]))
		last = turns
		out["narrowest"] = minf(out["narrowest"], turn)
		out["last"] = turn
		if bag.get("by_bar", false) and side and StallCarry.beside_row(_world.sim, p):
			out["narrow"] += 1
		if not Passenger.in_toilet(p.stage):
			var away := body.global_position - approach
			if Vector2(away.x, away.z).length() > AFTER_M:
				break
	return out
