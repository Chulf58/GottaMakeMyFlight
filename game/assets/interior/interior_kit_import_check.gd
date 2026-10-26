extends SceneTree
## Headless check that every interior kit .glb imported and that every mesh surface
## carries one of the shared toon materials the post-import binder assigns.
##
## Run after an import:
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://assets/interior/interior_kit_import_check.gd

const ATLAS := "res://assets/materials/tp_atlas_toon.tres"
const GLASS := "res://assets/materials/tp_glass.tres"
const LIGHTS := "res://assets/materials/tp_lights.tres"
## Piece -> the exact set of toon materials its surfaces must carry.
const PIECES := {
	"floor_tile": [ATLAS],
	"wall": [ATLAS],
	"wall_post": [ATLAS],
	"wall_glass": [ATLAS, GLASS],
	"wall_door": [ATLAS, GLASS],
	"checkin_desk": [ATLAS, LIGHTS],
	"security_scanner": [ATLAS, LIGHTS],
	"seat_row": [ATLAS],
	"kiosk": [ATLAS, LIGHTS],
	"info_screen": [ATLAS, LIGHTS],
}
const TOON_MATERIALS := [
	"res://assets/materials/tp_atlas_toon.tres",
	"res://assets/materials/tp_atlas_simple_toon.tres",
	"res://assets/materials/tcp_atlas_toon.tres",
	"res://assets/materials/tp_glass.tres",
	"res://assets/materials/tp_lights.tres",
]


func _initialize() -> void:
	var failed := 0
	for piece in PIECES:
		var path := "res://assets/interior/%s.glb" % piece
		var packed := load(path) as PackedScene
		if packed == null:
			print("CHECK_FAIL %s did not load" % path)
			failed += 1
			continue
		var scene := packed.instantiate()
		var surfaces := 0
		var bound := 0
		var used := {}
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				surfaces += 1
				var mat := (node as MeshInstance3D).get_active_material(i)
				var res_path := mat.resource_path if mat != null else "<none>"
				used[res_path] = true
				if res_path in TOON_MATERIALS:
					bound += 1
		var want: Array = PIECES[piece]
		var got := used.keys()
		got.sort()
		want = want.duplicate()
		want.sort()
		var ok := surfaces > 0 and bound == surfaces and got == want
		if not ok:
			failed += 1
		print(
			(
				"CHECK %s surfaces=%d bound=%d materials=%s %s"
				% [piece, surfaces, bound, used.keys(), "ok" if ok else "FAIL"]
			)
		)
		scene.free()
	print("CHECK done pieces=%d failed=%d" % [PIECES.size(), failed])
	quit(1 if failed > 0 else 0)
