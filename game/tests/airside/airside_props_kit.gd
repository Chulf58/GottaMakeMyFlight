extends RefCounted
## Shared set-up for the airside props tests (board 4c08b8e5): the real Airside
## markers and links from main.tscn's saved state, without instancing the
## scene, and a plane model parked or posed as PlaneView draws it.

const MAIN_SCENE := "res://main/main.tscn"


## A new Airside carrying main.tscn's Marker3D waypoints and links. The caller
## adds it to the tree and frees it.
static func airside_from_main() -> Airside:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	var airside := Airside.new()
	for i in state.get_node_count():
		var parent := String(state.get_node_path(i, true))
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		if parent == "./Airside" and state.get_node_type(i) == &"Marker3D":
			var marker := Marker3D.new()
			marker.name = state.get_node_name(i)
			marker.transform = props.get(&"transform", Transform3D.IDENTITY)
			airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			airside.links = props[&"links"]
	return airside


## A holder at `pose` with an instance of plane `model` under it, placed as
## PlaneView.model_position_at() places it on the ground for a stand at
## `stand_point` whose parked plane faces `stand_dir`. Returns the model; the
## holder is its parent, added under `parent`.
static func posed_model(
	parent: Node, model: String, pose: Transform3D, stand_point: Vector3, stand_dir: Vector3
) -> Node3D:
	var holder := Node3D.new()
	holder.transform = pose
	parent.add_child(holder)
	var plane: Node3D = (PlaneView.PLANE_SCENES[model] as PackedScene).instantiate()
	plane.position = FlightPose.model_position(model, pose, stand_point, stand_dir)
	holder.add_child(plane)
	return plane
