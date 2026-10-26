extends SceneTree
## Headless measurement for slice g: world AABBs of the terminal and the parked plane, and
## the clip names and lengths of both Toon characters. Prints MEASURE lines only.
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/passenger_measure_probe.gd


func _initialize() -> void:
	_aabb(
		"terminal",
		"res://assets/buildings/tp_airport_01a.glb",
		Transform3D(Basis(), Vector3(0, 0, -80))
	)
	var plane_at := (
		Transform3D(Basis(), Vector3(-18, 0, -117)) * Transform3D(Basis(), Vector3(0, 0, 1.7))
	)
	_aabb("plane", "res://assets/planes/tp_plane_05a.glb", plane_at)
	for stem in ["tcp_male_character_01", "tcp_female_character_01"]:
		var node: Node3D = load("res://assets/people/%s.glb" % stem).instantiate()
		var player := node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for clip in player.get_animation_list():
			print("MEASURE clip ", stem, " ", clip, " length=", player.get_animation(clip).length)
		print("MEASURE player_path ", stem, " ", node.get_path_to(player))
		node.free()
	quit(0)


func _aabb(label: String, path: String, xform: Transform3D) -> void:
	var node: Node3D = load(path).instantiate()
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var local := _to_root(node, mesh)
		var b: AABB = (xform * local) * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("MEASURE aabb ", label, " pos=", box.position, " end=", box.end)
	node.free()


func _to_root(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D()
	var n: Node = node
	while n != root and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
