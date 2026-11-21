class_name TestPlaneFarShadow
extends GdUnitTestSuite
## Regression test for PlaneView.far_shadow: verifies FAR_SHADOW_LIFT stays
## cleanly above 0.20 m paving/runways and hides when faded out.


func test_far_shadow_lifts_above_paving_and_hides_when_faded_out() -> void:
	assert_float(PlaneView.FAR_SHADOW_LIFT).is_greater(0.20)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 20.0, 0.0)
	sun.directional_shadow_max_distance = 400.0
	sun.directional_shadow_fade_start = 0.8
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 20.0, 0.0), Vector3(0.0, 0.0, -500.0), Vector3.UP)
	cam.make_current()
	var view := PlaneView.new()
	view.sun = sun
	add_child(view)
	view.set_process(false)
	view.show_model("tp_plane_05a")
	# Far past shadow max distance at ground level: silhouette visible above 0.20 m paving.
	view.global_position = Vector3(0.0, 0.20, -450.0)
	view._place_far_shadow()
	assert_bool(view._far_shadow.visible).is_true()
	assert_float(view._far_shadow.global_position.y).is_greater(0.20)
	assert_float(view._far_shadow.global_position.y).is_greater_equal(
		PlaneView.FAR_SHADOW_LIFT - 0.001
	)
	assert_float(view.far_shadow_alpha()).is_greater(0.1)
	# Close to camera inside shadow range: fade == 0 -> silhouette hidden.
	view.global_position = Vector3(0.0, 5.0, -30.0)
	view._place_far_shadow()
	assert_float(view.far_shadow_alpha()).is_equal_approx(0.0, 1e-4)
	assert_bool(view._far_shadow.visible).is_false()
	view.free()
	cam.free()
	sun.free()
