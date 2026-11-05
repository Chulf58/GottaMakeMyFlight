class_name TestRollerStandClearance
extends GdUnitTestSuite
## A roller stood up in a queue (RollerPark.queue_park()) stands clear of its
## walker's own body, for every body type (board 03454587: a male file waiter
## had 4 of his body points inside his stood roller, which was drawn over his
## near leg). Geometric: each body's idle clip is posed at PHASES points of its
## length and skinned by hand here (a headless bake has no skin, anti-pattern
## a-headless-count-of-body-points-inside-a-carried-bag-reads-0), and no vertex
## may lie inside the roller shell's box (its meshes but the rods, grown by
## MARGIN_M) parked for either hand. The box holds the rounded shell, so it is
## the stricter test; the windowed BODY_IN_STOOD_BAG count (spike/
## roller_queue_probe.gd) is the drawn one.

const PHASES := 8
const MARGIN_M := 0.01

## Per body (PassengerLooks.BODIES): its idle poses, each the body's vertices
## in its own frame (facing +z).
var _poses: Array = []
## The roller shell's box in the roller's own frame (its rods left out).
var _shell := AABB()


func before() -> void:
	var roller := InteriorKit.instantiate("carry_roller")
	add_child(roller)
	var rods: Array = CarryOnProps.REACH_NODES[SecurityLooks.Kind.ROLLER]
	var first := true
	for mi: MeshInstance3D in roller.find_children("*", "MeshInstance3D", true, false):
		var in_rods := false
		var at: Node = mi
		while at != roller:
			in_rods = in_rods or at.name in rods
			at = at.get_parent()
		if in_rods or mi.mesh == null:
			continue
		var part := (
			roller.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		)
		_shell = part if first else _shell.merge(part)
		first = false
	roller.free()
	for b in PassengerLooks.BODIES.size():
		var node := PassengerLooks.SCENES[b].instantiate() as Node3D
		add_child(node)
		var player := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.play("idle")
		var poses: Array[PackedVector3Array] = []
		for n in PHASES:
			player.seek(player.current_animation_length * n / PHASES, true)
			poses.append(_skinned(node))
		_poses.append(poses)
		node.free()


## Every body type, either hand, one bag or two (TWO_BAG_SCALE): no vertex of
## the idle body inside the stood roller's shell box. Control: the same box
## parked on the body's centre line holds many of its vertices.
func test_a_stood_roller_clears_every_body() -> void:
	print("shell box %s, grown %.2f m" % [_shell, MARGIN_M])
	assert_float(_shell.size.x).is_greater(0.2)
	var hits := 0
	for b in _poses.size():
		var worst := [0, 0]
		var centred := 0
		for scale_by in [1.0, SecurityLooks.TWO_BAG_SCALE]:
			for hand in 2:
				var parked := RollerPark.queue_park(Transform3D.IDENTITY, hand, scale_by, b)
				for points: PackedVector3Array in _poses[b]:
					worst[hand] = maxi(worst[hand], _inside(points, parked, scale_by))
		var centre := RollerPark.park(Transform3D.IDENTITY, 0, 1.0, RollerPark.PARK_AHEAD_M, 0.0)
		centred = _inside(_poses[b][0], centre, 1.0)
		print(
			(
				"body %d %s: vertices inside the stood roller right %d left %d (0); centred %d (> 0)"
				% [b, PassengerLooks.BODIES[b], worst[0], worst[1], centred]
			)
		)
		hits += worst[0] + worst[1]
		assert_int(centred).is_greater(0)
	assert_int(hits).is_equal(0)


## The queue stand's spot is its own: the seat parks (pull>floor, floor>pull)
## keep PARK_SIDE_M (decisions e4e88745 and 211c0142 pin them).
func test_the_seat_park_keeps_its_spot() -> void:
	var seat := RollerPark.park(Transform3D.IDENTITY, 0, 1.0)
	var axle := seat * CarryOnProps.ROLLER_AXLE
	print("seat park axle %s, queue sides %s" % [axle, RollerPark.QUEUE_SIDE_M])
	assert_float(axle.x).is_equal_approx(-RollerPark.PARK_SIDE_M, 0.0001)
	assert_float(axle.z).is_equal_approx(RollerPark.PARK_AHEAD_M, 0.0001)
	for b in [0, PassengerLooks.PER_VARIANT]:
		var queue := RollerPark.queue_park(Transform3D.IDENTITY, 1, 1.0, b)
		assert_float((queue * CarryOnProps.ROLLER_AXLE).x).is_greater(RollerPark.PARK_SIDE_M)


## How many of `points` lie in the shell box of a roller drawn at `parked`.
func _inside(points: PackedVector3Array, parked: Transform3D, scale_by: float) -> int:
	var box := _shell.grow(MARGIN_M / scale_by)
	var to_bag := parked.affine_inverse()
	var count := 0
	for v in points:
		count += int(box.has_point(to_bag * v))
	return count


## The vertices of `node`'s body mesh in the pose its skeleton holds now,
## skinned by hand (linear blend), in `node`'s frame.
static func _skinned(node: Node3D) -> PackedVector3Array:
	var mi := PassengerLooks.body_mesh(node)
	var skeleton := mi.get_node(mi.skeleton) as Skeleton3D
	var to_node := node.global_transform.affine_inverse() * skeleton.global_transform
	var mats: Array[Transform3D] = []
	for bind in mi.skin.get_bind_count():
		var name := mi.skin.get_bind_name(bind)
		var bone := skeleton.find_bone(name) if name != "" else mi.skin.get_bind_bone(bind)
		mats.append(to_node * skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind))
	var out := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		for k in verts.size():
			var v := Vector3.ZERO
			for j in per:
				v += (mats[bones[k * per + j]] * verts[k]) * weights[k * per + j]
			out.append(v)
	return out
