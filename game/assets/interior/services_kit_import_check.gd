extends SceneTree
## Headless check that every services kit .glb imported, that every mesh surface
## carries the shared toon materials the post-import binder assigns, that each Mount_*
## node sits where build_services_kit.py's SERVICES table puts it, and that the shower
## door's hinge node and its leaf mesh survived the import.
##
## Run after an import:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://assets/interior/services_kit_import_check.gd

const ATLAS := "res://assets/materials/tp_atlas_toon.tres"
const GLASS := "res://assets/materials/tp_glass.tres"
const LIGHTS := "res://assets/materials/tp_lights.tres"
## Piece -> the exact set of toon materials its surfaces must carry.
const PIECES := {
	"bar_counter": [ATLAS, GLASS],
	"restaurant_table": [ATLAS, GLASS],
	"restaurant_booth": [ATLAS, GLASS],
	"grab_and_go_stall": [ATLAS, LIGHTS, GLASS],
	"info_desk": [ATLAS, LIGHTS],
	"currency_exchange": [ATLAS, LIGHTS, GLASS],
	"atm": [ATLAS, LIGHTS],
	"pharmacy_counter": [ATLAS, LIGHTS],
	"pharmacy_shelf": [ATLAS, LIGHTS],
	"shower_cubicle": [ATLAS, GLASS],
	"nap_pod": [ATLAS, LIGHTS],
}
const FRONT := Vector3(0, 0, 1)
const BACK := Vector3(0, 0, -1)
const ORDER := [Vector3(-0.5, 0.0, 1.0), BACK]
const STAFF := [Vector3(-0.5, 0.0, -1.0), FRONT]
const FOUR_SEATS := {
	"Mount_SitRoot_FL": [Vector3(-0.5, 0.0, 0.55), BACK],
	"Mount_SitRoot_FR": [Vector3(0.5, 0.0, 0.55), BACK],
	"Mount_SitRoot_BL": [Vector3(-0.5, 0.0, -0.55), FRONT],
	"Mount_SitRoot_BR": [Vector3(0.5, 0.0, -0.55), FRONT],
}
## Piece -> {mount: [position, facing (+Z)]}, in the piece's own frame.
const MOUNTS := {
	"bar_counter":
	{
		"Mount_SitRoot_L": [Vector3(-0.5, 0.0, 0.05), BACK],
		"Mount_SitRoot_R": [Vector3(0.5, 0.0, 0.05), BACK],
		"Mount_Staff": [Vector3(-0.5, 0.0, -1.5), FRONT],
	},
	"restaurant_table": FOUR_SEATS,
	"restaurant_booth": FOUR_SEATS,
	"grab_and_go_stall": {"Mount_Order": ORDER, "Mount_Staff": STAFF},
	"info_desk": {"Mount_Order": ORDER, "Mount_Staff": STAFF},
	"currency_exchange": {"Mount_Order": ORDER, "Mount_Staff": STAFF},
	"atm": {"Mount_Use": [Vector3(0.0, 0.0, 1.0), BACK]},
	"pharmacy_counter": {"Mount_Order": ORDER, "Mount_Staff": STAFF},
	"pharmacy_shelf": {"Mount_Browse": [Vector3(-0.5, 0.0, 1.0), BACK]},
	"shower_cubicle": {"Mount_Use": [Vector3(0.0, 0.0, 1.0), BACK]},
	"nap_pod": {"Mount_SitRoot": [Vector3(0.0, 0.0, 0.45), FRONT]},
}
## Replaceable or animated nodes that must survive the import: [group, its mesh].
const NODES := {
	"grab_and_go_stall": ["Sign_Face", "Sign_Face_Mesh"],
	"currency_exchange": ["Sign_Face", "Sign_Face_Mesh"],
	"shower_cubicle": ["Door_Leaf_Shower", "Door_Leaf_Shower_Mesh"],
}
const DOOR_HINGE := Vector3(-0.365, 0.0, 0.37)


func _initialize() -> void:
	var failed := 0
	for piece in PIECES:
		var path := "res://assets/interior/%s.glb" % piece
		var packed := load(path) as PackedScene
		if packed == null:
			print("CHECK_FAIL %s did not load" % path)
			failed += 1
			continue
		var scene := packed.instantiate() as Node3D
		var ok := (
			_check_root(piece, scene)
			and _check_materials(piece, scene)
			and _check_mounts(piece, scene)
			and _check_nodes(piece, scene)
		)
		if not ok:
			failed += 1
		scene.free()
	print("CHECK done pieces=%d failed=%d" % [PIECES.size(), failed])
	quit(1 if failed > 0 else 0)


func _check_root(piece: String, scene: Node3D) -> bool:
	var root_name := piece.to_pascal_case() + "_ROOT"
	var root := scene.find_child(root_name, true, false) as Node3D
	var ok := root != null and _local_transform(root, scene).is_equal_approx(Transform3D.IDENTITY)
	print("ROOT %s %s identity=%s" % [piece, root_name, ok if root != null else "missing"])
	return ok


func _check_materials(piece: String, scene: Node3D) -> bool:
	var surfaces := 0
	var used := {}
	var aabb := AABB()
	var first := true
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var box := _local_transform(mi, scene) * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
		for i in mi.mesh.get_surface_count():
			surfaces += 1
			var mat := mi.get_active_material(i)
			used[mat.resource_path if mat != null else "<none>"] = true
	var want: Array = PIECES[piece].duplicate()
	want.sort()
	var got := used.keys()
	got.sort()
	var ok := surfaces > 0 and got == want
	print(
		(
			"CHECK %s surfaces=%d materials=%s aabb_pos=%s aabb_size=%s %s"
			% [piece, surfaces, got, aabb.position, aabb.size, "ok" if ok else "FAIL"]
		)
	)
	return ok


func _check_mounts(piece: String, scene: Node3D) -> bool:
	var ok := true
	var want: Dictionary = MOUNTS[piece]
	var found := 0
	for node in scene.find_children("Mount_*", "Node3D", true, false):
		found += 1
		var name := String(node.name)
		var xf := _local_transform(node as Node3D, scene)
		var facing := xf.basis.z.normalized()
		var scale := xf.basis.get_scale()
		var good := (
			name in want
			and xf.origin.distance_to(want[name][0]) < 1e-3
			and facing.distance_to(want[name][1]) < 1e-3
			and scale.is_equal_approx(Vector3.ONE)
		)
		ok = ok and good
		print(
			(
				"MOUNT %s %s pos=%s facing=%s scale=%s %s"
				% [piece, name, xf.origin, facing, scale, "ok" if good else "FAIL"]
			)
		)
	if found != want.size():
		print("CHECK_FAIL %s found %d mounts, expected %d" % [piece, found, want.size()])
		ok = false
	return ok


## Each [group, mesh] pair: the group a plain Node3D, the mesh a MeshInstance3D child of
## it with geometry, so hiding or turning the group moves the whole sign or door leaf.
func _check_nodes(piece: String, scene: Node3D) -> bool:
	var names: Array = NODES.get(piece, [])
	if names.is_empty():
		return true
	var group := scene.find_child(names[0], true, false) as Node3D
	var mesh := scene.find_child(names[1], true, false) as MeshInstance3D
	var plain := group != null and not (group is MeshInstance3D)
	var child := mesh != null and group != null and mesh.get_parent() == group
	var surfaces := mesh.mesh.get_surface_count() if mesh != null and mesh.mesh != null else 0
	var ok := plain and child and surfaces > 0
	print(
		(
			"NODE %s %s plain_node3d=%s %s child_of_group=%s surfaces=%d %s"
			% [piece, names[0], plain, names[1], child, surfaces, "ok" if ok else "FAIL"]
		)
	)
	if piece == "shower_cubicle" and ok:
		var at := _local_transform(group, scene).origin
		var good := at.distance_to(DOOR_HINGE) < 1e-3
		print("DOOR hinge_pos=%s %s" % [at, "ok" if good else "FAIL"])
		ok = ok and good
	return ok


func _local_transform(node: Node3D, scene: Node3D) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent()
	while parent != null and parent != scene:
		xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	return xf
