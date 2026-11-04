class_name TestPassengerViewsTurns
extends GdUnitTestSuite
## A passenger's body turns over a few frames, never in one (user ruling
## passenger-turns-on-the-spot-ease-over-a-few-frames-and-anima). A cafe guest
## walks to the counter, turning at the corners of its path, turns on the spot
## in the queue to face the counter, sets off from the counter to its seat
## (an about-turn on the spot) and sits down. The run is drawn a third of a
## tick a frame (1x at 60 frames a second), and every frame's drawn yaw is kept.

## The largest yaw change a frame may draw at 1x (board 908de167 allows 20).
const MAX_FRAME_DEG := 15.0
## A turn over this is one the ruling eases over 0.2-0.3 s.
const RULED_TURN_DEG := 30.0
const FRAMES_PER_TICK := 3
## Drawn this close to a heading (degrees), the body faces it.
const ON_DEG := 0.06

var _world: PassengerTestWorld
var _views: PassengerViews
var _run := {}


func before() -> void:
	PassengerTestWorld.tracker = self
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	p.carry_on = 0
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	_run["visit"] = _world.sim.cafes.try_visit(p)
	var seat: Dictionary = _world.sim.cafes.visit_of(p.id).seat
	var facing: Vector2i = seat["facing"]
	_run["seat_yaw"] = atan2(facing.x, facing.y)
	var frames: Array[Dictionary] = []
	var seated_ticks := 0
	while seated_ticks < 10 and _world.clock.tick < 1400:
		var tick := _world.clock.tick
		_world.clock.advance(SimClock.STEP / FRAMES_PER_TICK)
		_views.draw()
		var node := _views.node_for(p.id)
		var f := {
			"tick": _world.clock.tick,
			"new_tick": _world.clock.tick != tick,
			"yaw": node.rotation.y,
			"stage": p.stage,
			"step": _views.tick_position(p.id, true) - _views.tick_position(p.id, false),
		}
		frames.append(f)
		if p.stage == Passenger.Stage.CAFE_SEATED and _world.clock.tick != tick:
			seated_ticks += 1
	_run["frames"] = frames


func after() -> void:
	_views.free()
	_world.free_all()
	PassengerTestWorld.tracker = null


func _frames() -> Array[Dictionary]:
	return _run["frames"]


static func _deg(a: float, b: float) -> float:
	return rad_to_deg(absf(angle_difference(a, b)))


static func _heading(f: Dictionary) -> float:
	var step: Vector3 = f["step"]
	return atan2(step.x, step.z)


static func _walking(f: Dictionary) -> bool:
	return (f["step"] as Vector3).length() > 0.001


## The frame index of the first tick a standing guest sets off from the
## counter to its seat, or -1.
func _set_off() -> int:
	var frames := _frames()
	for i in range(1, frames.size()):
		var f := frames[i]
		if f["new_tick"] and f["stage"] == Passenger.Stage.CAFE_TO_SEAT and _walking(f):
			return i
	return -1


func test_the_guest_reached_its_seat_and_turned_on_the_way() -> void:
	# Controls: the run walked and sat the guest down, its heading changed by
	# more than the ruled turn at corners of its walk, and it set off from the
	# counter in a direction more than the ruled turn from the way it faced.
	assert_bool(_run["visit"]).is_true()
	var frames := _frames()
	assert_int(frames[-1]["stage"]).is_equal(Passenger.Stage.CAFE_SEATED)
	var walk_turns := 0
	var last_heading := INF
	for f in frames:
		if f["new_tick"] and f["stage"] == Passenger.Stage.CAFE_WALK and _walking(f):
			var heading := _heading(f)
			if is_finite(last_heading) and _deg(last_heading, heading) > RULED_TURN_DEG:
				walk_turns += 1
			last_heading = heading
	var off := _set_off()
	assert_int(off).is_greater(0)
	var standing := frames[off - 1]
	assert_bool(_walking(standing)).is_false()
	var set_off_turn := _deg(standing["yaw"], _heading(frames[off]))
	print(
		(
			"walk turns over %.0f deg: %d; set-off turn %.1f deg at tick %d"
			% [RULED_TURN_DEG, walk_turns, set_off_turn, frames[off]["tick"]]
		)
	)
	assert_int(walk_turns).is_greater(0)
	assert_float(set_off_turn).is_greater(RULED_TURN_DEG)


func test_no_frame_turns_the_body_more_than_the_bound() -> void:
	var frames := _frames()
	var worst := 0.0
	var at := 0
	for i in range(1, frames.size()):
		var turn := _deg(frames[i - 1]["yaw"], frames[i]["yaw"])
		if turn > worst:
			worst = turn
			at = frames[i]["tick"]
	print("largest yaw change in one frame: %.2f deg at tick %d" % [worst, at])
	assert_float(worst).is_less(MAX_FRAME_DEG)
	assert_float(worst).is_greater(0.5)


func test_the_set_off_turn_spreads_over_a_fifth_to_three_tenths_of_a_second() -> void:
	# From the first frame of the tick it sets off on (still drawn as it stood)
	# to the first frame drawn on the new heading.
	var frames := _frames()
	var off := _set_off()
	assert_int(off).is_greater(0)
	var heading := _heading(frames[off])
	var reached := -1
	for i in range(off, frames.size()):
		if _deg(frames[i]["yaw"], heading) < ON_DEG:
			reached = i
			break
	assert_int(reached).is_greater(off)
	var seconds := (reached - off) * SimClock.STEP / FRAMES_PER_TICK
	print("set-off turn from frame %d to %d: %.3f s" % [off, reached, seconds])
	assert_float(seconds).is_between(0.19, 0.31)
	# Several frames in between, each turning part of the way.
	var moving := 0
	for i in range(off, reached + 1):
		if _deg(frames[i - 1]["yaw"], frames[i]["yaw"]) > 0.5:
			moving += 1
	assert_int(moving).is_greater_equal(9)


func test_the_body_ends_facing_its_heading_and_its_seat() -> void:
	var frames := _frames()
	# Seated: on the seat's facing, exactly.
	assert_float(_deg(frames[-1]["yaw"], _run["seat_yaw"])).is_less(ON_DEG)
	# Walking: once a heading has held for more than a turn, the body faces it.
	var held := 0
	var last := INF
	var checked := 0
	var walks := [Passenger.Stage.CAFE_WALK, Passenger.Stage.CAFE_TO_SEAT]
	for f in frames:
		if not _walking(f) or not walks.has(f["stage"]):
			held = 0
			last = INF
			continue
		var heading := _heading(f)
		if f["new_tick"]:
			held = held + 1 if is_finite(last) and _deg(last, heading) < ON_DEG else 1
			last = heading
		if held > PassengerTurns.TURN_TICKS:
			assert_float(_deg(f["yaw"], heading)).is_less(ON_DEG)
			checked += 1
	print("walking frames checked on their heading: %d" % checked)
	assert_int(checked).is_greater(30)
