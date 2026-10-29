class_name TestCarryOnPlacement
extends GdUnitTestSuite
## A bag in hand ends each frame on its hand's final pose, and its stateful
## part steps exactly once per draw (decision carry-on-bag-kinds-as-built,
## item 6; CarryOnProps._step_hand_bags, _on_pose, _unposed). draw() steps it
## (counted by steps_of; a pulled roller's follower by follows_of); every
## skeleton report after a draw places it from the pose it reports, so the last
## report wins; a report before the draw places nothing; a draw no report
## followed has it placed before the frame is drawn. Checked over real frames
## for a skeleton that is new, animated, paused (not reporting), resumed,
## reporting before and after the draw, only before it, twice after it with
## the hand moved between, and for two draws with one report after them.
##
## Each frame: wait for the frame to start, let the views draw as the game
## does, wait for the tree to process, count the placements made by reports,
## then run the pre-draw fallback and count again.

const FRAMES := 6
## The bone a test poses to make the skeleton report (before the draw, or
## again after it), and how far it turns it (radians).
const POSED_BONE := "Arm.R"
const TURN := 0.6
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


## A world with the views drawing and one passenger whose first bag is of
## `kind` (the kind is a hash of the id, so passengers with another kind are
## sent without bags until one fits), walking to security; returns its id with
## the world and views appended to the lists. Stops on the tick the bag
## appears, before it is ever drawn.
func _make(kind := SecurityLooks.Kind.CASE) -> int:
	var w := SecurityTestWorld.make(false)
	_worlds.append(w)
	var views := PassengerViews.new()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	var id := w.send(1)
	while SecurityLooks.bag_kind(w.world.passenger(id), 0) != kind:
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


## The hand holding the passenger's first bag (0 right, 1 left).
func _hand(id: int) -> int:
	return SecurityLooks.hand_of(_worlds[-1].world.sim, _worlds[-1].world.passenger(id), 0)


## How far the held point of the passenger's case is from its hand now (INF
## for a bag not held by a point, such as a pulled roller).
func _grip_off(id: int) -> float:
	var props := _views[-1].carry_on_props()
	var at := props.held_point(id, 0)
	if not at.is_finite():
		return INF
	return at.distance_to(props.grip_of(_views[-1].node_for(id), _hand(id)))


## Turns POSED_BONE further, so the skeleton reports again.
func _turn_bone(skeleton: Skeleton3D) -> void:
	var bone := skeleton.find_bone(POSED_BONE)
	var turned := Quaternion(Vector3.FORWARD, TURN)
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * turned)


## Runs `frames` frames and returns, for each, {placed: times the bag was
## placed, by_report: of those, before the fallback ran, steps / follows / draws:
## the bag's steps, its follower's steps and the props' draws, early / late:
## reports before and after the views drew, grip_off: the held point's distance
## from the hand at the frame's end, moved: how far the hand moved from the
## first report that placed nothing new (an early one, or the first late one
## when `again`) to the frame's end}. `mode` "early" turns POSED_BONE as the
## frame starts, so the skeleton reports before the draw; "again" turns it
## after the tree processed and has the skeleton update at once (a call queued
## during the message flush runs only next frame), so it reports twice after
## the draw with the hand moved between; "redraw" draws the views once more as
## the frame starts, so two draws come before one report. The views draw in
## their own _process and the skeleton reports while the tree processes; the
## frame's end (the point RenderingServer.frame_pre_draw gives, which a
## headless run never reaches) is a timer that fires after the tree processed.
func _count(id: int, frames: int, mode := "") -> Array:
	var views := _views[-1]
	var props := views.carry_on_props()
	var skeleton := _skeleton(id)
	var hand := _hand(id)
	var seen := {"early": 0, "late": 0, "draws": 0, "first": Vector3.INF}
	var report := func() -> void:
		var late: bool = props.draws_of(id) > seen["draws"]
		seen["late" if late else "early"] += 1
		var watch: bool = (not late) or (mode == "again" and seen["late"] == 1)
		if watch and not (seen["first"] as Vector3).is_finite():
			seen["first"] = props.grip_of(views.node_for(id), hand)
	skeleton.skeleton_updated.connect(report)
	var out := []
	for f in frames:
		await get_tree().process_frame
		var before := [props.placements_of(id, 0), props.steps_of(id, 0), props.follows_of(id, 0)]
		var draws_before := props.draws_of(id)
		seen["early"] = 0
		seen["late"] = 0
		seen["draws"] = draws_before
		seen["first"] = Vector3.INF
		if mode == "early":
			_turn_bone(skeleton)
		elif mode == "redraw":
			views.draw()
			seen["draws"] = props.draws_of(id)
		await get_tree().create_timer(0.0, true, false, true).timeout
		if mode == "again":
			_turn_bone(skeleton)
			skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var by_report: int = props.placements_of(id, 0) - before[0]
		props._unposed()
		var final := props.grip_of(views.node_for(id), hand)
		var first: Vector3 = seen["first"]
		var frame := {
			"placed": props.placements_of(id, 0) - before[0],
			"by_report": by_report,
			"steps": props.steps_of(id, 0) - before[1],
			"follows": props.follows_of(id, 0) - before[2],
			"draws": props.draws_of(id) - draws_before,
			"early": seen["early"],
			"late": seen["late"],
			"grip_off": _grip_off(id),
			"moved": first.distance_to(final) if first.is_finite() else 0.0,
		}
		out.append(frame)
	skeleton.skeleton_updated.disconnect(report)
	return out


## Each frame: one step per draw, placed once per report after the draw (or
## once by the fallback when none came), the case held on the hand's final
## pose; returns the frames with a report after the draw.
func _expect(run: Array, label: String) -> int:
	print("per frame, %s: %s" % [label, run])
	var reported := 0
	for frame: Dictionary in run:
		assert_int(frame["steps"]).is_equal(frame["draws"])
		assert_int(frame["by_report"]).is_equal(frame["late"])
		assert_int(frame["placed"]).is_equal(maxi(1, frame["late"]))
		assert_float(frame["grip_off"]).is_less(GRIP_TOL_M)
		reported += int(frame["late"] > 0)
	return reported


## A skeleton drawn for the first time (no pose seen yet) has its bag placed in
## its first frame and in each frame after it.
func test_a_new_skeleton_places_its_bag_each_frame() -> void:
	var id := _make()
	assert_int(_views[-1].carry_on_props().placements_of(id, 0)).is_equal(0)
	var run := await _count(id, FRAMES)
	# Control: the skeleton reported, so the pose path was in use.
	assert_int(_expect(run, "new")).is_greater(0)


## Playing an animation, the skeleton reports once after every draw and the
## bag is placed by that report (the fallback adds nothing).
func test_an_animated_skeleton_places_its_bag_once_a_frame() -> void:
	var id := _make()
	await _count(id, 2)
	var player := _views[-1].node_for(id).get_node("AnimationPlayer") as AnimationPlayer
	assert_bool(player.is_playing()).is_true()
	var run := await _count(id, FRAMES)
	assert_int(_expect(run, "animated")).is_equal(FRAMES)
	for frame: Dictionary in run:
		assert_int(frame["draws"]).is_equal(1)
		assert_int(frame["placed"]).is_equal(1)


## A skeleton that does not report (paused) has its bag placed once a frame,
## before the frame is drawn. Control: it reported nothing.
func test_a_skeleton_that_does_not_report_places_its_bag_once_a_frame() -> void:
	var id := _make()
	await _count(id, 2)
	_hold(id)
	await _count(id, 2)
	var run := await _count(id, FRAMES)
	assert_int(_expect(run, "paused")).is_equal(0)
	for frame: Dictionary in run:
		assert_int(frame["early"]).is_equal(0)
		assert_int(frame["placed"]).is_equal(1)


## The frame a paused skeleton resumes reporting: its bag is placed by the
## report, not by the fallback as well. Control: the skeleton reported in the
## frames after the resume.
func test_a_resumed_skeleton_places_its_bag_by_its_report() -> void:
	var id := _make()
	_hold(id)
	await _count(id, 3)
	_release(id)
	var run := await _count(id, FRAMES)
	assert_int(_expect(run, "resumed")).is_greater(0)


## A skeleton that reports before the views draw (a bone posed as the frame
## starts) and after: the early report places nothing, the late one places the
## bag on the hand's final pose. Controls: both reports happened in every frame,
## and the hand at the early report was more than a centimetre from where it
## ends, so a bag placed then would be off it.
func test_a_report_before_the_draw_places_nothing() -> void:
	var id := _make()
	await _count(id, 2)
	var run := await _count(id, FRAMES, "early")
	assert_int(_expect(run, "early and late")).is_equal(FRAMES)
	for frame: Dictionary in run:
		assert_int(frame["early"]).is_equal(1)
		assert_int(frame["late"]).is_equal(1)
		assert_int(frame["placed"]).is_equal(1)
		assert_float(frame["moved"]).is_greater(0.01)


## A skeleton that reports only before the draw (held, a bone posed as the
## frame starts): the report places nothing, and the bag is placed once before
## the frame is drawn, on the posed hand. Control: the early report happened.
func test_a_skeleton_reporting_only_before_the_draw_places_its_bag_once() -> void:
	var id := _make()
	await _count(id, 2)
	_hold(id)
	await _count(id, 2)
	var run := await _count(id, FRAMES, "early")
	assert_int(_expect(run, "early only")).is_equal(0)
	for frame: Dictionary in run:
		assert_int(frame["early"]).is_equal(1)
		assert_int(frame["placed"]).is_equal(1)


## A skeleton that reports twice after the draw with the hand moved between
## (the bone turned at the first report): the bag ends on the second pose, and
## its stateful part stepped once. Controls: two reports after the draw in every
## frame, and the hand moved more than a centimetre between them, so a bag left
## on the first would be off it.
func test_the_last_report_after_the_draw_wins() -> void:
	var id := _make()
	await _count(id, 2)
	var run := await _count(id, FRAMES, "again")
	assert_int(_expect(run, "two late reports")).is_equal(FRAMES)
	for frame: Dictionary in run:
		assert_int(frame["late"]).is_equal(2)
		assert_int(frame["placed"]).is_equal(2)
		assert_int(frame["steps"]).is_equal(1)
		assert_float(frame["moved"]).is_greater(0.01)


## Two draws before one report (as on a PassengerViews.snap() frame): the bag
## steps once per draw and ends on the hand's final pose.
func test_two_draws_step_the_bag_twice() -> void:
	var id := _make()
	await _count(id, 2)
	var run := await _count(id, FRAMES, "redraw")
	assert_int(_expect(run, "two draws")).is_equal(FRAMES)
	for frame: Dictionary in run:
		assert_int(frame["draws"]).is_equal(2)
		assert_int(frame["steps"]).is_equal(2)


## A pulled roller's axle follower steps once per draw, never per report:
## twice in a frame drawn twice, once in a frame reported twice. Control: the
## roller is pulled (its carry is PULL), so the follower is in use.
func test_a_pulled_rollers_follower_steps_once_per_draw() -> void:
	var id := _make(SecurityLooks.Kind.ROLLER)
	await _count(id, 2)
	var carries: Array = _views[-1].carry_on_props().props_of(id)["carries"]
	assert_int(carries[0]).is_equal(SecurityLooks.Carry.PULL)
	var redrawn := await _count(id, FRAMES, "redraw")
	var again := await _count(id, FRAMES, "again")
	print("roller per frame, two draws: %s; two late reports: %s" % [redrawn, again])
	for frame: Dictionary in redrawn:
		assert_int(frame["follows"]).is_equal(2)
		assert_int(frame["steps"]).is_equal(2)
	for frame: Dictionary in again:
		assert_int(frame["late"]).is_equal(2)
		assert_int(frame["placed"]).is_equal(2)
		assert_int(frame["follows"]).is_equal(1)
