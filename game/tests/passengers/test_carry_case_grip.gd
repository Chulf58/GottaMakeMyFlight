class_name TestCarryCaseGrip
extends GdUnitTestSuite
## A hard case carried in front is on its grip when the hand is on its own
## handle (conductor ruling 2026-10-30: anywhere from its handle edge to the top
## of its handle, GRIP_ON_M plus the palm offset), measured from the case's drawn
## body mesh, never from CarryOnProps' placement (a check derived from the
## placement passes whatever the placement gets wrong:
## anti-pattern a-float-hand-gap-of-0-does-not-prove-a-carried-bag-is-grippe).
## Controls: the case was seen held in the front carry, and moved 10 cm off the
## hand (the hand staying put) the check reports it off.

const FloatCheck := preload("res://spike/carry_float_check.gd")
const DISPLACED_M := 0.10
## Alarm passengers sent so one of them carries a hard case (kind follows id).
const SENT := 10

var _world: SecurityTestWorld
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
		_world.world.free_all()
		_world = null


## Steps the lane (arch on (5, 6), a wall closing the corridor cell (4, 6)) until
## a hard case is held in the front carry; returns its passenger id.
func _case_in_front() -> int:
	_world = SecurityTestWorld.make(true)
	(
		assert_bool(
			(
				_world
				. world
				. sim
				. grid
				. apply(BuildEdit.place_wall(Vector2i(4, 6), BuildGrid.Side.WEST))
				. ok
			)
		)
		. is_true()
	)
	_views = PassengerViews.new()
	_views.clock = _world.world.clock
	_views.sim = _world.world.sim
	add_child(_views)
	var props := _views.carry_on_props()
	RenderingServer.frame_pre_draw.disconnect(props._unposed)
	var traits: Array = []
	for n in SENT:
		traits.append([1, false, true])
	var ids := _world.send_all(traits)
	for tick in 6000:
		_world.world.step()
		_views.draw()
		await get_tree().process_frame
		await get_tree().create_timer(0.0, true, false, true).timeout
		props._unposed()
		for id in ids:
			var p := _world.world.passenger(id)
			if SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.CASE:
				continue
			if props.bag_state(id, 0).get("held_by", -1) >= 0 and props.front_weight_of(id) >= 1.0:
				return id
	return -1


func test_a_front_carried_case_is_on_its_grip_and_a_displaced_one_is_not() -> void:
	var id: int = await _case_in_front()
	assert_int(id).is_greater_equal(0)
	var props := _views.carry_on_props()
	var body := _views.node_for(id)
	var node: Node3D = props.bag_state(id, 0)["node"]
	var on := FloatCheck.grip_on_gap(props, id, 0, body)
	print("front carry: grip gap %.4f m, limit %.4f m" % [on[0], on[1]])
	assert_float(on[0]).is_less_equal(on[1])
	# Control: the gap is a real distance, not a default (a case in hand reads
	# the palm offset FRONT_PALM_M, not 0).
	assert_float(on[0]).is_greater(0.0)
	# The case moved 10 cm down, off the hand (the hand stays put): over the limit.
	node.global_position += Vector3.DOWN * DISPLACED_M
	var off := FloatCheck.grip_on_gap(props, id, 0, body)
	print("displaced %.2f m: grip gap %.4f m, limit %.4f m" % [DISPLACED_M, off[0], off[1]])
	assert_float(off[0]).is_greater(off[1])


## Both ends of the segment lie on the drawn case: the top face, its handle
## edge and its middle (read here from the body mesh, not through the check).
func test_the_segment_ends_lie_on_the_cases_own_top() -> void:
	var id: int = await _case_in_front()
	assert_int(id).is_greater_equal(0)
	var props := _views.carry_on_props()
	var node: Node3D = props.bag_state(id, 0)["node"]
	var box := (node.find_child("CarryOnBag_Body", true, false) as MeshInstance3D).get_aabb()
	var own := FloatCheck.own_grips(props, id, 0)
	var edge := node.global_transform.affine_inverse() * own[0]
	var top := node.global_transform.affine_inverse() * own[1]
	assert_float(edge.y).is_equal_approx(box.end.y, 0.001)
	assert_float(edge.z).is_equal_approx(box.end.z, 0.001)
	assert_float(top.y).is_equal_approx(box.end.y, 0.001)
	assert_float(top.x).is_equal_approx(box.get_center().x, 0.001)
	assert_float(top.z).is_equal_approx(box.get_center().z, 0.001)
