extends SceneTree
## Windowed plates of the passenger bodies and looks (PassengerLooks): for each
## of the twelve bodies six orthographic views (front, back, left, right, top,
## bottom) at one true scale beside a 1 m cube; a sheet per gender of every
## body in every clothing tint; a distance shot of all twelve; and a crowd of
## passengers in spawn order with their tints and bag colours. Every plate
## proves its subjects are in frame (bounds projected inside the plate with a
## margin) and seen (sight lines land on them, none blocked) before it is
## saved; any failure prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <checkout>/game -s res://spike/passenger_looks_plates_probe.gd [-- --seed=N]
## Plates go to tools/blender/out/passenger_looks/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/passenger_looks"
## Orthographic plates: this many metres high, cropped square.
const ORTHO_M := 3.2
const MARGIN_PX := 8.0
const VIEWS := {
	"front": Vector3(0, 0, 1),
	"back": Vector3(0, 0, -1),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"top": Vector3(0, 1, 0),
	"bottom": Vector3(0, -1, 0),
}
const CROWD_ROWS := 3
const CROWD_COLS := 8

var _out := ""
var _failed := false
var _cam := Camera3D.new()
var _stage := Node3D.new()


func _initialize() -> void:
	_out = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	return false


func _run() -> void:
	var seed := randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
	print("PROBE seed=", seed, " out=", _out)
	_studio()
	root.add_child(_cam)
	root.add_child(_stage)
	_cam.current = true
	for body in PassengerLooks.BODIES.size():
		await _six_axis(body)
	for variant in 2:
		await _tint_sheet(variant)
	await _distance()
	await _crowd(seed)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)


## A passenger of `body` with tint `tint` at `at`, facing `yaw`, idle at `phase`.
func _person(body: int, tint: int, at: Vector3, yaw: float, phase: float) -> Node3D:
	var node := PassengerLooks.SCENES[body].instantiate() as Node3D
	_stage.add_child(node)
	PassengerLooks.paint_body(node, body, tint)
	node.position = at
	node.rotation.y = yaw
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	player.play("idle")
	player.seek(phase * player.current_animation_length, true)
	player.speed_scale = 0.0
	return node


func _cube(at: Vector3) -> Node3D:
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.45, 0.2)
	cube.material_override = mat
	cube.position = at + Vector3(0, 0.5, 0)
	_stage.add_child(cube)
	return cube


func _clear() -> void:
	for child in _stage.get_children():
		child.free()


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if node is MeshInstance3D:
		box = node.global_transform * (node as MeshInstance3D).get_aabb()
	return box


## The square crop of the window the camera sees, after the scene settled.
func _grab(crop: bool) -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if not crop:
		return img
	var side := mini(img.get_width(), img.get_height())
	var x := (img.get_width() - side) / 2
	var y := (img.get_height() - side) / 2
	return img.get_region(Rect2i(x, y, side, side))


## Subjects in frame (every bounds corner inside the window with a margin) and
## seen (sight lines from the camera land on each, none blocked). `crop` is the
## square window region a plate keeps.
func _proven(label: String, subjects: Dictionary, crop: bool, crowd := false) -> bool:
	var size := root.get_visible_rect().size
	var frame := Rect2(Vector2.ZERO, size)
	if crop:
		var side := minf(size.x, size.y)
		frame = Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	frame = frame.grow(-MARGIN_PX)
	var owners: Array[Node] = [_stage]
	var holder := PlateSight.colliders(root, owners, subjects)
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	var ok := true
	for node: Node3D in subjects:
		var tag: String = subjects[node]
		var box := _bounds(node)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for k in 8:
			var px := _cam.unproject_position(box.get_endpoint(k))
			lo = lo.min(px)
			hi = hi.max(px)
		var inside := frame.has_point(lo) and frame.has_point(hi)
		# A 3 x 3 grid on the plane through the subject facing the camera (middle
		# 40% of its width, 30-70% of its height along the camera's up); an
		# orthographic camera's lines run parallel to its view axis.
		var basis := _cam.global_transform.basis
		var span := absf(box.size.dot(basis.x))
		var tall := absf(box.size.dot(basis.y))
		var targets: Array[Vector3] = []
		for i in 3:
			for j in 3:
				targets.append(
					(
						box.get_center()
						+ basis.x * (0.2 * (i - 1) * span)
						+ basis.y * (0.2 * (j - 1) * tall)
					)
				)
		var on := 0
		var blocked: Array[String] = []
		for at in targets:
			var from := _cam.global_position
			if _cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
				from = at + basis.z * 20.0
			var one: Array[Vector3] = [at]
			var lines := PlateSight.sight_lines(space, from, one, tag)
			on += (lines["on_subject"] as Array).size()
			blocked.append_array(lines["blockers"])
		print(
			(
				"PROOF %s %s px=%s..%s in_frame=%s sight_on=%d of %d blockers=%s"
				% [label, tag, lo.round(), hi.round(), inside, on, targets.size(), blocked]
			)
		)
		# In a crowd a person may hide part of the one behind it; two of its lines
		# landing on it then count as seen (PlateSight.MIN_ON).
		var seen := on > 0 and blocked.is_empty()
		if crowd:
			seen = on >= PlateSight.MIN_ON
		if not inside or not seen:
			_invalid("%s: %s not in frame or not seen" % [label, tag])
			ok = false
	holder.free()
	return ok


func _save(img: Image, name: String) -> void:
	var path := _out.path_join(name)
	img.save_png(path)
	print("PLATE ", path, " size=", img.get_size())


func _sheet(images: Array[Image], cols: int, tile: int) -> Image:
	var rows := ceili(images.size() / float(cols))
	var sheet := Image.create(cols * tile, rows * tile, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(1, 1, 1))
	for i in images.size():
		var img := images[i].duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
		img.resize(tile, tile, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i % cols, i / cols) * tile
		)
	return sheet


func _six_axis(body: int) -> void:
	_clear()
	var person := _person(body, 0, Vector3.ZERO, 0.0, 0.0)
	var cube := _cube(Vector3(0.9, 0, 0.9))
	var stem := PassengerLooks.BODIES[body]
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = ORTHO_M
	var centre := Vector3(0.45, 1.0, 0.45)
	var plates: Array[Image] = []
	for view: String in VIEWS:
		var dir: Vector3 = VIEWS[view]
		_cam.global_position = centre + dir * 10.0
		var up := Vector3.FORWARD if absf(dir.y) > 0.5 else Vector3.UP
		_cam.look_at(centre, up)
		var ok: bool = await _proven("%s/%s" % [stem, view], {person: "body", cube: "cube"}, true)
		var img: Image = await _grab(true)
		if ok:
			_save(img, "%s_%s.png" % [stem, view])
		plates.append(img)
	_save(_sheet(plates, 3, 400), "%s_six_axis_sheet.png" % stem)


## Per body a front plate of it in every tint (left to right, tint 0 first);
## the six bodies of a gender stacked in one sheet.
func _tint_sheet(variant: int) -> void:
	var rows: Array[Image] = []
	for k in PassengerLooks.PER_VARIANT:
		_clear()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.keep_aspect = Camera3D.KEEP_WIDTH
		_cam.size = 9.0
		var body := variant * PassengerLooks.PER_VARIANT + k
		var stem := PassengerLooks.BODIES[body]
		var subjects := {}
		var tints := PassengerLooks.TINTS.size()
		for t in tints:
			var node := _person(body, t, Vector3(t * 1.2, 0, 0), 0.0, 0.0)
			subjects[node] = "t%d" % t
		var centre := Vector3((tints - 1) * 0.6, 1.0, 0)
		_cam.global_position = centre + Vector3(0, 0.4, 10)
		_cam.look_at(centre)
		var ok: bool = await _proven("tints/%s" % stem, subjects, false)
		var img: Image = await _grab(false)
		if ok:
			_save(img, "tints_%s.png" % stem)
		rows.append(img)
	var w := 960
	var h := 540
	var sheet := Image.create(w, h * rows.size(), false, Image.FORMAT_RGBA8)
	for i in rows.size():
		var img := rows[i].duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(0, i * h))
	_save(sheet, "tints_%s_sheet.png" % ["male", "female"][variant])


func _distance() -> void:
	_clear()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	var subjects := {}
	for body in PassengerLooks.BODIES.size():
		var node := _person(body, 0, Vector3(body * 1.2, 0, 0), 0.0, body / 12.0)
		subjects[node] = PassengerLooks.BODIES[body]
	_cube(Vector3(-1.5, 0, 0))
	var centre := Vector3(5.5 * 1.2, 1.0, 0)
	_cam.global_position = centre + Vector3(0, 12, 28)
	_cam.look_at(centre)
	var ok: bool = await _proven("distance_30m", subjects, false)
	var img: Image = await _grab(false)
	if ok:
		_save(img, "distance_30m.png")


## Passengers in spawn order (ids 1..), snaking through a queue: each with its
## body (its seeded variant), tint and a bag of its colour at its feet.
func _crowd(seed: int) -> void:
	_clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	(floor_mesh.mesh as PlaneMesh).size = Vector2(30, 30)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.78, 0.76, 0.72)
	floor_mesh.material_override = floor_mat
	_stage.add_child(floor_mesh)
	var subjects := {}
	var looks := {}
	var kinds := SecurityLooks.KIND_PIECES.keys()
	for n in CROWD_ROWS * CROWD_COLS:
		var id := n + 1
		var row := n / CROWD_COLS
		var col := n % CROWD_COLS if row % 2 == 0 else CROWD_COLS - 1 - n % CROWD_COLS
		var variant := rng.randi_range(0, 1)
		var body := PassengerLooks.body_of(id, variant)
		var tint := PassengerLooks.tint_of(id)
		var at := Vector3(col * 1.0, 0, -row * 1.6)
		var yaw := PI / 2.0 if row % 2 == 0 else -PI / 2.0
		var node := _person(body, tint, at, yaw + rng.randf_range(-0.4, 0.4), rng.randf())
		subjects[node] = "id%d" % id
		looks[Vector2i(col, row)] = [body, tint, PassengerLooks.bag_of(id)]
		var bag := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[kinds[id % kinds.size()]])
		_stage.add_child(bag)
		bag.position = at + Vector3(0, 0, 0.45)
		PassengerLooks.paint_bags([{"node": bag}], id)
		print(
			(
				"CROWD id=%d variant=%d body=%s tint=%d bag=%d at=%s"
				% [id, variant, PassengerLooks.BODIES[body], tint, PassengerLooks.bag_of(id), at]
			)
		)
	var same := 0
	for cell: Vector2i in looks:
		for step in [Vector2i(1, 0), Vector2i(0, 1)]:
			var next: Vector2i = cell + step
			if (
				looks.has(next)
				and looks[next][0] == looks[cell][0]
				and looks[next][1] == looks[cell][1]
			):
				same += 1
				print("CROWD_SAME %s %s %s" % [cell, next, looks[cell]])
	print("CROWD neighbour pairs with the same body and tint: %d" % same)
	var centre := Vector3((CROWD_COLS - 1) / 2.0, 1.0, -(CROWD_ROWS - 1) * 0.8)
	_cam.global_position = centre + Vector3(0, 9.0, 12.5)
	_cam.look_at(centre)
	var ok: bool = await _proven("crowd", subjects, false, true)
	var img: Image = await _grab(false)
	if ok:
		_save(img, "crowd.png")
