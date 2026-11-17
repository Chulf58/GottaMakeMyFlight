extends SceneTree
## Look-consistency contact sheets (board item look-consistency-pass-from-the-
## slotbound-breakdown-user-pick): one windowed run that plates every placeable
## piece, person, world model, HUD panel, in-world caption and icon set, so a
## reader can find what does not fit the Toon Series look. Evidence only; it
## changes nothing in the game.
##
## Pass A, studio: the main scene's sky, sun and ground, a perspective camera at
## the game's MEDIUM pitch (TycoonCamera.STEP_PITCH_DEGREES[1], 54 degrees) and
## a 3/4 yaw, fitted to the subject and a 1 m cube beside it. Pieces are the
## BuildCatalog ids drawn by BuildView.make_object_node, the wall kit pieces,
## the landside parking models and every other interior kit glb; people are the
## passenger bodies (PassengerLooks.SCENES) and the staff suits
## (StaffCharacters.CHARACTERS); world is vehicles, planes, airside props and
## works, runways, buildings, mess and the crow. Each subject proves its bounds
## project inside the viewport and that at least half of the camera rays to its
## camera-facing triangles hit it first (colliders on the subject, the cube and
## the ground), or the probe prints PROBE_INVALID. A control first proves the
## ray test fails behind a wall. The pass ends with a caption font plate: a
## Label3D in the engine default font beside one in Nunito and a HUD Label.
##
## Pass B, the real game: main.tscn with a new random seed (printed; replay
## with -- --seed=N), clock paused, isolated settings files. Plates the intro,
## the incidents question, the start view, every build-menu category tray, the
## Offers and Runway sheets, the alert rail with a flight result, the game menu
## and its settings, the checklist, the staff card, the departures list, the
## inspect card and the debug panel, each panel's rect asserted inside the
## view. In-world captions (Label3D and Sprite3D markers) are plated with the
## HUD layers hidden, at a mid zoom, once with the starter terminal unstaffed
## (closed-desk signs, room labels) and once with flights running and the mood
## overlay on hunger (need icons and clusters).
##
## Pass C: the bar SVG icons, the MarkerIcons glyphs and the build-menu
## thumbnails on HUD cards.
##
## Contact sheets carry a Nunito label per tile (ui/hud_theme.tres). Each tile is
## also saved on its own under tiles/<sheet>/.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 1500 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/look_pass_probe.gd
##
## Plates go to tools/blender/out/look_pass/ in the main checkout, also when the
## probe runs from a worktree under .claude/worktrees/.

const IntroClose := preload("res://spike/intro_close.gd")
const OUT_SUB := "tools/blender/out/look_pass"
const MAIN_SCENE := "res://main/main.tscn"
const HUD_THEME := preload("res://ui/hud_theme.tres")
const GLASS := "res://assets/materials/tp_glass.tres"
const WINDOW := Vector2i(1920, 1080)
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 150000
const YAW_DEG := 45.0
const FOV := 55.0
## The in-world caption plates' camera distance: a mid zoom, well inside the
## 300 m where the toon outline fades out (decision toon-outline-thins-with-
## camera-distance-and-fades-out-at-ful).
const CAPTION_DISTANCE := 30.0
const CAPTION_LIMIT := 14
const SIM_LIMIT_MS := 90000
const SETTINGS := "user://look_pass_probe_settings.cfg"
const HINTS_MEMORY := "user://look_pass_probe_hints.cfg"
const SHEET_TILE := Vector2i(400, 225)
const HUD_TILE := Vector2i(480, 270)
const ICON_TILE := Vector2i(128, 128)
const STRUCTURE := ["floor_tile", "wall", "wall_glass", "wall_door", "wall_post"]
const LANDSIDE := ["landside/tp_parking_01a", "landside/tc_parking_2a", "landside/tp_curb_bay_01a"]
const VEHICLES := [
	"tp_loading_truck_01a",
	"tp_suv_01a",
	"tp_suv_01b",
	"tp_suv_01c",
	"tp_taxi_01a",
	"tp_taxi_01b",
	"tp_taxi_01c",
	"tp_van_01a",
]
const WORLD_DIRS := [
	"res://assets/planes",
	"res://assets/airside/props",
	"res://assets/airside/props/works",
	"res://assets/airside",
	"res://assets/buildings",
	"res://assets/mess",
	"res://assets/birds",
]
const CAUSES := [
	["queue_a", "Check-in queue full", "1 desk full: open another desk or hire staff"],
	["route_b", "No route for 3 passengers", "They cannot walk to check-in: join the floor"],
	["gate_c", "Gate seats full", "12 passengers stand at gate C: add seats"],
	["more_d", "Security queue full", "1 lane full: open another lane"],
]
const FLIGHTS := [
	["W1", 13 * 60 + 40, "Rome", "Sunhop"],
	["W2", 17 * 60, "Berlin", "Nordic Wing"],
	["W3", 20 * 60 + 20, "Lisbon", "Sunhop"],
]
const HOLD := 1_000_000_000

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _studio: Node3D
var _holder: Node3D
var _cam: Camera3D
var _main: Node
var _hud: PassengerHud
var _menu: BuildMenu
var _staff: StaffPanel
var _stack: AlertStack
var _causes: Array[Dictionary] = []
## Sheet name -> Array of {"name": String, "path": String}.
var _sheets := {
	"pieces": [],
	"people": [],
	"world": [],
	"hud": [],
	"icons": [],
}
var _caption_kinds := {}
var _skipped: Array[String] = []


func _initialize() -> void:
	var probe_seed := IntroClose.seed_or_random()
	seed(probe_seed)
	print("PROBE seed=", probe_seed)
	var res_root := ProjectSettings.globalize_path("res://").simplify_path()
	var repo := res_root.get_base_dir()
	if "/.claude/worktrees/" in repo:
		repo = repo.get_slice("/.claude/worktrees/", 0)
	_out_dir = repo.path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


## Guard thread: a frozen main thread never reaches _process, so check from here.
func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle_ms])
			OS.crash("look pass probe hung")


func _run() -> void:
	var start := Time.get_ticks_msec()
	DisplayServer.window_set_size(WINDOW)
	await _frames(6)
	print("PROBE window=%s layout=%s" % [root.size, root.get_visible_rect().size])
	await _pass_a()
	print("PROBE pass_a_ms=%d" % (Time.get_ticks_msec() - start))
	await _pass_b()
	print("PROBE pass_b_ms=%d" % (Time.get_ticks_msec() - start))
	await _pass_c()
	_clean_files()
	for sheet in _sheets:
		print("PROBE sheet %s tiles=%d" % [sheet, _sheets[sheet].size()])
	for line in _skipped:
		print("PROBE skipped ", line)
	print("PROBE elapsed_ms=%d" % (Time.get_ticks_msec() - start))
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		if _hud != null and is_instance_valid(_hud):
			_hud.refresh()
		await process_frame
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Saves a tile under tiles/<sheet>/ and lists it on that sheet.
func _keep(sheet: String, label: String, img: Image) -> void:
	var dir := _out_dir.path_join("tiles").path_join(sheet)
	DirAccess.make_dir_recursive_absolute(dir)
	var file := label.to_lower().replace(" ", "_").replace("/", "_").validate_filename()
	var path := dir.path_join("%02d_%s.png" % [_sheets[sheet].size(), file])
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE %s saved %s size=%s" % [sheet, path, img.get_size()])
	_sheets[sheet].append({"name": label, "path": path})


# ------------------------------------------------------------ pass A: studio


func _pass_a() -> void:
	_beat("a_studio")
	_studio = _make_studio()
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 5000.0
	_studio.add_child(_cam)
	_cam.make_current()
	await _occlusion_control()
	for spec in _piece_specs():
		await _plate_subject("pieces", spec[0], spec[1])
	for scene in PassengerLooks.SCENES:
		await _plate_subject(
			"people", _base(scene.resource_path), _scene_maker(scene.resource_path)
		)
	var staff_names := ["staff check-in agent", "staff officer", "staff shop", "staff cleaner"]
	var seen := {}
	for i in StaffCharacters.CHARACTERS.size():
		var path := StaffCharacters.CHARACTERS[i].resource_path
		if seen.has(path):
			continue
		seen[path] = true
		await _plate_subject("people", "%s %s" % [staff_names[i], _base(path)], _scene_maker(path))
	for spec in _world_specs():
		await _plate_subject("world", spec[0], spec[1])
	await _font_plate()
	await _need_icon_plate()
	_studio.queue_free()
	_studio = null
	await _frames(4)


func _make_studio() -> Node3D:
	var studio := Node3D.new()
	studio.name = "LookStudio"
	# main.tscn's look: procedural sky, sky ambient, filmic tonemap, its sun.
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(
		Basis(
			Vector3(0.866025, 0, -0.5),
			Vector3(-0.353553, 0.707107, -0.612372),
			Vector3(0.353553, 0.707107, 0.612372)
		),
		Vector3(0, 20, 0)
	)
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 410.0
	studio.add_child(sun)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400, 2400)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.5, 0.3)
	mat.roughness = 1.0
	ground.material_override = mat
	# main.tscn sets its ground 0.1 m down; flat parking pieces sit just under 0.
	ground.position.y = -0.1
	studio.add_child(ground)
	root.add_child(studio)
	_add_colliders(ground)
	_holder = Node3D.new()
	_holder.name = "Holder"
	studio.add_child(_holder)
	return studio


func _base(path: String) -> String:
	return path.get_file().get_basename()


func _scene_maker(path: String) -> Callable:
	return func() -> Node3D: return (load(path) as PackedScene).instantiate()


## [label, maker] for every placeable: the catalog ids as the game draws them,
## the wall kit, the landside parking models, then each interior kit glb no
## catalog id or wall piece uses.
func _piece_specs() -> Array:
	var out := []
	var used := {}
	for id in BuildCatalog.ids():
		var def := BuildCatalog.get_def(id)
		out.append([str(id), func() -> Node3D: return BuildView.make_object_node(def, null)])
		used[InteriorKit.object_piece(id)] = true
	for piece in STRUCTURE:
		used[piece] = true
		out.append([piece, _scene_maker(InteriorKit.piece_path(piece))])
	for piece in LANDSIDE:
		out.append([_base(piece), _scene_maker(InteriorKit.piece_path(piece))])
	print("PROBE catalog_ids=%d" % BuildCatalog.ids().size())
	for file in _glbs("res://assets/interior"):
		if not used.has(file.get_basename()):
			out.append(
				["kit part " + file.get_basename(), _scene_maker("res://assets/interior/" + file)]
			)
	return out


func _world_specs() -> Array:
	var out := []
	for v in VEHICLES:
		out.append([v, _scene_maker("res://assets/vehicles/%s.glb" % v)])
	for dir in WORLD_DIRS:
		for file in _glbs(dir):
			out.append([file.get_basename(), _scene_maker(dir.path_join(file))])
	return out


func _glbs(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".glb"):
			out.append(file)
	out.sort()
	return out


## The 3/4 camera at the MEDIUM player pitch, back far enough that the box's
## bounding sphere fits the vertical field of view.
func _aim(box: AABB) -> void:
	var pitch := deg_to_rad(TycoonCamera.STEP_PITCH_DEGREES[TycoonCamera.AngleStep.MEDIUM])
	var yaw := deg_to_rad(YAW_DEG)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var r := maxf(box.size.length() / 2.0, 0.5)
	var dist := r / sin(deg_to_rad(FOV / 2.0)) * 1.04
	_cam.near = clampf(dist - r * 1.5, 0.05, 10.0)
	_cam.look_at_from_position(box.get_center() + dir * dist, box.get_center(), Vector3.UP)


func _plate_subject(sheet: String, label: String, make: Callable) -> void:
	_beat("a_%s_%s" % [sheet, label])
	var node: Node3D = make.call()
	if node == null:
		_invalid("%s: %s did not instantiate" % [sheet, label])
		return
	_holder.add_child(node)
	_pose(node)
	await _frames(2)
	var box := _aabb_of(node)
	# A model whose bottom dips under y 0 is lifted onto the studio floor, so the
	# floor cannot hide it; the lift is printed.
	if box.position.y < 0.0:
		print("LIFT %s/%s by %.3f m" % [sheet, label, -box.position.y])
		node.position.y -= box.position.y
		box = _aabb_of(node)
	if box.size.length() < 0.01:
		_invalid("%s: %s has no mesh bounds" % [sheet, label])
		_clear_holder()
		return
	# On the far side from the 3/4 camera (it sits toward +x +z), so the cube never
	# hides a small subject.
	var cube := _cube(_holder, Vector3(box.position.x - 0.9, 0.5, box.get_center().z))
	var whole := box.merge(_aabb_of(cube))
	print(
		(
			"MEASURE %s/%s size_m=(%.2f, %.2f, %.2f) min_y=%.3f"
			% [sheet, label, box.size.x, box.size.y, box.size.z, box.position.y]
		)
	)
	_add_colliders(_holder)
	await physics_frame
	await physics_frame
	_aim(whole)
	await _frames(3)
	var tag := "%s/%s" % [sheet, label]
	if _prove_in_frame(tag, _corners(whole)) and _prove_visible(tag, node, true):
		_keep(sheet, label, await _grab())
	_clear_holder()
	await _frames(1)


func _clear_holder() -> void:
	for child in _holder.get_children():
		child.queue_free()


## Idle, held at its first frame; a model without an idle clip holds the first
## clip it has.
func _pose(node: Node) -> void:
	for player in node.find_children("*", "AnimationPlayer", true, false):
		var p := player as AnimationPlayer
		var names := p.get_animation_list()
		if names.is_empty():
			continue
		var clip: String = "idle" if p.has_animation("idle") else names[0]
		p.play(clip)
		p.seek(0.0, true)
		p.pause()


func _cube(parent: Node, pos: Vector3) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	cube.material_override = mat
	cube.position = pos
	cube.name = "ReferenceCube1m"
	parent.add_child(cube)
	return cube


## A control for the ray test: a crate behind a wall facing the camera must fail
## it, and the same crate in the open must pass it, or the test cannot see.
func _occlusion_control() -> void:
	_beat("a_control")
	var crate := _cube(_holder, Vector3(0, 0.5, 0))
	var box := _aabb_of(crate)
	_aim(box)
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(6, 6, 0.2)
	wall.mesh = wall_mesh
	_holder.add_child(wall)
	wall.global_position = box.get_center().lerp(_cam.global_position, 0.5)
	wall.look_at(_cam.global_position, Vector3.UP)
	_add_colliders(_holder)
	await physics_frame
	await physics_frame
	var blocked := _prove_visible("control_blocked", crate, false)
	wall.queue_free()
	await physics_frame
	await physics_frame
	await physics_frame
	var open := _prove_visible("control_open", crate, false)
	print("PROBE control blocked_pass=%s open_pass=%s" % [blocked, open])
	if blocked or not open:
		_invalid("the occlusion control did not split: blocked=%s open=%s" % [blocked, open])
	_clear_holder()
	await _frames(2)


## A caption in the engine default font (the game's Label3D captions set no
## font) beside the same caption in the HUD theme's Nunito, and a HUD Label.
func _font_plate() -> void:
	_beat("a_font")
	var texts := ["Default font: Gate A  Check-in 3", "Nunito: Gate A  Check-in 3"]
	var labels: Array[Label3D] = []
	for i in 2:
		var label := Label3D.new()
		label.text = texts[i]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 64
		label.outline_size = 12
		label.pixel_size = 0.02
		if i == 1:
			label.font = HUD_THEME.default_font
		label.position = Vector3(0, 3.0 - i * 2.0, 0)
		_holder.add_child(label)
		labels.append(label)
	var points: Array[Vector3] = [labels[0].position, labels[1].position]
	_aim(AABB(Vector3(-6, 0, -1), Vector3(12, 4, 2)))
	var layer := CanvasLayer.new()
	var hud_label := Label.new()
	hud_label.theme = HUD_THEME
	hud_label.text = "HUD Label (hud_theme.tres): Gate A  Check-in 3"
	hud_label.position = Vector2(40, 40)
	layer.add_child(hud_label)
	_holder.add_child(layer)
	await _frames(4)
	if _prove_in_frame("font_compare", points):
		_keep("hud", "caption fonts default vs Nunito", await _grab())
	_clear_holder()
	await _frames(1)


## The need icons and a count badge as the game makes them (NeedIcons.make_sprite,
## NeedCluster.make_badge), over a passenger body at a mid zoom. In the real game
## they show only for needs a built facility answers (NeedIcons.provided), and
## the starter terminal answers none, so the studio is where they are plated.
func _need_icon_plate() -> void:
	_beat("a_need_icons")
	var body := (PassengerLooks.SCENES[0] as PackedScene).instantiate() as Node3D
	_holder.add_child(body)
	_pose(body)
	var needs := NeedIcons.Need.values()
	for i in needs.size():
		var sprite := NeedIcons.make_sprite("Need%d" % i)
		sprite.texture = NeedIcons.texture(needs[i])
		sprite.offset = NeedIcons.offset_of(i, needs.size())
		sprite.visible = true
		body.add_child(sprite)
	var badge := NeedCluster.make_badge()
	badge.texture = NeedIcons.texture(NeedIcons.Need.HUNGER)
	badge.visible = true
	badge.position = Vector3(1.6, NeedIcons.LIFT_M, 0.0)
	for part in badge.find_children("*", "", true, false):
		if part is Label3D:
			(part as Label3D).text = "6"
		if part is Node3D:
			(part as Node3D).visible = true
	_holder.add_child(badge)
	var box := AABB(Vector3(-1.5, 0, -1.5), Vector3(4.5, NeedIcons.LIFT_M + 1.0, 3))
	var pitch := deg_to_rad(TycoonCamera.STEP_PITCH_DEGREES[TycoonCamera.AngleStep.MEDIUM])
	var yaw := deg_to_rad(YAW_DEG)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_cam.look_at_from_position(box.get_center() + dir * 18.0, box.get_center(), Vector3.UP)
	await _frames(4)
	var points: Array[Vector3] = [body.global_position, badge.global_position]
	points.append(body.global_position + Vector3(0, NeedIcons.LIFT_M, 0))
	if _prove_in_frame("need_icons", points):
		_keep("hud", "need icons and count badge (studio)", await _grab())
	_clear_holder()
	await _frames(1)


# ------------------------------------------------------------ geometry and proof


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


## Local triangles of a mesh's opaque surfaces (glass is left out).
func _opaque_faces(mi: MeshInstance3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	if mi.mesh == null:
		return faces
	var mesh := _posed_mesh(mi)
	for i in mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat != null and mat.resource_path == GLASS:
			continue
		var kind := Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			kind = (mesh as ArrayMesh).surface_get_primitive_type(i)
		if kind != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			index = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			faces.append_array(verts)
		else:
			for k in index:
				faces.append(verts[k])
	return faces


## The mesh as drawn: a skinned mesh baked in its current skeleton pose, a mesh
## with blend shapes baked at its current mix (a pulled roller stretches its
## rods), else the mesh itself.
func _posed_mesh(mi: MeshInstance3D) -> Mesh:
	if mi.skin != null or not mi.skeleton.is_empty():
		var baked := mi.bake_mesh_from_current_skeleton_pose()
		if baked != null:
			return baked
	if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
		var mixed := mi.bake_mesh_from_current_blend_shape_mix()
		if mixed != null:
			return mixed
	return mi.mesh


## A static body per visible mesh with a trimesh of its opaque surfaces; meshes
## hidden in the tree get none (anti-pattern plate-probe-colliders-on-hidden-
## meshes-block-occlusion-rays).
func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if not mi.is_visible_in_tree() or mi.has_meta("look_body"):
			continue
		var faces := _opaque_faces(mi)
		if faces.is_empty():
			continue
		# World space on a top-level body: a model node scaled flat (a painted bay
		# has y scale 0) would give a body with a singular transform, which rays miss.
		faces = _with_depth(mi.global_transform * faces)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.add_child(shape_node)
		mi.add_child(body)
		body.top_level = true
		body.global_transform = Transform3D.IDENTITY
		mi.set_meta("look_body", body)


## A flat set of faces gets a copy 1 cm under it, so the shape has some depth;
## the drawn surface does not move.
func _with_depth(faces: PackedVector3Array) -> PackedVector3Array:
	var lo := INF
	var hi := -INF
	for p in faces:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	if hi - lo > 0.01:
		return faces
	var out := faces.duplicate()
	for p in faces:
		out.append(p - Vector3(0, 0.01, 0))
	return out


## Every point projects inside the viewport with a margin, and none is behind
## the camera.
func _prove_in_frame(label: String, points: Array[Vector3]) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		if _cam.is_position_behind(p):
			_invalid("%s: point %s is behind the camera" % [label, p])
			return false
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := rect.has_point(lo) and rect.has_point(hi)
	print("INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s" % [label, lo.x, lo.y, hi.x, hi.y, ok])
	if not ok:
		_invalid("%s: projected bounds leave the viewport" % label)
	return ok


## Rays from the camera to points on the subject's opaque camera-facing
## triangles; at least half must hit the subject first. Godot front faces wind
## clockwise, so a triangle faces the camera when its (b - a) x (c - a) normal
## points away from it. `strict` false reports without failing (the control).
func _prove_visible(label: String, subject: Node3D, strict: bool) -> bool:
	var targets: Array[Vector3] = []
	var centre := _aabb_of(subject).get_center()
	for mi in _meshes(subject):
		if not mi.is_visible_in_tree():
			continue
		var faces := _opaque_faces(mi)
		var facing: Array[Vector3] = []
		for i in range(0, faces.size() - 2, 3):
			var a: Vector3 = mi.global_transform * faces[i]
			var b: Vector3 = mi.global_transform * faces[i + 1]
			var c: Vector3 = mi.global_transform * faces[i + 2]
			var mid := (a + b + c) / 3.0
			if (b - a).cross(c - a).dot(_cam.global_position - mid) < 0.0:
				facing.append(mid)
		var step := maxi(1, floori(facing.size() / 12.0))
		for i in range(0, facing.size(), step):
			targets.append(facing[i].lerp(centre, 0.03))
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	var blockers := {}
	for t in targets:
		var from := _cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * 1.0)
		var hit := space.intersect_ray(q)
		if hit and subject.is_ancestor_of(hit.collider):
			hits += 1
		else:
			var what := (
				"miss" if hit.is_empty() else String((hit.collider as Node).get_parent().name)
			)
			blockers[what] = blockers.get(what, 0) + 1
	var ok := hits * 2 >= targets.size() and hits > 0
	print("VISIBLE %s ray_hits=%d/%d ok=%s other=%s" % [label, hits, targets.size(), ok, blockers])
	if strict and not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok


# ------------------------------------------------------------ pass B: the real game


func _pass_b() -> void:
	_beat("b_boot")
	_clean_files()
	await _boot()
	await _intro_plates()
	await _hud_plate("start view", _start_subjects())
	await _tray_plates()
	await _sheet_plates()
	for i in CAUSES.size():
		_raise(i)
	_post_result()
	await _frames(10)
	await _hud_plate("alert rail and flight result", {"rail": _stack})
	await _game_menu_plates()
	_hud.press_starter_terminal()
	await _frames(20)
	# Gate captions show only while a build tool is held (GateLinksView.set_building).
	var build := _main.get_node("BuildMode") as BuildMode
	(build.get_node("Ghost") as Node3D).visible = false
	build.set_tool(BuildMode.Tool.GATE_DESK)
	await _frames(10)
	await _caption_plates("unstaffed terminal, gate desk tool")
	build.set_tool(BuildMode.Tool.NONE)
	(build.get_node("Ghost") as Node3D).visible = true
	await _frames(6)
	await _hud_plate("checklist", {"checklist card": _staff.hint_card()})
	_menu.press_staff()
	await _frames(10)
	await _hud_plate("staff card", {"staff card": _staff.card()})
	_menu.press_staff()
	await _frames(6)
	await _open_with_flights()
	await _hud_plate("departures", _departures_subjects())
	await _select_scanner()
	var inspect := _hud.find_child("PassengerInspect", true, false)
	await _hud_plate("inspect card", {"inspect card": inspect})
	(_hud.get("_built") as BuiltSelection).kind = BuiltSelection.Kind.NONE
	_hud.set_debug_open(true)
	await _frames(10)
	await _hud_plate("debug panel", {"debug panel": _hud.find_child("DebugPanel", true, false)})
	_hud.set_debug_open(false)
	await _need_captions()
	_main.queue_free()
	_main = null
	_hud = null
	await _frames(4)


func _clean_files() -> void:
	for path in [SETTINGS, HINTS_MEMORY]:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")


func _boot() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var sim_seed := randi()
	clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	_hud = _main.get_node("PassengerHud")
	_hud.alert_settings_path = SETTINGS
	_hud.departures_settings_path = SETTINGS
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = SETTINGS
	(_main.get_node("TycoonCamera") as TycoonCamera).settings_path = SETTINGS
	root.add_child(_main)
	clock.set_paused(true)
	_stack = _hud.find_child("AlertStack", false, false) as AlertStack
	_menu = _main.get_node("BuildMenu") as BuildMenu
	_staff = _main.get_node("StaffPanel") as StaffPanel
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = HINTS_MEMORY
	hints.hud = _hud
	hints.scene_root = _main
	hints.reads_world = false
	_hud.add_child(hints)
	await _frames(30)


## The new-game intro, then the incidents question it asks, then both closed
## the way IntroClose does.
func _intro_plates() -> void:
	if _hud.intro() == null:
		_hud.open_intro()
		await _frames(10)
	if _hud.intro() != null:
		await _hud_plate("intro dialogue", {"intro": _hud.intro()})
	else:
		_skipped.append("hud intro dialogue: the intro never opened")
	_hud.dismiss_intro()
	await _frames(10)
	var menu := _main.get_node("GameMenu") as GameMenu
	if menu.question() != null:
		await _hud_plate("incidents question", {"question": menu.question()})
	else:
		_skipped.append("hud incidents question: it never opened")
	var problem := IntroClose.close(_main)
	if problem != "":
		_invalid(problem)
	await _frames(10)


func _start_subjects() -> Dictionary:
	return {
		"checklist card": _staff.hint_card(),
		"clock panel": _hud.find_child("FlightPanel", true, false),
		"bar": _menu.bar(),
	}


func _tray_plates() -> void:
	for i in BuildMenu.categories().size():
		if i == BuildMenu.remove_category():
			continue
		_menu.press_category(i)
		var name: String = BuildMenu.categories()[i]["name"]
		await _settle(_menu.tray())
		if not _menu.is_tray_open():
			_skipped.append("hud tray %s: it did not open" % name)
			continue
		await _hud_plate("tray %02d %s" % [i, name], {"tray": _menu.tray(), "bar": _menu.bar()})
	if _menu.is_tray_open():
		_menu.press_category(_menu.open_category())
	await _frames(6)


## Waits until a panel's rect holds still for three frames (a sliding or
## fading panel), capped; anti-pattern a-plate-probe-that-waits-a-fixed-frame-
## count-can-take-its-si.
func _settle(panel: Control) -> void:
	var last := Rect2()
	var still := 0
	for i in 90:
		await _frames(1)
		var now := panel.get_global_rect()
		var shade := panel.modulate.a * panel.self_modulate.a
		still = still + 1 if now.is_equal_approx(last) and shade > 0.99 else 0
		last = now
		if still >= 3:
			return
	print("PROBE settle cap reached for %s at %s" % [panel.name, last])


func _sheet_plates() -> void:
	var offers := _main.get_node("OfferPanel") as OfferPanel
	var runway := _main.get_node("RunwayCard") as RunwayCard
	offers.open()
	await _settle(offers.sheet())
	await _hud_plate("offers sheet", {"offers sheet": offers.sheet()})
	runway.open()
	await _settle(runway.sheet())
	await _hud_plate("runway sheet", {"runway sheet": runway.sheet()})
	runway.close()
	await _frames(10)


func _raise(i: int) -> void:
	var c: Array = CAUSES[i]
	(
		_causes
		. append(
			{
				"key": StringName(c[0]),
				"title": c[1],
				"detail": c[2],
				"targets": [],
				"show_after": 0,
				"clear_after": HOLD,
			}
		)
	)
	_stack.board().update(_causes, (_main.get_node("PassengerSim") as PassengerSim).tick)
	_hud.refresh()


func _post_result() -> void:
	var summary := {
		"flight": "GMF101-d0",
		"title": "Sunhop Lisbon",
		"made": 31,
		"missed": 6,
		"reasons":
		[
			{"count": 3, "text": "Still at the cafe"},
			{"count": 2, "text": "Held up by crowds at the gate"},
		],
	}
	var card := FlightResultPanel.new()
	card.show_result(summary)
	var lines := card.result_text().split("\n")
	_stack.post_notice(
		PassengerHud.RESULT_KEY,
		card,
		FlightResultPanel.SHOW_SECONDS * 1000.0,
		lines[0],
		"\n".join(lines.slice(1))
	)


func _game_menu_plates() -> void:
	var menu := _main.get_node("GameMenu") as GameMenu
	if not menu.open():
		_skipped.append("hud game menu: open() refused")
		return
	await _frames(10)
	await _hud_plate("game menu", {"menu": _largest_panel(menu)})
	menu.press_settings()
	await _frames(10)
	await _hud_plate("game menu settings", {"settings": _largest_panel(menu)})
	menu.press_back()
	await _frames(4)
	menu.close()
	await _frames(10)


## The largest visible panel under `node`, the window a menu draws.
func _largest_panel(node: Node) -> Control:
	var best: Control = null
	var area := 0.0
	for c in node.find_children("*", "PanelContainer", true, false):
		var p := c as Control
		if p.is_visible_in_tree() and p.get_global_rect().get_area() > area:
			best = p
			area = p.get_global_rect().get_area()
	return best


func _open_with_flights() -> void:
	_beat("b_open")
	var clock: SimClock = _main.get_node("SimClock")
	var flights := _main.get_node("FlightSim") as FlightSim
	print("PROBE hired=%d" % StaffTestKit.staff_all(_main.get_node("Staff") as StaffSim))
	clock.set_paused(false)
	for i in 20:
		clock.advance(SimClock.STEP)
		if flights.opened_tick >= 0:
			break
	clock.set_paused(true)
	print("PROBE opened_tick=%d tick=%d" % [flights.opened_tick, clock.tick])
	if flights.opened_tick < 0:
		_invalid("the airport did not open")
	for f in FLIGHTS:
		var terms := TestFlightContracts.terms(f[0], f[1])
		terms["destination"] = f[2]
		terms["airline"] = f[3]
		terms["plane_size"] = "small"
		terms["booked_passengers"] = 12
		print("PROBE accept %s=%s" % [f[0], flights.accept_contract(terms)])
	await _frames(20)


func _departures_subjects() -> Dictionary:
	return {
		"departures list": _main.find_child("DeparturesPanel", true, false),
		"clock panel": _hud.find_child("FlightPanel", true, false),
	}


func _select_scanner() -> void:
	var build := _main.get_node("BuildMode") as BuildMode
	var scanners: Array = ReferenceTerminal.object_ids(build.grid)["scanners"]
	if scanners.is_empty():
		_invalid("the starter terminal has no scanner to select")
		return
	var selection := _hud.get("_built") as BuiltSelection
	selection.kind = BuiltSelection.Kind.OBJECT
	selection.id = scanners[0]
	await _frames(10)


## One HUD state: every subject showing and inside the view, then the plate.
func _hud_plate(label: String, subjects: Dictionary) -> void:
	_beat("b_" + label)
	await _frames(4)
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var ok := true
	for what in subjects:
		var node := subjects[what] as Control
		if node == null or not node.is_visible_in_tree():
			_invalid("%s: %s is not showing" % [label, what])
			ok = false
			continue
		var r := node.get_global_rect()
		var inside := view.encloses(r) and r.has_area()
		print("RECT %s %s %s in_view=%s" % [label, what, r, inside])
		if not inside:
			_invalid("%s: %s at %s is not inside the view %s" % [label, what, r, view.size])
			ok = false
	if ok:
		_keep("hud", label, await _grab())


# ------------------------------------------------------------ pass B: captions


## Plates one of each kind of in-world caption or marker showing now, with the
## HUD layers hidden (anti-pattern a-plate-probe-s-occlusion-rays-see-only-
## meshes-so-a-hud-pane) and a camera at the MEDIUM pitch, CAPTION_DISTANCE off.
func _caption_plates(moment: String) -> void:
	_beat("b_captions_" + moment)
	var found := _captions()
	print("PROBE captions moment='%s' kinds=%s" % [moment, found.keys()])
	if found.is_empty():
		_skipped.append("captions at '%s': none showing" % moment)
		return
	var game_cam := root.get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 2000.0
	_main.add_child(_cam)
	_cam.make_current()
	_show_hud(false)
	for kind in found:
		if _caption_kinds.size() >= CAPTION_LIMIT or _caption_kinds.has(kind):
			continue
		var node: Node3D = found[kind]
		_caption_kinds[kind] = true
		await _plate_caption(moment, kind, node)
	_show_hud(true)
	_cam.queue_free()
	if game_cam != null:
		game_cam.make_current()
	await _frames(4)


func _plate_caption(moment: String, kind: String, node: Node3D) -> void:
	var at := node.global_position
	var pitch := deg_to_rad(TycoonCamera.STEP_PITCH_DEGREES[TycoonCamera.AngleStep.MEDIUM])
	var clear := false
	for yaw_deg in [0.0, 90.0, 180.0, 270.0]:
		var yaw := deg_to_rad(yaw_deg)
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		_cam.look_at_from_position(at + dir * CAPTION_DISTANCE, at, Vector3.UP)
		await _frames(4)
		_drop_colliders()
		_add_colliders(_main)
		await physics_frame
		await physics_frame
		var q := PhysicsRayQueryParameters3D.create(_cam.global_position, at)
		var hit := _cam.get_world_3d().direct_space_state.intersect_ray(q)
		var over := _draws_over(node)
		clear = hit.is_empty() or (hit["position"] as Vector3).distance_to(at) < 0.3
		print("SIGHT caption %s yaw=%d clear=%s draws_over_depth=%s" % [kind, yaw_deg, clear, over])
		if clear or over:
			clear = true
			break
	var label := "caption %s (%s) '%s'" % [kind, moment, _text_of(node).left(24)]
	if not clear:
		_invalid("%s: blocked from every yaw" % label)
	elif _prove_in_frame(label, [at]):
		_keep("hud", label, await _grab())
	_drop_colliders()


func _draws_over(node: Node3D) -> bool:
	if node is Label3D:
		return (node as Label3D).no_depth_test
	return node is Sprite3D and (node as Sprite3D).no_depth_test


func _text_of(node: Node3D) -> String:
	if node is Label3D:
		return (node as Label3D).text.replace("\n", " ")
	return "sprite"


## kind -> the first showing node of that kind: every visible Label3D with text
## and Sprite3D with a texture under the main scene, keyed by its nearest
## scripted ancestor's class and its own name with digits dropped.
func _captions() -> Dictionary:
	var out := {}
	var digits := RegEx.create_from_string("[0-9#@_]+$")
	for n in _main.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.is_visible_in_tree() and l.text.strip_edges() != "":
			var key := "%s %s" % [_owner_class(l), digits.sub(String(l.name), "")]
			if not out.has(key):
				out[key] = l
	for n in _main.find_children("*", "Sprite3D", true, false):
		var s := n as Sprite3D
		if s.is_visible_in_tree() and s.texture != null:
			var key := "%s %s" % [_owner_class(s), digits.sub(String(s.name), "")]
			if not out.has(key):
				out[key] = s
	return out


func _owner_class(node: Node) -> String:
	var at := node.get_parent()
	while at != null and at != _main:
		var script := at.get_script() as Script
		if script != null and script.get_global_name() != &"":
			return String(script.get_global_name())
		at = at.get_parent()
	return "Main"


func _drop_colliders() -> void:
	for mi in _main.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("look_body"):
			var body: Node = mi.get_meta("look_body")
			if is_instance_valid(body):
				body.free()
			mi.remove_meta("look_body")


func _show_hud(on: bool) -> void:
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = on


## Flights running with the mood overlay on hunger until need icons or clusters
## show, capped by SIM_LIMIT_MS of wall time.
func _need_captions() -> void:
	_beat("b_needs")
	var clock: SimClock = _main.get_node("SimClock")
	var overlay := _main.get_node("MoodOverlay") as MoodOverlay
	overlay.set_shown(true)
	overlay.set_mode(MoodTint.Mode.HUNGER)
	# Need icons show only inside the home zoom (NeedIcons.shown_at).
	var rig := _main.get_node("TycoonCamera") as TycoonCamera
	rig.distance = minf(25.0, rig.home_distance * 0.5)
	var started := Time.get_ticks_msec()
	var views := _main.get_node("PassengerViews")
	clock.set_paused(false)
	var steps := 0
	while Time.get_ticks_msec() - started < SIM_LIMIT_MS:
		for i in 10:
			clock.advance(SimClock.STEP)
		steps += 10
		await _frames(1)
		_beat("b_needs_%d" % steps)
		var shown := 0
		for n in views.find_children("*", "Sprite3D", true, false):
			if (n as Sprite3D).is_visible_in_tree():
				shown += 1
		if (shown >= 1 and steps >= 100) or steps >= 2000:
			break
	clock.set_paused(true)
	await _frames(10)
	print("PROBE needs steps=%d tick=%d" % [steps, clock.tick])
	await _caption_plates("flights running, hunger overlay")


# ------------------------------------------------------------ pass C: icons


func _pass_c() -> void:
	_beat("c_icons")
	var icons := []
	for file in DirAccess.get_files_at("res://assets/ui/icons"):
		if file.ends_with(".svg"):
			var tex := load("res://assets/ui/icons/" + file) as Texture2D
			icons.append(["svg " + file.get_basename(), tex.get_image()])
	for glyph in MarkerIcons.Glyph.values():
		icons.append(
			["glyph " + MarkerIcons.Glyph.keys()[glyph].to_lower(), MarkerIcons.image(glyph)]
		)
	var thumbs := []
	for file in DirAccess.get_files_at("res://assets/ui/thumbnails"):
		if file.ends_with(".png"):
			var tex := load("res://assets/ui/thumbnails/" + file) as Texture2D
			thumbs.append(["thumb " + file.get_basename(), tex.get_image()])
	for entry in icons + thumbs:
		var img: Image = entry[1]
		img.convert(Image.FORMAT_RGBA8)
		print("ICON %s size=%s" % [entry[0], img.get_size()])
		_keep("icons", entry[0], img)
	await _compose(
		"pieces", "Placeable pieces: catalog, wall kit, landside, kit parts", 7, SHEET_TILE
	)
	await _compose("people", "People (passenger bodies, staff suits)", 6, SHEET_TILE)
	await _compose(
		"world", "World: vehicles, planes, airside, runways, buildings, mess, crow", 6, SHEET_TILE
	)
	await _compose("hud", "HUD panels, trays and in-world captions at 1920x1080", 5, HUD_TILE)
	await _compose("icons", "Bar icons (SVG), marker glyphs, build-menu thumbnails", 12, ICON_TILE)


## A contact sheet of every tile on `sheet`, each on a HUD card with a Nunito
## caption, drawn by a SubViewport so the labels use the game's own font.
func _compose(sheet: String, title: String, cols: int, tile: Vector2i) -> void:
	_beat("c_compose_" + sheet)
	var entries: Array = _sheets[sheet]
	if entries.is_empty():
		_invalid("sheet %s has no tiles" % sheet)
		return
	var cell := Vector2i(tile.x + 16, tile.y + 40)
	var rows := ceili(entries.size() / float(cols))
	var vp := SubViewport.new()
	vp.size = Vector2i(cols * cell.x + 32, rows * cell.y + 80)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var base := ColorRect.new()
	base.color = Color(0.32, 0.36, 0.42)
	base.size = vp.size
	base.theme = HUD_THEME
	vp.add_child(base)
	var heading := Label.new()
	heading.text = "%s  (%d tiles)" % [title, entries.size()]
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88))
	heading.position = Vector2(16, 16)
	base.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.position = Vector2(16, 64)
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	base.add_child(grid)
	for entry in entries:
		grid.add_child(_card(entry, tile, cell))
	root.add_child(vp)
	await _frames(2)
	# The cards grow by the panel style margins; size the sheet to the laid-out grid.
	vp.size = Vector2i(grid.get_combined_minimum_size() + Vector2(32, 80))
	base.size = vp.size
	await _frames(6)
	var img := vp.get_texture().get_image()
	var path := _out_dir.path_join("contact_%s.png" % sheet)
	var err := img.save_png(path)
	print("PLATE contact %s tiles=%d size=%s err=%d" % [path, entries.size(), img.get_size(), err])
	if err != OK:
		_invalid("could not save %s" % path)
	vp.queue_free()
	await _frames(2)


func _card(entry: Dictionary, tile: Vector2i, cell: Vector2i) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = cell
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var img := Image.load_from_file(entry["path"])
	img.convert(Image.FORMAT_RGBA8)
	var fit := minf(tile.x / float(img.get_width()), tile.y / float(img.get_height()))
	if fit < 1.0:
		img.resize(
			maxi(1, roundi(img.get_width() * fit)),
			maxi(1, roundi(img.get_height() * fit)),
			Image.INTERPOLATE_LANCZOS
		)
	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(img)
	picture.custom_minimum_size = tile
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	box.add_child(picture)
	var caption := Label.new()
	caption.text = entry["name"]
	caption.clip_text = true
	caption.custom_minimum_size = Vector2(tile.x, 0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 13 if tile.x < 200 else 16)
	box.add_child(caption)
	return panel
