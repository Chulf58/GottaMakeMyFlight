extends SceneTree
## Headless check that every retail kit .glb imported, that every mesh surface carries
## the shared toon materials the post-import binder assigns, that each piece stays
## inside its 2x1 footprint less the 0.08 m furniture inset, and that each Mount_* node
## sits where build_retail_kit.py's RETAIL table puts it.
##
## Run after an import:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://assets/interior/retail_kit_import_check.gd

const ATLAS := "res://assets/materials/tp_atlas_toon.tres"
const LIGHTS := "res://assets/materials/tp_lights.tres"
## Piece -> the exact set of toon materials its surfaces must carry.
const PIECES := {
	"duty_free_shelf": [ATLAS],
	"duty_free_till": [ATLAS, LIGHTS],
	"fashion_rail": [ATLAS],
	"fashion_till": [ATLAS, LIGHTS],
}
## A 2x1 footprint less the 0.08 m inset: |x| <= 0.92, |z| <= 0.42, nothing below the floor.
const LIMIT_X := 0.92
const LIMIT_Z := 0.42
const EPS := 1e-3
const FRONT := Vector3(0, 0, 1)
const BACK := Vector3(0, 0, -1)
const ORDER := [Vector3(-0.5, 0.0, 1.0), BACK]
const STAFF := [Vector3(-0.5, 0.0, -1.0), FRONT]
const BROWSE := {
	"Mount_Browse_0": [Vector3(-0.5, 0.0, 1.0), BACK],
	"Mount_Browse_1": [Vector3(0.5, 0.0, 1.0), BACK],
}
## Piece -> {mount: [position, facing (+Z)]}, in the piece's own frame.
const MOUNTS := {
	"duty_free_shelf": BROWSE,
	"duty_free_till": {"Mount_Order": ORDER, "Mount_Staff": STAFF},
	"fashion_rail": BROWSE,
	"fashion_till": {"Mount_Order": ORDER, "Mount_Staff": STAFF},
}


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
	var lo := aabb.position
	var hi := aabb.end
	var inside := (
		lo.x >= -LIMIT_X - EPS
		and hi.x <= LIMIT_X + EPS
		and lo.z >= -LIMIT_Z - EPS
		and hi.z <= LIMIT_Z + EPS
		and lo.y >= -EPS
	)
	var ok := surfaces > 0 and got == want and inside
	print(
		(
			"CHECK %s surfaces=%d materials=%s aabb_min=%s aabb_max=%s inside_footprint=%s %s"
			% [piece, surfaces, got, lo, hi, inside, "ok" if ok else "FAIL"]
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


func _local_transform(node: Node3D, scene: Node3D) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent()
	while parent != null and parent != scene:
		xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	return xf
