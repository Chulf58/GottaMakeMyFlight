extends GdUnitTestSuite
## A worn backpack clears the wearer's buttocks and thighs through the walk's
## stride (board 0dd2c787 item a): the basic scanner probe found the left
## buttock (vertices skinned to Quad.L) inside the bottom of a one-bag pack's
## back panel (drawn at scale 1.0) on bodies 9 and 11 (tcp_female_character_05
## and _11). worn_back_sweep_probe.gd set CarryWorn.BACK_ON_SPINE_M from the
## torso alone and leaves out every vertex owned by a leg bone, so it never saw
## them. Each body is posed in its walk and idle clips at MOMENTS points and
## skinned by hand (every skinned mesh, as the probe samples them); the pack is
## placed by CarryWorn.worn_back() on its Spine_03 bone, as drawn, one bag and
## two (SecurityLooks.TWO_BAG_SCALE). Leg points must stay LEG_CLEAR_M out of
## the pack's box, torso points out of the box itself, and the panel must still
## rest on the back (its least torso gap at most WORN_GAP_M on every moment).

const MOMENTS := 32
const CLIPS: Array[String] = ["walk", "idle"]
## The stride clearance asked of the legs (1 cm).
const LEG_CLEAR_M := 0.01
## The resting limit of the worn-backpack float check (spike/worn_back_gap.gd).
const WORN_GAP_M := 0.03
const BODIES_CHECKED: Array[int] = [9, 11]
const LEGS: Array[String] = ["Quad", "Shin", "Foot", "Toes", "Knee", "Thigh"]
const ARMS: Array[String] = [
	"Arm", "Forearm", "Hand", "Fingers", "Fingertips", "Thumb", "Thumb_Tip"
]


## Bodies 9 and 11 with one bag and two: no leg vertex within LEG_CLEAR_M of
## the pack, no torso vertex in it, and the panel resting on the back.
func test_worn_pack_clears_the_stride_of_bodies_9_and_11() -> void:
	var legs_in := 0
	var torso_in := 0
	var worst_rest := 0.0
	for run in BODIES_CHECKED.size() * 2:
		var b := BODIES_CHECKED[run / 2]
		var scale_by := 1.0 if run % 2 == 0 else SecurityLooks.TWO_BAG_SCALE
		var got := _measure(b, scale_by)
		print(
			(
				(
					"body %d %s scale %.2f: leg points within %.2f m %d (least leg gap %.4f m at %s),"
					+ " torso points inside %d, panel rest gap at most %.4f m (<= %.2f)"
				)
				% [
					b,
					PassengerLooks.BODIES[b],
					scale_by,
					LEG_CLEAR_M,
					got["legs_in"],
					got["leg_gap"],
					got["leg_at"],
					got["torso_in"],
					got["rest"],
					WORN_GAP_M
				]
			)
		)
		print(
			(
				(
					"  sampled %d moments (%d each clip), %d with no leg or torso point or no rest gap;"
					+ " fewest leg points %d, fewest torso points %d"
				)
				% [got["moments"], MOMENTS, got["empty"], got["least_legs"], got["least_torso"]]
			)
		)
		assert_int(got["moments"]).is_equal(MOMENTS * CLIPS.size())
		assert_int(got["empty"]).is_equal(0)
		assert_int(got["least_legs"]).is_greater(0)
		assert_int(got["least_torso"]).is_greater(0)
		assert_bool(is_finite(got["leg_gap"])).is_true()
		legs_in += got["legs_in"]
		torso_in += got["torso_in"]
		worst_rest = maxf(worst_rest, got["rest"])
	assert_int(legs_in).is_equal(0)
	assert_int(torso_in).is_equal(0)
	assert_float(worst_rest).is_less_equal(WORN_GAP_M)


## Body `b`'s pack at `scale_by` over its walk and idle moments: leg points
## within LEG_CLEAR_M of the pack's box ("legs_in"), the least distance of a
## leg point to the box ("leg_gap", negative inside) and its clip moment,
## torso points inside the box ("torso_in"), and the largest of each moment's
## least torso gap behind the panel inside its outline ("rest").
func _measure(b: int, scale_by: float) -> Dictionary:
	var out := {
		"legs_in": 0,
		"torso_in": 0,
		"leg_gap": INF,
		"leg_at": "",
		"rest": 0.0,
		"moments": 0,
		"empty": 0,
		"least_legs": 1 << 30,
		"least_torso": 1 << 30,
	}
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.BACKPACK)
	var grown := box.grow(LEG_CLEAR_M / scale_by)
	var node := PassengerLooks.SCENES[b].instantiate() as Node3D
	add_child(node)
	var player := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in CLIPS:
		player.play(clip)
		for n in MOMENTS:
			player.seek(player.current_animation_length * n / MOMENTS, true)
			var sampled := _sample(node)
			var points: PackedVector3Array = sampled[0]
			var owners: PackedInt32Array = sampled[1]
			var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var bone := skeleton.find_bone(CarryOnProps.SPINE_BONE)
			# In the node's frame, as _sample() gives the points.
			var spine := (
				node.global_transform.affine_inverse()
				* skeleton.global_transform
				* skeleton.get_bone_global_pose(bone)
			)
			var xf := CarryWorn.worn_back(spine, 0.0, scale_by, b)
			var to_bag := xf.affine_inverse()
			var rest := INF
			var legs := 0
			var torso := 0
			for k in points.size():
				var local := to_bag * points[k]
				legs += int(owners[k] == 1)
				torso += int(owners[k] == 0)
				match owners[k]:
					1:
						var gap := _box_gap(box, local) * scale_by
						if gap < out["leg_gap"]:
							out["leg_gap"] = gap
							out["leg_at"] = "%s %d/%d" % [clip, n, MOMENTS]
						out["legs_in"] += int(grown.has_point(local))
					0:
						out["torso_in"] += int(box.has_point(local))
						var inside := (
							local.x >= box.position.x
							and local.x <= box.end.x
							and local.z >= box.position.z
							and local.z <= box.end.z
							and local.y <= box.end.y
						)
						if inside:
							rest = minf(rest, (box.position.y - local.y) * scale_by)
			# The control: every moment sampled leg and torso points, and some
			# torso points lay behind the panel inside its outline (a finite rest
			# gap); a body whose skin was not found would pass empty otherwise.
			out["moments"] += 1
			out["empty"] += int(legs == 0 or torso == 0 or rest == INF)
			out["least_legs"] = mini(out["least_legs"], legs)
			out["least_torso"] = mini(out["least_torso"], torso)
			if rest < INF:
				out["rest"] = maxf(out["rest"], rest)
	node.free()
	return out


## The signed distance from `at` (the bag's frame) to `box`: positive outside,
## negative inside (the least way out).
static func _box_gap(box: AABB, at: Vector3) -> float:
	var out := (box.position - at).max(at - box.end)
	if out.x > 0.0 or out.y > 0.0 or out.z > 0.0:
		return out.max(Vector3.ZERO).length()
	return maxf(out.x, maxf(out.y, out.z))


## Every skinned mesh of `node` (the body and any other piece drawn with it,
## as the crossing probe samples them, CarryContact.body_points()), skinned by
## hand in `node`'s frame: [points, and per point 1 when its main bone is a leg
## bone, 2 an arm bone, 0 the torso and head].
static func _sample(node: Node3D) -> Array:
	var points := PackedVector3Array()
	var owners := PackedInt32Array()
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var skeleton := mi.get_node(mi.skeleton) as Skeleton3D
		var to_node := node.global_transform.affine_inverse() * skeleton.global_transform
		var mats: Array[Transform3D] = []
		var kind := {}
		for bind in mi.skin.get_bind_count():
			var name := mi.skin.get_bind_name(bind)
			var bone := skeleton.find_bone(name) if name != "" else mi.skin.get_bind_bone(bind)
			mats.append(to_node * skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind))
			var part := skeleton.get_bone_name(bone).get_slice(".", 0)
			kind[bind] = 1 if part in LEGS else (2 if part in ARMS else 0)
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
				points.append(v)
				owners.append(kind[bones[k * per + top]])
	return [points, owners]
