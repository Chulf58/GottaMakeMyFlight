extends SceneTree
## Windowed Vulkan plate probe for the airfield visual overhaul.
## Boots main.tscn with a random seed, verifies framing (camera.unproject_position)
## and occlusion (raycast), and writes 4 plates to tools/blender/out/airfield_overhaul/:
##   1. godot_overview.png (pulled-back gameplay camera view across terminal + airfield)
##   2. godot_runway_tower_hangars.png (runway markings, tire wear, tower, hangars, windsock, PAPI)
##   3. godot_taxiway_shoulders_lights.png (taxiway shoulders, double-yellow lines, blue lights)
##   4. godot_dusk_lights.png (dusk lighting showcasing glowing airfield/tower/GSE lights)
##
## Run (one windowed Godot slot project-wide):
##   tools/godot.sh --display-driver windows --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/airfield_overhaul_plates_probe.gd

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/airfield_overhaul"
const MARGIN_PX := 8.0

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate() as Node3D
	var clock: SimClock = _main.get_node("SimClock")
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE world_seed=%d" % world_seed)
	root.add_child(_main)
	clock.set_process(false)
	await _frames(6)

	var build_mode := _main.get_node("BuildMode") as BuildMode
	StarterFlight.add_gate_desk(build_mode.grid)
	await _frames(6)

	var hud := _main.find_child("PassengerHud", true, false) as CanvasLayer
	if hud != null:
		hud.visible = false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false

	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 1600.0
	_main.add_child(_cam)
	_cam.make_current()
	_add_colliders(_main)
	await _frames(4)

	# 1. Overview from gameplay-like camera angle looking north across terminal and airfield.
	await _shoot(
		"godot_overview.png",
		Vector3(-10.0, 145.0, 20.0),
		Vector3(-10.0, 4.0, -280.0),
		[
			Vector3(-92.0, 52.5, -422.0),
			Vector3(12.0, 18.8, -422.0),
			Vector3(96.0, 21.8, -428.0),
			Vector3(0.0, 0.4, -338.0),
			Vector3(-26.0, 0.4, -284.0),
		]
	)

	# 2. Close-up of runway markings, tire wear, control tower, radar, hangars, windsock & PAPI.
	await _shoot(
		"godot_runway_tower_hangars.png",
		Vector3(-25.0, 58.0, -225.0),
		Vector3(-12.0, 10.0, -405.0),
		[
			Vector3(-92.0, 52.5, -422.0),
			Vector3(-126.0, 24.8, -415.0),
			Vector3(12.0, 18.8, -422.0),
			Vector3(96.0, 21.8, -428.0),
			Vector3(-56.0, 7.0, -390.0),
			Vector3(-108.0, 0.6, -373.5),
		]
	)

	# 3. Close-up of taxiway shoulders, double-yellow lines, blue edge lights & apron markings.
	await _shoot(
		"godot_taxiway_shoulders_lights.png",
		Vector3(-70.0, 42.0, -185.0),
		Vector3(-25.0, 0.2, -285.0),
		[
			Vector3(-26.0, 0.4, -284.0),
			Vector3(-10.35, 0.4, -250.0),
			Vector3(-41.65, 0.4, -250.0),
		]
	)

	# 4. Dusk lighting shot showing glowing blue, white, amber, red/green edge lights & tower.
	var sun := _main.get_node("Sun") as DirectionalLight3D
	var world_env := _main.get_node("WorldEnvironment") as WorldEnvironment
	var prev_energy := sun.light_energy
	var prev_color := sun.light_color
	var prev_amb := world_env.environment.ambient_light_energy
	sun.light_energy = 0.16
	sun.light_color = Color(0.85, 0.55, 0.42)
	world_env.environment.ambient_light_energy = 0.22
	await _shoot(
		"godot_dusk_lights.png",
		Vector3(-45.0, 52.0, -205.0),
		Vector3(-20.0, 10.0, -355.0),
		[
			Vector3(-92.0, 52.5, -422.0),
			Vector3(-108.0, 0.6, -373.5),
			Vector3(0.0, 0.6, -305.4),
			Vector3(-26.0, 0.4, -284.0),
		]
	)
	sun.light_energy = prev_energy
	sun.light_color = prev_color
	world_env.environment.ambient_light_energy = prev_amb

	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _shoot(filename: String, eye: Vector3, target: Vector3, subjects: Array[Vector3]) -> void:
	_cam.look_at_from_position(eye, target, Vector3.UP)
	await _frames(4)
	var rect := root.get_visible_rect()
	var space := _main.get_world_3d().direct_space_state
	var ok := true
	for pt in subjects:
		if _cam.is_position_behind(pt):
			_invalid("%s subject %s is behind camera" % [filename, pt])
			ok = false
		var uv := _cam.unproject_position(pt)
		print("PROBE %s unproject %s -> (%.1f, %.1f)" % [filename, pt, uv.x, uv.y])
		if (
			uv.x < MARGIN_PX
			or uv.y < MARGIN_PX
			or uv.x > rect.size.x - MARGIN_PX
			or uv.y > rect.size.y - MARGIN_PX
		):
			_invalid("%s subject %s outside viewport margin: %s" % [filename, pt, uv])
			ok = false
		var q := PhysicsRayQueryParameters3D.create(eye, pt + (eye - pt).normalized() * 0.5)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var hit_pos: Vector3 = hit["position"]
			if hit_pos.distance_to(pt) > 2.5:
				_invalid("%s occlusion hit=%s near=%s" % [filename, hit_pos, pt])
				ok = false
	if not ok:
		return
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join(filename)
	var err := img.save_png(path)
	if err != OK:
		_invalid("failed to save %s err=%d" % [path, err])
	else:
		print("PROBE saved %s" % path)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _add_colliders(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var mi := child as MeshInstance3D
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			shape.shape = mi.mesh.create_trimesh_shape()
			body.add_child(shape)
			mi.add_child(body)
		_add_colliders(child)
