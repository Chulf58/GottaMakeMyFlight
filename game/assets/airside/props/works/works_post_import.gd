@tool
extends EditorScenePostImport
## Binds the toon materials to the construction-works props (board ecd67e67), the
## .glb files tools/blender/airside/convert_works_props.py writes beside this file.
##
## Kept beside the works assets, as bird_post_import.gd is beside the crow: the props
## come from three packs, and the Toon Industries excavator atlas is used by nothing
## else. Same rule as toon_post_import.gd: every surface gets the shared .tres as it
## is, and an unmapped name or a missing resource fails the import.

const MATERIALS := {
	"TC_Road_1A_D": "res://assets/materials/tc_road_1a_toon.tres",
	"TC_Props_2A_D": "res://assets/materials/tc_props_2a_toon.tres",
	"TI_Excavator_1A_D": "res://assets/airside/props/works/ti_excavator_1a_toon.tres",
	"TFP_Atlas_1A_D": "res://assets/birds/tfp_atlas_toon.tres",
}


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
						"works import: %s: %s surface %d: no toon material for '%s'"
						% [get_source_file(), node.name, i, key]
					)
				)
				failed += 1
				continue
			mesh.surface_set_material(i, toon)
			bound += 1
	print("works import: %s bound=%d unmapped=%d" % [get_source_file(), bound, failed])
	if failed > 0 or bound == 0:
		# Returning null fails the import, so a half-bound prop never ships.
		return null
	return scene
