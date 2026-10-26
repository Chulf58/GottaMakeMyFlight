extends SceneTree
## Clip probe for the Toon characters' walk, run and sit clips.
##
## Run from WSL (headless: the numeric checks only; windowed: also the plates):
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s C:/Users/chulf/Gotta-make-my-flight/tools/blender/anim/anim_plates_probe.gd
##   (windowed: --display-driver windows --rendering-driver vulkan instead of --headless;
##   one windowed Godot run project-wide)
##
## Numeric checks, both characters: the AnimationPlayer lists exactly the six clips with
## the right loop modes; walk and run, played for three cycles while the node moves at
## the speed convert_toon_batch.py printed, keep every planted foot marker within
## SLIDE_TOLERANCE_M of where it landed and on the floor, using the contact windows the
## converter took from the unstripped Mixamo source (so a slide cannot hide itself);
## the feet stay put through sit_down; every clip moves its bones.
## Plates (windowed): walk, run and sit frame strips of the male character, and both
## characters walking side by side. Every frame proves its subjects are in frame and
## not occluded before it is saved; otherwise PROBE_INVALID and exit 1.

const OUT_REL := "res://../tools/blender/out/anim_clips"
const STEMS := ["tcp_male_character_01", "tcp_female_character_01"]
const PEOPLE := "res://assets/people/%s.glb"
const CLIPS := ["idle", "walk", "run", "sit_down", "sit_idle", "stand_up"]
const LOOPING := ["idle", "walk", "run", "sit_idle"]
const SLIDE_TOLERANCE_M := 0.03
const HEIGHT_TOLERANCE_M := 0.03
const CYCLES := 3
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 120000
const STRIP_FRAMES := 6
const MARKERS := ["Hips", "Head", "Foot.L", "Foot.R", "Toes.L", "Toes.R", "Hand.L", "Hand.R"]

var _out_dir := ""
var _failed := false
var _windowed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_windowed = DisplayServer.get_name() != "headless"
	print("PROBE out_dir=%s windowed=%s" % [_out_dir, _windowed])
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
			OS.crash("anim plates probe hung")


func _run() -> void:
	if _windowed:
		get_root().size = Vector2i(1280, 720)
	var studio := _studio()
	for stem in STEMS:
		_beat("numbers " + stem)
		var rig := _spawn(stem, studio, Vector3.ZERO)
		_check_clips(stem, rig)
		var info := _clip_info(stem)
		_check_lengths(stem, rig, info)
		for clip in ["walk", "run"]:
			_check_contacts(stem, rig, clip, info)
		_check_sit(stem, rig)
		for clip in CLIPS:
			_check_motion(stem, rig, clip)
		rig.queue_free()
	await _frames(2)
	if _windowed:
		await _plates(studio)
	_finish()


func _finish() -> void:
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
		await process_frame
	if _windowed:
		await RenderingServer.frame_post_draw


# ------------------------------------------------------------ rig access


func _spawn(stem: String, parent: Node, pos: Vector3) -> Node3D:
	var node: Node3D = load(PEOPLE % stem).instantiate()
	node.position = pos
	parent.add_child(node)
	return node


func _player(rig: Node3D) -> AnimationPlayer:
	return rig.find_children("*", "AnimationPlayer", true, false)[0]


func _skeleton(rig: Node3D) -> Skeleton3D:
	return rig.find_children("*", "Skeleton3D", true, false)[0]


func _bone(skel: Skeleton3D, bone_name: String) -> int:
	var idx := skel.find_bone(bone_name)
	if idx < 0:
		idx = skel.find_bone(bone_name.replace(".", "_"))
	if idx < 0:
		_invalid("no bone %s" % bone_name)
	return idx


## Pose the rig at clip time t, then return the world position of one bone.
func _pose(rig: Node3D, clip: String, t: float) -> void:
	var player := _player(rig)
	if player.current_animation != clip:
		player.play(clip)
	player.seek(t, true)
	_skeleton(rig).force_update_all_bone_transforms()


func _bone_world(rig: Node3D, bone_name: String) -> Vector3:
	var skel := _skeleton(rig)
	return skel.global_transform * skel.get_bone_global_pose(_bone(skel, bone_name)).origin


func _bone_tip(rig: Node3D, bone_name: String) -> Vector3:
	var skel := _skeleton(rig)
	var pose := skel.get_bone_global_pose(_bone(skel, bone_name))
	return skel.global_transform * (pose * Vector3(0, 0.1, 0))


## The converter's report: speed, forward direction and contact windows per clip.
func _clip_info(stem: String) -> Dictionary:
	var path := _out_dir.path_join(stem + "_clips.json")
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		_invalid("cannot read %s" % path)
		return {}
	return data


## Blender (x, y, z) Z-up to Godot (x, z, -y) Y-up, as the glTF exporter writes it.
func _from_blender(v: Array) -> Vector3:
	return Vector3(v[0], v[2], -v[1])


# ------------------------------------------------------------ numeric checks


func _check_clips(stem: String, rig: Node3D) -> void:
	var player := _player(rig)
	var names: Array = Array(player.get_animation_list())
	names.sort()
	var want: Array = CLIPS.duplicate()
	want.sort()
	var modes := []
	for clip in names:
		var anim := player.get_animation(clip)
		modes.append("%s:%.3fs:loop=%d" % [clip, anim.length, anim.loop_mode])
		var expect := Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
		if anim.loop_mode != expect:
			_invalid("%s %s loop_mode=%d, want %d" % [stem, clip, anim.loop_mode, expect])
	print("CLIPS %s %s" % [stem, " ".join(modes)])
	if names != want:
		_invalid("%s clips %s, want %s" % [stem, names, want])


## Contact windows of one clip, with a window that ends on the last frame joined to the
## same marker's window that starts at frame 0 of the next cycle (the loop seam).
func _merged_windows(ci: Dictionary) -> Array:
	var frames: int = ci["frames"]
	var out: Array = []
	var heads := {}
	for w: Dictionary in ci["contacts"]:
		if int(w["start"]) == 0:
			heads[w["bone"]] = w
	for w: Dictionary in ci["contacts"]:
		var first := int(w["start"])
		var last := int(w["end"])
		if first == 0 and heads.get(w["bone"]) == w:
			var joined := false
			for o: Dictionary in ci["contacts"]:
				joined = joined or (o["bone"] == w["bone"] and int(o["end"]) == frames)
			if joined:
				continue
		if last == frames and heads.has(w["bone"]):
			last = frames + int(heads[w["bone"]]["end"])
		out.append({"bone": w["bone"], "start": first, "end": last, "rest": w["rest_height_m"]})
	return out


func _check_contacts(stem: String, rig: Node3D, clip: String, info: Dictionary) -> void:
	var ci: Dictionary = info["clips"][clip]
	var fps: float = info["fps"]
	var frames: int = ci["frames"]
	var speed: float = ci["speed_mps"]
	var forward := _from_blender(ci["forward_blender"]).normalized()
	var length := _player(rig).get_animation(clip).length
	var worst_slide := 0.0
	var worst_height := 0.0
	var samples := 0
	var windows := 0
	for cycle in CYCLES:
		for w: Dictionary in _merged_windows(ci):
			windows += 1
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			# Half-frame steps, so poses between the baked keys are tested too; playback
			# time wraps at the IMPORTED length, so a wrong length shifts later cycles.
			for h in range(int(w["start"]) * 2, int(w["end"]) * 2 + 1):
				var t_total := (cycle * frames + h * 0.5) / fps
				rig.position = forward * speed * t_total
				_pose(rig, clip, fmod(t_total, length))
				var p := _bone_world(rig, w["bone"])
				lo = lo.min(Vector2(p.x, p.z))
				hi = hi.max(Vector2(p.x, p.z))
				worst_height = maxf(worst_height, absf(p.y - float(w["rest"])))
				samples += 1
			worst_slide = maxf(worst_slide, (hi - lo).length())
	rig.position = Vector3.ZERO
	var seam := 0.0
	for m in MARKERS:
		_pose(rig, clip, 0.0)
		var a := _bone_world(rig, m)
		_pose(rig, clip, length - 0.0001)
		seam = maxf(seam, a.distance_to(_bone_world(rig, m)))
	print(
		(
			(
				"CONTACT %s %s speed_mps=%.3f windows=%d samples=%d worst_slide_extent_m=%.4f "
				+ "worst_height_err_m=%.4f loop_seam_m=%.4f"
			)
			% [stem, clip, speed, windows, samples, worst_slide, worst_height, seam]
		)
	)
	if windows == 0 or samples < windows * 3:
		_invalid("%s %s: no usable contact windows" % [stem, clip])
	if worst_slide > SLIDE_TOLERANCE_M or worst_height > HEIGHT_TOLERANCE_M:
		_invalid("%s %s: planted foot slides or leaves the floor" % [stem, clip])
	if seam > 0.01:
		_invalid("%s %s: loop seam jumps %.3f m" % [stem, clip, seam])


func _check_sit(stem: String, rig: Node3D) -> void:
	var length := _player(rig).get_animation("sit_down").length
	var feet_move := 0.0
	var start := {}
	for i in 11:
		_pose(rig, "sit_down", length * i / 10.0)
		for f in ["Foot.L", "Foot.R", "Toes.L", "Toes.R"]:
			var p := _bone_world(rig, f)
			if i == 0:
				start[f] = p
			feet_move = maxf(feet_move, p.distance_to(start[f]))
	_pose(rig, "sit_down", 0.0)
	var hips_top := _bone_world(rig, "Hips")
	_pose(rig, "sit_down", length)
	var hips_seat := _bone_world(rig, "Hips")
	print(
		(
			"SIT %s feet_max_move_m=%.4f hips_from=(%.3f,%.3f,%.3f) hips_to=(%.3f,%.3f,%.3f)"
			% [
				stem,
				feet_move,
				hips_top.x,
				hips_top.y,
				hips_top.z,
				hips_seat.x,
				hips_seat.y,
				hips_seat.z
			]
		)
	)
	if feet_move > 0.01:
		_invalid("%s sit_down moves the feet %.3f m" % [stem, feet_move])
	if hips_top.y - hips_seat.y < 0.2:
		_invalid("%s sit_down does not lower the hips" % stem)


## Positive proof of motion: some bone moves between consecutive sample times.
func _check_motion(stem: String, rig: Node3D, clip: String) -> void:
	var length := _player(rig).get_animation(clip).length
	var least := INF
	var prev := {}
	for i in STRIP_FRAMES:
		_pose(rig, clip, length * i / STRIP_FRAMES)
		var moved := 0.0
		for m in MARKERS:
			# A point 0.1 m along the bone, so a pure rotation (a head turn) counts too.
			var p := _bone_tip(rig, m)
			if prev.has(m):
				moved = maxf(moved, p.distance_to(prev[m]))
			prev[m] = p
		if i > 0:
			least = minf(least, moved)
	print("MOTION %s %s least_max_bone_move_between_frames_m=%.4f" % [stem, clip, least])
	if least < 0.005:
		_invalid("%s %s: a frame step moves no bone" % [stem, clip])


# ------------------------------------------------------------ plates


func _studio() -> Node3D:
	var studio := Node3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	studio.add_child(sun)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.55, 0.58, 0.55)
	_box(studio, Vector3(0, -0.05, 4), Vector3(12, 0.1, 20), floor_mat)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.2, 0.22, 0.25)
	# Floor marks every 0.5 m along the walking direction, so a slide shows as a foot
	# crossing a mark while it should stand still.
	for i in 25:
		_box(studio, Vector3(0, 0.002, -2.0 + i * 0.5), Vector3(4, 0.004, 0.02), line_mat)
	var cube_mat := StandardMaterial3D.new()
	cube_mat.albedo_color = Color(1.0, 0.45, 0.1)
	_box(studio, Vector3(-1.4, 0.5, -0.8), Vector3.ONE, cube_mat).name = "ReferenceCube1m"
	root.add_child(studio)
	return studio


func _box(parent: Node, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body


func _camera(parent: Node, pos: Vector3, target: Vector3, ortho_size := 0.0) -> Camera3D:
	var cam := Camera3D.new()
	parent.add_child(cam)
	cam.position = pos
	cam.look_at(target)
	if ortho_size > 0.0:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = ortho_size
	else:
		cam.fov = 40.0
	cam.make_current()
	return cam


## Subject markers in frame with a margin, and no collider between camera and marker.
func _prove(cam: Camera3D, label: String, rigs: Array) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var space := cam.get_world_3d().direct_space_state
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var blocked := 0
	for rig: Node3D in rigs:
		for m in MARKERS:
			var p := _bone_world(rig, m)
			if cam.is_position_behind(p):
				_invalid("%s: %s behind the camera" % [label, m])
				return false
			var s := cam.unproject_position(p)
			lo = lo.min(s)
			hi = hi.max(s)
			var from := cam.global_position
			if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
				from = p + cam.global_basis.z * 50.0
			var to := p + (from - p).normalized() * 0.15
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to)):
				blocked += 1
	var ok := rect.has_point(lo) and rect.has_point(hi) and blocked == 0
	print(
		(
			"INFRAME %s screen=(%.0f,%.0f)-(%.0f,%.0f) height_px=%.0f blocked=%d ok=%s"
			% [label, lo.x, lo.y, hi.x, hi.y, hi.y - lo.y, blocked, ok]
		)
	)
	if not ok:
		_invalid("%s: subject leaves the frame or is occluded" % label)
	return ok


func _plates(studio: Node3D) -> void:
	var male := STEMS[0]
	var info := _clip_info(male)
	for clip in ["walk", "run"]:
		_beat("strip " + clip)
		var rig := _spawn(male, studio, Vector3.ZERO)
		var ci: Dictionary = info["clips"][clip]
		var speed: float = ci["speed_mps"]
		var length: float = ci["duration_s"]
		var travel := speed * length
		var mid := Vector3(0, 1.0, travel * 0.5)
		var cam := _camera(
			studio, mid + Vector3(8, 0.6, 0), mid, maxf(2.6, (travel + 1.6) * 0.5625)
		)
		var frames: Array[Image] = []
		for i in STRIP_FRAMES:
			var t := length * i / STRIP_FRAMES
			rig.position = Vector3(0, 0, speed * t)
			_pose(rig, clip, t)
			_player(rig).pause()
			await _frames(3)
			if not _prove(cam, "%s_%s_f%d" % [male, clip, i], [rig]):
				return
			frames.append(await _grab())
		_save(_sheet(frames, 3), "%s_%s_strip.png" % [male, clip])
		cam.queue_free()
		rig.queue_free()
	await _sit_strip(studio, male, info)
	await _side_by_side(studio)


func _sit_strip(studio: Node3D, stem: String, info: Dictionary) -> void:
	_beat("strip sit")
	var seat: Dictionary = info["seat"]
	var seat_mat := StandardMaterial3D.new()
	seat_mat.albedo_color = Color(0.25, 0.45, 0.7)
	# The seat the clip implies: top at seat_top_m, its contact behind the origin.
	var top: float = seat["top"]
	var back: float = seat["back"]
	var seat_box := _box(
		studio, Vector3(0, top * 0.5, -back - 0.05), Vector3(0.6, top, 0.45), seat_mat
	)
	var rig := _spawn(stem, studio, Vector3.ZERO)
	var cam := _camera(studio, Vector3(3.2, 1.4, 2.6), Vector3(0, 0.85, -0.2))
	var frames: Array[Image] = []
	var down := _player(rig).get_animation("sit_down").length
	var times := [
		["sit_down", 0.0],
		["sit_down", down * 0.33],
		["sit_down", down * 0.66],
		["sit_down", down],
		["sit_idle", 2.0],
		["stand_up", down * 0.5],
	]
	for i in times.size():
		_pose(rig, times[i][0], times[i][1])
		_player(rig).pause()
		await _frames(3)
		if not _prove(cam, "%s_sit_f%d" % [stem, i], [rig]):
			return
		frames.append(await _grab())
	_save(_sheet(frames, 3), "%s_sit_strip.png" % stem)
	cam.queue_free()
	rig.queue_free()
	seat_box.queue_free()


func _side_by_side(studio: Node3D) -> void:
	_beat("side by side")
	var rigs: Array = []
	var x := -0.55
	for stem in STEMS:
		rigs.append(_spawn(stem, studio, Vector3(x, 0, 0)))
		x += 1.1
	var cam := _camera(studio, Vector3(3.0, 2.0, 6.5), Vector3(0, 0.95, 1.0))
	var frames: Array[Image] = []
	for i in 3:
		for r: Node3D in rigs:
			var stem: String = STEMS[rigs.find(r)]
			var ci: Dictionary = _clip_info(stem)["clips"]["walk"]
			var t: float = ci["duration_s"] * (0.15 + 0.3 * i)
			r.position.z = float(ci["speed_mps"]) * t
			_pose(r, "walk", t)
			_player(r).pause()
		await _frames(3)
		if not _prove(cam, "side_by_side_f%d" % i, rigs):
			return
		frames.append(await _grab())
	_save(_sheet(frames, 3), "both_walk_side_by_side.png")


func _grab() -> Image:
	await _frames(2)
	return root.get_texture().get_image()


func _sheet(frames: Array[Image], columns: int) -> Image:
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var rows := ceili(frames.size() / float(columns))
	var sheet := Image.create(w * columns, h * rows, false, frames[0].get_format())
	for i in frames.size():
		var src := Rect2i(Vector2i.ZERO, Vector2i(w, h))
		sheet.blit_rect(frames[i], src, Vector2i((i % columns) * w, (i / columns) * h))
	return sheet


func _save(img: Image, file_name: String) -> void:
	var path := _out_dir.path_join(file_name)
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


## Imported clip lengths equal the lengths the converter baked (no lead-in or trailing hold).
func _check_lengths(stem: String, rig: Node3D, info: Dictionary) -> void:
	for clip in CLIPS:
		var want: float = info["clips"][clip]["duration_s"]
		var got := _player(rig).get_animation(clip).length
		if absf(got - want) > 0.001:
			_invalid("%s %s imported length %.4f s, baked %.4f s" % [stem, clip, got, want])
