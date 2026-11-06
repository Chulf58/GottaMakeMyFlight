class_name TestRollerHandChangeReach
extends GdUnitTestSuite
## A pulled roller handed from one pulling hand to the other (pull.R>pull.L)
## is handed over where the receiving hand reaches (CarryLead.pull_swap_goal()):
## the cafe guest of test_roller_queue_stand, drawn every third of a tick
## through its change of hand. While both hands are aimed at the bar (reach
## weights at least FULL), the receiving grip is within MISS_M of its target,
## and the bag moves less than STEP_M against the body as it is handed over.
## On 4f39514 the receiving hand missed by 0.158 m (its target 0.80 m from its
## shoulder, the end it reached for following the hand itself) and the bag
## jumped 0.173 m (0.150 on c8969cc).

const FloatCheck := preload("res://spike/carry_float_check.gd")
const ROLLER := SecurityLooks.Kind.ROLLER
const MISS_M := 0.05
const STEP_M := 0.10
const FULL := 0.9

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


func test_the_receiving_hand_reaches_the_bar_where_it_is_handed_over() -> void:
	var p := await _cafe_guest()
	var props := _views.carry_on_props()
	var last := Vector3.INF
	var window := 0
	var worst_miss := 0.0
	var worst_step := 0.0
	var held_before := -1
	while _world.clock.tick < 400 and p.stage != Passenger.Stage.CAFE_SITTING_DOWN:
		await _tick(1.0 / 3.0)
		var body := _views.node_for(p.id)
		if body == null or props.props_of(p.id).get("bags", []).is_empty():
			continue
		var node: Node3D = props.props_of(p.id)["bags"][0]
		var bag := props.bag_state(p.id, 0)
		var rel := node.global_position - body.global_position
		var step := rel.distance_to(last) if last.is_finite() else 0.0
		last = rel
		var held_by := int(bag.get("held_by", -1))
		var swap := _hand_change(FloatCheck.move_of(props, p.id, 0))
		if swap and held_before >= 0 and held_by >= 0 and held_by != held_before:
			worst_step = maxf(worst_step, step)
			print("tick %.2f handed over %d>%d, step %.3f" % [_now(), held_before, held_by, step])
		held_before = held_by
		var lead: Dictionary = bag.get("lead", {})
		if not swap or lead.is_empty():
			continue
		var weights: Array = lead["weights"]
		if weights[0] < FULL or weights[1] < FULL:
			continue
		var to := CarryLead.hand_of(int(bag["home"]))
		var miss := props.grip_of(body, to).distance_to(lead["targets"][to])
		window += 1
		worst_miss = maxf(worst_miss, miss)
		print("tick %.2f both hands on the bar, receiving grip misses %.3f" % [_now(), miss])
	print(
		"window %d frames, worst miss %.3f, hand-over step %.3f" % [window, worst_miss, worst_step]
	)
	# Control: the change of hand was drawn with both hands on the bar.
	assert_int(window).is_greater(2)
	assert_float(worst_step).is_greater(0.0)
	assert_float(worst_miss).is_less(MISS_M)
	assert_float(worst_step).is_less(STEP_M)


## Whether `move` (FloatCheck.move_of()) passes a pulled roller between the
## pulling hands: "pull.R>pull.L" or "pull.L>pull.R".
static func _hand_change(move: String) -> bool:
	return move in ["pull.R>pull.L", "pull.L>pull.R"]


func _now() -> float:
	return _world.clock.tick + _world.clock.alpha


## As test_roller_queue_stand's _cafe_guest(): a hungry walker with a roller,
## kept on time, sent to the cafe.
func _cafe_guest() -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != ROLLER:
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = 1
	p.hunger = 0
	p.cafe_cooldown = 1000000
	_followed = [p]
	_world.clock.ticked.connect(_keep_on_time)
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	await _tick(1.0)
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	return p


func _keep_on_time(_tick_now: int) -> void:
	for p in _followed:
		p.late = false


## One frame `ticks` sim ticks on, the walker's clip played by the same sim
## time (as test_roller_queue_stand's _tick()).
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
