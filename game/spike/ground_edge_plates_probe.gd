extends SceneTree
## Windowed plate probe for the edge of the ground plane (board item
## at-far-zoom-the-edge-of-the-700x700-m-ground-plane-shows-as).
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <game> -s res://spike/ground_edge_plates_probe.gd -- <tag>
## <tag> (default "after") prefixes every plate, so a run on the old ground
## ("before") and one on the new ground ("after") sit side by side.
##
## Boots main.tscn with the clock stopped. Plates, under
## tools/blender/out/ground-edge/:
##  a. <tag>_home.png: the start view, as the game boots. On an "after" run the
##     pixel difference against before_home.png is printed.
##  b. <tag>_far_<name>.png: the farthest zoom, panned through the camera's own
##     pan() far past its bounds toward each of the four edges and the four
##     corners, looking outward. Each prints the focus, distance and yaw
##     against the camera's limits, proves the old ground edge point ahead is
##     in frame and in plain sight, and casts a grid of view rays: every ray
##     must land on the ground plane, inside its mesh and nearer than the far
##     clip. On a "before" run the misses are the control: they must be above 0
##     at the edges, or the check would pass by accident.
##  c. <tag>_far_<name>_21x9 and _32x9: the worst corner again in wider windows.
##  d. Frame time at the farthest zoom (vsync off), printed per view.
## Any failed proof prints PROBE_INVALID and the probe exits 1.

const OUT_REL := "res://../tools/blender/out/ground-edge"
const MAIN_SCENE := "res://main/main.tscn"
const HANG_LIMIT_MS := 120000
const MARGIN_PX := 8.0
const THUMB := Vector2i(512, 288)
## A pan amount far past any bound: pan() scales it by the zoom distance and
## clamps the focus to the camera's bounds.
const PAN_PUSH := 1.0e4
## View rays per side of the coverage grid.
const RAY_GRID := 24
## Where the old 700 m ground ended, half its side.
const OLD_EDGE := 350.0
## A sight line to a ground point may stop this close to it on the ground.
const SIGHT_SLACK := 2.0
const WARM_FRAMES := 60
const TIMING_FRAMES := 240
## Outward directions (x, z) of the eight extremes.
const EXTREMES := {
	"east": Vector2(1, 0),
	"west": Vector2(-1, 0),
	"north": Vector2(0, -1),
	"south": Vector2(0, 1),
	"northeast": Vector2(1, -1),
	"northwest": Vector2(-1, -1),
	"southeast": Vector2(1, 1),
	"southwest": Vector2(-1, 1),
}
## Window sizes (screen pixels) for the wide-screen retakes.
const WIDE_WINDOWS := {"21x9": Vector2i(1680, 720), "32x9": Vector2i(1920, 540)}

var _tag := "after"
var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _rig: TycoonCamera
var _cam: Camera3D
var _ground_half := 0.0
var _plates: Array[Image] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_tag = args[0]
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for old_plate in DirAccess.get_files_at(_out_dir):
		if old_plate.begins_with(_tag + "_") and old_plate.ends_with(".png"):
			DirAccess.remove_absolute(_out_dir.path_join(old_plate))
	print("PROBE tag=%s out_dir=%s" % [_tag, _out_dir])
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
			OS.crash("ground edge plates probe hung")


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE seed=", world_seed)
	root.add_child(_main)
	# Processing turns on when the clock becomes ready; only this probe steps it.
	clock.set_process(false)
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	var ground: MeshInstance3D = _main.get_node("Ground")
	_ground_half = (ground.mesh as PlaneMesh).size.x * 0.5
	var env: Environment = (_main.get_node("WorldEnvironment") as WorldEnvironment).environment
	print(
		(
			"PROBE limits min_distance=%.1f max_distance=%.1f bounds_half_extent=%.1f fov=%.1f far=%.1f"
			% [_rig.min_distance, _rig.max_distance, _rig.bounds_half_extent, _cam.fov, _cam.far]
		)
	)
	print(
		(
			"PROBE ground size=%s y=%.2f fog=%s"
			% [(ground.mesh as PlaneMesh).size, ground.global_position.y, env.fog_enabled]
		)
	)
	await _frames(20)
	print("PROBE viewport=%s" % root.get_visible_rect().size)
	await _plate_home()
	print("PROBE colliders=", _add_colliders())
	await physics_frame
	await physics_frame
	var edge_misses := 0
	for name in EXTREMES:
		_beat("far_" + name)
		var misses := await _plate_far(name, EXTREMES[name], "")
		var outward: Vector2 = EXTREMES[name]
		if outward.x == 0.0 or outward.y == 0.0:
			edge_misses += misses
	print("PROBE edge_misses_total=%d" % edge_misses)
	if _tag == "before" and edge_misses == 0:
		_invalid("control: the old ground showed no miss at any edge")
	for wide in WIDE_WINDOWS:
		_beat("wide_" + wide)
		DisplayServer.window_set_size(WIDE_WINDOWS[wide])
		await _frames(20)
		print("PROBE window=%s viewport=%s" % [wide, root.get_visible_rect().size])
		await _plate_far("northeast", EXTREMES["northeast"], "_" + wide)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await _frames(20)
	await _time_far()
	_sheet()
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
	var path := _out_dir.path_join("%s_%s.png" % [_tag, name])
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	_plates.append(img)
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)


## Screen position of `point`, or a negative vector when it is behind the
## camera or outside the frame less the margin.
func _on_screen(point: Vector3) -> Vector2:
	if _cam.is_position_behind(point):
		return -Vector2.ONE
	var s := _cam.unproject_position(point)
	return s if _screen_rect().has_point(s) else -Vector2.ONE


## One trimesh body per visible mesh, so sight lines stop at what is drawn.
func _add_colliders() -> int:
	var count := 0
	for mi in _main.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		m.create_trimesh_collision()
		count += 1
	return count


## Whether a sight line from the camera reaches ground point `point`: it hits
## nothing, or the ground within SIGHT_SLACK of the point.
func _in_sight(point: Vector3) -> String:
	var from := _cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, point + (point - from).normalized() * 0.5)
	var hit := _cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return "clear"
	var by := str(hit.collider.get_path())
	if hit.position.distance_to(point) <= SIGHT_SLACK:
		return "clear (lands on %s)" % by.get_file()
	return "blocked by %s at %.1f m from it" % [by, hit.position.distance_to(point)]


func _plate_home() -> void:
	_beat("home")
	print(
		(
			"HOME focus=%s distance=%.1f yaw=%.3f pitch=%.1f"
			% [_rig.position, _rig.distance, _rig.yaw, _rig.pitch_for_distance(_rig.distance)]
		)
	)
	var at := _on_screen(_rig.position)
	if at.x < 0.0:
		_invalid("home: the focus %s is not in frame" % _rig.position)
		return
	print("HOME focus in frame at %s" % at)
	var img := await _grab()
	_save(img, "home")
	if _tag == "before":
		return
	var before_path := _out_dir.path_join("before_home.png")
	if not FileAccess.file_exists(before_path):
		print("HOME no before_home.png to compare with")
		return
	var before := Image.load_from_file(before_path)
	before.convert(Image.FORMAT_RGBA8)
	if before.get_size() != img.get_size():
		print("HOME before size %s differs from %s" % [before.get_size(), img.get_size()])
		return
	var changed := 0
	var total := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y)
			var b := before.get_pixel(x, y)
			var d := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			total += d
			if d > 8.0 / 255.0:
				changed += 1
	var count := img.get_width() * img.get_height()
	print(
		(
			"HOME diff vs before: pixels_changed=%d of %d (%.3f%%) mean_abs=%.5f"
			% [changed, count, 100.0 * changed / count, total / count]
		)
	)


## Shoots the farthest zoom pushed toward `outward`; returns the coverage misses.
func _plate_far(name: String, outward: Vector2, suffix: String) -> int:
	var dir := outward.normalized()
	_rig.position = _rig.home_position
	_rig.yaw = atan2(-dir.x, -dir.y)
	_rig.zoom(1000.0)
	_rig.distance = _rig.target_distance
	# Forward is the rig's -y pan axis.
	_rig.pan(Vector2(0.0, -PAN_PUSH))
	await _frames(10)
	var bound := _rig.bounds_half_extent
	var pos := _rig.position
	var pinned := (
		(outward.x == 0.0 or is_equal_approx(absf(pos.x), bound))
		and (outward.y == 0.0 or is_equal_approx(absf(pos.z), bound))
	)
	print(
		(
			(
				"EXTREME %s%s focus=(%.1f, %.1f) distance=%.1f yaw=%.3f"
				+ " | bounds=+-%.1f max_distance=%.1f pinned=%s"
			)
			% [
				name,
				suffix,
				pos.x,
				pos.z,
				_rig.distance,
				_rig.yaw,
				bound,
				_rig.max_distance,
				pinned
			]
		)
	)
	if not pinned or not is_equal_approx(_rig.distance, _rig.max_distance):
		_invalid("%s%s: the camera is not at its extreme" % [name, suffix])
	var edge_point := Vector3(
		OLD_EDGE * signf(outward.x) if outward.x != 0.0 else pos.x,
		-0.1,
		OLD_EDGE * signf(outward.y) if outward.y != 0.0 else pos.z
	)
	var at := _on_screen(edge_point)
	var sight := _in_sight(edge_point)
	print(
		"EXTREME %s%s old_edge_point=%s screen=%s sight=%s" % [name, suffix, edge_point, at, sight]
	)
	if at.x < 0.0:
		_invalid("%s%s: the old ground edge point is not in frame" % [name, suffix])
	if not sight.begins_with("clear"):
		_invalid("%s%s: the old ground edge point is hidden" % [name, suffix])
	var misses := _coverage(name + suffix)
	if _tag != "before" and misses > 0:
		_invalid("%s%s: %d view rays miss the ground" % [name, suffix, misses])
	_save(await _grab(), "far_%s%s" % [name, suffix])
	return misses


## Casts RAY_GRID x RAY_GRID view rays across the whole frame and counts those
## that do not land on the ground mesh nearer than the far clip.
func _coverage(label: String) -> int:
	var size := root.get_visible_rect().size
	var to_view := _cam.global_transform.affine_inverse()
	var misses := 0
	var reach := Vector2.ZERO
	var deepest := 0.0
	var sky := 0
	for j in RAY_GRID + 1:
		for i in RAY_GRID + 1:
			var px := Vector2(size.x * i / RAY_GRID, size.y * j / RAY_GRID)
			px = px.clamp(Vector2.ZERO, size - Vector2.ONE)
			var origin := _cam.project_ray_origin(px)
			var normal := _cam.project_ray_normal(px)
			if normal.y >= 0.0:
				sky += 1
				misses += 1
				continue
			var hit := origin + normal * ((-0.1 - origin.y) / normal.y)
			var depth := -(to_view * hit).z
			reach = reach.max(Vector2(absf(hit.x), absf(hit.z)))
			deepest = maxf(deepest, depth)
			if absf(hit.x) > _ground_half or absf(hit.z) > _ground_half or depth > _cam.far:
				misses += 1
	print(
		(
			"COVER %s rays=%d misses=%d sky=%d reach=(%.0f, %.0f) ground_half=%.0f deepest=%.0f far=%.0f"
			% [
				label,
				(RAY_GRID + 1) * (RAY_GRID + 1),
				misses,
				sky,
				reach.x,
				reach.y,
				_ground_half,
				deepest,
				_cam.far
			]
		)
	)
	return misses


## Frame time at the farthest zoom with vsync off: wall time per frame and the
## renderer's own CPU and GPU times, for two views.
func _time_far() -> void:
	_beat("timing")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var views := {"far_home": Vector2.ZERO, "far_east": EXTREMES["east"]}
	for label in views:
		_rig.position = _rig.home_position
		_rig.yaw = _rig.home_yaw if label == "far_home" else atan2(-1.0, 0.0)
		_rig.zoom(1000.0)
		_rig.distance = _rig.target_distance
		if label != "far_home":
			_rig.pan(Vector2(0.0, -PAN_PUSH))
		await _frames(WARM_FRAMES)
		var walls: Array[float] = []
		var gpu := 0.0
		var cpu := 0.0
		var last := Time.get_ticks_usec()
		for k in TIMING_FRAMES:
			_beat("timing")
			await process_frame
			var now := Time.get_ticks_usec()
			walls.append((now - last) / 1000.0)
			last = now
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		walls.sort()
		var mean := 0.0
		for w in walls:
			mean += w
		mean /= walls.size()
		print(
			(
				(
					"TIMING %s %s frames=%d wall_mean_ms=%.3f wall_median_ms=%.3f"
					+ " wall_p95_ms=%.3f gpu_mean_ms=%.3f cpu_mean_ms=%.3f"
				)
				% [
					_tag,
					label,
					TIMING_FRAMES,
					mean,
					walls[walls.size() / 2],
					walls[int(walls.size() * 0.95)],
					gpu / TIMING_FRAMES,
					cpu / TIMING_FRAMES
				]
			)
		)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


func _sheet() -> void:
	var columns := 4
	var rows := ceili(_plates.size() / float(columns))
	var sheet := Image.create(THUMB.x * columns, THUMB.y * rows, false, Image.FORMAT_RGBA8)
	for k in _plates.size():
		var thumb: Image = _plates[k].duplicate()
		thumb.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			thumb,
			Rect2i(Vector2i.ZERO, THUMB),
			Vector2i((k % columns) * THUMB.x, (k / columns) * THUMB.y)
		)
	var path := _out_dir.path_join("%s_contact_sheet.png" % _tag)
	if sheet.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, sheet.get_size()])
