class_name TestWorksPropsAssets
extends GdUnitTestSuite
## The construction-works props (board ecd67e67, S8b phase 1) as Godot imports
## them: each .glb under assets/airside/props/works/ loads as a scene with meshes,
## every surface carries the shared toon material works_post_import.gd binds by
## name, and the scene's bounds match the size convert_works_props.py measured in
## the written file (true metres, standing on y 0).

const WORKS := "res://assets/airside/props/works/"
const SIZE_TOLERANCE_M := 0.02
const FLOOR_TOLERANCE_M := 0.05
## stem: [material .tres, expected bounds size in metres (x, y, z)].
const PROPS := {
	"ti_traffic_cone_1b":
	["res://assets/materials/tc_props_2a_toon.tres", Vector3(0.880, 1.079, 0.880)],
	"tc_concrete_barrier_1a":
	["res://assets/materials/tc_road_1a_toon.tres", Vector3(1.000, 1.200, 3.900)],
	"tc_metal_fence_2a":
	["res://assets/materials/tc_road_1a_toon.tres", Vector3(2.126, 3.500, 0.237)],
	"ti_excavator_1a":
	["res://assets/airside/props/works/ti_excavator_1a_toon.tres", Vector3(3.966, 3.567, 7.409)],
	"ti_brick_pile_1c":
	["res://assets/materials/tc_props_2a_toon.tres", Vector3(1.964, 1.500, 2.038)],
	"tfp_dump_trailer_01a":
	["res://assets/birds/tfp_atlas_toon.tres", Vector3(7.551, 2.950, 2.661)],
}

var _scenes := {}


func before() -> void:
	for stem in PROPS:
		var packed := load(WORKS + stem + ".glb") as PackedScene
		_scenes[stem] = packed.instantiate() if packed != null else null


func after() -> void:
	for node in _scenes.values():
		if node != null:
			(node as Node).free()
	_scenes.clear()


func test_every_prop_loads_with_meshes() -> void:
	for stem in PROPS:
		var node: Node = _scenes[stem]
		assert_object(node).override_failure_message("%s did not load" % stem).is_not_null()
		var meshes := _meshes(node)
		print("works %s meshes=%d" % [stem, meshes.size()])
		assert_int(meshes.size()).override_failure_message("%s has no mesh" % stem).is_greater(0)


func test_every_surface_has_the_toon_material() -> void:
	for stem in PROPS:
		var want: String = PROPS[stem][0]
		var surfaces := 0
		for mi in _meshes(_scenes[stem]):
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				var got := mat.resource_path if mat != null else "<none>"
				(
					assert_str(got)
					. override_failure_message(
						"%s %s surface %d: %s, expected %s" % [stem, mi.name, i, got, want]
					)
					. is_equal(want)
				)
				assert_bool(mat is ShaderMaterial).is_true()
				surfaces += 1
		print("works %s surfaces=%d material=%s" % [stem, surfaces, want])
		assert_int(surfaces).is_greater(0)


func test_every_prop_has_its_measured_size_on_the_ground() -> void:
	for stem in PROPS:
		var want: Vector3 = PROPS[stem][1]
		var box := _bounds(_scenes[stem])
		print("works %s size=%s want=%s low_y=%.3f" % [stem, box.size, want, box.position.y])
		for axis in 3:
			(
				assert_float(box.size[axis])
				. override_failure_message("%s size %s, expected %s" % [stem, box.size, want])
				. is_equal_approx(want[axis], SIZE_TOLERANCE_M)
			)
		assert_float(box.position.y).is_equal_approx(0.0, FLOOR_TOLERANCE_M)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null:
			out.append(mi)
	return out


## Bounds in the scene root's frame (the scene is not in the tree, so each mesh's
## transform is composed up to the root by hand).
func _bounds(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
