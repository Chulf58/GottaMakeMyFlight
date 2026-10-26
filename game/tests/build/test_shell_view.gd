class_name TestShellView
extends GdUnitTestSuite
## ShellView on the real tp_airport_shell.glb: each shell gets its own
## dissolve materials (the shared .tres and a second shell stay untouched),
## the roof hides at full dissolve, a cut side is squashed in shell space and
## restored exactly, pieces get the side their name says, and a hidden or
## freed facade piece is left alone.

const SHELL := "res://assets/buildings/tp_airport_shell.glb"
const SHARED_TOON := "res://assets/materials/tp_atlas_toon.tres"
const TOON_DISSOLVE := "res://shaders/toon_dissolve.gdshader"
const OUTLINE_DISSOLVE := "res://shaders/toon_outline_dissolve.gdshader"
const UNSHADED_DISSOLVE := "res://shaders/unshaded_dissolve.gdshader"
const SOUTH := ShellCutaway.Side.SOUTH
const NORTH := ShellCutaway.Side.NORTH

var _world: Node3D
var _a: ShellView
var _b: ShellView


func before() -> void:
	_world = Node3D.new()
	add_child(_world)
	_a = _make_view("A", Vector3.ZERO)
	_b = _make_view("B", Vector3(200.0, 0.0, 0.0))


func after() -> void:
	_world.free()


func after_test() -> void:
	for view in [_a, _b]:
		view.cutaway.roof_level = 0.0
		view.cutaway.side_levels = [0.0, 0.0, 0.0, 0.0]
		view.apply()


func _make_view(label: String, at: Vector3) -> ShellView:
	var shell := (load(SHELL) as PackedScene).instantiate() as Node3D
	shell.name = "Shell" + label
	shell.position = at
	_world.add_child(shell)
	var view := ShellView.new()
	view.name = "View" + label
	view.shell = shell
	_world.add_child(view)
	return view


func _mesh(view: ShellView, node_name: String) -> MeshInstance3D:
	return view.shell.find_child(node_name, true, false) as MeshInstance3D


## The AABB of a mesh node in its shell's frame.
func _shell_box(view: ShellView, mi: MeshInstance3D) -> AABB:
	return view.shell.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()


## A parameter's value as the shader sees it: the material's own value, or
## the shader's default when the material leaves it unset.
func _effective(material: ShaderMaterial, uniform: String) -> Variant:
	var value: Variant = material.get_shader_parameter(uniform)
	if value == null:
		value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), uniform)
	return value


func test_setup_found_the_roof_and_four_sides() -> void:
	assert_bool(_a.is_ready()).is_true()
	var names: Array = []
	for mi in _a.roof_nodes:
		names.append(String(mi.name))
	names.sort()
	# Poles are the canopy's struts and fade with it (user ruling 2026-10-26).
	assert_array(names).is_equal(["Canopy", "Lights_Upper", "Poles", "Upper"])
	var counts := {}
	for side in 4:
		counts[side] = _a.side_pieces[side].size()
	# 22 or 12 facade bays per side, the ground light panels on it, and on the
	# long sides four doors and four porches.
	assert_int(counts[NORTH]).is_greater_equal(22 + 8)
	assert_int(counts[SOUTH]).is_greater_equal(22 + 8)
	assert_int(counts[ShellCutaway.Side.EAST]).is_greater_equal(12)
	assert_int(counts[ShellCutaway.Side.WEST]).is_greater_equal(12)


## Every Facade_<side>_* and Lights_<side>_* node, and Door_1..8 and
## Porch_1..8, is registered exactly once, on its own side; nothing else is.
func test_pieces_get_the_side_their_name_or_door_number_says() -> void:
	var expected := {}
	for mi in _a.shell.find_children("*", "MeshInstance3D", true, false):
		var piece_name := String(mi.name)
		var by_name := ShellCutaway.side_of_name(piece_name)
		if by_name != -1:
			expected[mi] = by_name
		elif piece_name.begins_with("Door_") or piece_name.begins_with("Porch_"):
			var number := piece_name.get_slice("_", 1).to_int()
			expected[mi] = NORTH if number <= 4 else SOUTH
	var facades := _a.shell.find_children("Facade_*", "MeshInstance3D", true, false).size()
	assert_int(facades).is_equal(68)
	assert_int(expected.size()).is_greater_equal(68 + 16)
	var seen := {}
	for side in 4:
		for piece in _a.side_pieces[side]:
			var piece_name := String(piece.name)
			assert_bool(seen.has(piece)).override_failure_message("twice: " + piece_name).is_false()
			seen[piece] = true
			(
				assert_bool(expected.has(piece))
				. override_failure_message("extra: " + piece_name)
				. is_true()
			)
			assert_int(side).override_failure_message(piece_name).is_equal(expected.get(piece, -1))
	assert_int(seen.size()).is_equal(expected.size())
	# The box rule, used for doors and porches, agrees with every name.
	for piece in expected:
		var by_name := ShellCutaway.side_of_name(String(piece.name))
		if by_name != -1:
			var box := _shell_box(_a, piece as MeshInstance3D)
			(
				assert_int(ShellCutaway.side_of_box(box, _a.facade_box))
				. override_failure_message("box rule for " + String(piece.name))
				. is_equal(by_name)
			)


func test_the_roof_casts_no_shadow_while_it_fades() -> void:
	for level in [0.5, 1.0]:
		_a.cutaway.roof_level = level
		_a.apply()
		for mi in _a.roof_nodes:
			(
				assert_int(mi.cast_shadow)
				. override_failure_message("%s at %s" % [mi.name, level])
				. is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			)
	_a.cutaway.roof_level = 0.0
	_a.apply()
	for mi in _a.roof_nodes:
		var other := _mesh(_b, mi.name)
		assert_int(mi.cast_shadow).is_equal(other.cast_shadow)
		assert_int(mi.cast_shadow).is_not_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_roof_surfaces_get_their_own_dissolve_materials() -> void:
	var shared := load(SHARED_TOON) as ShaderMaterial
	var surfaces := 0
	for mi in _a.roof_nodes:
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i) as ShaderMaterial
			assert_object(mat).override_failure_message(String(mi.name)).is_not_null()
			assert_object(mat).is_not_same(shared)
			var other := _mesh(_b, mi.name).get_surface_override_material(i)
			assert_object(mat).is_not_same(other)
			if mi.name == "Lights_Upper":
				assert_str(mat.shader.resource_path).is_equal(UNSHADED_DISSOLVE)
			else:
				assert_str(mat.shader.resource_path).is_equal(TOON_DISSOLVE)
				var outline := mat.next_pass as ShaderMaterial
				assert_str(outline.shader.resource_path).is_equal(OUTLINE_DISSOLVE)
				assert_object(outline).is_not_same(shared.next_pass)
			surfaces += 1
	assert_int(surfaces).is_equal(4)


func test_the_copies_keep_every_source_value() -> void:
	var shared := load(SHARED_TOON) as ShaderMaterial
	var copy := _mesh(_a, "Upper").get_surface_override_material(0) as ShaderMaterial
	var pairs := [[shared, copy], [shared.next_pass, copy.next_pass]]
	var compared := 0
	for pair in pairs:
		var source := pair[0] as ShaderMaterial
		var made := pair[1] as ShaderMaterial
		assert_int(made.render_priority).is_equal(source.render_priority)
		for uniform in source.shader.get_shader_uniform_list():
			var key: String = uniform["name"]
			assert_that(_effective(made, key)).override_failure_message(key).is_equal(
				_effective(source, key)
			)
			compared += 1
	assert_int(compared).is_greater_equal(4 + 5)
	var lights_src := _mesh(_a, "Lights_Upper").mesh.surface_get_material(0) as StandardMaterial3D
	var lights := _mesh(_a, "Lights_Upper").get_surface_override_material(0) as ShaderMaterial
	assert_object(lights.get_shader_parameter("albedo_texture")).is_same(lights_src.albedo_texture)
	assert_that(lights.get_shader_parameter("albedo_color")).is_equal(lights_src.albedo_color)


func test_full_dissolve_hides_this_roof_only() -> void:
	var shared := load(SHARED_TOON) as ShaderMaterial
	_a.cutaway.roof_level = 1.0
	_a.apply()
	var mat := _mesh(_a, "Upper").get_surface_override_material(0) as ShaderMaterial
	assert_float(mat.get_shader_parameter("dissolve")).is_equal(1.0)
	assert_float(mat.next_pass.get_shader_parameter("dissolve")).is_equal(1.0)
	var lights := _mesh(_a, "Lights_Upper").get_surface_override_material(0) as ShaderMaterial
	assert_float(lights.get_shader_parameter("dissolve")).is_equal(1.0)
	for mi in _a.roof_nodes:
		assert_bool(mi.visible).override_failure_message(String(mi.name)).is_false()
	var other := _mesh(_b, "Upper").get_surface_override_material(0) as ShaderMaterial
	assert_float(other.get_shader_parameter("dissolve")).is_equal(0.0)
	assert_bool(_mesh(_b, "Upper").visible).is_true()
	assert_that(shared.get_shader_parameter("dissolve")).is_null()
	_a.cutaway.roof_level = 0.5
	_a.apply()
	assert_float(mat.get_shader_parameter("dissolve")).is_equal(0.5)
	assert_bool(_mesh(_a, "Upper").visible).is_true()


func test_a_cut_side_is_squashed_in_shell_space_and_restored_exactly() -> void:
	var bases := {}
	for side in 4:
		for piece in _a.side_pieces[side]:
			bases[piece] = (piece as Node3D).transform
	var bay := _mesh(_a, "Facade_S_05")
	var door := _mesh(_a, "Door_5")
	var bay_before := _shell_box(_a, bay)
	var door_before := _shell_box(_a, door)
	_a.cutaway.roof_level = 1.0
	_a.cutaway.side_levels = [0.0, 1.0, 0.0, 0.0]
	_a.apply()
	var bay_after := _shell_box(_a, bay)
	var floor_y := ShellCutaway.FLOOR_Y
	var stub_top := floor_y + InteriorKit.STUB_HEIGHT
	assert_float(bay_after.end.y).is_equal_approx(stub_top, 0.01)
	assert_float(bay_after.position.y).is_equal_approx(bay_before.position.y, 0.01)
	assert_float(bay_after.size.x).is_equal_approx(bay_before.size.x, 0.001)
	assert_float(bay_after.size.z).is_equal_approx(bay_before.size.z, 0.001)
	# The door is rotated in its own frame; the squash must still be vertical.
	var door_after := _shell_box(_a, door)
	assert_float(door_after.size.x).is_equal_approx(door_before.size.x, 0.001)
	assert_float(door_after.size.z).is_equal_approx(door_before.size.z, 0.001)
	assert_float(door_after.end.y).is_less(stub_top + 0.05)
	var north := _mesh(_a, "Facade_N_05")
	assert_bool(north.transform.is_equal_approx(bases[north])).is_true()
	_a.cutaway.side_levels = [0.0, 0.0, 0.0, 0.0]
	_a.apply()
	for piece in bases:
		(
			assert_bool((piece as Node3D).transform.is_equal_approx(bases[piece]))
			. override_failure_message(String(piece.name))
			. is_true()
		)


## Whether a material drops world point `p`: the shader test (dissolve_in_holes),
## lo <= p <= hi on every axis of any of its first hole_count boxes.
func _drops(mat: ShaderMaterial, p: Vector3) -> bool:
	var los: PackedVector3Array = mat.get_shader_parameter("hole_min")
	var his: PackedVector3Array = mat.get_shader_parameter("hole_max")
	assert_int(los.size()).is_equal(ShellView.HOLE_SLOTS)
	var count: int = mat.get_shader_parameter("hole_count")
	for i in mini(count, los.size()):
		var lo := los[i]
		var hi := his[i]
		if (
			p.x >= lo.x
			and p.y >= lo.y
			and p.z >= lo.z
			and p.x <= hi.x
			and p.y <= hi.y
			and p.z <= hi.z
		):
			return true
	return false


## A side cut past half opens its doorways: door and porch hidden, two jambs
## shown each, the door bay's hole set over the opening and Lot's over the
## porch sign. Uncut, all of it goes back.
func test_a_cut_side_opens_its_doorways() -> void:
	assert_int(_a.doorways.size()).is_equal(8)
	var lot := _mesh(_a, "Lot").get_surface_override_material(0) as ShaderMaterial
	assert_str(lot.shader.resource_path).is_equal(TOON_DISSOLVE)
	_a.cutaway.roof_level = 1.0
	_a.cutaway.side_levels = [0.0, 1.0, 0.0, 0.0]
	_a.apply()
	var open_count := 0
	for doorway in _a.doorways:
		var south: bool = doorway.side == SOUTH
		var label := String((doorway.door as Node3D).name)
		assert_bool((doorway.door as Node3D).visible).override_failure_message(label).is_equal(
			not south
		)
		assert_bool((doorway.porch as Node3D).visible).override_failure_message(label).is_equal(
			not south
		)
		assert_int(doorway.jambs.size()).override_failure_message(label).is_equal(2)
		for jamb in doorway.jambs:
			assert_bool((jamb as Node3D).visible).override_failure_message(label).is_equal(south)
		var bay := (
			(doorway.bay as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		)
		assert_str(bay.shader.resource_path).is_equal(TOON_DISSOLVE)
		var over_opening := (doorway.centre_world as Vector3) + Vector3(0.0, 0.25, 0.0)
		assert_bool(_drops(bay, over_opening)).override_failure_message(label).is_equal(south)
		var sign_point: Vector3 = (doorway.sign_hole as AABB).get_center()
		assert_bool(_drops(lot, sign_point)).override_failure_message(label).is_equal(south)
		open_count += 1 if south else 0
	assert_int(open_count).is_equal(4)
	# The real letter sign of Porch_6, measured in Lot (shell A sits at the
	# origin, so shell space is world space here).
	for corner in [Vector3(15.6, 4.1, 19.0), Vector3(16.4, 5.0, 19.2)]:
		(
			assert_bool(_drops(lot, corner))
			. override_failure_message("Porch_6 sign %s" % corner)
			. is_true()
		)
	# Lot keeps its ground: the floor inside an open doorway is not dropped.
	for doorway in _a.doorways:
		assert_bool(_drops(lot, doorway.centre_world as Vector3)).is_false()
	_a.cutaway.side_levels = [0.0, 0.0, 0.0, 0.0]
	_a.apply()
	for doorway in _a.doorways:
		assert_bool((doorway.door as Node3D).visible).is_true()
		assert_bool((doorway.porch as Node3D).visible).is_true()
		for jamb in doorway.jambs:
			assert_bool((jamb as Node3D).visible).is_false()
		var bay := (
			(doorway.bay as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
		)
		var over_opening := (doorway.centre_world as Vector3) + Vector3(0.0, 0.25, 0.0)
		assert_bool(_drops(bay, over_opening)).is_false()
		assert_bool(_drops(lot, (doorway.sign_hole as AABB).get_center())).is_false()


## A turn from north to south passes a frame where both sides are cut exactly
## 0.5: all eight doorways are open and every porch sign must still be dropped.
func test_a_half_turn_opens_all_eight_doorways_and_drops_every_sign() -> void:
	_a.cutaway.roof_level = 1.0
	_a.cutaway.side_levels = [0.5, 0.5, 0.0, 0.0]
	_a.apply()
	var lot := _mesh(_a, "Lot").get_surface_override_material(0) as ShaderMaterial
	assert_int(lot.get_shader_parameter("hole_count")).is_equal(8)
	for doorway in _a.doorways:
		var label := String((doorway.door as Node3D).name)
		assert_bool((doorway.porch as Node3D).visible).override_failure_message(label).is_false()
		var sign_point: Vector3 = (doorway.sign_hole as AABB).get_center()
		assert_bool(_drops(lot, sign_point)).override_failure_message(label).is_true()


func test_a_hidden_bay_stays_hidden_through_a_cut() -> void:
	var bay := _mesh(_a, "Facade_S_03")
	bay.visible = false
	for level in [1.0, 0.5, 0.0]:
		_a.cutaway.roof_level = 1.0
		_a.cutaway.side_levels = [level, level, level, level]
		_a.apply()
		assert_bool(bay.visible).is_false()
	bay.visible = true


func test_a_freed_piece_does_not_break_updates() -> void:
	var view := _make_view("C", Vector3(-200.0, 0.0, 0.0))
	_mesh(view, "Facade_S_07").free()
	view.cutaway.roof_level = 1.0
	view.cutaway.side_levels = [1.0, 1.0, 1.0, 1.0]
	view.apply()
	var bay := _mesh(view, "Facade_S_08")
	assert_float(_shell_box(view, bay).end.y).is_less(1.0)
	view.shell.free()
	view.free()
