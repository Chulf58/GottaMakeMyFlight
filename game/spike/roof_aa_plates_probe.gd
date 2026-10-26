extends SceneTree
## Windowed plates of the terminal roof (TP_Airport_01A) in the real main
## scene, made to find what made the roof look jagged (the outline hull) and
## to check the fix (decision toon-outline-thins-with-camera-distance-and-fades-out-at-ful):
##   A  the old constant-width outline (the fade pushed out of range)
##   N  the shipped outline, thinning with view depth
## Diagnosis variants, all with the old outline (add them to VARIANTS):
##   B  Sun shadow fixes at runtime: 2 cascades, max distance 350 m, atlas 4096,
##      a little more bias
##   C  Sun shadows off
##   D  A plus MSAA 8x (the project already runs msaa_3d = 2, which is 4x)
##   E  A plus SMAA
##   F  A with the terminal's outline pass removed (diagnosis only)
##   G  A with automatic mesh LOD off (mesh_lod_threshold 0)
##   H  G with the outline pass removed
## Each variant is shot from a close pose (part of the roof), a near pose
## (the whole roof), a mid pose (150 m) and the far pose (camera max
## distance), with a full plate and a nearest-scaled crop of the roof. Then a
## check-in desk and a passenger in the hand-built terminal are shot with A
## and N at 40 m and 80 m.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/roof_aa_plates_probe.gd
##
## The sim clock is paused and the passenger HUD hidden. Roof points are found
## by vertical rays onto the terminal's own trimesh colliders; each pose must
## project every point inside the frame (below the build toolbar), and at least
## half the camera rays to them must first hit the terminal within 0.5 m of the
## point, or the probe prints PROBE_INVALID and exits 1. A guard thread calls
## OS.crash() on a stall. Plates go to tools/blender/out/roof_aa/.

const OUT_REL := "res://../tools/blender/out/roof_aa"
const MARGIN_PX := 8.0
const TOOLBAR_PX := 80.0
const YAW := 0.6
## Near pose: the first distance that frames every roof point.
const NEAR_DISTANCES := [30.0, 40.0, 50.0, 60.0, 80.0, 100.0]
## Close pose: a part of the roof fills the frame; it must show at least
## CLOSE_MIN_POINTS roof points.
const CLOSE_DISTANCE := 40.0
const CLOSE_MIN_POINTS := 6
## Mid pose: the middle of the outline fade.
const MID_DISTANCE := 150.0
## The diagnosis also ran B, C, D, E, G and H; add them here to rerun.
const VARIANTS := ["A", "N", "F"]
const PEOPLE_VARIANTS := ["A", "N"]
const PEOPLE_DISTANCES := [40.0, 80.0]
const DESK_CELL := Vector2i(11, 11)
const PASSENGER_CELL := Vector2i(11, 12)
const PASSENGER := "res://assets/people/tcp_male_character_01.glb"
const GLASS := "res://assets/materials/tp_glass.tres"
const CROP_PAD_PX := 24.0
const CROP_MIN_W := 900
const HANG_MS := 60000

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false
var _cam: Camera3D
var _sun: DirectionalLight3D
var _defaults := {}
var _outlines: Array = []
var _seen_outlines := {}


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	randomize()
	var world_seed := randi()
	seed(world_seed)
	print("PROBE seed=%d" % world_seed)
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	(main.get_node("SimClock") as SimClock).set_paused(true)
	(main.get_node("PassengerHud") as CanvasLayer).visible = false
	_sun = main.get_node("Sun") as DirectionalLight3D
	var terminal := main.get_node("Airside/Terminal") as Node3D
	var rig := main.get_node("TycoonCamera") as TycoonCamera
	_cam = rig.get_node("Camera3D") as Camera3D
	_cam.make_current()
	await _frames(3)
	_record_defaults()
	_collect_outlines(terminal, "terminal")
	_beat("colliders")
	for mi in terminal.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).create_trimesh_collision()
	await physics_frame
	await physics_frame
	var box := _aabb_of(terminal)
	print("PROBE terminal_aabb pos=%s size=%s" % [box.position, box.size])
	var roof := _roof_points(terminal, box)
	print("PROBE roof_points=%d" % roof.size())
	if roof.size() < 4:
		_invalid("too few roof points (%d)" % roof.size())
	print("PROBE viewport=%s" % root.get_visible_rect().size)
	var crops := {}
	for pose in ["close", "near", "mid", "far"]:
		_beat(pose)
		var dists: Array = NEAR_DISTANCES
		if pose == "far":
			dists = [rig.max_distance]
		elif pose == "mid":
			dists = [MID_DISTANCE]
		elif pose == "close":
			dists = [CLOSE_DISTANCE]
		var framed := false
		var points := roof
		for d in dists:
			_place(rig, box, d)
			await _frames(6)
			if pose == "close":
				points = _framed_subset(roof)
				framed = points.size() >= CLOSE_MIN_POINTS
				print("PROBE close framed_points=%d of %d" % [points.size(), roof.size()])
				break
			if _in_frame(pose, roof, false):
				framed = true
				break
		print(
			(
				"CAMERA %s focus=%s yaw=%.2f distance=%.1f pitch_deg=%.1f cam_pos=%s"
				% [
					pose,
					rig.position,
					rig.yaw,
					rig.distance,
					-_cam.rotation_degrees.x,
					_cam.global_position
				]
			)
		)
		if not framed:
			_invalid("%s: no distance frames every roof point" % pose)
		var ok := _in_frame(pose, points, true)
		ok = _prove_visible(pose, terminal, points) and ok
		_print_depths(pose, points)
		var rect := _crop_rect(points)
		var row: Array[Image] = []
		for variant in VARIANTS:
			_beat("%s_%s" % [pose, variant])
			_apply(variant)
			await _frames(8)
			var img := await _grab()
			if ok:
				var crop := _crop(img, rect)
				_save(img, "%s_%s.png" % [pose, variant])
				_save(crop, "%s_%s_crop.png" % [pose, variant])
				row.append(crop)
			_apply("reset")
		crops[pose] = row
	_contact_sheet(crops)
	await _people_plates(main, rig)
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


## A check-in desk and a passenger in the hand-built terminal, shot with the
## old (A) and the shipped (N) outline at the close and near distances, to
## show their silhouettes keep the outline.
func _people_plates(main: Node3D, rig: TycoonCamera) -> void:
	_beat("people_build")
	var mode := main.get_node("BuildMode") as BuildMode
	var view := mode.get_node("BuildView") as BuildView
	var builder := HandBuiltTerminal.new(mode)
	builder.on_edit = func() -> void: _beat("people_build")
	builder.build()
	print("PROBE built applied=%d refused=%d" % [builder.applied, builder.refused.size()])
	await _frames(3)
	var at := mode.grid.cell_to_world(DESK_CELL)
	var desk: Node3D = null
	for child in view.get_children():
		if child.has_meta("record") and (child as Node3D).global_position.distance_to(at) < 1.5:
			desk = child
	if desk == null:
		_invalid("no desk object near %s" % at)
		return
	var passenger := (load(PASSENGER) as PackedScene).instantiate() as Node3D
	main.add_child(passenger)
	passenger.global_position = mode.grid.cell_to_world(PASSENGER_CELL)
	var players := passenger.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		(players[0] as AnimationPlayer).play("idle")
	_collect_outlines(desk, "desk")
	_collect_outlines(passenger, "passenger")
	for subject in [desk, passenger]:
		for mi in (subject as Node3D).find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).create_trimesh_collision()
	var occluders := _colliders(view, desk)
	await physics_frame
	await physics_frame
	var box := _aabb_of(desk).merge(_aabb_of(passenger))
	print(
		(
			"PROBE people desk=%s desk_aabb=%s passenger_aabb=%s"
			% [desk.name, _aabb_of(desk), _aabb_of(passenger)]
		)
	)
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(box.get_endpoint(i))
	for d in PEOPLE_DISTANCES:
		var pose := "people_%dm" % int(d)
		_beat(pose)
		rig.position = Vector3(box.get_center().x, 0.0, box.get_center().z)
		rig.yaw = YAW
		rig.distance = d
		rig.zoom(1.0)
		await _frames(6)
		print(
			(
				"CAMERA %s focus=%s distance=%.1f cam_pos=%s"
				% [pose, rig.position, d, _cam.global_position]
			)
		)
		var ok := _in_frame(pose, corners, true)
		ok = _prove_hits(pose + "/desk", desk) and ok
		ok = _prove_hits(pose + "/passenger", passenger) and ok
		_print_depths(pose, corners)
		var rect := _crop_rect(corners)
		for variant in PEOPLE_VARIANTS:
			_beat("%s_%s" % [pose, variant])
			_apply(variant)
			await _frames(8)
			var img := await _grab()
			if ok:
				_save(img, "%s_%s.png" % [pose, variant])
				_save(_crop(img, rect), "%s_%s_crop.png" % [pose, variant])
			_apply("reset")
	occluders.free()


## Rays from the camera to the subject's centre line at three heights; at
## least two must first hit the subject.
func _prove_hits(label: String, subject: Node3D) -> bool:
	var box := _aabb_of(subject)
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	for f in [0.3, 0.6, 0.85]:
		var p := box.get_center()
		p.y = box.position.y + box.size.y * f
		var from := _cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, p + (p - from).normalized() * 0.5)
		var hit := space.intersect_ray(q)
		if hit and subject.is_ancestor_of(hit.collider):
			hits += 1
	var ok := hits >= 2
	print("VISIBLE %s ray_hits=%d/3 ok=%s" % [label, hits, ok])
	if not ok:
		_invalid("%s: occluded or not hit (%d of 3 rays)" % [label, hits])
	return ok


## Occluders for the people plates: one static body per drawn wall or floor
## multimesh instance and per mesh of every other placed object, glass left out.
func _colliders(view: BuildView, skip: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ProbeColliders"
	root.add_child(holder)
	for child in view.get_children():
		if child is MultiMeshInstance3D:
			var multimesh := (child as MultiMeshInstance3D).multimesh
			var faces := _opaque_faces(multimesh.mesh)
			for i in multimesh.instance_count:
				if not faces.is_empty():
					var at: Transform3D = (
						(child as Node3D).global_transform * multimesh.get_instance_transform(i)
					)
					holder.add_child(_body(at, faces))
		elif child != skip and child.has_meta("record") and (child as Node3D).is_visible_in_tree():
			for mi in child.find_children("*", "MeshInstance3D", true, false):
				var faces := _opaque_faces((mi as MeshInstance3D).mesh)
				if not faces.is_empty():
					holder.add_child(_body((mi as MeshInstance3D).global_transform, faces))
	return holder


func _body(at: Transform3D, local_faces: PackedVector3Array) -> StaticBody3D:
	var faces := PackedVector3Array()
	for p in local_faces:
		faces.append(at * p)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var body := StaticBody3D.new()
	body.add_child(shape_node)
	return body


func _opaque_faces(mesh: Mesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat != null and mat.resource_path == GLASS:
			continue
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			faces.append_array(verts)
		else:
			for k in index:
				faces.append(verts[k])
	return faces


## The view depths of `points`, with the outline width the shipped fade
## gives a 1.5 px outline there.
func _print_depths(label: String, points: Array[Vector3]) -> void:
	var inv := _cam.global_transform.affine_inverse()
	var lo := INF
	var hi := -INF
	for p in points:
		var depth := -(inv * p).z
		lo = minf(lo, depth)
		hi = maxf(hi, depth)
	print(
		(
			"DEPTH %s view_depth=%.1f..%.1f m shipped_width_px=%.2f..%.2f"
			% [label, lo, hi, _shipped_width(lo), _shipped_width(hi)]
		)
	)


## Mirrors width_at() in toon_outline.gdshader with its defaults (60 m, 240 m).
func _shipped_width(depth: float) -> float:
	var d := maxf(depth, 60.0)
	var t := clampf(log(d / 60.0) / log(240.0 / 60.0), 0.0, 1.0)
	return 1.5 * (1.0 - smoothstep(0.0, 1.0, t))


func _record_defaults() -> void:
	_defaults = {
		"mode": _sun.directional_shadow_mode,
		"max_distance": _sun.directional_shadow_max_distance,
		"split_1": _sun.directional_shadow_split_1,
		"split_2": _sun.directional_shadow_split_2,
		"split_3": _sun.directional_shadow_split_3,
		"blend_splits": _sun.directional_shadow_blend_splits,
		"fade_start": _sun.directional_shadow_fade_start,
		"bias": _sun.shadow_bias,
		"normal_bias": _sun.shadow_normal_bias,
		"blur": _sun.shadow_blur,
		"atlas_size":
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),
		"atlas_16_bits":
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits"),
		"soft_filter":
		ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"
		),
		"msaa_3d": root.msaa_3d,
		"msaa_4x_enum": Viewport.MSAA_4X,
		"screen_space_aa": root.screen_space_aa,
		"mesh_lod_threshold": root.mesh_lod_threshold,
	}
	print("DEFAULTS %s" % _defaults)


func _apply(variant: String) -> void:
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = _defaults["mode"]
	_sun.directional_shadow_max_distance = _defaults["max_distance"]
	_sun.shadow_bias = _defaults["bias"]
	RenderingServer.directional_shadow_atlas_set_size(
		_defaults["atlas_size"], _defaults["atlas_16_bits"]
	)
	root.msaa_3d = _defaults["msaa_3d"]
	root.screen_space_aa = _defaults["screen_space_aa"]
	root.mesh_lod_threshold = _defaults["mesh_lod_threshold"]
	for pair in _outlines:
		(pair[0] as Material).next_pass = pair[1]
		_set_outline_fade(pair[1] as ShaderMaterial, variant == "N")
	match variant:
		"B":
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_sun.directional_shadow_max_distance = 350.0
			_sun.shadow_bias = _defaults["bias"] + 0.05
			RenderingServer.directional_shadow_atlas_set_size(4096, _defaults["atlas_16_bits"])
		"C":
			_sun.shadow_enabled = false
		"D":
			root.msaa_3d = Viewport.MSAA_8X
		"E":
			root.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
	if variant in ["G", "H"]:
		root.mesh_lod_threshold = 0.0
	if variant in ["F", "H"]:
		for pair in _outlines:
			(pair[0] as Material).next_pass = null
	if variant != "reset":
		var outlines_on := 0
		for pair in _outlines:
			outlines_on += 1 if (pair[0] as Material).next_pass != null else 0
		print(
			(
				(
					"VARIANT %s shadow=%s mode=%d max_distance=%.0f bias=%.2f msaa_3d=%d"
					+ " ssaa=%d lod_px=%.1f outline_passes_on=%d"
				)
				% [
					variant,
					_sun.shadow_enabled,
					_sun.directional_shadow_mode,
					_sun.directional_shadow_max_distance,
					_sun.shadow_bias,
					root.msaa_3d,
					root.screen_space_aa,
					root.mesh_lod_threshold,
					outlines_on
				]
			)
		)


## Variant N runs the shipped outline shader (its own fade defaults). Every
## other variant reproduces the old constant-width outline by pushing the
## fade past any view depth and keeping every hull fragment.
func _set_outline_fade(pass_mat: ShaderMaterial, shipped: bool) -> void:
	pass_mat.set_shader_parameter("fade_start", null if shipped else 1.0e6)
	pass_mat.set_shader_parameter("fade_end", null if shipped else 2.0e6)
	pass_mat.set_shader_parameter("min_px", null if shipped else 0.0)


## Adds every material under `node` with an outline next_pass, with that pass.
## Returns how many outline passes the node's meshes carry.
func _collect_outlines(node: Node3D, label: String) -> int:
	var found := 0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := (mi as MeshInstance3D).get_active_material(i)
			if mat == null or mat.next_pass == null:
				continue
			found += 1
			if not _seen_outlines.has(mat):
				_seen_outlines[mat] = true
				_outlines.append([mat, mat.next_pass])
	print("PROBE %s outline_surfaces=%d materials_total=%d" % [label, found, _outlines.size()])
	if found == 0:
		_invalid("no outline pass found on %s" % label)
	if label == "terminal":
		var shader := (_outlines[0][1] as ShaderMaterial).shader
		var defaults := []
		for key in ["outline_px", "fade_start", "fade_end", "min_px"]:
			defaults.append(
				"%s=%s" % [key, RenderingServer.shader_get_parameter_default(shader.get_rid(), key)]
			)
		print("PROBE outline_shader_defaults %s" % " ".join(defaults))
	return found


func _framed_subset(points: Array[Vector3]) -> Array[Vector3]:
	var size := root.get_visible_rect().size
	var rect := Rect2(Vector2(MARGIN_PX, TOOLBAR_PX), size - Vector2(MARGIN_PX * 2, TOOLBAR_PX))
	var out: Array[Vector3] = []
	for p in points:
		if not _cam.is_position_behind(p) and rect.has_point(_cam.unproject_position(p)):
			out.append(p)
	return out


## Puts the focus on the ground point behind the roof centre, so the roof
## centre (at the roof's top height) sits in the middle of the view, the way a
## player pans to look at the roof.
func _place(rig: TycoonCamera, box: AABB, d: float) -> void:
	var c := box.get_center()
	var pitch := deg_to_rad(rig.pitch_for_distance(d))
	var forward := Basis(Vector3.UP, YAW) * Vector3.FORWARD
	var focus := Vector3(c.x, 0.0, c.z) + forward * box.end.y / tan(pitch)
	rig.position = focus
	rig.yaw = YAW
	rig.distance = d
	rig.zoom(1.0)


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Points on the roof: vertical rays over a 7x7 grid of the terminal's
## footprint, kept where they land in the top 40 % of its height.
func _roof_points(terminal: Node3D, box: AABB) -> Array[Vector3]:
	var space := _cam.get_world_3d().direct_space_state
	var out: Array[Vector3] = []
	var floor_y := box.position.y + box.size.y * 0.6
	for i in 7:
		for j in 7:
			var x := lerpf(box.position.x, box.end.x, 0.1 + 0.8 * i / 6.0)
			var z := lerpf(box.position.z, box.end.z, 0.1 + 0.8 * j / 6.0)
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(x, box.end.y + 5.0, z), Vector3(x, box.position.y - 1.0, z)
			)
			var hit := space.intersect_ray(q)
			if hit and terminal.is_ancestor_of(hit.collider) and hit.position.y > floor_y:
				out.append(hit.position)
	return out


func _in_frame(label: String, points: Array[Vector3], report: bool) -> bool:
	var size := root.get_visible_rect().size
	var rect := Rect2(Vector2(MARGIN_PX, TOOLBAR_PX), size - Vector2(MARGIN_PX * 2, TOOLBAR_PX))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var behind := false
	for p in points:
		behind = behind or _cam.is_position_behind(p)
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := not behind and rect.has_point(lo) and rect.has_point(hi)
	if report:
		print(
			(
				"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f,%.0f) ok=%s"
				% [label, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
			)
		)
		if not ok:
			_invalid("%s: roof leaves the frame" % label)
	return ok


func _prove_visible(label: String, terminal: Node3D, points: Array[Vector3]) -> bool:
	var space := _cam.get_world_3d().direct_space_state
	var hits := 0
	for p in points:
		var from := _cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, p + (p - from).normalized() * 0.3)
		var hit := space.intersect_ray(q)
		if hit and terminal.is_ancestor_of(hit.collider) and hit.position.distance_to(p) < 0.5:
			hits += 1
	var ok := hits > 0 and hits * 2 >= points.size()
	print("VISIBLE %s roof ray_hits=%d/%d ok=%s" % [label, hits, points.size(), ok])
	if not ok:
		_invalid("%s: roof occluded or not hit (%d of %d rays)" % [label, hits, points.size()])
	return ok


func _crop_rect(points: Array[Vector3]) -> Rect2i:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var size := root.get_visible_rect().size
	var r := Rect2(lo, hi - lo).grow(CROP_PAD_PX).intersection(Rect2(Vector2.ZERO, size))
	var out := Rect2i(r)
	print("CROP rect=%s" % out)
	return out


func _crop(img: Image, rect: Rect2i) -> Image:
	var crop := img.get_region(rect)
	var k := maxi(1, ceili(float(CROP_MIN_W) / rect.size.x))
	crop.resize(rect.size.x * k, rect.size.y * k, Image.INTERPOLATE_NEAREST)
	return crop


## One sheet: a row of A, B, C, D roof crops per pose.
func _contact_sheet(crops: Dictionary) -> void:
	var w := 0
	var h := 0
	for pose in crops:
		var row_w := 0
		var row_h := 0
		for img in crops[pose]:
			row_w += (img as Image).get_width() + 8
			row_h = maxi(row_h, (img as Image).get_height())
		w = maxi(w, row_w)
		h += row_h + 8
	if w == 0 or h == 0:
		return
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var y := 0
	for pose in crops:
		var x := 0
		var row_h := 0
		for img in crops[pose]:
			var src := img as Image
			sheet.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(x, y))
			x += src.get_width() + 8
			row_h = maxi(row_h, src.get_height())
		y += row_h + 8
	_save(sheet, "contact_sheet.png")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("roof_aa_plates_probe: main thread stalled in %s" % stage)
