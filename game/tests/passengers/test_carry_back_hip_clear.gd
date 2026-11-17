extends GdUnitTestSuite
## A backpack taken out of a lane tray onto the back clears the hips, the back
## and the legs while the hand carries it (board 606ae8a2): from the side hang
## onto the back CarryLead.plan() blended it straight, and the crossing probe
## (--lane, seed 1106001) found Hips and Quad.L in the pack at k 0.67. Pure
## geometry: each body is posed in its idle clip and skinned by hand (as
## test_worn_back_stride_clear does), never by the baked skin a headless count
## reads 0 from (anti-pattern 6d691dee); the pack is placed where the plan puts
## it, its worn end by CarryWorn.worn_back() on the body's own Spine_03. Arm
## points are left out: the hand holds the pack. The windowed crossing probe is
## the check on the drawn move.

## [tray x in the body's frame (the body faces +Z, its left is +X), the hand
## that should lead]: the table on either side of the walker.
const SIDES := [[0.6, 1], [-0.6, 0]]
## Moments of the move checked, k from 0 to 1.
const STEPS := 60
const ARMS: Array[String] = [
	"Arm", "Forearm", "Hand", "Fingers", "Fingertips", "Thumb", "Thumb_Tip"
]


## Every body, the tray on either side: no point of the body's torso, hips or
## legs inside the pack's box at any moment the hand holds it. Controls: the
## hand held the pack over the checked moments, every body sampled hip and
## thigh points, and the old straight blend from the side hang onto the back
## (worked out here) does put body points in the pack, so the check can see the
## hit it guards against.
func test_out_of_a_tray_onto_the_back_the_pack_clears_hips_and_legs() -> void:
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK)
	var hits := 0
	var straight := 0
	var held := 0
	var named := {}
	for b in PassengerLooks.BODIES.size():
		var node := PassengerLooks.SCENES[b].instantiate() as Node3D
		add_child(node)
		var player := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.play("idle")
		player.seek(0.0, true)
		var sampled := _sample(node)
		var points: PackedVector3Array = sampled[0]
		var bones: PackedStringArray = sampled[1]
		assert_bool(bones.has("Hips")).is_true()
		assert_bool(bones.has("Quad.L") and bones.has("Quad.R")).is_true()
		var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var to_node := node.global_transform.affine_inverse() * skeleton.global_transform
		var spine := to_node * skeleton.get_bone_global_pose(skeleton.find_bone("Spine_03"))
		var want := CarryWorn.worn_back(spine, 0.0, 1.0, b)
		var shoulders := [
			(to_node * skeleton.get_bone_global_pose(skeleton.find_bone("Arm.R"))).origin.y,
			(to_node * skeleton.get_bone_global_pose(skeleton.find_bone("Arm.L"))).origin.y,
		]
		for side: Array in SIDES:
			var start := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(side[0], 0.8, 0.4))
			for n in STEPS + 1:
				var k := float(n) / STEPS
				var plan := _plan(k, start, want, shoulders)
				if plan["holder"] != side[1]:
					continue
				held += 1
				var in_pack := _inside(plan["xf"], box, points, bones)
				hits += in_pack.size()
				for bone: String in in_pack:
					named["%s at k %.2f" % [bone, k]] = true
			# The control: the straight blend from the side hang onto the back.
			var hang := CarryLead.back_side(
				Vector3.ZERO, 0.0, side[1], shoulders[side[1]] - CarryLead.BACK_HANG_BELOW_M, 1.0
			)
			for n in 21:
				var blended := hang.interpolate_with(want, smoothstep(0.0, 1.0, n / 20.0))
				straight += _inside(blended, box, points, bones).size()
		node.free()
	print(
		(
			"held moments %d, body points in the pack %d (%s); straight blend %d"
			% [held, hits, named.keys(), straight]
		)
	)
	assert_int(held).is_greater(PassengerLooks.BODIES.size() * SIDES.size() * STEPS / 3)
	assert_int(straight).is_greater(0)
	assert_int(hits).is_equal(0)


## The plan of a lone backpack's move out of a tray at `start` (the body's
## frame, the body at its origin facing +Z) onto the back at `want`, at `k`.
static func _plan(k: float, start: Transform3D, want: Transform3D, shoulders: Array) -> Dictionary:
	var frame := Transform3D()
	var bag := {
		"kind": SecurityLooks.Kind.BACKPACK,
		"home": SecurityLooks.Home.HAND * 4,
		"carry": SecurityLooks.Carry.BACK,
		"carry_from": SecurityLooks.Carry.BACK,
		"was": SecurityLooks.Home.TRAY * 4,
		"from": start,
		"start_body": frame,
	}
	var body := {
		"hand": 0,
		"grips": [Vector3(-0.2, 0.9, 0.05), Vector3(0.2, 0.9, 0.05)],
		"shoulders_y": shoulders,
		"bar_z": 0.0,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
	var flags := {
		"in_stall": false,
		"hand_carry": false,
		"from_floor": false,
		"to_floor": false,
		"hand": 0,
		"clear": CarryOnProps.TRANSFER_CLEAR_M,
		"yaw": 0.0,
	}
	return CarryLead.plan(bag, k, start, want, frame, flags, body)


## The bones of the `points` (each owned by the bone in `bones`) inside `box`
## (the pack's own frame) placed at `xf`, one entry a point.
static func _inside(
	xf: Transform3D, box: AABB, points: PackedVector3Array, bones: PackedStringArray
) -> Array:
	var to_bag := xf.affine_inverse()
	var out := []
	for i in points.size():
		if box.has_point(to_bag * points[i]):
			out.append(bones[i])
	return out


## Every skinned mesh point of `node` whose main bone is not an arm bone,
## skinned by hand in `node`'s frame: [points, and per point its main bone's
## name].
static func _sample(node: Node3D) -> Array:
	var points := PackedVector3Array()
	var names := PackedStringArray()
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var skeleton := mi.get_node(mi.skeleton) as Skeleton3D
		var to_node := node.global_transform.affine_inverse() * skeleton.global_transform
		var mats: Array[Transform3D] = []
		var owner_of: Array[String] = []
		for bind in mi.skin.get_bind_count():
			var name := mi.skin.get_bind_name(bind)
			var bone := skeleton.find_bone(name) if name != "" else mi.skin.get_bind_bone(bind)
			mats.append(to_node * skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind))
			owner_of.append(skeleton.get_bone_name(bone))
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			for k in verts.size():
				var v := Vector3.ZERO
				var top := 0
				for j in per:
					v += (mats[bones[k * per + j]] * verts[k]) * weights[k * per + j]
					if weights[k * per + j] > weights[k * per + top]:
						top = j
				var bone_name := owner_of[bones[k * per + top]]
				if bone_name.get_slice(".", 0) in ARMS:
					continue
				points.append(v)
				names.append(bone_name)
	return [points, names]
