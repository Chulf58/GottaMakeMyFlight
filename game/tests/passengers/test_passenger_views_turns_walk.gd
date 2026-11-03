class_name TestPassengerViewsTurnsWalk
extends GdUnitTestSuite
## A walking passenger faces its step at once; only turns on the spot ease
## (user ruling passenger-turns-on-the-spot-ease-over-a-few-frames-and-anima,
## board 908de167). A passenger pulling a roller walks from security to a cafe
## and on to its seat, round the corners of its path, every frame drawn as the
## game draws it, at 1x and at 3x. CarryOnProps._trail lays the roller's trail
## on the pulling hand's side of the step's heading, so a body still easing
## round a walking corner faced one way while its trail was laid for another.
## Checked on each walking frame once the walker has stepped on for more than
## a turn (past any turn from setting off): the body faces its step, the
## heading the trail is laid on. The largest change in a frame of the distance
## from the pulling hand to the axle (a settled pull, the same hand on both
## frames) is printed, within a turn's ticks of a corner and elsewhere.

## Ticks a frame: a game at 1x (20 ticks a second at 60 frames) and at 3x.
const FRAME_TICKS := [1.0 / 3.0, 1.0]
## A heading change over this between two walking ticks is a corner.
const CORNER_DEG := 30.0
## Drawn this close to a heading (degrees), the body faces it.
const ON_DEG := 0.06

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


static func _deg(a: float, b: float) -> float:
	return rad_to_deg(absf(angle_difference(a, b)))


## A passenger whose one bag is a roller, past security and sent to a cafe in
## a new world.
func _roller_walker() -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	# The test runs the pre-draw fallback itself at the end of each frame.
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = 1
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 3000:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	return p


## One frame `ticks` sim ticks on, as the game draws it.
func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## The walk to the cafe seat, one entry a frame: {"new_tick", "step" (the step
## drawn over this tick), "yaw", "walked": ticks walked since the walker last
## stood, "pulled", "hand": the pulling hand, "settled": no move or swap of
## the roller under way, "grip": the pulling hand's grip, "axle": the
## roller's axle}.
func _walk(p: Passenger, ticks: float) -> Array[Dictionary]:
	var props := _views.carry_on_props()
	var frames: Array[Dictionary] = []
	var walked := 0
	while p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 3000:
		var tick := _world.clock.tick
		await _tick(ticks)
		var body := _views.node_for(p.id)
		var step := _views.tick_position(p.id, true) - _views.tick_position(p.id, false)
		var new_tick := _world.clock.tick != tick
		if new_tick:
			walked = walked + _world.clock.tick - tick if step.length() > 0.001 else 0
		var held := props.props_of(p.id)
		var pulled: bool = (
			held["carries"][0] == SecurityLooks.Carry.PULL
			and SecurityLooks.bag_homes(_world.sim, p)[0] == SecurityLooks.Home.HAND
		)
		var hand: int = props._held[p.id]["hands"][0]
		var bag: Node3D = held["bags"][0]
		var settled := not props.swapping(p.id, 0) and props.transfer_progress(p.id, 0) >= 1.0
		(
			frames
			. append(
				{
					"new_tick": new_tick,
					"step": step,
					"yaw": body.rotation.y,
					"walked": walked,
					"pulled": pulled,
					"hand": hand,
					"settled": settled,
					"grip": props.grip_of(body, hand),
					"axle": bag.global_transform * CarryOnProps.ROLLER_AXLE,
				}
			)
		)
	return frames


func _check(ticks: float) -> void:
	var p := _roller_walker()
	var frames := await _walk(p, ticks)
	var corners := 0
	var checked := 0
	var worst_yaw := 0.0
	var reach := {"corner": 0.0, "other": 0.0}
	var last := INF
	var since_corner := 1000
	for i in frames.size():
		var f := frames[i]
		var step: Vector3 = f["step"]
		if step.length() <= 0.001 or not f["pulled"]:
			last = INF
			continue
		var heading := atan2(step.x, step.z)
		if f["new_tick"]:
			since_corner += 1
			if is_finite(last) and _deg(last, heading) > CORNER_DEG:
				since_corner = 0
				corners += int(f["walked"] > PassengerTurns.TURN_TICKS)
		last = heading
		if f["walked"] <= PassengerTurns.TURN_TICKS:
			continue
		worst_yaw = maxf(worst_yaw, _deg(f["yaw"], heading))
		checked += 1
		var before := frames[i - 1]
		if not (f["settled"] and before["settled"] and before["hand"] == f["hand"]):
			continue
		var now := (f["grip"] as Vector3).distance_to(f["axle"])
		var was := (before["grip"] as Vector3).distance_to(before["axle"])
		var key := "corner" if since_corner < PassengerTurns.TURN_TICKS else "other"
		reach[key] = maxf(reach[key], absf(now - was))
	print(
		(
			(
				"%.2f ticks a frame: %d frames, %d walking corners, %d walking frames;"
				% [ticks, frames.size(), corners, checked]
			)
			+ " worst yaw off the step %.2f deg;" % worst_yaw
			+ (
				" largest hand-to-axle change a frame %.3f m at corners, %.3f m elsewhere"
				% [reach["corner"], reach["other"]]
			)
		)
	)
	assert_int(corners).is_greater(0)
	assert_int(checked).is_greater(30)
	assert_float(worst_yaw).is_less(ON_DEG)


func test_a_roller_walker_faces_its_step_round_corners_at_1x() -> void:
	await _check(FRAME_TICKS[0])


func test_a_roller_walker_faces_its_step_round_corners_at_3x() -> void:
	await _check(FRAME_TICKS[1])
