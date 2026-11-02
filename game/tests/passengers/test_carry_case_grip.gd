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


## Every grip point of the case lies on its drawn body mesh (within 1 mm of one
## of its triangles, read here from the mesh, not through the check): the side
## carry's top edge on its handle face (the chamfer's edge, also
## CarryOnProps.grip_anchor()), the top of its handle and the middle and edge of
## its top end. Control: the corner of the mesh's bounds at that edge (the
## handle's height at the top end, the side carry's grip before 2026-11-02) is
## not on it.
func test_the_segment_ends_lie_on_the_cases_own_top() -> void:
	var id: int = await _case_in_front()
	assert_int(id).is_greater_equal(0)
	var props := _views.carry_on_props()
	var node: Node3D = props.bag_state(id, 0)["node"]
	var body := node.find_child("CarryOnBag_Body", true, false) as MeshInstance3D
	var to_case := node.global_transform.affine_inverse()
	var faces: Array[Vector3] = []
	for v: Vector3 in body.mesh.get_faces():
		faces.append(to_case * (body.global_transform * v))
	var own := FloatCheck.own_grips(props, id, 0)
	assert_int(own.size()).is_equal(4)
	for at: Vector3 in own:
		var local := to_case * at
		print("grip point %s on the mesh: %s" % [local, _on_mesh(faces, local)])
		assert_bool(_on_mesh(faces, local)).is_true()
	var edge := to_case * own[0]
	var box := body.get_aabb()
	var depth := CarryLead.STALL_CASE_DEPTH_M
	var cut := CarryLead.STALL_CASE_CHAMFER_M
	assert_vector(edge).is_equal_approx(Vector3(0.0, depth, box.end.z - cut), Vector3.ONE * 0.001)
	var anchor := CarryOnProps.grip_anchor(SecurityLooks.Kind.CASE)
	assert_vector(anchor).is_equal_approx(edge, Vector3.ONE * 0.001)
	var corner := Vector3(0.0, box.end.y, box.end.z)
	print("bounds corner %s on the mesh: %s" % [corner, _on_mesh(faces, corner)])
	assert_bool(_on_mesh(faces, corner)).is_false()


## Whether `at` is within 1 mm of one of the triangles `faces` (three points
## each): inside one, off its plane by no more, or that near one of its edges.
func _on_mesh(faces: Array[Vector3], at: Vector3) -> bool:
	for t in range(0, faces.size(), 3):
		var tri: Array[Vector3] = [faces[t], faces[t + 1], faces[t + 2]]
		for e in 3:
			var near := Geometry3D.get_closest_point_to_segment(at, tri[e], tri[(e + 1) % 3])
			if near.distance_to(at) < 0.001:
				return true
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).length() < 0.0000001:
			continue
		var plane := Plane(tri[0], tri[1], tri[2])
		var bary := Geometry3D.get_triangle_barycentric_coords(
			plane.project(at), tri[0], tri[1], tri[2]
		)
		if (
			bary.x >= 0.0
			and bary.y >= 0.0
			and bary.z >= 0.0
			and absf(plane.distance_to(at)) < 0.001
		):
			return true
	return false
