class_name TestToiletKitView
extends GdUnitTestSuite
## The toilet pieces in the build view (Toilets 5/5): the toilet stall and the
## sink are drawn with their kit pieces (decision toilet-stall-kit-piece-1x2-
## footprint-side-partitions-out-to), centred on their footprints with no
## offset, instead of the catalog's boxes.


func test_the_stall_and_sink_use_their_kit_pieces_with_no_offset() -> void:
	for id in [&"toilet_stall", &"toilet_sink"]:
		assert_object(BuildCatalog.get_def(id)).is_not_null()
		assert_str(InteriorKit.object_piece(id)).is_equal(str(id))
		assert_vector(InteriorKit.object_offset(id)).is_equal(Vector3.ZERO)
		assert_bool(ResourceLoader.exists(InteriorKit.PIECE_PATH % str(id))).is_true()


func test_each_piece_has_meshes_inside_its_footprint() -> void:
	for id in [&"toilet_stall", &"toilet_sink"]:
		var def := BuildCatalog.get_def(id)
		var parts := InteriorKit.meshes(str(id))
		assert_int(parts.size()).override_failure_message(str(id)).is_greater(0)
		var box := AABB()
		for i in parts.size():
			var part_box: AABB = (parts[i][1] as Transform3D) * (parts[i][0] as Mesh).get_aabb()
			box = part_box if i == 0 else box.merge(part_box)
		print("%s: %d meshes, bounds %s, footprint %s" % [id, parts.size(), box, def.size])
		# The pivot is on the footprint centre: the piece spans it within the
		# cells, its front +Z at facing 0.
		var half := Vector2(def.size) / 2.0
		assert_float(box.position.x).is_greater_equal(-half.x - 0.01)
		assert_float(box.end.x).is_less_equal(half.x + 0.01)
		assert_float(box.position.z).is_greater_equal(-half.y - 0.01)
		assert_float(box.end.z).is_less_equal(half.y + 0.01)
		assert_float(box.position.y).is_greater_equal(-0.01)
		assert_float(box.size.y).is_greater(0.5)
