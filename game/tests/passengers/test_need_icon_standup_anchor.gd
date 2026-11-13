class_name TestNeedIconStandupAnchor
extends GdUnitTestSuite
## While a passenger stands up from a gate chair, its icon anchor and head top
## (NeedIcons.head_anchor, head_top, board 3a5e1d0d) rise with the drawn body:
## the seated value at the clip's start, halfway at its middle, the standing
## value at its end, and over the real Head bone throughout. Measured on the
## real PassengerViews: the stage is set by hand and snap() starts the
## stand_up clip where the sim is in it, as a load does (no crossfade).

## Ticks into the stand-up (PassengerSim.STAND_UP_TICKS is the whole clip).
const START := 0
const MIDDLE := 12
const END := 24
## The anchor stands at least this far over the Head bone, and at most
## SIDE_M from over it across the ground (the bone measured 1.28 m up and
## 0.55 m behind the root seated, 1.68 m up and 0.06 m behind standing).
const OVER_M := 0.25
const SIDE_M := 0.15
## head_top() stays this close to the bone's top (the bone plus HEAD_UP_M).
const HEAD_UP_M := 0.12
const TOP_NEAR_M := 0.15

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


## A passenger on the first gate chair of the reference terminal (as the sim
## seats one), the views drawing.
func _sitter() -> Passenger:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.cleared = true
	var seat: Dictionary = _world.sim.layout.seats[0]
	p.seat_object = seat["object_id"]
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.stage = Passenger.Stage.SEATED
	p.stage_tick = _world.sim.tick
	_views.sync()
	return p


## The passenger frozen `ticks` into its stand-up.
func _rising(p: Passenger, ticks: int) -> Node3D:
	p.stage = Passenger.Stage.STANDING_UP
	p.stage_tick = _world.sim.tick - ticks
	_views.snap()
	return _views.node_for(p.id)


## The Head bone in the node's space.
func _head(node: Node3D) -> Vector3:
	var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).to_lower().contains("head"):
			var at := skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
			return node.global_transform.affine_inverse() * at
	return Vector3.INF


## Whether `anchor` stands over `head`: OVER_M or more above it and within
## SIDE_M of it across the ground.
func _over(anchor: Vector3, head: Vector3) -> bool:
	var side := Vector2(anchor.x - head.x, anchor.z - head.z).length()
	return anchor.y - head.y >= OVER_M and side <= SIDE_M


func test_the_anchor_rises_with_the_head_through_the_stand_up() -> void:
	var p := _sitter()
	var standing := Vector3(0.0, NeedIcons.LIFT_M, 0.0)
	var seated := Vector3(0.0, NeedIcons.SEATED_LIFT_M, -NeedIcons.SEATED_BACK_M)
	var want := {START: seated, MIDDLE: seated.lerp(standing, 0.5), END: standing}
	var heads := {}
	for ticks: int in want:
		var node := _rising(p, ticks)
		var tag := "ticks %d" % ticks
		# The clip is engaged at the sim's point in it (the control that the
		# anchor reads a real progress, not a default).
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		assert_str(player.assigned_animation).override_failure_message(tag).is_equal("stand_up")
		assert_int(node.get_meta(&"icon_rise", NeedIcons.Rise.NONE)).is_equal(NeedIcons.Rise.SEAT)
		assert_bool(node.get_meta(&"icon_seated", true)).is_false()
		var anchor := NeedIcons.head_anchor(node)
		assert_vector(anchor).override_failure_message(tag + " anchor %s" % anchor).is_equal_approx(
			want[ticks], Vector3.ONE * 0.02
		)
		var head := _head(node)
		heads[ticks] = head
		(
			assert_bool(_over(anchor, head))
			. override_failure_message("%s: anchor %s, head bone %s" % [tag, anchor, head])
			. is_true()
		)
		# The badges' head rect (head_top) follows the same head.
		var top := NeedIcons.head_top(node)
		var bone_top := head + Vector3.UP * HEAD_UP_M
		(
			assert_float(Vector2(top.y - bone_top.y, top.z - bone_top.z).length())
			. override_failure_message("%s: head_top %s, bone top %s" % [tag, top, bone_top])
			. is_less_equal(TOP_NEAR_M)
		)
	# The head really rose and came forward over the clip (the subject moved).
	assert_float((heads[END] as Vector3).y - (heads[START] as Vector3).y).is_greater(0.3)
	assert_float((heads[END] as Vector3).z - (heads[START] as Vector3).z).is_greater(0.4)


## The mutation control: the standing anchor taken at the stand-up's start (the
## old behaviour, icon_rise cleared by hand) fails the same over-the-head check.
func test_the_standing_anchor_at_the_start_is_not_over_the_head() -> void:
	var p := _sitter()
	var node := _rising(p, START)
	var head := _head(node)
	assert_bool(_over(NeedIcons.head_anchor(node), head)).is_true()
	node.set_meta(&"icon_rise", NeedIcons.Rise.NONE)
	var old := NeedIcons.head_anchor(node)
	assert_vector(old).is_equal(Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	assert_bool(_over(old, head)).override_failure_message("%s %s" % [old, head]).is_false()


## Walking off (the clip ended, the stage moved on) and a released node take
## the standing anchor and drop the rise.
func test_walking_off_and_a_released_node_drop_the_rise() -> void:
	var p := _sitter()
	var node := _rising(p, MIDDLE)
	assert_int(node.get_meta(&"icon_rise", NeedIcons.Rise.NONE)).is_equal(NeedIcons.Rise.SEAT)
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.sim.tick
	_views.sync()
	assert_int(node.get_meta(&"icon_rise", NeedIcons.Rise.SEAT)).is_equal(NeedIcons.Rise.NONE)
	assert_vector(NeedIcons.head_anchor(node)).is_equal(Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	node = _rising(p, MIDDLE)
	_views._release(p.id)
	assert_int(node.get_meta(&"icon_rise", NeedIcons.Rise.SEAT)).is_equal(NeedIcons.Rise.NONE)
