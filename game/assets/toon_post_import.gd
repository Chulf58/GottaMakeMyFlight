@tool
extends EditorScenePostImport
## Binds the Toon Series toon materials to every imported surface by glTF material
## name, and makes the characters' looping clips (idle, walk, run, sit_idle) loop.
##
## The .glb files come from tools/blender/convert_toon_batch.py, which names every
## material after its pack and atlas. Each .glb.import points its
## import_script/path here. The surfaces get the shared .tres resources as they are;
## nothing is copied from the glTF material, so no PBR scalar or map can leak into
## the toon look. An unmapped name or a missing resource fails the import.

const MATERIALS := {
	"TP_Atlas_1A_D": "res://assets/materials/tp_atlas_toon.tres",
	"TP_Atlas_Simple_1A_D": "res://assets/materials/tp_atlas_simple_toon.tres",
	"TP_Atlas_Lights_1A_D": "res://assets/materials/tp_lights.tres",
	"TP_Glass_1A_D": "res://assets/materials/tp_glass.tres",
	"TCP_Atlas_1A_D": "res://assets/materials/tcp_atlas_toon.tres",
}
const LOOPING_ANIMATIONS: Array[String] = ["idle", "walk", "run", "sit_idle"]


func _post_import(scene: Node) -> Object:
	var bound := 0
	var failed := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var source := mesh.surface_get_material(i)
			var key := source.resource_name if source != null else ""
			if not MATERIALS.has(key):
				push_error(
					(
						"toon import: %s: %s surface %d has unmapped material '%s'"
						% [get_source_file(), node.name, i, key]
					)
				)
				failed += 1
				continue
			var toon := load(MATERIALS[key]) as Material
			if toon == null:
				push_error("toon import: cannot load %s" % MATERIALS[key])
				failed += 1
				continue
			mesh.surface_set_material(i, toon)
			bound += 1
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for anim_name in player.get_animation_list():
			if anim_name in LOOPING_ANIMATIONS:
				player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	print("toon import: %s bound=%d unmapped=%d" % [get_source_file(), bound, failed])
	if failed > 0 or bound == 0:
		# Returning null fails the import, so a half-bound asset never ships.
		return null
	return scene
