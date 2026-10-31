@tool
extends EditorScenePostImport
## Binds the toon material to the crow (tfp_crow_01.glb, written by
## tools/blender/convert_crow.py) and makes its looping clips loop.
##
## Kept beside the bird assets rather than in toon_post_import.gd: the Toon
## Farm Pack atlas is used by the crow alone. Same rule as that binder: the
## surface gets the shared .tres as it is, and an unmapped name or a missing
## resource fails the import.

const MATERIALS := {
	"TFP_Atlas_1A_D": "res://assets/birds/tfp_atlas_toon.tres",
}
## Takeoff and land play once; every other clip loops.
const ONE_SHOT: Array[String] = ["takeoff", "land"]


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
			var toon: Material = load(MATERIALS[key]) if MATERIALS.has(key) else null
			if toon == null:
				push_error(
					(
						"bird import: %s: %s surface %d: no toon material for '%s'"
						% [get_source_file(), node.name, i, key]
					)
				)
				failed += 1
				continue
			mesh.surface_set_material(i, toon)
			bound += 1
	var looped := 0
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for anim_name in player.get_animation_list():
			if not anim_name in ONE_SHOT:
				player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
				looped += 1
	print(
		(
			"bird import: %s bound=%d unmapped=%d looped=%d"
			% [get_source_file(), bound, failed, looped]
		)
	)
	if failed > 0 or bound == 0:
		return null
	return scene
