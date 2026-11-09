extends SceneTree
## Headless reach probe for the jet bridge rooted at the gate's exit door
## (board 0adca5c6). Prints, per plane model 03 to 07 parked at a stand: the
## door sill, and JetBridgePose.solve() from JetBridgePose.root_for() (dockable,
## slide, pitch, drive height, the column-to-cab reach and the tunnel length
## hinge to cab). For comparison it prints the same for a column standing at the
## exit door itself (ROOT_OUT_M out, EXIT_X_M 0) and for the root the R11 build
## used (_r11_root(): 2.9 m out, its cab pivot 10 m from the column). Then,
## for models 03 and 04, the swung-clear
## pose against the plane: edge crossings per bridge mesh and the touching
## plane parts' bounds. It rules nothing; it prints numbers.
##
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##   --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/jet_bridge_reach_probe.gd

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const MODELS: Array[String] = [
	"tp_plane_03a", "tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var airside := Kit.airside_from_main()
	root.add_child(airside)
	var stand := StandPlacement.make(1, 20.0, -230.0)
	airside.set_gate_stands({"A": stand})
	var entry: Dictionary = airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var roots := {
		"exit_door_stair_box": JetBridgePose.root_for(stand),
		"column_at_exit_door":
		Transform3D(
			Basis(Vector3.UP, PI),
			Vector3(float(stand["x"]), 0.0, float(stand["wall_z"]) - JetBridgePose.ROOT_OUT_M)
		),
		"r11_root": _r11_root(stand),
	}
	var sill := (bridge.find_child("Mount_StairBottom", true, false) as Node3D).global_position
	print(
		(
			"REACH stand %s exit door (%.2f, %.2f) stair sill %s"
			% [stand, stand["x"], stand["wall_z"], sill]
		)
	)
	for model: String in MODELS:
		var plane := _park(model, stand, airside)
		var door: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
		for key: String in roots:
			var r: Transform3D = roots[key]
			var at := JetBridgePose.solve(r, door, Vector3.RIGHT)
			var c := r.affine_inverse() * (door + Vector3.RIGHT * JetBridgePose.MOUNT_DOOR_Z)
			var reach := Vector2(c.x, c.z).length()
			print(
				(
					(
						"REACH %s %s sill %.2f: dockable %s slide %.2f (0..%.1f) pitch %.2f deg (max %.0f)"
						+ " drive_h %.2f reach %.2f m tunnel %.2f m"
					)
					% [
						model,
						key,
						door.y,
						at["ok"],
						at["slide"],
						JetBridgePose.SLIDE_MAX,
						rad_to_deg(at["pitch"]),
						JetBridgePose.PITCH_MAX_DEG,
						at["drive_h"],
						reach,
						JetBridgePose.CAB_Z + float(at["slide"]),
					]
				)
			)
		if not entry["docked"]:
			_contacts(model, plane, bridge)
		plane.get_parent().free()
	airside.free()
	quit(0)


func _contacts(model: String, plane: Node3D, bridge: Node3D) -> void:
	for mi in bridge.find_children("*_Mesh", "MeshInstance3D", true, false):
		var found := Kit.crossings(plane, mi as Node3D)
		if found["count"] == 0:
			continue
		print(
			"CLEAR %s %s: %d crossings with %s" % [model, mi.name, found["count"], found["meshes"]]
		)
		for part: String in found["meshes"]:
			var pm := plane.find_child(part, true, false) as MeshInstance3D
			print("CLEAR %s %s world box %s" % [model, part, pm.global_transform * pm.get_aabb()])
		var b := mi as MeshInstance3D
		print("CLEAR %s %s world box %s" % [model, mi.name, b.global_transform * b.get_aabb()])


func _park(model: String, stand: Dictionary, airside: Airside) -> Node3D:
	var at := StandPlacement.stand_point(stand)
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	var plane := Kit.posed_model(root, model, pose, at, Vector3.BACK)
	var props := PlaneProps.new()
	plane.get_parent().add_child(props)
	props.follow(true, plane, model, FlightSim.State.BOARDING, "A", airside, 1)
	return plane


## The root R11 built (JetBridgePose.root_for() before board 0adca5c6): 2.9 m
## out from the wall line, east of the stand door where the cab pivot is 10 m
## from the column.
func _r11_root(stand: Dictionary) -> Transform3D:
	var cab := JetBridgePose.stand_door(stand) + Vector3(JetBridgePose.MOUNT_DOOR_Z, 0.0, 0.0)
	var z := float(stand["wall_z"]) - 2.9
	var across := z - cab.z
	var x := cab.x + sqrt(maxf(100.0 - across * across, 0.0))
	print("REACH r11 root %.2f m east of the exit door, 2.90 m out" % (x - float(stand["x"])))
	return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0.0, z))
