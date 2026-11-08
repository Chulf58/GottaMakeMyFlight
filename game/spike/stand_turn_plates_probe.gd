extends SceneTree
## Windowed plate probe for board 13e98b04: a small plane (model 03) and a
## large plane (model 07) through their pushback turn, each drawn by a real
## PlaneView (model_position_at(), the code update_pose() places the model
## with) on its own stand, beside its class's StandEnvelope swing square.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/stand_turn_plates_probe.gd
##
## Builds two Airsides from main.tscn's saved markers, moves each one's stand
## with set_stand() (small at x -40, large at x +40, both under a wall at z 40),
## and poses each plane at FlightPose.pose(PUSHBACK, t) for t in FRAMES. The
## swing squares are drawn as yellow (small) and blue (large) outlines, the wall
## line red, a 1 m white cube sits beside each stand. Plates per frame: a
## top-down orthographic of both stands, and a close top-down of the small one;
## plus a perspective view of both at the mid-turn frame, and a contact sheet.
## Before each plate every plane's drawn mesh bounds are projected and must fall
## inside the viewport with MARGIN_PX, and a ray from the camera to each plane's
## middle must hit nothing first; otherwise PROBE_INVALID is printed and the
## probe exits 1. Prints each plane's drawn corner reach against its square.
## Plates go to tools/blender/out/stand_turn/. Prints the seed.

const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/stand_turn"
const MARGIN_PX := 8.0
const WALL_Z := 40.0
const FRAMES: Array[float] = [0.0, 0.45, 0.65, 0.85, 1.0]
const MID_TURN := 0.65
const SUBJECTS := [
	{"model": "tp_plane_03a", "class": PlaneClasses.SMALL, "x": -40.0, "colour": Color.YELLOW},
	{"model": "tp_plane_07a", "class": PlaneClasses.LARGE, "x": 40.0, "colour": Color.SKY_BLUE},
]
const SHEET_TILE := Vector2i(640, 360)

var _out_dir := ""
var _failed := false
var _world: Node3D
var _views: Array[PlaneView] = []
var _airsides: Array[Airside] = []
var _stands: Array[Dictionary] = []
var _cam: Camera3D
var _plates: Array[String] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var seed_value := randi()
	seed(seed_value)
	print("PROBE out_dir=%s seed=%d" % [_out_dir, seed_value])
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_world = Node3D.new()
	root.add_child(_world)
	_run.call_deferred()


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(400.0, 400.0)
	ground.mesh = plane_mesh
	ground.material_override = _flat(Color(0.35, 0.36, 0.38))
	ground.position = Vector3(0.0, -0.02, 0.0)
	_world.add_child(ground)
	_strip(Vector3(-100.0, 0.05, WALL_Z), Vector3(100.0, 0.05, WALL_Z), Color.RED)
	var markers := _main_markers()
	for subject: Dictionary in SUBJECTS:
		var airside := Airside.new()
		for marker: Marker3D in markers["markers"]:
			airside.add_child(marker.duplicate())
		airside.links = markers["links"]
		_world.add_child(airside)
		# The stand's door sits DOOR_SIDE_M to port of the stand point.
		var stand := StandPlacement.make(1, subject["x"] + StandPlacement.DOOR_SIDE_M, WALL_Z)
		if not airside.set_stand(stand):
			_invalid("set_stand(%s) failed" % [stand])
		_airsides.append(airside)
		_stands.append(stand)
		var swing: Rect2 = StandEnvelope.rects(stand, subject["class"])[0]
		_outline(swing, subject["colour"])
		var cube := MeshInstance3D.new()
		cube.mesh = BoxMesh.new()
		cube.material_override = _flat(Color.WHITE)
		cube.position = Vector3(swing.end.x + 2.0, 0.5, StandPlacement.stand_point(stand).z)
		_world.add_child(cube)
		var view := PlaneView.new()
		view.airside = airside
		_world.add_child(view)
		view.set_process(false)
		view.show_model(subject["model"])
		view.visible = true
		_views.append(view)
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_cam.current = true


func _run() -> void:
	# Built once the root is ready, so each PlaneView._ready() runs on add_child.
	_build_scene()
	await _frames(5)
	for t in FRAMES:
		_pose_all(t)
		_top_down(Rect2(-52.0, -42.0, 128.0, 84.0))
		await _shot("both_t%03d.png" % int(t * 100.0))
		var small_at := StandPlacement.stand_point(_stands[0])
		_top_down(Rect2(small_at.x - 11.0, -17.0, 22.0, 59.0))
		await _shot("small_t%03d.png" % int(t * 100.0), [0])
	_pose_all(MID_TURN)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 50.0
	_cam.look_at_from_position(Vector3(12.0, 90.0, 110.0), Vector3(12.0, 0.0, 0.0))
	await _shot("both_perspective_t%03d.png" % int(MID_TURN * 100.0))
	_contact_sheet()
	quit(1 if _failed else 0)


## Poses every plane `t` through its pushback, as PlaneView.update_pose() does.
func _pose_all(t: float) -> void:
	for i in _views.size():
		var subject: Dictionary = SUBJECTS[i]
		var view := _views[i]
		var path := _airsides[i].phase_path(FlightSim.State.PUSHBACK, "", subject["class"])
		var entry := FlightPose.exit_dir(
			_airsides[i].phase_path(FlightSim.State.TAXI_IN, "", subject["class"])
		)
		view.transform = FlightPose.pose(FlightSim.State.PUSHBACK, t, path, entry)
		view.phase = FlightSim.State.PUSHBACK
		view._set_model_position(
			view.model_position_at(FlightSim.State.PUSHBACK, view.transform, subject["class"])
		)
		var box := _drawn_bounds(view)
		var at := StandPlacement.stand_point(_stands[i])
		var swing: Rect2 = StandEnvelope.rects(_stands[i], subject["class"])[0]
		var reach := maxf(absf(box.position.x - at.x), absf(box.end.x - at.x))
		print(
			(
				(
					"t %.2f %s: drawn x %.2f..%.2f z %.2f..%.2f, reach %.2f of half-size %.2f,"
					+ " north edge %.2f vs square %.2f"
				)
				% [
					t,
					subject["model"],
					box.position.x,
					box.end.x,
					box.position.z,
					box.end.z,
					reach,
					swing.size.x / 2.0,
					box.position.z,
					swing.position.y,
				]
			)
		)


## Points the camera straight down so it frames `area` (world x, z) whole at
## the viewport's own aspect, north up.
func _top_down(area: Rect2) -> void:
	var view := root.get_visible_rect().size
	var centre := Vector3(area.get_center().x, 0.0, area.get_center().y)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = maxf(area.size.y, area.size.x * view.y / view.x)
	_cam.look_at_from_position(centre + Vector3(0.0, 150.0, 0.0), centre, Vector3.FORWARD)
	print("top-down over %s, size %.1f m, viewport %s" % [area, _cam.size, view])


func _shot(file: String, which: Array = [0, 1]) -> void:
	await _frames(3)
	var size := Vector2(root.get_visible_rect().size)
	var space := _world.get_world_3d().direct_space_state
	for i: int in which:
		var box := _drawn_bounds(_views[i])
		for k in 8:
			var corner := box.get_endpoint(k)
			var screen := _cam.unproject_position(corner)
			var inside := (
				not _cam.is_position_behind(corner)
				and screen.x >= MARGIN_PX
				and screen.y >= MARGIN_PX
				and screen.x <= size.x - MARGIN_PX
				and screen.y <= size.y - MARGIN_PX
			)
			if not inside:
				_invalid(
					"%s: %s corner %s at screen %s" % [file, SUBJECTS[i]["model"], corner, screen]
				)
		var middle := box.get_center()
		var origin := _cam.project_ray_origin(_cam.unproject_position(middle))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, middle))
		print(
			(
				"%s: %s middle %s at screen %s, first hit %s"
				% [file, SUBJECTS[i]["model"], middle, _cam.unproject_position(middle), hit]
			)
		)
		if not hit.is_empty():
			_invalid("%s: %s hidden behind %s" % [file, SUBJECTS[i]["model"], hit["collider"]])
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	_plates.append(path)
	print("PLATE saved %s size=%s" % [path, img.get_size()])


## The world bounds of every mesh `view` draws (its model, not the silhouette).
func _drawn_bounds(view: PlaneView) -> AABB:
	var out := AABB()
	var first := true
	var pivot := view.get_node("Pivot")
	for mesh: MeshInstance3D in pivot.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.global_transform * mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _contact_sheet() -> void:
	var columns := 3
	var rows := ceili(float(_plates.size()) / columns)
	var sheet := Image.create(
		SHEET_TILE.x * columns, SHEET_TILE.y * rows, false, Image.FORMAT_RGBA8
	)
	for i in _plates.size():
		var img := Image.load_from_file(_plates[i])
		img.convert(Image.FORMAT_RGBA8)
		img.resize(SHEET_TILE.x, SHEET_TILE.y)
		var at := Vector2i(i % columns, i / columns) * SHEET_TILE
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, SHEET_TILE), at)
	var path := _out_dir.path_join("contact_sheet.png")
	if sheet.save_png(path) != OK:
		_invalid("could not save %s" % path)
	print("SHEET saved %s with %d plates" % [path, _plates.size()])


## main.tscn's Airside markers and links, read from its saved state.
func _main_markers() -> Dictionary:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	var markers: Array[Marker3D] = []
	var links: Variant = null
	for i in state.get_node_count():
		var parent := String(state.get_node_path(i, true))
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		if parent == "./Airside" and state.get_node_type(i) == &"Marker3D":
			var marker := Marker3D.new()
			marker.name = state.get_node_name(i)
			marker.transform = props.get(&"transform", Transform3D.IDENTITY)
			markers.append(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			links = props[&"links"]
	return {"markers": markers, "links": links}


func _outline(rect: Rect2, colour: Color) -> void:
	var a := Vector3(rect.position.x, 0.06, rect.position.y)
	var b := Vector3(rect.end.x, 0.06, rect.position.y)
	var c := Vector3(rect.end.x, 0.06, rect.end.y)
	var d := Vector3(rect.position.x, 0.06, rect.end.y)
	for pair in [[a, b], [b, c], [c, d], [d, a]]:
		_strip(pair[0], pair[1], colour)


## A flat 0.4 m wide strip from `from` to `to`.
func _strip(from: Vector3, to: Vector3, colour: Color) -> void:
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	var length := from.distance_to(to)
	box.size = Vector3(0.4, 0.05, length)
	strip.mesh = box
	strip.material_override = _flat(colour)
	_world.add_child(strip)
	strip.look_at_from_position((from + to) / 2.0, to, Vector3.UP)


func _flat(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	# A headless run (a logic check only) never draws, so it never posts a frame.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
