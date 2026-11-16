extends SceneTree
## Windowed plate probe for the construction-works props (board ecd67e67, S8b
## phase 1): the six converted props in a row beside the loading truck, at the
## game camera's home distance and close up. It prints each prop's measured size
## and saves plates under tools/blender/out/s8b_assets/godot/; it rules nothing.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/works_props_plates_probe.gd
##
## Boots main.tscn for the game's own sun and environment, stops the clock and the
## plane fleets, hides the HUD and lays the row on its own ground patch at SITE,
## far from the airport, so nothing of the airport stands in a plate. Each plate
## projects every subject's bounds into the viewport with MARGIN_PX and casts
## camera rays at it (trimesh colliders on every mesh) before it is saved; on
## failure it prints PROBE_INVALID and exits 1. Prints the world seed.

const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/s8b_assets/godot"
const WORKS := "res://assets/airside/props/works/"
const TRUCK := "res://assets/vehicles/tp_loading_truck_01a.glb"
const PROPS: Array[String] = [
	"ti_traffic_cone_1b",
	"tc_concrete_barrier_1a",
	"tc_metal_fence_2a",
	"ti_excavator_1a",
	"ti_brick_pile_1c",
	"tfp_dump_trailer_01a",
]
const SITE := Vector3(1500.0, 0.0, 1500.0)
const GAP_M := 1.5
const MARGIN_PX := 8.0
const MIN_RAY_SHARE := 0.25
## The game camera: tycoon_camera.tscn fov 55, home_distance 80 m, angle steps
## 38, 54 and 70 degrees (tycoon_camera.gd STEP_PITCH_DEGREES).
const FOV := 55.0
## name, subjects (keys of _subjects), yaw, pitch, distance.
const PLATES := [
	["works_play_54", ["truck"] + PROPS, 200.0, 54.0, 80.0],
	["works_play_38", ["truck"] + PROPS, 200.0, 38.0, 80.0],
	[
		"works_close_edge",
		["ti_traffic_cone_1b", "tc_concrete_barrier_1a", "tc_metal_fence_2a"],
		210.0,
		30.0,
		13.0
	],
	[
		"works_close_yard",
		["ti_excavator_1a", "ti_brick_pile_1c", "tfp_dump_trailer_01a"],
		205.0,
		35.0,
		24.0
	],
]

var _out_dir := ""
var _failed := false
var _plates := 0
var _main: Node
var _cam: Camera3D
var _subjects := {}


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE world_seed=%d" % world_seed)
	root.add_child(_main)
	clock.set_process(false)
	for fleet in _main.find_children("*", "PlaneFleet", true, false):
		fleet.set_process(false)
	await _frames(6)
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_build_row()
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 2000.0
	_main.add_child(_cam)
	_cam.make_current()
	await _frames(4)
	for plate in PLATES:
		var subjects: Array = plate[1]
		var focus := _focus_of(subjects)
		_aim(focus, plate[2], plate[3], plate[4])
		await _frames(3)
		var ok := true
		for key in subjects:
			ok = _prove(plate[0], key) and ok
		if ok:
			await _save(plate[0] + ".png")
	_finish()


## The truck, then the six props in a row along +x with GAP_M between their
## bounds, each centred on the row line, on a grey ground patch at SITE.
func _build_row() -> void:
	var holder := Node3D.new()
	holder.name = "WorksRow"
	_main.add_child(holder)
	holder.global_position = SITE
	var x := 0.0
	for key in ["truck"] + PROPS:
		var path: String = TRUCK if key == "truck" else WORKS + key + ".glb"
		var packed := load(path) as PackedScene
		if packed == null:
			_invalid("cannot load %s" % path)
			continue
		var node := packed.instantiate() as Node3D
		node.name = key
		holder.add_child(node)
		var box := _aabb_of(node)
		var local := box
		local.position -= node.global_position
		node.position = Vector3(x - local.position.x, 0.0, -local.get_center().z)
		_add_colliders(node)
		_subjects[key] = node
		var placed := _aabb_of(node)
		print(
			(
				"SIZE %s godot_xyz_m=(%.3f, %.3f, %.3f) low_y=%.3f origin_to_box_min=(%.3f, %.3f, %.3f)"
				% [
					key,
					box.size.x,
					box.size.y,
					box.size.z,
					placed.position.y - SITE.y,
					local.position.x,
					local.position.y,
					local.position.z,
				]
			)
		)
		x += box.size.x + GAP_M
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(x + 30.0, 40.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.56, 0.58)
	ground.material_override = mat
	holder.add_child(ground)
	ground.position = Vector3(x / 2.0, -0.01, 0.0)


func _focus_of(keys: Array) -> Vector3:
	var box := AABB()
	var first := true
	for key in keys:
		if not _subjects.has(key):
			continue
		var b := _aabb_of(_subjects[key])
		box = b if first else box.merge(b)
		first = false
	return box.get_center()


func _finish() -> void:
	print("PROBE done failed=%s plates=%d" % [_failed, _plates])
	quit(1 if _failed or _plates == 0 else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


## Puts the camera `distance` from `focus`, `pitch` degrees above it, looking
## at it from yaw `yaw` (0: from the south, looking north).
func _aim(focus: Vector3, yaw: float, pitch: float, distance: float) -> void:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var back := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	_cam.look_at_from_position(focus + back * distance, focus, Vector3.UP)
	print(
		(
			"CAMERA focus=%s yaw=%.0f pitch=%.0f distance=%.1f fov=%.0f"
			% [focus, yaw, pitch, distance, _cam.fov]
		)
	)


## Proves the subject's bounds project inside the viewport with MARGIN_PX, in
## front of the camera, and that camera rays reach it first.
func _prove(label: String, key: String) -> bool:
	if not _subjects.has(key):
		_invalid("%s: %s was not placed" % [label, key])
		return false
	var subject: Node3D = _subjects[key]
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var box := _aabb_of(subject)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var corner := box.get_endpoint(i)
		if _cam.is_position_behind(corner):
			_invalid("%s: %s is behind the camera" % [label, key])
			return false
		var s := _cam.unproject_position(corner)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print(
		(
			"INFRAME %s %s screen=(%.0f,%.0f)-(%.0f,%.0f) height_px=%.0f ok=%s"
			% [label, key, lo.x, lo.y, hi.x, hi.y, hi.y - lo.y, ok]
		)
	)
	if not ok:
		_invalid("%s: %s leaves the viewport" % [label, key])
		return false
	var share := _ray_share(subject)
	print("VISIBLE %s %s share=%.2f (needs %.2f)" % [label, key, share, MIN_RAY_SHARE])
	if share < MIN_RAY_SHARE:
		_invalid("%s: %s is occluded" % [label, key])
		return false
	return true


## Casts rays from the camera at sampled surface points of `subject` and returns
## the share that hit it first.
func _ray_share(subject: Node3D) -> float:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _meshes(subject):
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step := maxi(1, floori(faces.size() / 24.0))
		for i in range(0, faces.size(), step):
			targets.append((mi.global_transform * faces[i]).lerp(centre, 0.05))
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	for t in targets:
		var q := PhysicsRayQueryParameters3D.create(
			_cam.global_position, t + (t - _cam.global_position).normalized() * 0.05
		)
		var hit := space.intersect_ray(q)
		if hit and (hit.collider == subject or subject.is_ancestor_of(hit.collider)):
			hits += 1
	return float(hits) / maxf(1.0, targets.size())


func _save(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(name)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_plates += 1
	print("PLATE saved %s" % path)


func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.mesh != null:
			mi.create_trimesh_collision()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
