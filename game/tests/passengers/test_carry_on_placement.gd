class_name TestCarryOnPlacement
extends GdUnitTestSuite
## A bag in hand is put in place exactly once per frame, from its hand's final
## pose (decision carry-on-bag-kinds-as-built, item 6): by _on_pose on the
## first skeleton report after the frame's draw, else before the frame is drawn
## (_unposed), never by both; a report before the draw (a pose set before the
## views draw) places nothing. Counted with CarryOnProps.placements_of over
## real frames for a skeleton that is new, animated, paused (not reporting),
## resumed, reporting before and after the draw, and reporting only before it.
##
## Each frame: wait for the frame to start, let the views draw as the game
## does, wait for the tree to process, count the placements made by reports,
## then run the pre-draw fallback and count again.

const FRAMES := 6
## The bone a test poses before the draw, so the skeleton reports early, and
## how far it turns it (radians).
const EARLY_BONE := "Arm.R"
const EARLY_TURN := 0.6
## A grip on the hand: the bag's held point within this of the hand.
const GRIP_TOL_M := 0.001

var _worlds: Array[SecurityTestWorld] = []
var _views: Array[PassengerViews] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for v in _views:
		v.free()
	_views.clear()
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


## A world with the views drawing and one passenger with a hard case in hand
## (the kind is a hash of the id, so passengers with another kind are sent
## without bags until one has a case), walking to security; returns its id
## with the world and views appended to the lists. Stops on the tick the bag
## appears, before it is ever drawn.
func _make() -> int:
	var w := SecurityTestWorld.make(false)
	_worlds.append(w)
	var views := PassengerViews.new()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	var id := w.send(1)
	while SecurityLooks.bag_kind(w.world.passenger(id), 0) != SecurityLooks.Kind.CASE:
		w.world.passenger(id).carry_on = 0
		id = w.send(1)
	var props := views.carry_on_props()
	# The game's own pre-draw hook is there; the test calls it itself at the
	# end of each frame (_count), so a windowed run does not call it twice.
	assert_bool(RenderingServer.frame_pre_draw.is_connected(props._unposed)).is_true()
	RenderingServer.frame_pre_draw.disconnect(props._unposed)
	for i in 600:
		w.world.step()
		if not props.props_of(id)["bags"].is_empty():
			break
	return id


func _skeleton(id: int) -> Skeleton3D:
	return _views[-1].node_for(id).find_children("*", "Skeleton3D", true, false)[0]


## Stops the skeleton reporting: no animation and no modifier updates.
func _hold(id: int) -> void:
	_skeleton(id).modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	(_views[-1].node_for(id).get_node("AnimationPlayer") as AnimationPlayer).pause()


func _release(id: int) -> void:
	_skeleton(id).modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	(_views[-1].node_for(id).get_node("AnimationPlayer") as AnimationPlayer).play()


## The hand holding the passenger's case (0 right, 1 left).
func _hand(id: int) -> int:
	return SecurityLooks.hand_of(_worlds[-1].world.sim, _worlds[-1].world.passenger(id), 0)


## How far the held point of the passenger's case is from its hand now.
func _grip_off(id: int) -> float:
	var props := _views[-1].carry_on_props()
	var hand := props.grip_of(_views[-1].node_for(id), _hand(id))
	return props.held_point(id, 0).distance_to(hand)


## Runs `frames` frames and returns, for each, {placed: times the bag was
## placed, by_report: of those, before the fallback ran, early / late: reports
## before and after the views drew, grip_off: the held point's distance from
## the hand at the frame's end, early_moved: how far the hand moved from the
## first early report to the frame's end}. With `early`, the test turns
## EARLY_BONE as the frame starts, so the skeleton reports before the draw.
## The views draw in their own _process and the skeleton reports while the
## tree processes; the frame's end (the point RenderingServer.frame_pre_draw
## gives, which a headless run never reaches) is a timer that fires after the
## tree has processed.
func _count(id: int, frames: int, early := false) -> Array:
	var views := _views[-1]
	var props := views.carry_on_props()
	var skeleton := _skeleton(id)
	var hand := _hand(id)
	var seen := {"early": 0, "late": 0, "draws": 0, "early_grip": Vector3.INF}
	var report := func() -> void:
		if props.draws_of(id) > seen["draws"]:
			seen["late"] += 1
			return
		seen["early"] += 1
		if not (seen["early_grip"] as Vector3).is_finite():
			seen["early_grip"] = props.grip_of(views.node_for(id), hand)
	skeleton.skeleton_updated.connect(report)
	var out := []
	for f in frames:
		await get_tree().process_frame
		var before := props.placements_of(id, 0)
		seen["early"] = 0
		seen["late"] = 0
		seen["draws"] = props.draws_of(id)
		seen["early_grip"] = Vector3.INF
		if early:
			var bone := skeleton.find_bone(EARLY_BONE)
			var turned := Quaternion(Vector3.FORWARD, EARLY_TURN)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * turned)
		await get_tree().create_timer(0.0, true, false, true).timeout
		var by_report := props.placements_of(id, 0) - before
		props._unposed()
		var final := props.grip_of(views.node_for(id), hand)
		var early_grip: Vector3 = seen["early_grip"]
		var frame := {
			"placed": props.placements_of(id, 0) - before,
			"by_report": by_report,
			"early": seen["early"],
			"late": seen["late"],
			"grip_off": _grip_off(id),
			"early_moved": early_grip.distance_to(final) if early_grip.is_finite() else 0.0,
		}
		out.append(frame)
	skeleton.skeleton_updated.disconnect(report)
	return out


## Exactly one placement a frame, its case held on the hand's final pose;
## returns the frames with a report after the draw.
func _expect_once(run: Array, label: String) -> int:
	print("per frame, %s: %s" % [label, run])
	var reported := 0
	for frame: Dictionary in run:
		assert_int(frame["placed"]).is_equal(1)
		assert_float(frame["grip_off"]).is_less(GRIP_TOL_M)
		reported += int(frame["late"] > 0)
	return reported


## A skeleton drawn for the first time (no pose seen yet) places its bag once
## in its first frame and in each frame after it.
func test_a_new_skeleton_places_its_bag_once_a_frame() -> void:
	var id := _make()
	assert_int(_views[-1].carry_on_props().placements_of(id, 0)).is_equal(0)
	var run := await _count(id, FRAMES)
	# Control: the skeleton reported, so the pose path was in use.
	assert_int(_expect_once(run, "new")).is_greater(0)


## Playing an animation, the skeleton reports after every draw and the bag is
## placed once in each frame, by that report (the fallback adds nothing).
func test_an_animated_skeleton_places_its_bag_once_a_frame() -> void:
	var id := _make()
	await _count(id, 2)
	var player := _views[-1].node_for(id).get_node("AnimationPlayer") as AnimationPlayer
	assert_bool(player.is_playing()).is_true()
	var run := await _count(id, FRAMES)
	assert_int(_expect_once(run, "animated")).is_equal(FRAMES)
	for frame: Dictionary in run:
		assert_int(frame["by_report"]).is_equal(1)


## A skeleton that does not report (paused) has its bag placed once a frame,
## before the frame is drawn. Control: it reported nothing.
func test_a_skeleton_that_does_not_report_places_its_bag_once_a_frame() -> void:
	var id := _make()
	await _count(id, 2)
	_hold(id)
	await _count(id, 2)
	var run := await _count(id, FRAMES)
	assert_int(_expect_once(run, "paused")).is_equal(0)
	for frame: Dictionary in run:
		assert_int(frame["early"]).is_equal(0)
		assert_int(frame["by_report"]).is_equal(0)


## The frame a paused skeleton resumes reporting: its bag is placed once, not
## by the draw and again by the pose, and once a frame after it. Control: the
## skeleton reported in the frames after the resume.
func test_a_resumed_skeleton_places_its_bag_once_a_frame() -> void:
	var id := _make()
	_hold(id)
	await _count(id, 3)
	_release(id)
	var run := await _count(id, FRAMES)
	assert_int(_expect_once(run, "resumed")).is_greater(0)


## A skeleton that reports twice in a frame, once before the views draw (a bone
## posed as the frame starts) and once after: the bag is placed once, by the
## report after the draw, and held on the hand's final pose. Controls: both
## reports happened in every frame, and the hand at the early report was more
## than a centimetre from where it ends, so a bag placed then would be off it.
func test_a_skeleton_reporting_before_and_after_the_draw_places_its_bag_once() -> void:
	var id := _make()
	await _count(id, 2)
	var run := await _count(id, FRAMES, true)
	assert_int(_expect_once(run, "early and late")).is_equal(FRAMES)
	for frame: Dictionary in run:
		assert_int(frame["early"]).is_equal(1)
		assert_int(frame["late"]).is_equal(1)
		assert_int(frame["by_report"]).is_equal(1)
		assert_float(frame["early_moved"]).is_greater(0.01)


## A skeleton that reports only before the draw (held, a bone posed as the
## frame starts): the report places nothing, and the bag is placed once before
## the frame is drawn, on the posed hand. Control: the early report happened.
func test_a_skeleton_reporting_only_before_the_draw_places_its_bag_once() -> void:
	var id := _make()
	await _count(id, 2)
	_hold(id)
	await _count(id, 2)
	var run := await _count(id, FRAMES, true)
	assert_int(_expect_once(run, "early only")).is_equal(0)
	for frame: Dictionary in run:
		assert_int(frame["early"]).is_equal(1)
		assert_int(frame["by_report"]).is_equal(0)
