class_name TestWorksPropsGrounding
extends GdUnitTestSuite
## Regression test verifying ti_excavator_1a.glb wheels sit grounded at y >= 0
## with zero wheel sinkage.


func test_ti_excavator_sits_grounded_without_wheel_sinkage() -> void:
	var exc: Node3D = load(TaxiwayWorks.DIR + "ti_excavator_1a.glb").instantiate()
	var exc_min_y := INF
	for mi: MeshInstance3D in exc.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != exc and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		exc_min_y = minf(exc_min_y, (xf * mi.get_aabb()).position.y)
	exc.free()
	assert_float(exc_min_y).is_greater_equal(-0.005)
