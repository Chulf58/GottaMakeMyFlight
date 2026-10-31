extends SceneTree
## Windowed plate probe for the planes' sky path (ruling
## ambient-life-starts-with-planes-each-real-flight-in-the-sim).
##
## Run (one windowed Godot run project-wide; hold the windowed lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <game> -s res://spike/sky_path_plates_probe.gd
##
## Boots main.tscn, opens the airport, waits for the starter's second-day flight
## (its first day takes the straight-in; the second has the full lead-in) and
## steps the sim by hand, forward only. Frame ticks are planned first from
## PlaneView.pose_at for each camera, then shot in time order. Plates, under
## tools/blender/out/sky_path/:
##  a. the default view: eight frames of the arrival's sun shadow crossing the
##     terminal floor. Each proves the shadow's ground point is in frame and in
##     plain sight, and that the pixels there are darker than in a twin frame
##     with the planes hidden.
##  b. full zoom-out: eight frames of the arrival and eight of the departure,
##     each proving the plane's bounds are in frame and that rays reach it, and
##     printing its height, the far silhouette's darkness and the screen gap
##     between the plane and its silhouette.
## Any failed proof prints PROBE_INVALID and the probe exits 1.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/sky_path"
const MAIN_SCENE := "res://main/main.tscn"
## Ticks the probe may step to reach the starter's second day.
const DAY_LIMIT_TICKS := 40000
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 120000
const FRAMES_PER_STRIP := 8
const THUMB := Vector2i(768, 432)
## The terminal floor, from its walls (x -43..43, z -100..-40).
const TERMINAL_FLOOR := Rect2(-43.0, -100.0, 86.0, 60.0)
## A sight line to the shadow's ground point may stop this far from it: the
## terminal floor sits about 0.3 m above the ground plane.
const SIGHT_SLACK := 1.5
## The shadow must darken its ground point by at least this much luminance.
const SHADOW_DARKENING := 0.05
## Full zoom-out focus points, inside the camera's bounds.
## The arrival is seen from the south, as the game starts; the departure from
## the east end of the runway looking west (a quarter turn of the camera), so
## the climb-out comes toward the viewer clear of the HUD in the top right.
const FAR_ARRIVAL_FOCUS := Vector3(-260.0, 0.0, -40.0)
const FAR_DEPARTURE_FOCUS := Vector3(260.0, 0.0, -230.0)
const FAR_DEPARTURE_YAW := PI / 2.0
## Where the HUD sits in the viewport (1536 x 864), measured on these plates:
## money and rating, Offers, the clock panel and result card, Departures, the
## opening toast and the build bar. Planning keeps the plane clear of them; the
## HUD twin in _prove_airborne is the proof.
const HUD_BOXES: Array[Rect2] = [
	Rect2(0, 0, 560, 62),
	Rect2(890, 0, 180, 56),
	Rect2(1070, 0, 466, 335),
	Rect2(0, 325, 165, 50),
	Rect2(470, 750, 600, 50),
	Rect2(240, 800, 1296, 64),
	# The right edge, where an arrival frame measured 2% HUD cover.
	Rect2(1380, 0, 156, 864),
]
## Share of the plane's screen box the HUD may cover.
const HUD_COVER_LIMIT := 0.02
## The far silhouette must sit at least this many plane-sizes from the plane on
## screen, so the plane is seen clear of the ground under it.
const AIRBORNE_GAP := 0.6

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _clock: SimClock
var _sim: FlightSim
var _plane: PlaneView
var _cam: Camera3D
var _rig: TycoonCamera
var _flight := ""
## The start view as main.tscn boots it, kept for the default plates.
var _home := {}


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for old_plate in DirAccess.get_files_at(_out_dir):
		if old_plate.ends_with(".png"):
			DirAccess.remove_absolute(_out_dir.path_join(old_plate))
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
			OS.crash("sky path plates probe hung")


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.set_process(false)
	var world_seed := randi()
	_clock.seed_rng(world_seed)
	print("PROBE seed=", world_seed)
	root.add_child(_main)
	# A node that defines _process gets processing turned on when it becomes
	# ready, so turn the clock's off again now: only this probe steps it.
	_clock.set_process(false)
	_sim = _main.get_node("FlightSim")
	_plane = _main.get_node("PlaneView")
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	await _frames(10)
	var gate := _main.get_node("AirportGate") as AirportGate
	if not gate.open():
		_invalid("the airport did not open")
		_finish()
		return
	# The starter's first day flies the straight-in (it may be listed late);
	# its second day is issued with the full lead and flies the terminal pass.
	_flight = FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 1)
	var guard := 0
	while not _sim.flight_ids().has(_flight) and guard < DAY_LIMIT_TICKS:
		_clock.advance(SimClock.STEP)
		guard += 1
		if guard % 500 == 0:
			_beat("to_day_1")
	if not _sim.flight_ids().has(_flight):
		_invalid("the starter's second-day flight %s was not issued" % _flight)
		_finish()
		return
	var starts := _plane.starts_of(_flight)
	print("PROBE flight=%s starts=%s tick=%d" % [_flight, starts, _clock.tick])
	var sun: DirectionalLight3D = _main.get_node("Sun")
	print(
		(
			"PROBE sun light=%s shadow=%s max_distance=%.0f mode=%d"
			% [
				-sun.global_basis.z,
				sun.shadow_enabled,
				sun.directional_shadow_max_distance,
				sun.directional_shadow_mode
			]
		)
	)
	print("PROBE colliders=", _add_colliders())
	await physics_frame
	await physics_frame
	var local_box := _plane_local_box()
	var plan := {
		"default": _plan_default(starts, local_box),
		"arrival": _plan_far(starts, "arrival", local_box),
		"departure": _plan_far(starts, "departure", local_box),
	}
	var shots: Array[Array] = []
	for kind in plan:
		print("PLAN %s ticks=%s" % [kind, plan[kind]])
		if plan[kind].size() != FRAMES_PER_STRIP:
			_invalid("%s: the subject was in frame for too few ticks" % kind)
		for tick in plan[kind]:
			shots.append([tick, kind])
	shots.sort()
	var frames := {"default": [] as Array[Image], "arrival": [] as Array[Image]}
	frames["departure"] = [] as Array[Image]
	for shot in shots:
		var img := await _shoot(shot[0], shot[1])
		if img != null:
			frames[shot[1]].append(img)
	_sheet(frames["default"], "strip_default_shadow.png")
	_sheet(frames["arrival"], "strip_far_arrival.png")
	_sheet(frames["departure"], "strip_far_departure.png")
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


## Steps the clock so PlaneView draws sim time `time` exactly: to tick
## `time` + 1 with no alpha left over.
func _draw_at(time: int) -> void:
	_step_to(time)
	_clock.advance((1.0 - _clock.alpha) * SimClock.STEP)
	var drawn := float(_clock.tick) - 1.0 + _clock.alpha
	if absf(drawn - time) > 0.01:
		_invalid("the clock drew time %.3f, not %d" % [drawn, time])


## Steps the sim tick by tick (1x, one STEP each) up to `target`.
func _step_to(target: int) -> void:
	_clock.set_speed(1)
	var guard := 0
	while _clock.tick < target and guard < 200000:
		_clock.advance(SimClock.STEP)
		guard += 1
		if guard % 500 == 0:
			_beat("step_to")


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _plane_box() -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(_plane.get_node("Pivot")):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## One trimesh body per mesh drawn now, except the far silhouettes.
func _add_colliders() -> int:
	var count := 0
	for mi in _meshes(_main):
		var path := String(mi.get_path())
		if mi.mesh == null or path.contains("FarShadow"):
			continue
		if not mi.is_visible_in_tree() and not path.contains("/Pivot/"):
			continue
		mi.create_trimesh_collision()
		count += 1
	return count


func _screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)


func _in_frame(points: Array[Vector3]) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		if _cam.is_position_behind(p):
			return Rect2()
		var s := _cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var rect := Rect2(lo, hi - lo)
	return rect if _screen_rect().encloses(rect) else Rect2()


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


## The first thing a ray from the camera to `point` hits, and how far that hit
## is from the point (a floor raised a little above y 0 is hit just short of a
## ground point; a wall or roof is hit metres away).
func _blocked_by(point: Vector3) -> Dictionary:
	var from := _cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, point + (point - from).normalized() * 0.3)
	var hit := _cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"away": 0.0, "by": "nothing"}
	return {"away": hit.position.distance_to(point), "by": str(hit.collider.get_path())}


## Rays from the camera to points on the plane; how many hit the plane first.
func _plane_ray_hits() -> Vector2i:
	var pivot := _plane.get_node("Pivot")
	var centre := _plane_box().get_center()
	var targets: Array[Vector3] = []
	for mi in _meshes(pivot):
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
		if hit and pivot.is_ancestor_of(hit.collider):
			hits += 1
	return Vector2i(hits, targets.size())


func _luminance(img: Image, at: Vector2) -> float:
	var total := 0.0
	var count := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var p := Vector2i(at) + Vector2i(dx, dy)
			if Rect2i(Vector2i.ZERO, img.get_size()).has_point(p):
				total += img.get_pixelv(p).get_luminance()
				count += 1
	return total / maxf(count, 1.0)


## Plate pixels (every second one) the planes darken by more than 0.15
## luminance: count, box, centroid.
func _darkened(shown: Image, bare: Image) -> Dictionary:
	var count := 0
	var sum := Vector2.ZERO
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for y in range(0, shown.get_height(), 2):
		for x in range(0, shown.get_width(), 2):
			var drop := bare.get_pixel(x, y).get_luminance() - shown.get_pixel(x, y).get_luminance()
			if drop > 0.15:
				count += 1
				sum += Vector2(x, y)
				lo = lo.min(Vector2(x, y))
				hi = hi.max(Vector2(x, y))
	var centroid := sum / maxf(count, 1.0)
	return {"count": count, "box": Rect2(lo, hi - lo), "centroid": centroid}


func _set_planes_shown(shown: bool) -> void:
	for name in ["PlaneView", "PlaneView2"]:
		var view: PlaneView = _main.get_node(name)
		view.set_process(shown)
		if shown:
			view.update_pose()
		else:
			view.visible = false


## Up to FRAMES_PER_STRIP ticks spread evenly over `ticks`.
func _spread(ticks: Array[int]) -> Array[int]:
	var out: Array[int] = []
	if ticks.size() < FRAMES_PER_STRIP:
		return out
	for k in FRAMES_PER_STRIP:
		var index := roundi(float(k) * (ticks.size() - 1) / (FRAMES_PER_STRIP - 1))
		out.append(ticks[index])
	return out


func _sheet(frames: Array[Image], name: String) -> void:
	if frames.size() != FRAMES_PER_STRIP:
		_invalid("%s has %d of %d frames" % [name, frames.size(), FRAMES_PER_STRIP])
		return
	var columns := 4
	var sheet := Image.create(
		THUMB.x * columns, THUMB.y * (FRAMES_PER_STRIP / columns), false, Image.FORMAT_RGBA8
	)
	for k in frames.size():
		var thumb: Image = frames[k].duplicate()
		thumb.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			thumb,
			Rect2i(Vector2i.ZERO, THUMB),
			Vector2i((k % columns) * THUMB.x, (k / columns) * THUMB.y)
		)
	_save(sheet, name)


func _use_camera(kind: String) -> bool:
	if _home.is_empty():
		_home = {"position": _rig.position, "distance": _rig.distance, "yaw": _rig.yaw}
	var want := {"position": _home["position"], "distance": _home["distance"], "yaw": _home["yaw"]}
	if kind == "arrival":
		want = {"position": FAR_ARRIVAL_FOCUS, "distance": _rig.max_distance, "yaw": 0.0}
	elif kind == "departure":
		want = {
			"position": FAR_DEPARTURE_FOCUS, "distance": _rig.max_distance, "yaw": FAR_DEPARTURE_YAW
		}
	var moved: bool = (
		not _rig.position.is_equal_approx(want["position"])
		or not is_equal_approx(_rig.distance, want["distance"])
		or not is_equal_approx(_rig.yaw, want["yaw"])
	)
	_rig.stop_follow()
	_rig.position = want["position"]
	_rig.yaw = want["yaw"]
	_rig.distance = want["distance"]
	_rig.zoom(1.0)
	return moved


func _under_hud(box: Rect2) -> bool:
	for hud in HUD_BOXES:
		if hud.grow(MARGIN_PX).intersects(box):
			return true
	return false


## The plane model's bounds in PlaneView's own space.
func _plane_local_box() -> AABB:
	var to_local := _plane.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in _meshes(_plane.get_node("Pivot")):
		var b: AABB = (to_local * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Planned frames are sim times in whole ticks, drawn with _draw_at.
func _time_at(tick: int) -> float:
	return float(tick)


## a. Ticks of the lead-in when the shadow's ground point (under the middle of
## the plane's bounds) is on the terminal floor and inside the start view.
func _plan_default(starts: Array[int], local_box: AABB) -> Array[int]:
	_use_camera("default")
	var approach := starts[FlightSim.State.APPROACH]
	var candidates: Array[int] = []
	for tick in range(approach - 2000, approach):
		var at := _plane.pose_at(starts, _time_at(tick))
		if at.is_empty() or at["phase"] != PlaneView.PHASE_LEAD_IN:
			continue
		var pose: Transform3D = at["transform"]
		var ground := _plane.ground_point_of((pose * local_box).get_center())
		if not TERMINAL_FLOOR.has_point(Vector2(ground.x, ground.z)):
			continue
		if not _cam.is_position_behind(ground):
			if _screen_rect().has_point(_cam.unproject_position(ground)):
				candidates.append(tick)
	print("PLAN default shadow on the floor and in frame for %d ticks" % candidates.size())
	return _spread(candidates)


## b. Ticks when the airborne plane's whole bounds are inside the full zoom-out
## view: the lead-in for the arrival, the late takeoff roll and climb-out for
## the departure.
func _plan_far(starts: Array[int], kind: String, local_box: AABB) -> Array[int]:
	_use_camera(kind)
	var first := starts[FlightSim.State.APPROACH] - 2000
	var last := starts[FlightSim.State.APPROACH]
	if kind == "departure":
		first = starts[FlightSim.State.TAKEOFF] + 140
		last = starts[FlightSim.State.DEPARTED] + 1200
	var candidates: Array[int] = []
	for tick in range(first, last):
		var at := _plane.pose_at(starts, _time_at(tick))
		if at.is_empty():
			continue
		var pose: Transform3D = at["transform"]
		var box := _in_frame(_corners(pose * local_box))
		if pose.origin.y < 10.0 or not box.has_area() or _under_hud(box):
			continue
		var ground := _plane.ground_point_of(pose.origin)
		var gap := _cam.unproject_position(pose.origin).distance_to(_cam.unproject_position(ground))
		if gap >= AIRBORNE_GAP * maxf(box.size.x, box.size.y):
			candidates.append(tick)
	print("PLAN %s camera=%s" % [kind, _cam.global_position])
	print("PLAN %s plane in frame and clear of its shadow for %d ticks" % [kind, candidates.size()])
	return _spread(candidates)


func _shoot(tick: int, kind: String) -> Image:
	_beat("shoot_%s_%d" % [kind, tick])
	if _use_camera(kind):
		# The roof dithers in or out over real time when the zoom crosses its band.
		await _frames(60)
	_draw_at(tick)
	_plane.update_pose()
	await physics_frame
	await physics_frame
	await _frames(2)
	var tag := "%s_t%d" % [kind, tick]
	print(
		(
			"SHOT %s camera=%s tick=%d alpha=%.3f"
			% [tag, _cam.global_position, _clock.tick, _clock.alpha]
		)
	)
	if not _plane.visible:
		_invalid("%s: the plane is not drawn" % tag)
		return null
	var ok := false
	if kind == "default":
		ok = await _prove_shadow(tag)
	else:
		ok = await _prove_airborne(tag)
	if not ok:
		return null
	var img := await _grab()
	_save(img, "frame_%s.png" % tag)
	return img


## The shadow's ground point is where the sun drops the middle of the plane's
## drawn bounds (the model sits off PlaneView's own origin).
func _prove_shadow(tag: String) -> bool:
	var ground := _plane.ground_point_of(_plane_box().get_center())
	var s := _cam.unproject_position(ground)
	var in_frame := _screen_rect().has_point(s) and not _cam.is_position_behind(ground)
	var sight := _blocked_by(ground)
	var plane_on_screen := _in_frame(_corners(_plane_box())).has_area()
	print(
		(
			"INFRAME %s shadow_ground=%s screen=(%.0f,%.0f) ok=%s plane_y=%.1f plane_on_screen=%s"
			% [tag, ground, s.x, s.y, in_frame, _plane.position.y, plane_on_screen]
		)
	)
	print("SIGHT %s first_hit=%s hit_to_point=%.2f m" % [tag, sight["by"], sight["away"]])
	if not in_frame:
		_invalid("%s: the shadow's ground point is out of frame" % tag)
		return false
	if sight["away"] > SIGHT_SLACK:
		_invalid("%s: the shadow's ground point is hidden by %s" % [tag, sight["by"]])
		return false
	var shown := await _grab()
	_set_planes_shown(false)
	var bare := await _grab()
	_set_planes_shown(true)
	_save(bare, "twin_%s_planes_hidden.png" % tag)
	# unproject_position works in the viewport's own size; the plate is the
	# window's, which the stretch mode scales up.
	var on_plate := s * Vector2(shown.get_size()) / root.get_visible_rect().size
	var lit := _luminance(bare, on_plate)
	var shaded := _luminance(shown, on_plate)
	print("SHADOW %s luminance planes_hidden=%.3f shown=%.3f" % [tag, lit, shaded])
	var dark := _darkened(shown, bare)
	print("SHADOW %s darkened_plate_px=%d in %s" % [tag, dark["count"], dark["box"]])
	if lit - shaded < SHADOW_DARKENING:
		_save(shown, "rejected_%s.png" % tag)
		_invalid("%s: no shadow darkens its ground point" % tag)
		return false
	return true


func _prove_airborne(tag: String) -> bool:
	var box := _in_frame(_corners(_plane_box()))
	var rays := _plane_ray_hits()
	var ground := _plane.shadow_ground_point()
	var gap := _cam.unproject_position(_plane.global_position).distance_to(
		_cam.unproject_position(ground)
	)
	print(
		(
			"INFRAME %s phase=%d pos=%s screen=%s size_px=%.0fx%.0f ok=%s"
			% [
				tag,
				_plane.phase,
				_plane.position,
				box.position,
				box.size.x,
				box.size.y,
				box.has_area()
			]
		)
	)
	print(
		(
			"AIRBORNE %s height=%.1f far_shadow_alpha=%.2f plane_to_shadow_px=%.0f rays=%d/%d"
			% [tag, _plane.position.y, _plane.far_shadow_alpha(), gap, rays.x, rays.y]
		)
	)
	if not box.has_area():
		_invalid("%s: the plane leaves the frame" % tag)
		return false
	if rays.x * 2 < rays.y or rays.x == 0:
		_invalid("%s: the plane is occluded (%d of %d rays)" % [tag, rays.x, rays.y])
		return false
	var clear := gap >= AIRBORNE_GAP * maxf(box.size.x, box.size.y)
	if _plane.position.y < 10.0 or _plane.far_shadow_alpha() < 0.2 or not clear:
		_invalid("%s: does not read as airborne" % tag)
		return false
	# The HUD is drawn over the 3D view; the plane must not sit under it.
	var shown := await _grab()
	var bare: Image = (await PlateSight.hud_twin(self, _main))["image"]
	var scale := Vector2(shown.get_size()) / root.get_visible_rect().size
	var on_plate := Rect2i(Rect2(box.position * scale, box.size * scale))
	var covered := PlateSight.differing(shown, bare, on_plate, 2)
	var share := covered / maxf(on_plate.get_area() / 4.0, 1.0)
	print("HUD %s covers %.3f of the plane's box %s" % [tag, share, on_plate])
	if share > HUD_COVER_LIMIT:
		_invalid("%s: the HUD covers the plane" % tag)
		return false
	return true
