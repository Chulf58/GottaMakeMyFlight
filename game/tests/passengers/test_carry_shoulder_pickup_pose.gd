class_name TestCarryShoulderPickupPose
extends GdUnitTestSuite
## F1 (board 74e713be): during hand-led floor>shoulder and tray>shoulder moves,
## CarryArmPose keeps the worn chest-strap pose (Arm.STRAP) off until CarryLead
## places the bag on the shoulder, preventing premature chest-strap elbow bend
## from twisting the reaching arm/wrist or pulling the bag into the body, while
## keeping the settled k = 1.0 worn pose and shoulder>floor / shoulder>tray
## put-downs.

const CarryContact := preload("res://spike/carry_contact.gd")
const CarryChecks := preload("res://spike/carry_probe_checks.gd")
const CHECKED_BONES: Array[String] = [
	"Arm", "Forearm", "Quad", "Shin", "Hips", "Spine_01", "Spine_02", "Spine_03"
]

var _world: SecurityTestWorld
var _views: PassengerViews
var _subject: Passenger
var _bag_idx := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_free()


func _free() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.world.free_all()
		_world = null
	_subject = null


static func _build_skin_surfaces(body: Node3D, skeleton: Skeleton3D) -> Array:
	var surfaces := []
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null:
			continue
		var bind_bones := PackedInt32Array()
		var bind_poses: Array[Transform3D] = []
		var bone_names := PackedStringArray()
		var keep_bind := PackedByteArray()
		for bind in mi.skin.get_bind_count():
			var bname := mi.skin.get_bind_name(bind)
			var bid := skeleton.find_bone(bname) if bname != "" else mi.skin.get_bind_bone(bind)
			var full := skeleton.get_bone_name(bid)
			bind_bones.append(bid)
			bind_poses.append(mi.skin.get_bind_pose(bind))
			bone_names.append(full)
			keep_bind.append(1 if full.get_slice(".", 0) in CHECKED_BONES else 0)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			var kept_verts := PackedVector3Array()
			var kept_bones := PackedInt32Array()
			var kept_weights := PackedFloat32Array()
			var dom_binds := PackedInt32Array()
			for k in verts.size():
				var top := 0
				for j in range(1, per):
					if weights[k * per + j] > weights[k * per + top]:
						top = j
				var db := bones[k * per + top]
				if keep_bind[db] == 0:
					continue
				kept_verts.append(verts[k])
				dom_binds.append(db)
				for j in per:
					kept_bones.append(bones[k * per + j])
					kept_weights.append(weights[k * per + j])
			surfaces.append(
				[
					bind_bones,
					bind_poses,
					bone_names,
					kept_verts,
					kept_bones,
					kept_weights,
					per,
					dom_binds
				]
			)
	return surfaces


static func _bag_hits(
	skeleton: Skeleton3D, surfaces: Array, gripping: Array, bag: Node3D
) -> Dictionary:
	var skip := {}
	for side in gripping:
		for prefix in CarryContact.HAND_CHAIN:
			var id := skeleton.find_bone(prefix + str(side))
			if id >= 0:
				skip[id] = true
	var meshes := []
	var bag_world := AABB()
	var first := true
	for mi: MeshInstance3D in bag.find_children("*", "MeshInstance3D", true, false):
		var wb := mi.global_transform * mi.get_aabb()
		bag_world = wb if first else bag_world.merge(wb)
		first = false
		meshes.append(
			[
				mi.name,
				mi.global_transform.affine_inverse(),
				mi.mesh.get_faces(),
				mi.get_aabb().grow(0.001)
			]
		)
	bag_world = bag_world.grow(0.01)
	var hits := {}
	var skel_xf := skeleton.global_transform
	for surf: Array in surfaces:
		var bind_bones: PackedInt32Array = surf[0]
		var bind_poses: Array[Transform3D] = surf[1]
		var bone_names: PackedStringArray = surf[2]
		var verts: PackedVector3Array = surf[3]
		var bones: PackedInt32Array = surf[4]
		var weights: PackedFloat32Array = surf[5]
		var per: int = surf[6]
		var dom_binds: PackedInt32Array = surf[7]
		var mats: Array[Transform3D] = []
		for b in bind_bones.size():
			mats.append(skel_xf * skeleton.get_bone_global_pose(bind_bones[b]) * bind_poses[b])
		for k in verts.size():
			var db := dom_binds[k]
			if skip.has(bind_bones[db]):
				continue
			var v := Vector3.ZERO
			for j in per:
				var w := weights[k * per + j]
				if w > 0.0:
					v += (mats[bones[k * per + j]] * verts[k]) * w
			if not bag_world.has_point(v):
				continue
			for m: Array in meshes:
				var lp: Vector3 = (m[1] as Transform3D) * v
				if (m[3] as AABB).has_point(lp) and CarryContact._odd(lp, m[2]):
					var key := "%s@%s" % [bone_names[db], m[0]]
					hits[key] = int(hits.get(key, 0)) + 1
					break
	return hits


func test_strap_weight_waits_for_hand_led_carry_and_preserves_ends() -> void:
	for from_home in [SecurityLooks.Home.FLOOR, SecurityLooks.Home.TRAY]:
		var pickup := {
			"was": from_home * 4,
			"home": SecurityLooks.Home.HAND * 4,
			"carry": SecurityLooks.Carry.SHOULDER,
			"carry_from": SecurityLooks.Carry.SHOULDER,
			"since": 10.0,
			"led": true,
		}
		for k in [0.0, 0.25, 0.34, 0.50, 0.55, 0.75]:
			var now: float = 10.0 + k * CarryOnProps.TRANSFER_TICKS
			(
				assert_float(CarryArmPose.strap_weight(pickup, SecurityLooks.Home.HAND, k, now))
				. is_equal(0.0)
			)
		var late := CarryArmPose.strap_weight(
			pickup, SecurityLooks.Home.HAND, 0.88, 10.0 + 0.88 * CarryOnProps.TRANSFER_TICKS
		)
		assert_float(late).is_between(0.4, 0.6)
		(
			assert_float(
				CarryArmPose.strap_weight(
					pickup, SecurityLooks.Home.HAND, 1.0, 10.0 + CarryOnProps.TRANSFER_TICKS
				)
			)
			. is_equal(1.0)
		)

	for to_home in [SecurityLooks.Home.FLOOR, SecurityLooks.Home.TRAY]:
		var putdown := {
			"was": SecurityLooks.Home.HAND * 4,
			"home": to_home * 4,
			"carry": SecurityLooks.Carry.SHOULDER,
			"carry_from": SecurityLooks.Carry.SHOULDER,
			"since": 20.0,
			"led": true,
		}
		assert_float(CarryArmPose.strap_weight(putdown, to_home, 0.0, 20.0)).is_equal(1.0)
		var reach_mid := CarryArmPose.strap_weight(
			putdown, to_home, 0.125, 20.0 + 0.125 * CarryOnProps.TRANSFER_TICKS
		)
		assert_float(reach_mid).is_equal_approx(0.5, 0.01)
		for k in [0.25, 0.50, 0.75, 1.0]:
			var now: float = 20.0 + k * CarryOnProps.TRANSFER_TICKS
			assert_float(CarryArmPose.strap_weight(putdown, to_home, k, now)).is_equal(0.0)

	var interrupted := {
		"was": SecurityLooks.Home.HAND * 4,
		"home": SecurityLooks.Home.FLOOR * 4,
		"carry": SecurityLooks.Carry.SHOULDER,
		"carry_from": SecurityLooks.Carry.SHOULDER,
		"from_holder": 0,
		"since": 30.0,
		"led": true,
	}
	(
		assert_float(CarryArmPose.strap_weight(interrupted, SecurityLooks.Home.FLOOR, 0.05, 30.3))
		. is_equal(0.0)
	)


## Full rig check over floor>shoulder, tray>shoulder, shoulder>floor and
## shoulder>tray on male and female skeletons: during k = 0.25..0.55 the
## reaching arm tracks CarryLead's Strap_Top grip with zero premature Arm.STRAP
## forearm/hand twist, settles to the worn strap pose at k = 1.0, and eases off
## cleanly on put-downs.
func test_mid_pickup_reach_tracks_bag_grip_without_premature_strap_twist() -> void:
	var props := auto_free(CarryOnProps.new()) as CarryOnProps
	add_child(props)
	for body_idx: int in [0, 10]:
		var body := auto_free(PassengerLooks.SCENES[body_idx].instantiate()) as Node3D
		body.set_meta(&"body", body_idx)
		body.set_meta(&"clip", "walk")
		var fade := auto_free(ClipCrossfade.new()) as ClipCrossfade
		body.set_meta(&"crossfade", fade)
		add_child(body)
		var player := body.get_node("AnimationPlayer") as AnimationPlayer
		player.speed_scale = 0.0
		player.play("walk")
		player.seek(0.2, true)
		var rig := props._rig(body)
		var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		await skeleton.skeleton_updated
		var forearm_id := skeleton.find_bone("Forearm.R")
		var hand_id := skeleton.find_bone("Hand.R")
		var starts := [
			[
				SecurityLooks.Home.FLOOR,
				Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-0.2, 0.0, 0.5))
			],
			[
				SecurityLooks.Home.TRAY,
				Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-0.55, 0.78, -0.2))
			],
		]
		for entry: Array in starts:
			var from_home: int = entry[0]
			var start_xf: Transform3D = entry[1]
			var tote := (
				auto_free(
					InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.SHOULDER])
				)
				as Node3D
			)
			add_child(tote)
			tote.global_transform = start_xf
			var bag := {
				"node": tote,
				"kind": SecurityLooks.Kind.SHOULDER,
				"carry": SecurityLooks.Carry.SHOULDER,
				"carry_from": SecurityLooks.Carry.SHOULDER,
				"was": from_home * 4,
				"home": SecurityLooks.Home.HAND * 4,
				"place": SecurityLooks.Home.HAND * 4,
				"from": start_xf,
				"from_world": start_xf,
				"since": 10.0,
				"reach_from": CarryOnProps.REACH_BUILT_M,
				"led": true,
			}
			var held := {
				"bags": [bag],
				"homes": [SecurityLooks.Home.HAND],
				"hands": [0],
				"scale": 1.0,
				"weight": 0.0,
				"tuck_weight": 0.0,
				"floor": [start_xf],
				"floor_at": [null],
			}
			for k: float in [0.25, 0.34, 0.50, 0.55]:
				var now := 10.0 + k * CarryOnProps.TRANSFER_TICKS
				player.seek(0.0, true)
				player.seek(0.2, true)
				held.erase("arm_key")
				CarryPlace.place_bags(
					props, held, body, start_xf, now, CarryOnProps.Placing.NOT_HAND
				)
				CarryArmPose.lead_arms(props, held, body, now)
				CarryArmPose.pose_arms(props, held, body, now)
				await skeleton.skeleton_updated
				CarryPlace.place_bags(props, held, body, start_xf, now, CarryOnProps.Placing.HAND)
				var arm := rig["arms"][0] as CarryArm
				assert_float(arm.front_weight).is_equal(0.0)
				(
					assert_bool(
						is_equal_approx(arm.front_up_degrees, CarryArmPose.STRAP_HAND_UP_DEGREES)
					)
					. is_false()
				)
				var top := CarryOnProps._in_piece(props._part(tote, "Strap_Top"), tote).origin
				(
					assert_float(props.grip_of(body, 0).distance_to(tote.global_transform * top))
					. is_less(0.001)
				)
				var fixed_fore := (
					skeleton.get_bone_global_pose(forearm_id).basis.get_rotation_quaternion()
				)
				var fixed_hand := (
					skeleton.get_bone_global_pose(hand_id).basis.get_rotation_quaternion()
				)

				player.seek(0.0, true)
				player.seek(0.2, true)
				arm.front_weight = 0.0
				await skeleton.skeleton_updated
				var pure_fore := (
					skeleton.get_bone_global_pose(forearm_id).basis.get_rotation_quaternion()
				)
				var pure_hand := (
					skeleton.get_bone_global_pose(hand_id).basis.get_rotation_quaternion()
				)

				player.seek(0.0, true)
				player.seek(0.2, true)
				arm.front_upper_degrees = 0.0
				arm.front_up_degrees = CarryArmPose.STRAP_HAND_UP_DEGREES
				arm.front_half_width = CarryArmPose.STRAP_HAND_M
				arm.front_weight = clampf(k / 0.6, 0.0, 1.0)
				await skeleton.skeleton_updated
				var old_hand := (
					skeleton.get_bone_global_pose(hand_id).basis.get_rotation_quaternion()
				)

				assert_bool(fixed_fore.is_equal_approx(pure_fore)).is_true()
				assert_bool(fixed_hand.is_equal_approx(pure_hand)).is_true()
				assert_float(rad_to_deg(old_hand.angle_to(pure_hand))).is_greater(2.0)

			var settled_now := 10.0 + CarryOnProps.TRANSFER_TICKS
			held.erase("arm_key")
			CarryPlace.place_bags(
				props, held, body, start_xf, settled_now, CarryOnProps.Placing.HAND
			)
			CarryArmPose.lead_arms(props, held, body, settled_now)
			CarryArmPose.pose_arms(props, held, body, settled_now)
			var settled_arm := rig["arms"][0] as CarryArm
			assert_bool(settled_arm.active).is_true()
			assert_bool(settled_arm.holds).is_false()
			assert_float(settled_arm.front_weight).is_equal(1.0)
			assert_float(settled_arm.front_half_width).is_equal(CarryArmPose.STRAP_HAND_M)
			assert_float(settled_arm.front_up_degrees).is_equal(CarryArmPose.STRAP_HAND_UP_DEGREES)

			# Put-down (shoulder>floor and shoulder>tray): starts in the worn
			# strap pose at k = 0.0, eases off over the reach, and ends free.
			var worn_xf := tote.global_transform
			var bar := CarryOnProps._in_piece(props._part(tote, "Strap_Top"), tote).origin
			bag["was"] = SecurityLooks.Home.HAND * 4
			bag["home"] = from_home * 4
			bag["place"] = from_home * 4
			bag["since"] = 20.0
			held["homes"] = [from_home]
			for k_down: float in [0.0, 0.30, 0.55, 1.0]:
				var down_now := 20.0 + k_down * CarryOnProps.TRANSFER_TICKS
				if k_down < 1.0:
					bag["lead"] = (
						CarryLead
						. plan(
							bag,
							k_down,
							worn_xf,
							start_xf,
							body.global_transform,
							{
								"hand": 0,
								"yaw": 0.0,
								"to_floor": from_home == SecurityLooks.Home.FLOOR
							},
							{
								"hand": 0,
								"grips": [props.grip_of(body, 0), props.grip_of(body, 1)],
								"shoulders_y": [1.4, 1.4],
								"bar_z": 0.0,
								"scale": 1.0,
								"strap_top": bar,
							}
						)
					)
				else:
					bag.erase("lead")
				held.erase("arm_key")
				CarryArmPose.lead_arms(props, held, body, down_now)
				CarryArmPose.pose_arms(props, held, body, down_now)
				if is_equal_approx(k_down, 0.0):
					assert_float(settled_arm.front_weight).is_equal(1.0)
					assert_float(settled_arm.front_up_degrees).is_equal(
						CarryArmPose.STRAP_HAND_UP_DEGREES
					)
				else:
					assert_float(settled_arm.front_weight).is_equal(0.0)
			assert_bool(settled_arm.active).is_false()
		await get_tree().process_frame


func _run_shoulder_pickup(
	use_lane: bool,
	mirror: int,
	body_idx: int,
	liquids: bool,
	alarm: bool,
	late: bool,
	wait_phase: SecurityRuntime.Phase,
	wait_stage: Passenger.Stage,
	opts := {}
) -> Dictionary:
	var clip_start: float = opts.get("clip_start", 0.0)
	var bag_count: int = opts.get("bag_count", 1)
	var bag_slot: int = opts.get("bag_slot", 0)
	_free()
	_world = SecurityTestWorld.make(use_lane, 7, mirror)
	_views = PassengerTestWorld.views()
	_views.clock = _world.world.clock
	_views.sim = _world.world.sim
	add_child(_views)
	var variant := PassengerLooks.variant_of(body_idx)
	for i in 400:
		var p := _world.world.passenger(_world.send(bag_count, liquids, alarm))
		if (
			PassengerLooks.body_of(p.id, variant) == body_idx
			and SecurityLooks.bag_kind(p, bag_slot) == SecurityLooks.Kind.SHOULDER
		):
			p.variant = variant
			if late:
				p.late = true
			_subject = p
			_bag_idx = bag_slot
			break
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
	assert_object(_subject).is_not_null()
	while true:
		if late:
			_subject.late = true
		if wait_phase == SecurityRuntime.Phase.TO_BERTH:
			if (
				_subject.stage == Passenger.Stage.SECURITY
				and _subject.security_phase == SecurityRuntime.Phase.ARCH
				and (
					_subject.at
					== _world.world.sim.layout.security_lanes.lane(_world.station)["arch"]
				)
			):
				break
		elif wait_stage == Passenger.Stage.TO_GATE:
			if (
				_subject.stage == Passenger.Stage.SECURITY
				and _subject.security_phase == SecurityRuntime.Phase.REPACK
				and _subject.security_work <= 2
			):
				break
		elif _subject.stage == wait_stage and _subject.security_phase == wait_phase:
			break
		_world.world.step()
	var props := _views.carry_on_props()
	var sim := _world.world.sim
	await get_tree().process_frame
	var body := _views.node_for(_subject.id)
	assert_object(body).is_not_null()
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var surfaces := _build_skin_surfaces(body, skeleton)
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	player.speed_scale = 0.0
	if clip_start > 0.0 and player.current_animation != "":
		var init_len := maxf(player.current_animation_length, 0.001)
		player.seek(fposmod(clip_start, init_len), true)
	var side := SecurityLooks.worn_side(bag_slot)
	var frames := 0
	var hits_total := 0
	var mid_strap_on := false
	var settled_strap := -1.0
	var last_k := 0.0
	var min_mid_grip_z := INF
	var max_grip_gap := 0.0
	var in_pickup := false
	var step_ticks := 0.25
	for step in 120:
		if late:
			_subject.late = true
		var seconds := SimClock.STEP * step_ticks
		_world.world.clock.advance(seconds)
		if player.current_animation != "":
			var len_s := maxf(player.current_animation_length, 0.001)
			player.seek(fposmod(player.current_animation_position + seconds, len_s), true)
		await skeleton.skeleton_updated
		var st := props.bag_state(_subject.id, bag_slot)
		if not st.has("home"):
			continue
		var home := int(st["home"]) / 4
		var k := props.transfer_progress(_subject.id, bag_slot)
		var arm := props._rig(body)["arms"][side] as CarryArm
		if not in_pickup:
			if home == SecurityLooks.Home.HAND and k < 1.0:
				in_pickup = true
			else:
				continue
		if home != SecurityLooks.Home.HAND:
			break
		last_k = k
		if k >= 1.0:
			settled_strap = arm.front_weight
			break
		frames += 1
		if (
			k >= 0.25
			and k <= 0.55
			and is_equal_approx(arm.front_up_degrees, CarryArmPose.STRAP_HAND_UP_DEGREES)
		):
			mid_strap_on = true
		if k >= 0.45 and k <= 0.55:
			var local_grip := body.global_transform.affine_inverse() * props.grip_of(body, side)
			min_mid_grip_z = minf(min_mid_grip_z, local_grip.z)
		var bag_node: Node3D = props.props_of(_subject.id)["bags"][bag_slot]
		if int(st.get("held_by", -1)) == side:
			var strap_top := (
				(bag_node.find_child("Strap_Top", true, false) as Node3D).global_position
			)
			max_grip_gap = maxf(max_grip_gap, strap_top.distance_to(props.grip_of(body, side)))
		var hits := _bag_hits(
			skeleton, surfaces, CarryChecks.gripping(sim, _subject, props), bag_node
		)
		if not hits.is_empty():
			print("HIT body=%d slot=%d k=%.2f hits=%s" % [body_idx, bag_slot, k, hits])
		for v: int in hits.values():
			hits_total += v
	await get_tree().process_frame
	return {
		"frames": frames,
		"hits": hits_total,
		"mid_strap_on": mid_strap_on,
		"settled_strap": settled_strap,
		"last_k": last_k,
		"min_mid_grip_z": min_mid_grip_z,
		"max_grip_gap": max_grip_gap,
	}


func test_lane_tray_to_shoulder_clears_body_through_pickup() -> void:
	for body_idx: int in [0, PassengerLooks.body_of(24, 0), PassengerLooks.body_of(24, 1)]:
		var got := await _run_shoulder_pickup(
			true,
			SecurityLanes.LEFT,
			body_idx,
			false,
			false,
			false,
			SecurityRuntime.Phase.PICKUP,
			Passenger.Stage.SECURITY
		)
		print("lane_left PICKUP body=%d got=%s" % [body_idx, got])
		assert_int(got["frames"]).is_greater_equal(15)
		assert_bool(got["mid_strap_on"]).is_false()
		assert_float(got["settled_strap"]).is_equal(1.0)
		assert_float(got["max_grip_gap"]).is_less_equal(0.03)
		assert_int(got["hits"]).is_equal(0)


func test_lane_to_berth_tray_to_shoulder_clears_body_and_avoids_backward_arm() -> void:
	# Reproduces lane p8 (male_10, liquids -> TO_BERTH) and p27 (female_03,
	# late runner + alarm -> TO_BERTH) walking away from the left tray.
	for spec: Array in [[8, true, false, false], [10, false, true, true]]:
		var got := await _run_shoulder_pickup(
			true,
			SecurityLanes.LEFT,
			spec[0],
			spec[1],
			spec[2],
			spec[3],
			SecurityRuntime.Phase.TO_BERTH,
			Passenger.Stage.SECURITY
		)
		print("lane_left TO_BERTH body=%d late=%s got=%s" % [spec[0], spec[3], got])
		assert_int(got["frames"]).is_greater_equal(15)
		if not bool(spec[3]):
			assert_float(got["settled_strap"]).is_equal(1.0)
		assert_float(got["max_grip_gap"]).is_less_equal(0.03)
		assert_float(got["min_mid_grip_z"]).is_greater_equal(0.05)
		assert_int(got["hits"]).is_equal(0)


func test_booth_repack_floor_to_shoulder_clears_stepping_thigh() -> void:
	# Reproduces booth p8 (1-bag male_10, floor>shoulder.R) and p9 (2-bag male_09,
	# floor>shoulder.L) across walk-clip phases, including forward thigh strides.
	for clip_start: float in [0.0, 0.35, 0.65]:
		var got := await _run_shoulder_pickup(
			false,
			SecurityLanes.RIGHT,
			8,
			true,
			false,
			false,
			SecurityRuntime.Phase.NONE,
			Passenger.Stage.TO_GATE,
			{"clip_start": clip_start}
		)
		print("booth REPACK exit 1-bag body=8 clip=%.2f got=%s" % [clip_start, got])
		assert_int(got["frames"]).is_greater_equal(15)
		assert_float(got["settled_strap"]).is_equal(1.0)
		assert_float(got["max_grip_gap"]).is_less_equal(0.03)
		assert_int(got["hits"]).is_equal(0)
	var two_bag := await _run_shoulder_pickup(
		false,
		SecurityLanes.RIGHT,
		5,
		true,
		false,
		false,
		SecurityRuntime.Phase.NONE,
		Passenger.Stage.TO_GATE,
		{"clip_start": 0.35, "bag_count": 2, "bag_slot": 1}
	)
	print("booth REPACK exit 2-bag body=5 got=%s" % [two_bag])
	assert_int(two_bag["frames"]).is_greater_equal(15)
	assert_float(two_bag["settled_strap"]).is_equal(1.0)
	assert_float(two_bag["max_grip_gap"]).is_less_equal(0.03)
	assert_int(two_bag["hits"]).is_equal(0)
