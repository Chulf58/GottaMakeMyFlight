extends SceneTree
## Windowed plate probe for the one-flight airside slice.
##
## Run (one windowed Godot run project-wide; hold game/.godot/windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/airside_plates_probe.gd
##
## Plates: a top-down overview of the runway, taxi route and stand with the plane at the
## stand, and a frame strip of landing, taxiing and takeoff at 3x. The sim is stepped by
## hand (the clock's own process is off) with a 60 fps frame delta, so every frame is
## ticks, not wall time. Each plate proves the plane is in frame and hit by rays first;
## otherwise PROBE_INVALID is printed and the probe exits 1. Plates go to
## tools/blender/out/airside_flight/.

const OUT_REL := "res://../tools/blender/out/airside_flight"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 90000
const FRAME := 1.0 / 60.0
const FOLLOW_DISTANCE := 75.0
## Sim ticks sampled for the strip, four per row: landing, taxiing, takeoff.
const STRIP_ROWS := [
	["landing", [150, 228, 280, 345]],
	["taxiing", [420, 500, 580, 655]],
	["takeoff", [1590, 1670, 1730, 1770]],
]

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _clock: SimClock
var _plane: Node3D
var _cam: Camera3D
var _rig: Node3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
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
			OS.crash("airside plates probe hung")


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.set_process(false)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_plane = _main.get_node("PlaneView")
	await _frames(10)
	_add_colliders(_main)
	await physics_frame
	print("PROBE speed_set=", _clock.set_speed(3), " speed=", _clock.speed)
	await _strip()
	await _overview()
	await _framing()
	await _stand_view()
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
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(3)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name)
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


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


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


func _add_colliders(node: Node) -> void:
	for mi in _meshes(node):
		if mi.mesh != null:
			mi.create_trimesh_collision()


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


## Rays from the camera to sampled surface points of the subject; at least half must hit
## the subject first. Supporting evidence only: the plate itself shows visibility.
func _prove_visible(label: String, subject: Node3D) -> bool:
	var centre := _aabb_of(subject).get_center()
	var targets: Array[Vector3] = []
	for mi in _meshes(subject):
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var step := maxi(1, floori(faces.size() / 8.0))
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
	var ok := hits * 2 >= targets.size() and hits > 0
	print("VISIBLE %s ray_hits=%d/%d ok=%s" % [label, hits, targets.size(), ok])
	if not ok:
		_invalid("%s: occluded or not hit (%d of %d rays)" % [label, hits, targets.size()])
	return ok


## Steps the sim by 60 fps frames at the clock's speed until it reaches `target`.
func _step_to(target: int) -> void:
	var guard := 0
	while _clock.tick < target and guard < 100000:
		_clock.advance(FRAME)
		guard += 1


func _sim() -> FlightSim:
	return _main.get_node("FlightSim")


func _follow() -> void:
	var p: Vector3 = _plane.global_position
	_rig.position = Vector3(p.x, p.y, p.z)
	_rig.distance = FOLLOW_DISTANCE
	_rig.yaw = 0.0
	_rig.zoom(1.0)


func _strip() -> void:
	_beat("strip")
	var rows: Array[Image] = []
	for row in STRIP_ROWS:
		var frames: Array[Image] = []
		for target in row[1]:
			_step_to(target)
			_plane.update_pose()
			_follow()
			await physics_frame
			await physics_frame
			await _frames(2)
			var model: Node3D = _plane.get_node("Pivot")
			var tag := "%s_t%d" % [row[0], _clock.tick]
			print(
				(
					"FRAME %s tick=%d state=%d pos=%s nose=%s pitch_deg=%.1f"
					% [
						tag,
						_clock.tick,
						_sim().state_of("GMF101-d0"),
						_plane.global_position,
						_plane.global_basis.z,
						rad_to_deg(asin(_plane.global_basis.z.y))
					]
				)
			)
			if not _plane.visible:
				_invalid("%s: plane hidden" % tag)
				continue
			if not (_prove_in_frame(tag, _corners(_aabb_of(model))) and _prove_visible(tag, model)):
				continue
			var img := await _grab()
			_save(img, "frame_%s.png" % tag)
			img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
			frames.append(img)
		var line := Image.create(640 * frames.size(), 360, false, Image.FORMAT_RGBA8)
		for k in frames.size():
			line.blit_rect(frames[k], Rect2i(0, 0, 640, 360), Vector2i(k * 640, 0))
		rows.append(line)
	var sheet := Image.create(2560, 360 * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		sheet.blit_rect(rows[r], Rect2i(Vector2i.ZERO, rows[r].get_size()), Vector2i(0, r * 360))
	_save(sheet, "frame_strip_3x.png")


## A straight-down orthographic view of the whole airfield with the plane at the stand,
## and marker spheres on every waypoint.
func _overview() -> void:
	_beat("overview")
	# The strip ran the clock to the end of the flight; rewind to mid-boarding through the
	# sim's own snapshot so the plane stands at the gate.
	var snap := _sim().to_snapshot()
	snap["tick"] = 800
	snap["flights"][0]["state"] = FlightSim.State.BOARDING
	print("OVERVIEW restore=", _sim().from_snapshot(snap))
	_clock.tick = 800
	_plane.update_pose()
	var airside: Node3D = _main.get_node("Airside")
	for m in airside.get_children():
		if m is Marker3D:
			var dot := MeshInstance3D.new()
			dot.mesh = SphereMesh.new()
			dot.scale = Vector3.ONE * 4.0
			dot.position = m.position + Vector3(0, 1, 0)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1, 0.2, 0.9)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dot.material_override = mat
			airside.add_child(dot)
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 290.0
	top.far = 1000.0
	_main.add_child(top)
	top.look_at_from_position(Vector3(0, 400, -100), Vector3(0, 0, -100), Vector3.FORWARD)
	top.make_current()
	_cam = top
	await _frames(4)
	var model: Node3D = _plane.get_node("Pivot")
	print(
		"OVERVIEW plane_state=", _sim().state_of("GMF101-d0"), " plane_pos=", _plane.global_position
	)
	var terminal: Node3D = airside.get_node("Terminal")
	var pts: Array[Vector3] = _corners(_aabb_of(model)) + _corners(_aabb_of(terminal))
	if _prove_in_frame("overview", pts):
		_save(await _grab(), "overview_top.png")


## Candidate default framings for the camera: projects the stand, the terminal's airside
## edge and the build grid corners, and saves a plate of each.
func _framing() -> void:
	_beat("framing")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_cam.make_current()
	var stand: Vector3 = _main.get_node("Airside/Stand").global_position
	var terminal: Node3D = _main.get_node("Airside/Terminal")
	var targets := {
		"stand": stand,
		"terminal_airside": terminal.global_position + Vector3(0, 8, -20),
		"terminal_centre": terminal.global_position + Vector3(0, 8, 0),
		"grid_nw": Vector3(-32, 0, -32),
		"grid_se": Vector3(32, 0, 32),
	}
	var shots := {"default": [Vector3.ZERO, 60.0], "airport": [Vector3(0, 0, -50), 120.0]}
	for key in shots:
		_rig.position = shots[key][0]
		_rig.distance = shots[key][1]
		_rig.yaw = 0.0
		_rig.zoom(1.0)
		await _frames(4)
		var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
		for name in targets:
			var s := _cam.unproject_position(targets[name])
			print(
				(
					"FRAMING %s %s screen=(%.0f,%.0f) on_screen=%s"
					% [key, name, s.x, s.y, rect.has_point(s)]
				)
			)
		_save(await _grab(), "framing_%s.png" % key)


## The plane at the stand seen from the apron side (camera yawed to look south), to check
## it is nose-in at the terminal's airside face.
func _stand_view() -> void:
	_beat("stand_view")
	_plane.update_pose()
	_rig.position = Vector3(_plane.global_position.x, 0.0, _plane.global_position.z + 8.0)
	_rig.distance = 60.0
	_rig.yaw = PI
	_rig.zoom(1.0)
	await physics_frame
	await physics_frame
	await _frames(4)
	var model: Node3D = _plane.get_node("Pivot")
	if (
		_prove_in_frame("stand_view", _corners(_aabb_of(model)))
		and _prove_visible("stand_view", model)
	):
		_save(await _grab(), "stand_view.png")
