class_name TestPassengerViewsCrossfade
extends GdUnitTestSuite
## A passenger's clip change blends from the pose drawn to the new clip (user
## ruling passenger-turns-on-the-spot-ease-over-a-few-frames-and-anima), so the
## hands never jump in a frame, and a snap (a load) starts the clip and the
## turn over with no blend from before. A cafe guest walks to the counter and
## its seat (walk and idle in the queue, idle to sit_down, sit_down to
## sit_idle), sits, stands up and is snapped; each frame is a third of a tick,
## and the clips are played a third of a tick a frame by hand, from the first
## tick the guest is drawn.

## On a clip change and while it blends, the most a hand's move may change
## from one frame to the next, in the skeleton's frame (board 908de167: no
## clip-change grip jump over 0.05 m; the kink, as
## park_recovery_plates_probe.gd measures it).
const MAX_KINK_M := 0.05
## On a clip change and while it blends, the most a hand may move in a frame
## (the walk clip alone swings it up to 0.084 m a frame at 1x; played with no
## blend, a change to idle moved it 0.41 m).
const MAX_MOVE_M := 0.09
const FRAMES_PER_TICK := 3
const HANDS: Array[String] = ["Fingers.R", "Fingers.L"]

var _world: PassengerTestWorld
var _views: PassengerViews
var _p: Passenger
var _run := {}


func before() -> void:
	PassengerTestWorld.tracker = self
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_p.hunger = 0
	_p.cafe_cooldown = 1000000
	_p.carry_on = 0
	_run["changes"] = []
	_run["worst"] = 0.0
	_run["worst_at"] = ""
	_run["kink"] = 0.0
	_run["kink_at"] = ""
	_world.step()
	var last := {}
	while _p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		last = _frame(last)
	_run["visit"] = _world.sim.cafes.try_visit(_p)
	_snap_mid_turn(last)
	# A snap may move the hands at once: the moves are measured from the frame
	# after it.
	last = {}
	while _p.stage != Passenger.Stage.CAFE_SEATED and _world.clock.tick < 1400:
		last = _frame(last)
	for i in 30:
		last = _frame(last)
	_snap_mid_stand_up(last)


func after() -> void:
	_views.free()
	_world.free_all()
	PassengerTestWorld.tracker = null


## One frame: the clock a third of a tick on, drawn, the clip played on as
## far; each hand's move and its kink against `last` are kept. Returns this
## frame's clip, hands and moves.
func _frame(last: Dictionary) -> Dictionary:
	_world.clock.advance(SimClock.STEP / FRAMES_PER_TICK)
	_views.draw()
	var node := _views.node_for(_p.id)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	player.advance(SimClock.STEP / FRAMES_PER_TICK)
	var fade: ClipCrossfade = node.get_meta(&"crossfade")
	var now := {
		"clip": String(node.get_meta(&"clip", "")),
		"hands": _hands(node),
		"moves": [],
		"fading": fade.blending(),
	}
	if last.is_empty():
		return now
	if now["clip"] != last["clip"]:
		now["fading"] = true
		(_run["changes"] as Array).append("%s>%s" % [last["clip"], now["clip"]])
	_run["fade_frames"] = int(_run.get("fade_frames", 0)) + int(fade.blending())
	var what := "tick %d %s>%s" % [_world.clock.tick, last["clip"], now["clip"]]
	for i in HANDS.size():
		var move: Vector3 = (now["hands"][i] as Vector3) - last["hands"][i]
		(now["moves"] as Array).append(move)
		if not (now["fading"] or last["fading"]):
			continue
		if move.length() > _run["worst"]:
			_run["worst"] = move.length()
			_run["worst_at"] = "%s hand %d" % [what, i]
		if (last["moves"] as Array).size() == HANDS.size():
			var kink := move.distance_to(last["moves"][i])
			if kink > _run["kink"]:
				_run["kink"] = kink
				_run["kink_at"] = "%s hand %d" % [what, i]
	return now


## Each hand's place in the skeleton's frame, in metres, as drawn: read while
## the skeleton updates, after its modifiers (the skeleton puts the clip's pose
## back after an update).
static func _hands(node: Node3D) -> Array[Vector3]:
	var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var scale_by := skeleton.global_transform.basis.get_scale().x
	var at: Array[Vector3] = []
	var read := func() -> void:
		at.clear()
		for bone in HANDS:
			at.append(skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin * scale_by)
	skeleton.skeleton_updated.connect(read)
	skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	skeleton.skeleton_updated.disconnect(read)
	return at


## The hands of a fresh body of the same kind playing `clip` alone at `at` s.
func _clip_alone(body: int, clip: String, at: float) -> Array[Vector3]:
	var fresh := PassengerLooks.SCENES[body].instantiate() as Node3D
	add_child(fresh)
	fresh.global_transform = _views.node_for(_p.id).global_transform
	var player := fresh.get_node("AnimationPlayer") as AnimationPlayer
	player.play(clip)
	player.seek(at, true)
	var hands := _hands(fresh)
	fresh.free()
	return hands


## Plays on to the first frame of the stand-up clip and two frames into its
## blend, snaps, and keeps the hands against the clip played alone.
func _snap_mid_stand_up(from: Dictionary) -> void:
	var last := from
	while _p.stage != Passenger.Stage.CAFE_STANDING_UP and _world.clock.tick < 2000:
		last = _frame(last)
	last = _frame(_frame(last))
	_run["stand_up_reached"] = _p.stage == Passenger.Stage.CAFE_STANDING_UP
	var node := _views.node_for(_p.id)
	var fade: ClipCrossfade = node.get_meta(&"crossfade")
	_run["blending_before_snap"] = fade.blending()
	_views.snap()
	_run["blending_after_snap"] = fade.blending()
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	player.advance(0.0)
	_run["snap_clip"] = player.current_animation
	var alone := _clip_alone(
		node.get_meta(&"body"), player.current_animation, player.current_animation_position
	)
	var drawn := _hands(node)
	_run["snap_gap"] = maxf(drawn[0].distance_to(alone[0]), drawn[1].distance_to(alone[1]))


## Plays on to the second tick of the walk from the counter to the seat (an
## about-turn on the spot), snaps, and keeps the drawn yaw against the walk's
## heading.
func _snap_mid_turn(from: Dictionary) -> void:
	var last := from
	var walking := 0
	while walking < 2 and _world.clock.tick < 1400:
		var tick := _world.clock.tick
		last = _frame(last)
		var to_seat := _p.stage == Passenger.Stage.CAFE_TO_SEAT
		if _world.clock.tick != tick and to_seat and _views.walk_heading(_p) != Vector2.ZERO:
			walking += 1
	var heading := _views.walk_heading(_p)
	var yaw := atan2(heading.x, heading.y)
	var node := _views.node_for(_p.id)
	_run["turn_left_deg"] = rad_to_deg(absf(angle_difference(node.rotation.y, yaw)))
	_views.snap()
	_run["walk_heading"] = heading
	_run["snap_yaw_gap_deg"] = rad_to_deg(absf(angle_difference(node.rotation.y, yaw)))


func test_the_guest_changed_clips_on_the_way_to_its_seat() -> void:
	# Control: without the clip changes the bounds below prove nothing.
	assert_bool(_run["visit"]).is_true()
	var changes: Array = _run["changes"]
	print("clip changes: %s" % [changes])
	for change in ["walk>idle", "idle>walk", "idle>sit_down", "sit_down>sit_idle"]:
		assert_bool(changes.has(change)).is_true()
	# Each change blends over several frames (0.18 s is about 11 at 1x).
	print("frames drawn blending: %d" % _run["fade_frames"])
	assert_int(_run["fade_frames"]).is_greater_equal(changes.size() * 8)


func test_no_hand_jumps_in_a_frame() -> void:
	print(
		(
			"largest hand move in one frame: %.3f m at %s; largest kink %.3f m at %s"
			% [_run["worst"], _run["worst_at"], _run["kink"], _run["kink_at"]]
		)
	)
	assert_float(_run["kink"]).is_less(MAX_KINK_M)
	assert_float(_run["worst"]).is_less(MAX_MOVE_M)
	assert_float(_run["worst"]).is_greater(0.001)


func test_a_snap_mid_blend_plays_the_new_clip_alone() -> void:
	# Control: the snap came while the stand-up was blending in.
	assert_bool(_run["stand_up_reached"]).is_true()
	assert_bool(_run["blending_before_snap"]).is_true()
	print(
		(
			"after the snap: %s, hands %.4f m off the clip alone"
			% [_run["snap_clip"], _run["snap_gap"]]
		)
	)
	assert_bool(_run["blending_after_snap"]).is_false()
	assert_str(_run["snap_clip"]).is_equal("stand_up")
	assert_float(_run["snap_gap"]).is_less(0.002)


func test_a_snap_mid_turn_faces_the_walk_at_once() -> void:
	# Control: the walk away was still turning when the snap came.
	print(
		(
			"before the snap %.1f deg left to turn, after it %.3f deg"
			% [_run["turn_left_deg"], _run["snap_yaw_gap_deg"]]
		)
	)
	assert_bool(_run["walk_heading"] != Vector2.ZERO).is_true()
	assert_float(_run["turn_left_deg"]).is_greater(1.0)
	assert_float(_run["snap_yaw_gap_deg"]).is_less(0.01)
