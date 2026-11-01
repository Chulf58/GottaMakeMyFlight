class_name TestMessViews
extends GdUnitTestSuite
## MessViews draws one floor prop per mess (by kind, grown when grown) on its
## cell with a turn from its id, and the rubbish of the full bin model on a
## full bin, and drops each when the mess is cleaned or the bin emptied. One
## world for the file; each case clears the messes and removes what it built.

const CELL := Vector2i(10, 8)
const BIN_AT := Vector2i(14, 8)

var _w: PassengerTestWorld
var _views: MessViews


func before() -> void:
	PassengerTestWorld.tracker = self
	_w = MessTestKit.open_world()


func after() -> void:
	_w.free_all()
	PassengerTestWorld.tracker = null


func before_test() -> void:
	assert_bool(MessTestKit.clear(_w)).is_true()
	_views = MessViews.new()
	_views.sim = _w.sim
	add_child(_views)


func after_test() -> void:
	_views.free()


func _scene_of(node: Node3D) -> String:
	return node.scene_file_path


## The meshes of `node` that draw something.
func _drawn_meshes(node: Node3D) -> Array[String]:
	var names: Array[String] = []
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null:
			names.append(String(mesh.name))
	return names


func test_each_kind_draws_its_own_prop_on_its_cell() -> void:
	var cells: Array[Vector2i] = [CELL, CELL + Vector2i(3, 0), CELL + Vector2i(6, 0)]
	var ids: Array[int] = []
	for kind in [MessSim.Kind.LITTER, MessSim.Kind.SPILL, MessSim.Kind.TOILET]:
		ids.append(_w.sim.messes.add(kind, cells[ids.size()]))
	_views.sync()
	assert_int(_views.prop_count()).is_equal(3)
	for i in ids.size():
		var node := _views.prop_for(ids[i])
		var want := _w.grid.cell_to_world(cells[i])
		print(
			(
				"mess %d kind %d drawn %s at %s (cell %s), turn %.3f"
				% [ids[i], i, _scene_of(node), node.position, want, node.rotation.y]
			)
		)
		assert_str(_scene_of(node)).is_equal(MessViews.prop_scene(i, false).resource_path)
		assert_vector(node.position).is_equal_approx(want, Vector3.ONE * 0.001)
		var turn := node.basis.get_euler().y
		var want_turn := wrapf(MessViews.turn_of(ids[i]), -PI, PI)
		assert_float(turn).is_equal_approx(want_turn, 0.001)


func test_grown_litter_swaps_to_the_grown_prop_and_cleaning_removes_it() -> void:
	var id := _w.sim.messes.add(MessSim.Kind.LITTER, CELL)
	_views.sync()
	var small := _scene_of(_views.prop_for(id))
	# Loaded as saved GROW_TICKS after its birth: grown, as the load check wants.
	var data := _w.sim.messes.to_snapshot()
	data["tick"] = MessSim.GROW_TICKS
	data["messes"][0]["born_tick"] = 0
	data["messes"][0]["grown"] = true
	assert_bool(_w.sim.messes.from_snapshot(data)).is_true()
	_views.sync()
	var big := _scene_of(_views.prop_for(id))
	assert_bool(_w.sim.messes.clean(id)).is_true()
	_views.sync()
	print(
		"litter %d: %s, grown %s, after cleaning %d props" % [id, small, big, _views.prop_count()]
	)
	assert_str(small).is_equal(MessViews.prop_scene(MessSim.Kind.LITTER, false).resource_path)
	assert_str(big).is_equal(MessViews.prop_scene(MessSim.Kind.LITTER, true).resource_path)
	assert_int(_views.prop_count()).is_equal(0)


func test_a_full_bin_shows_only_its_rubbish_until_it_is_emptied() -> void:
	var bin := PassengerTestWorld.place(_w.grid, MessSim.BIN_ID, BIN_AT, 1)
	_views.sync()
	var before_full := _views.rubbish_count()
	var data := _w.sim.messes.to_snapshot()
	data["bins"][str(bin)] = MessSim.BIN_CAPACITY
	assert_bool(_w.sim.messes.from_snapshot(data)).is_true()
	_views.sync()
	var node := _views.rubbish_for(bin)
	assert_object(node).is_not_null()
	var record := _w.grid.get_object(bin)
	var def := BuildCatalog.get_def(record["def"])
	var want := BuildView.object_transform(
		_w.grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
	)
	var meshes := _drawn_meshes(node)
	print(
		(
			"bin %d: rubbish before full %d; full at %s (bin %s), drawn meshes %s"
			% [bin, before_full, node.transform.origin, want.origin, meshes]
		)
	)
	assert_int(before_full).is_equal(0)
	assert_bool(node.transform.is_equal_approx(want)).is_true()
	assert_array(meshes).contains_exactly([MessViews.RUBBISH])
	assert_bool(_w.sim.messes.empty_bin(bin)).is_true()
	_views.sync()
	assert_int(_views.rubbish_count()).is_equal(0)
	_w.grid.apply(BuildEdit.remove_object(bin))
