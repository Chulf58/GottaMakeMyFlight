class_name TestAirsidePropsBridgeSlide
extends GdUnitTestSuite
## Regression test for jet_bridge.glb slide wall and baseboard continuity:
## folded 03a hides Walk_Slide/Cab_Yaw for apron walk, and 04a 1.78 m slide
## keeps Walk_Slide_Mesh continuous inside Vest_Full without an apron_in cutout.

const BRIDGE_SCENE := preload("res://assets/airside/props/jet_bridge.glb")


func test_jet_bridge_baseboard_and_stair_wall_stay_continuous_at_04a_slide() -> void:
	var bridge: Node3D = BRIDGE_SCENE.instantiate()
	add_child(bridge)
	var joints := JetBridgePose.joints_of(bridge)
	var stand := StandPlacement.make(1, 20.0, -230.0)
	# Small 03a folds the bridge back so apron_walk has zero cab overhead.
	var pose_03 := JetBridgePose.pose_for(stand, "tp_plane_03a", true, 0.0)
	assert_bool(pose_03["folded"]).is_true()
	assert_bool((pose_03["apron_walk"] as PackedVector3Array).is_empty()).is_false()
	JetBridgePose.apply(joints, pose_03["pose"], true)
	(
		assert_bool((bridge.find_child("Fold_Cap", true, false) as Node3D).is_visible_in_tree())
		. is_true()
	)
	(
		assert_bool((bridge.find_child("Cab_Yaw", true, false) as Node3D).is_visible_in_tree())
		. is_false()
	)
	(
		assert_bool((bridge.find_child("Walk_Slide", true, false) as Node3D).is_visible_in_tree())
		. is_false()
	)
	# Medium 04a/05a dock inside the bridge with continuous stair wall & baseboard.
	var pose_04: Dictionary = JetBridgePose.pose_for(stand, "tp_plane_04a", true, 0.0)["pose"]
	JetBridgePose.apply(joints, pose_04, false)
	var slide_mesh := bridge.find_child("Walk_Slide_Mesh", true, false) as MeshInstance3D
	var inv := bridge.global_transform.affine_inverse()
	var west_low_min_z := INF
	var west_band_min_z := INF
	var spans_old_doorway := false
	var faces := slide_mesh.mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var z_min_tri := INF
		var z_max_tri := -INF
		var west_mid := false
		for k in 3:
			var root_pt := inv * (slide_mesh.global_transform * faces[i + k])
			z_min_tri = minf(z_min_tri, root_pt.z)
			z_max_tri = maxf(z_max_tri, root_pt.z)
			if root_pt.x > 0.99 and root_pt.y < 0.15:
				west_band_min_z = minf(west_band_min_z, root_pt.z)
			if root_pt.x > 0.90 and root_pt.y > 0.20 and root_pt.y < 1.50:
				west_low_min_z = minf(west_low_min_z, root_pt.z)
			if root_pt.x > 0.90 and root_pt.y > 0.30 and root_pt.y < 1.10:
				west_mid = true
		if west_mid and z_min_tri <= 2.85 and z_max_tri >= 2.85:
			spans_old_doorway = true
	bridge.free()
	print(
		(
			"04a slide=%.2f west_band_min_z=%.3f west_low_min_z=%.3f spans_old_doorway=%s"
			% [pose_04["slide"], west_band_min_z, west_low_min_z, spans_old_doorway]
		)
	)
	# Baseboard and wall start inside Vest_Full (<= VEST_END 2.30 m) and span old apron_in doorway.
	assert_float(west_band_min_z).is_less_equal(JetBridgePose.VEST_END + 0.001)
	assert_float(west_low_min_z).is_less_equal(JetBridgePose.VEST_END + 0.001)
	assert_bool(spans_old_doorway).is_true()
