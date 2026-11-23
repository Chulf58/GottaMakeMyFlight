extends SceneTree
## Windowed Vulkan plate probe for the Living Operations Apron.
## Boots main.tscn with a random seed, verifies framing (camera.unproject_position)
## and occlusion (raycast), and writes 4 plates to tools/blender/out/hangar_life/:
##   1. 01_apron_overview.png (operations apron overview: tower, radar, hangars, vehicles, plane)
##   2. 02_hangar_plane_mechanics_t1.png (parked plane, 6 cones, tug, bay glow, mechanics at t1)
##   3. 03_tower_radar_beacons.png (tower, rotating radar dish, beacons, windsock, west pickup)
##   4. 04_apron_motion_t2.png (same apron after advancing SimClock proving motion & cycle)
##
## Run (one windowed Godot slot project-wide):
##   tools/godot.sh --display-driver windows --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/airfield_hangar_life_plate_probe.gd

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/hangar_life"
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
	await _frames(6)

	var build_mode := _main.get_node("BuildMode") as BuildMode
	StarterFlight.add_gate_desk(build_mode.grid)
	await _frames(4)

	clock.set_paused(true)
	clock.set_process(false)
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false

	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 1600.0
	_main.add_child(_cam)
	_cam.make_current()
	_add_colliders(_main)
	await _frames(4)

	var life := _main.find_child("OperationsLife", true, false) as AirfieldOperationsLife
	if life == null:
		_invalid("OperationsLife node missing")
		quit(1)
		return
	var pickup := life.get_node("PatrolVehicles/WestApronPickup") as Node3D
	var truck := life.get_node("PatrolVehicles/EastApronTruck") as Node3D
	var mech0 := life.get_node("Mechanics/MechanicPortWing") as Node3D
	var mech1 := life.get_node("Mechanics/MechanicStarboardWing") as Node3D
	var dish := _main.find_child("RadarDishPivot", true, false) as Node3D
	var p_t1 := pickup.global_position
	var t_t1 := truck.global_position
	var m0_t1 := mech0.global_position
	var m1_t1 := mech1.global_position
	var dish_yaw_t1 := dish.rotation.y if dish != null else 0.0

	# 1. Back operations apron overview.
	await _shoot(
		"01_apron_overview.png",
		Vector3(0.0, 72.0, -252.0),
		Vector3(0.0, 4.0, -416.0),
		[
			Vector3(-91.73, 51.90, -440.36),
			Vector3(-126.0, 24.55, -415.0),
			Vector3(12.0, 18.45, -391.5),
			Vector3(96.0, 2.0, -397.5),
			pickup.global_position + Vector3(0.0, 1.0, 0.0),
			truck.global_position + Vector3(0.0, 1.5, 0.0),
		]
	)

	# 2. Close-up of parked maintenance plane, 6 cones, tug, warm bay glow, and mechanics at t1.
	await _shoot(
		"02_hangar_plane_mechanics_t1.png",
		Vector3(122.0, 18.0, -366.0),
		Vector3(94.0, 2.0, -402.0),
		[
			Vector3(96.0, 1.5, -397.5),
			Vector3(105.4, 0.5, -397.5),
			Vector3(86.6, 0.5, -397.5),
			Vector3(110.8, 0.8, -391.6),
			mech0.global_position + Vector3(0.0, 1.0, 0.0),
			mech1.global_position + Vector3(0.0, 1.0, 0.0),
		]
	)

	# 3. Close-up of control tower, radar dish, beacons, windsock, and West apron pickup.
	await _shoot(
		"03_tower_radar_beacons.png",
		Vector3(-42.0, 34.0, -342.0),
		Vector3(-84.0, 14.0, -418.0),
		[
			Vector3(-91.73, 51.90, -440.36),
			Vector3(-126.0, 24.55, -415.0),
			Vector3(-56.0, 6.2, -390.0),
			pickup.global_position + Vector3(0.0, 1.0, 0.0),
		]
	)

	# Advance SimClock by 5.5 s in bounded steps and capture t2 proof shot.
	clock.set_paused(false)
	for _i in 22:
		clock.advance(0.25)
	clock.set_paused(true)
	life.sync_to_clock()
	await _frames(4)

	var d_pickup := pickup.global_position.distance_to(p_t1)
	var d_truck := truck.global_position.distance_to(t_t1)
	var d_m0 := mech0.global_position.distance_to(m0_t1)
	var d_m1 := mech1.global_position.distance_to(m1_t1)
	var d_dish := absf(dish.rotation.y - dish_yaw_t1) if dish != null else 0.0
	print(
		(
			"PROBE motion t1->t2 pickup=%.2fm truck=%.2fm mech0=%.2fm mech1=%.2fm radar=%.2frad"
			% [d_pickup, d_truck, d_m0, d_m1, d_dish]
		)
	)
	if d_pickup < 1.0 or d_truck < 1.0:
		_invalid("Patrol vehicles failed to move between t1 and t2")
	if d_m0 < 0.5 and d_m1 < 0.5:
		_invalid("Mechanics failed to move between t1 and t2")
	if d_dish < 1.0:
		_invalid("Radar dish failed to rotate between t1 and t2")

	await _shoot(
		"04_apron_motion_t2.png",
		Vector3(128.0, 22.0, -356.0),
		Vector3(92.0, 2.0, -404.0),
		[
			Vector3(96.0, 1.5, -397.5),
			mech0.global_position + Vector3(0.0, 1.0, 0.0),
			mech1.global_position + Vector3(0.0, 1.0, 0.0),
			truck.global_position + Vector3(0.0, 1.5, 0.0),
		]
	)

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
