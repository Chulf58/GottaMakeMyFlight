class_name TestCarryOnPlacement
extends GdUnitTestSuite
## A bag in hand is put in place once per frame, with its hand's final pose
## (decision carry-on-bag-kinds-as-built, item 6): by _on_pose when its
## skeleton reports that frame, else before the frame is drawn (_unposed),
## never by both. Counted with CarryOnProps.placements_of over real frames
## for a skeleton that is new, animated, paused (not reporting) and resumed.
##
## Each frame: wait for the frame to start, draw the views once as the game
## does, wait for the frame to be drawn, read the count.

const FRAMES := 6

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


## A world with the views drawing and one passenger with a bag in hand, walking
## to security; returns the passenger's id with the world and views appended to
## the lists. Stops on the tick the bag appears, before it is ever drawn.
func _make() -> int:
	var w := SecurityTestWorld.make(false)
	_worlds.append(w)
	var views := PassengerViews.new()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	var id := w.send(1)
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


## Runs `frames` frames and returns, for each, [times the bag was placed, times
## the skeleton reported its pose]. The views draw in their own _process and
## the skeleton reports (or not) while the tree processes; the frame's end
## (the point RenderingServer.frame_pre_draw gives, which a headless run never
## reaches) is a timer that fires after the tree has processed.
func _count(id: int, frames: int) -> Array:
	var views := _views[-1]
	var props := views.carry_on_props()
	var skeleton := _skeleton(id)
	var reported := [0]
	var report := func() -> void: reported[0] += 1
	skeleton.skeleton_updated.connect(report)
	var out := []
	for f in frames:
		await get_tree().process_frame
		var before := props.placements_of(id, 0)
		reported[0] = 0
		await get_tree().create_timer(0.0, true, false, true).timeout
		props._unposed()
		out.append([props.placements_of(id, 0) - before, reported[0]])
	skeleton.skeleton_updated.disconnect(report)
	return out


## One placement a frame, or one for each report of the pose when the skeleton
## reports more than once (its first frames); returns the frames reported in.
func _expect_once(run: Array, label: String) -> int:
	print("[placed, reported] per frame, %s: %s" % [label, run])
	var reported := 0
	for frame: Array in run:
		assert_int(frame[0]).is_equal(maxi(1, frame[1]))
		reported += int(frame[1] > 0)
	return reported


## A skeleton drawn for the first time (no pose seen yet) places its bag once
## in its first frame and in each frame after it.
func test_a_new_skeleton_places_its_bag_once_a_frame() -> void:
	var id := _make()
	assert_int(_views[-1].carry_on_props().placements_of(id, 0)).is_equal(0)
	var run := await _count(id, FRAMES)
	# Control: the skeleton reported, so the pose path was in use.
	assert_int(_expect_once(run, "new")).is_greater(0)


## Playing an animation, the skeleton reports every frame and the bag is
## placed once in each.
func test_an_animated_skeleton_places_its_bag_once_a_frame() -> void:
	var id := _make()
	await _count(id, 2)
	var player := _views[-1].node_for(id).get_node("AnimationPlayer") as AnimationPlayer
	assert_bool(player.is_playing()).is_true()
	var run := await _count(id, FRAMES)
	assert_int(_expect_once(run, "animated")).is_equal(FRAMES)


## A skeleton that does not report (paused) has its bag placed once a frame,
## before the frame is drawn. Control: it reported nothing.
func test_a_skeleton_that_does_not_report_places_its_bag_once_a_frame() -> void:
	var id := _make()
	await _count(id, 2)
	_hold(id)
	await _count(id, 2)
	var run := await _count(id, FRAMES)
	assert_int(_expect_once(run, "paused")).is_equal(0)


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
