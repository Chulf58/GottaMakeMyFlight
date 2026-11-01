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
## Seated close-ups (side and front of each body on its chair).
const SEAT_OUT_REL := "res://../tools/blender/out/seat-row"
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
## Seated plates: body points this close to the hips in plan are the seat side.
const SEAT_PROBE_M := 0.15
## A body point this far behind every face of a chair part is inside it.
const OVERLAP_SLACK_M := 0.002
## Points of the sit_idle loop at which the seated bodies are checked.
const SIT_PHASES: Array[float] = [0.0, 0.25, 0.5, 0.75]
## Seated close-ups: view name -> direction from the subject to the camera.
const CLOSE_VIEWS := {
	"side": Vector3(1, 0, 0),
	"front": Vector3(0, 0, 1),
	"top": Vector3(0, 1, 0),
}

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
	# --parts=six,tints,distance,crowd,seated picks what is shot (default: all).
	var parts := ["six", "tints", "distance", "crowd", "seated"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1))
		if arg.begins_with("--parts="):
			parts = Array(arg.get_slice("=", 1).split(","))
	print("PROBE seed=", seed, " out=", _out, " parts=", parts)
	_studio()
	root.add_child(_cam)
	root.add_child(_stage)
	_cam.current = true
	if "six" in parts:
		for body in PassengerLooks.BODIES.size():
			await _six_axis(body)
	if "tints" in parts:
		for variant in 2:
			await _tint_sheet(variant)
	if "distance" in parts:
		await _distance()
	if "crowd" in parts:
		await _crowd(seed)
	if "seated" in parts:
		var close: Array[Image] = []
		for group in 4:
			await _seated(group, close)
		_save(_sheet(close, 9, 240), "seated_close_sheet.png", SEAT_OUT_REL)
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
func _person(body: int, tint: int, at: Vector3, yaw: float, phase: float, clip := "idle") -> Node3D:
	var node := PassengerLooks.SCENES[body].instantiate() as Node3D
	_stage.add_child(node)
	PassengerLooks.paint_body(node, body, tint)
	node.set_meta(&"body", body)
	node.position = at
	node.rotation.y = yaw
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	player.play(clip)
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
		# A skinned body's own AABB is its rest (T) pose; take the drawn pose.
		var local := mi.get_aabb()
		if mi.skin != null:
			local = mi.bake_mesh_from_current_skeleton_pose().get_aabb()
		var b := mi.global_transform * local
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
## `tagged` maps more nodes to a subject's tag for the sight lines only (a
## chair whose frame stands in front of the legs), not for the frame check.
func _proven(label: String, subjects: Dictionary, crop: bool, crowd := false, tagged := {}) -> bool:
	var size := root.get_visible_rect().size
	var frame := Rect2(Vector2.ZERO, size)
	if crop:
		var side := minf(size.x, size.y)
		frame = Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	frame = frame.grow(-MARGIN_PX)
	var owners: Array[Node] = [_stage]
	var holder := PlateSight.colliders(root, owners, subjects.merged(tagged))
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


func _save(img: Image, name: String, dir_rel := "") -> void:
	var dir := _out
	if dir_rel != "":
		dir = ProjectSettings.globalize_path(dir_rel).simplify_path()
		DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(name)
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


## Three bodies of `group` (bodies group*3 .. +2), each seated in sit_idle on
## the middle chair of its own gate seat row, placed as PassengerSim and
## GateChairs place a seated passenger (SIT_FORWARD_M ahead of the seat cell,
## CHAIR_OFFSET_M across, the body's PassengerLooks.SEAT_SHIFT_M forward and
## up, facing the row's front, +z at facing 0). Shot side-on (orthographic,
## along the rows) so a gap between body and seat pan shows, then each body
## alone side-on and from the front (_close_ups, appended to `close`).
## Prints SEAT_GAP: the lowest body point within SEAT_PROBE_M of the hips (in
## plan) above the seat pan under the hips (a ray down onto the chair only),
## and the SEAT_OVERLAP checks (_overlaps).
func _seated(group: int, close: Array[Image]) -> void:
	_clear()
	var chairs := Node3D.new()
	_stage.add_child(chairs)
	var subjects := {}
	var people: Array[Node3D] = []
	for k in 3:
		var body := group * 3 + k
		var row := InteriorKit.instantiate(&"seat_row")
		chairs.add_child(row)
		row.position = Vector3(0, 0, k * 2.6)
		# The row's origin is its footprint's centre, the middle cell's centre.
		var seat := row.position
		var shift := PassengerLooks.SEAT_SHIFT_M[body]
		var at := (
			seat
			+ Vector3(GateChairs.CHAIR_OFFSET_M[1], shift.y, PassengerSim.SIT_FORWARD_M + shift.x)
		)
		var node := _person(body, 0, at, 0.0, 0.0, "sit_idle")
		subjects[node] = PassengerLooks.BODIES[body]
		people.append(node)
		# The chair a person sits on is part of what the plate shows of it: its
		# frame and back may stand in front of the legs and the seat.
		subjects[row] = subjects[node]
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.size = 8.0
	var centre := Vector3(0, 0.8, 2.6)
	_cam.global_position = centre + Vector3(12, 0, 0)
	_cam.look_at(centre)
	for i in 3:
		await process_frame
	var owners: Array[Node] = [chairs]
	var holder := PlateSight.colliders(root, owners, {})
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	for node in people:
		var skel := node.find_child("Skeleton3D", true, false) as Skeleton3D
		var hips := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin
		var down := PhysicsRayQueryParameters3D.create(
			Vector3(hips.x, 1.2, hips.z), Vector3(hips.x, 0.0, hips.z)
		)
		var hit := space.intersect_ray(down)
		var mi := PassengerLooks.body_mesh(node)
		var baked := mi.bake_mesh_from_current_skeleton_pose()
		var low := INF
		for s in baked.get_surface_count():
			for v: Vector3 in baked.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var w := mi.global_transform * v
				if Vector2(w.x - hips.x, w.z - hips.z).length() < SEAT_PROBE_M:
					low = minf(low, w.y)
		var pan: float = hit["position"].y if not hit.is_empty() else NAN
		print(
			(
				"SEAT_GAP %s hips=%s pan_top=%.3f body_low=%.3f gap_m=%.3f"
				% [subjects[node], hips, pan, low, low - pan]
			)
		)
		if hit.is_empty():
			_invalid("%s: no seat pan under the hips" % subjects[node])
	holder.free()
	await _overlaps(group, people, chairs, subjects)
	var ok: bool = await _proven("seated_%d" % group, subjects, false)
	var img: Image = await _grab(false)
	if ok:
		_save(img, "seated_%d.png" % group)
		_save(img, "seated_%d.png" % group, SEAT_OUT_REL)
	await _close_ups(people, chairs, subjects, close)


## SEAT_OVERLAP: the body points inside the seat row at each SIT_PHASES point
## of sit_idle, which must be none. SEAT_OVERLAP_OLD is the control: the same
## body without its SEAT_SHIFT_M (where it was drawn before), which must
## overlap, or the check could not see one. --sweep prints, per body and lift,
## the least step forward from that old spot that leaves no point inside.
func _overlaps(group: int, people: Array[Node3D], chairs: Node3D, subjects: Dictionary) -> void:
	var parts := {}
	for island: Dictionary in _islands(chairs.get_child(0)):
		parts[island["part"]] = parts.get(island["part"], 0) + 1
	print("SEAT_ISLANDS ", parts)
	for phase in SIT_PHASES:
		await _seek_all(people, phase)
		for k in people.size():
			var total := _overlap_total(people[k], chairs.get_child(k), "SEAT_OVERLAP", phase)
			if total > 0:
				_invalid("%s: %d body points inside the seat row" % [subjects[people[k]], total])
	await _seek_all(people, 0.0)
	for k in people.size():
		var shift := PassengerLooks.SEAT_SHIFT_M[group * 3 + k]
		var back := Vector3(0, shift.y, shift.x)
		people[k].position -= back
		var total := _overlap_total(people[k], chairs.get_child(k), "SEAT_OVERLAP_OLD", 0.0)
		if total == 0:
			_invalid("control: %s does not overlap at its old spot" % subjects[people[k]])
		if "--sweep" in OS.get_cmdline_user_args():
			for dyi in 5:
				var dy := dyi * 0.005
				var found := -1.0
				for dzi in 33:
					var dz := dzi * 0.005
					people[k].position += Vector3(0, dy, dz)
					var empty := _seat_overlap(people[k], chairs.get_child(k)).is_empty()
					people[k].position -= Vector3(0, dy, dz)
					if empty:
						found = dz
						break
				print("SWEEP %s dy=%.3f min_dz=%.3f" % [subjects[people[k]], dy, found])
		people[k].position += back


func _seek_all(people: Array[Node3D], phase: float) -> void:
	for node in people:
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		player.seek(phase * player.current_animation_length, true)
	for i in 2:
		await process_frame


## Prints `label` with the body's points inside `row` by bone and part, and
## returns their count.
func _overlap_total(person: Node3D, row: Node3D, label: String, phase: float) -> int:
	var hits := _seat_overlap(person, row)
	var total := 0
	for key: String in hits:
		total += hits[key]
	var stem := PassengerLooks.BODIES[person.get_meta(&"body")]
	print("%s %s phase=%.2f points=%d %s" % [label, stem, phase, total, hits])
	return total


## Each body alone on its chair, orthographic and cropped square (CLOSE_VIEWS):
## side-on from +x (the next chair's armrest stands in front of the thighs, as
## it does in the group plate), from the front and from above (the armrests
## beside the legs).
func _close_ups(
	people: Array[Node3D], chairs: Node3D, subjects: Dictionary, close: Array[Image]
) -> void:
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = 1.8
	for k in people.size():
		for j in people.size():
			people[j].visible = j == k
			(chairs.get_child(j) as Node3D).visible = j == k
		var row := chairs.get_child(k) as Node3D
		var centre := Vector3(people[k].position.x, 0.8, row.position.z + 0.2)
		var stem: String = subjects[people[k]]
		for view: String in CLOSE_VIEWS:
			var dir: Vector3 = CLOSE_VIEWS[view]
			_cam.global_position = centre + dir * 10.0
			_cam.look_at(centre, Vector3.FORWARD if view == "top" else Vector3.UP)
			var ok: bool = await _proven(
				"seat_%s/%s" % [view, stem], {people[k]: stem}, true, false, {row: stem}
			)
			var img: Image = await _grab(true)
			if ok:
				_save(img, "seat_%s_%s.png" % [view, stem], SEAT_OUT_REL)
			close.append(img)
	for j in people.size():
		people[j].visible = true
		(chairs.get_child(j) as Node3D).visible = true


## Body vertices inside the seat row's mesh at `row`, by the bone that moves
## each most and the chair part it is inside: {"Bone part": count}. The row is
## one joined mesh of boxes; every box is a convex island (welded by position),
## so a point is inside the mesh when it is behind every face of one island.
func _seat_overlap(person: Node3D, row: Node3D) -> Dictionary:
	var islands := _islands(row)
	var mi := PassengerLooks.body_mesh(person)
	var baked := mi.bake_mesh_from_current_skeleton_pose()
	var counts := {}
	for s in baked.get_surface_count():
		var posed: PackedVector3Array = baked.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var rest := mi.mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = rest[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = rest[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(posed.size(), 1)
		for v in posed.size():
			var part := _inside(islands, mi.global_transform * posed[v])
			if part == "":
				continue
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			var key := "%s %s" % [_bone_name(mi, bones[v * per + best]), part]
			counts[key] = counts.get(key, 0) + 1
	return counts


func _bone_name(mi: MeshInstance3D, bind: int) -> String:
	var skel := mi.get_node(mi.skeleton) as Skeleton3D
	var bone := mi.skin.get_bind_bone(bind)
	if bone < 0:
		return mi.skin.get_bind_name(bind)
	return skel.get_bone_name(bone)


## The seat row's convex islands in world space: [{"part", "planes"}], each
## plane a [point, outward normal] pair.
func _islands(row: Node3D) -> Array:
	var out := []
	for mi: MeshInstance3D in row.find_children("*", "MeshInstance3D", true, false):
		var faces := mi.mesh.get_faces()
		var tris := faces.size() / 3
		var parent := {}
		for t in tris:
			var a := _root_of(parent, _weld(faces[t * 3]))
			for c in [1, 2]:
				var b := _root_of(parent, _weld(faces[t * 3 + c]))
				if a != b:
					parent[b] = a
		var groups := {}
		for t in tris:
			var r := _root_of(parent, _weld(faces[t * 3]))
			if not groups.has(r):
				groups[r] = []
			(groups[r] as Array).append(t)
		for r: Vector3i in groups:
			var pts := PackedVector3Array()
			for t: int in groups[r]:
				for c in 3:
					pts.append(mi.global_transform * faces[t * 3 + c])
			var box := AABB(pts[0], Vector3.ZERO)
			for p in pts:
				box = box.expand(p)
			var centre := box.get_center()
			var planes := []
			for i in range(0, pts.size(), 3):
				var n := (pts[i + 1] - pts[i]).cross(pts[i + 2] - pts[i])
				if n.length() < 1e-9:
					continue
				n = n.normalized()
				if n.dot(centre - pts[i]) > 0.0:
					n = -n
				planes.append([pts[i], n])
			out.append({"part": _part(box, row), "planes": planes})
	return out


func _weld(p: Vector3) -> Vector3i:
	return Vector3i((p * 1000.0).round())


func _root_of(parent: Dictionary, k: Vector3i) -> Vector3i:
	while parent.has(k):
		k = parent[k]
	return k


## A chair part named by its bounds in the row's frame (build_seat_row in
## tools/blender/interior/build_interior_kit.py).
func _part(box: AABB, row: Node3D) -> String:
	var local := row.global_transform.affine_inverse() * box
	var c := local.get_center()
	if local.size.y < 0.06 and c.y > 0.65:
		return "armrest"
	if local.size.x < 0.06 and local.size.y > 0.2 and c.y > 0.4:
		return "arm_post"
	if local.size.x > 0.5 and c.y > 0.4 and c.y < 0.56:
		return "pan"
	if local.size.x > 0.5 and c.y >= 0.56:
		return "back"
	return "frame"


## The part `p` is inside ("" when outside every island).
func _inside(islands: Array, p: Vector3) -> String:
	for island: Dictionary in islands:
		var ok := true
		for plane: Array in island["planes"]:
			if (p - (plane[0] as Vector3)).dot(plane[1]) > -OVERLAP_SLACK_M:
				ok = false
				break
		if ok:
			return island["part"]
	return ""
