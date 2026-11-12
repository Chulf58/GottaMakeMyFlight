extends SceneTree
## Windowed before and after plates of the sun's cast-shadow edges (board
## 1f05ff29). Boots the real main scene at 1920x1080 with a new random sim seed
## (printed), builds the starter terminal, hires staff, opens the airport and
## runs the clock until passengers are inside, then pauses it and hides the
## HUD's canvas layers (anti-pattern a-plate-probe-s-occlusion-rays-see-only-
## meshes-so-a-hud-pane).
##
## The same frozen frame is drawn under each shadow VARIANT, set at run time,
## at the Home zoom and at a closer zoom:
##   before     Godot's defaults, which the game used until board 1f05ff29:
##              a 4096 directional atlas, the Soft Low filter, 100 m distance
##   after      the settings as committed (project.godot and the Sun)
##   the rest   diagnostics (DIAGNOSTICS): the round-two splits and distance at
##              blur 1.0, 1.5, 2.0 and 3.0, with the 8192 and the 4096 atlas
## and a third shot at the farthest zoom, where the after plate must show cast
## shadows (a twin with the sun shadow off is the control). With -- --angles it
## draws only before and after, at the TOP_DOWN, MEDIUM and LOW camera angles.
## Every subject (a wall, a seat row, a check-in desk, a scanner, a passenger)
## is projected into the viewport with a margin and checked with a sight line
## from the camera (ten for an object or a person, aimed inside its box) that
## must land on the subject's own mesh first; a failure
## prints PROBE_INVALID and exits 1. The probe also counts the pixels that
## differ between before and after, so a setting that did nothing cannot pass.
## For each variant it prints the GPU time of the frozen frame, then measures
## frame time and GPU time for every variant at 1x and 3x with vsync off.
##
## Run (one windowed Godot run project-wide; hold tools/blender/out/.windowed.lock):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/shadow_edge_plates_probe.gd
##
## Plates go to tools/blender/out/shadows/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/shadows"
const MAIN_SCENE := "res://main/main.tscn"
const SETTINGS := "user://shadow_edge_probe_settings.cfg"
const SIZE := Vector2i(1920, 1080)
const SOFT_LOW := RenderingServer.SHADOW_QUALITY_SOFT_LOW
const SOFT_HIGH := RenderingServer.SHADOW_QUALITY_SOFT_HIGH
const FOUR := DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
## Godot defaults, which the game used until board 1f05ff29.
const BEFORE: Dictionary = {
	"atlas": 4096,
	"quality": SOFT_LOW,
	"max_distance": 100.0,
	"blur": 1.0,
	"mode": FOUR,
	"splits": Vector3(0.1, 0.2, 0.5),
}
## Round two of board 1f05ff29: splits that put the Home view in the first
## split, and a distance that reaches the farthest zoom.
const NEW: Dictionary = {
	"atlas": 8192,
	"quality": SOFT_HIGH,
	"max_distance": 410.0,
	"mode": FOUR,
	"splits": Vector3(0.1, 0.3, 0.6),
}
## Name -> the settings that differ from NEW. "after" is read at boot.
const DIAGNOSTICS := {
	"blur10": {"blur": 1.0},
	"blur15": {"blur": 1.5},
	"blur20": {"blur": 2.0},
	"blur30": {"blur": 3.0},
	"a4096_blur15": {"atlas": 4096, "blur": 1.5},
	"a4096_blur20": {"atlas": 4096, "blur": 2.0},
	"a4096_blur30": {"atlas": 4096, "blur": 3.0},
}
## The blur steps laid side by side in crop_strip_home.png.
const STRIP: Array[String] = ["blur10", "blur15", "blur20", "blur30"]
## The committed blur at both atlas sizes, side by side in crop_atlas_home.png.
const ATLAS_PAIR: Array[String] = ["blur20", "a4096_blur20"]
## With -- --angles: only before and after, Home, close and the farthest zoom
## at each camera angle step, then the frame times.
const ANGLES := [
	TycoonCamera.AngleStep.TOP_DOWN, TycoonCamera.AngleStep.MEDIUM, TycoonCamera.AngleStep.LOW
]
const MARGIN_PX := 24.0
const CLOSE_DISTANCE := 15.0
const MIN_PASSENGERS := 3
const TICK_CAP := 9000
const STILL_FRAMES := 120
const MEASURE_FRAMES := 240
const TAGS: Array[String] = ["wall", "desk", "scanner", "seats", "passenger"]
## The guard thread crashes the probe when no frame arrives for this long.
const HANG_MS := 60_000
const LIMIT_MS := 840_000

var _out_dir := ""
var _failed := false
var _start_ms := 0
var _main: Node
var _clock: SimClock
var _cam: TycoonCamera
var _views: Node
var _sun: DirectionalLight3D
var _variants: Dictionary = {}
var _angles := OS.get_cmdline_user_args().has("--angles")
var _plates: Array[String] = []
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false


func _initialize() -> void:
	var probe_seed := randi()
	seed(probe_seed)
	print("PROBE probe_seed=", probe_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_start_ms = Time.get_ticks_msec()
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _watch() -> void:
	while true:
		OS.delay_msec(1000)
		_lock.lock()
		var quiet := Time.get_ticks_msec() - _beat_ms
		var stage := _stage
		var done := _done
		_lock.unlock()
		if done:
			return
		if quiet > HANG_MS:
			print("PROBE_INVALID hang stage=%s quiet_ms=%d" % [stage, quiet])
			OS.crash("shadow edge probe hung")


func _beat(stage := "") -> void:
	_lock.lock()
	_beat_ms = Time.get_ticks_msec()
	if stage != "":
		_stage = stage
	_lock.unlock()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_invalid(msg)


func _frames(count: int) -> void:
	for i in count:
		_beat()
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	DisplayServer.window_set_size(SIZE)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _frames(6)
	print("PROBE window=%s layout=%s" % [root.size, root.get_visible_rect().size])
	_expect(root.size == SIZE, "the window is %s, not %s" % [root.size, SIZE])
	await _boot()
	if not _failed:
		await _shots()
	if not _failed:
		await _measure()
	if not _variants.is_empty():
		_set_variant("after")
		_expect(_variants["after"] != BEFORE, "the committed settings are still the defaults")
	_contact_sheet()
	DirAccess.remove_absolute(SETTINGS)
	print("PROBE plates=%d elapsed_ms=%d" % [_plates.size(), Time.get_ticks_msec() - _start_ms])
	_expect(Time.get_ticks_msec() - _start_ms < LIMIT_MS, "the probe ran past %d ms" % LIMIT_MS)
	print("PROBE done failed=", _failed)
	_lock.lock()
	_done = true
	_lock.unlock()
	_guard.wait_to_finish()
	quit(1 if _failed else 0)


## before, after (the committed settings, read before anything changes them)
## and each diagnostic, as full settings.
func _read_variants() -> void:
	var after := {
		"atlas":
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")),
		"quality":
		int(
			ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"
			)
		),
		"max_distance": _sun.directional_shadow_max_distance,
		"blur": _sun.shadow_blur,
		"mode": _sun.directional_shadow_mode,
		"splits":
		Vector3(
			_sun.directional_shadow_split_1,
			_sun.directional_shadow_split_2,
			_sun.directional_shadow_split_3
		),
	}
	_variants = {"before": BEFORE, "after": after}
	if not _angles:
		for name in DIAGNOSTICS:
			var v := BEFORE.duplicate()
			v.merge(NEW, true)
			v.merge(DIAGNOSTICS[name], true)
			_variants[name] = v
	for name in _variants:
		print("PROBE variant %s %s" % [name, _variants[name]])


func _set_variant(name: String) -> void:
	var v: Dictionary = _variants[name]
	RenderingServer.directional_shadow_atlas_set_size(v["atlas"], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		v["quality"] as RenderingServer.ShadowQuality
	)
	_sun.directional_shadow_max_distance = v["max_distance"]
	_sun.shadow_blur = v["blur"]
	_sun.directional_shadow_mode = v["mode"]
	var splits: Vector3 = v["splits"]
	_sun.directional_shadow_split_1 = splits.x
	_sun.directional_shadow_split_2 = splits.y
	_sun.directional_shadow_split_3 = splits.z


func _boot() -> void:
	_beat("boot main")
	# A run cut short leaves its last camera angle in SETTINGS; start clean.
	DirAccess.remove_absolute(SETTINGS)
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var sim_seed := randi()
	_clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	var hud := _main.get_node("PassengerHud") as PassengerHud
	hud.alert_settings_path = SETTINGS
	hud.departures_settings_path = SETTINGS
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = SETTINGS
	# --angles calls set_angle_step(), which saves the angle; keep it, and the
	# need-icon toggle, off the player's settings file too (anti-pattern
	# 1639342a). SETTINGS is removed at the end of the run.
	(_main.get_node("TycoonCamera") as TycoonCamera).settings_path = SETTINGS
	_main.get_node("PassengerViews").need_icons_toggle.settings_path = SETTINGS
	root.add_child(_main)
	_clock.set_paused(true)
	_cam = _main.get_node("TycoonCamera") as TycoonCamera
	_views = _main.get_node("PassengerViews")
	_sun = _main.get_node("Sun") as DirectionalLight3D
	print(
		(
			"PROBE sun mode=%d bias=%.2f normal_bias=%.2f blur=%.2f"
			% [
				_sun.directional_shadow_mode,
				_sun.shadow_bias,
				_sun.shadow_normal_bias,
				_sun.shadow_blur,
			]
		)
	)
	_read_variants()
	await _frames(30)
	hud.press_starter_terminal()
	await _frames(10)
	print("PROBE hired=%d" % StaffTestKit.staff_all(_main.get_node("Staff") as StaffSim))
	await _fill_terminal()
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false


## Runs the clock until MIN_PASSENGERS passengers stand on the terminal's
## indoor cells, then pauses it.
func _fill_terminal() -> void:
	_beat("fill terminal")
	var sim := _main.get_node("PassengerSim") as PassengerSim
	var grid: BuildGrid = (_main.get_node("BuildMode") as BuildMode).grid
	_clock.set_paused(false)
	var ticks := 0
	var inside := 0
	while ticks < TICK_CAP:
		for i in 30:
			_clock.advance(SimClock.STEP)
		ticks += 30
		await _frames(1)
		inside = _inside(sim, grid).size()
		if inside >= MIN_PASSENGERS:
			break
	_clock.set_paused(true)
	await _frames(10)
	print("PROBE ticks=%d tick=%d inside=%d" % [ticks, _clock.tick, inside])
	_expect(inside >= MIN_PASSENGERS, "only %d passengers inside after %d ticks" % [inside, ticks])


func _inside(sim: PassengerSim, grid: BuildGrid) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for id in sim.passenger_ids():
		var node: Node3D = _views.node_for(id)
		if node == null or not node.is_visible_in_tree():
			continue
		var cell := grid.world_to_cell(node.global_position)
		if grid.in_bounds(cell) and grid.is_indoor(cell):
			out.append(node)
	return out


func _shots() -> void:
	_beat("shots")
	var grid: BuildGrid = (_main.get_node("BuildMode") as BuildMode).grid
	var subjects := _subjects(grid)
	if _failed:
		return
	if not _angles:
		await _views_at("", subjects)
		_strip(STRIP, "crop_strip_home.png")
		_strip(ATLAS_PAIR, "crop_atlas_home.png")
		return
	for step in ANGLES:
		_cam.set_angle_step(step)
		print("PROBE angle step=%d pitch=%.1f" % [step, _cam.pitch_degrees()])
		await _views_at("_%s" % ["low", "medium", "top"][step], subjects)


## Home, close and the farthest zoom at the current angle; shot names end in
## `suffix`.
func _views_at(suffix: String, subjects: Dictionary) -> void:
	_cam.go_home()
	await _settle()
	var home_distance := _cam.distance
	await _shoot("home" + suffix, subjects)
	# The nearest view that holds every subject, but no farther than CLOSE_DISTANCE.
	var first: Vector3 = (subjects["desk"] as Node3D).global_position
	var box := Rect2(Vector2(first.x, first.z), Vector2.ZERO)
	for tag in ["scanner", "seats", "passenger"]:
		var p: Vector3 = (subjects[tag] as Node3D).global_position
		box = box.expand(Vector2(p.x, p.z))
	var fit := _cam.framing_for(box.grow(1.0))
	_cam.position = fit["position"]
	_cam.distance = minf(fit["distance"], CLOSE_DISTANCE)
	await _settle()
	_expect(_cam.distance < home_distance, "the close view is not closer than Home")
	print("PROBE distances home=%.1f close=%.1f" % [home_distance, _cam.distance])
	await _shoot("close" + suffix, subjects)
	_cam.go_home()
	await _settle()
	_cam.distance = _cam.max_distance
	await _settle()
	_far_depth()
	await _shoot("max_zoom" + suffix, subjects)


## The deepest view depth (along the camera axis) of the ground at the four
## viewport corners, at the current zoom. A corner above the horizon fails.
func _far_depth() -> float:
	var cam := root.get_camera_3d()
	var view := root.get_visible_rect().size
	var ground := Plane(Vector3.UP, 0.0)
	var deepest := 0.0
	for corner in [Vector2.ZERO, Vector2(view.x, 0.0), Vector2(0.0, view.y), view]:
		var hit: Variant = ground.intersects_ray(
			cam.project_ray_origin(corner), cam.project_ray_normal(corner)
		)
		if hit == null:
			print("PROBE far corner %s sees above the horizon" % [corner])
		if hit != null:
			var depth: float = (hit - cam.global_position).dot(-cam.global_transform.basis.z)
			deepest = maxf(deepest, depth)
	print("PROBE far_depth=%.1f camera_distance=%.1f" % [deepest, _cam.distance])
	return deepest


func _settle() -> void:
	var still := 0
	var last := Transform3D()
	for i in 600:
		await _frames(1)
		var now := root.get_camera_3d().global_transform
		still = still + 1 if now.is_equal_approx(last) and not _cam.is_gliding() else 0
		last = now
		if still >= 8:
			break
	_expect(still >= 8, "the camera did not settle")


## One object of each kind and one passenger inside, keyed by tag, plus a
## world point on top of a wall.
func _subjects(grid: BuildGrid) -> Dictionary:
	var out := {}
	var build_view := _main.get_node("BuildMode/BuildView")
	var defs := {&"checkin_desk": "desk", &"security_scanner": "scanner", &"seat_row": "seats"}
	for child in build_view.get_children():
		if not child.has_meta("record"):
			continue
		var tag: String = defs.get(StringName(child.get_meta("record")["def"]), "")
		if tag != "" and not out.has(tag):
			out[tag] = child
	for tag in ["desk", "scanner", "seats"]:
		_expect(out.has(tag), "no %s to show" % tag)
	if _failed:
		return out
	# The passenger and the wall nearest the desk and the scanner, so the close
	# shot holds them too.
	var near := (
		((out["desk"] as Node3D).global_position + (out["scanner"] as Node3D).global_position) / 2.0
	)
	var best := INF
	for person in _inside(_main.get_node("PassengerSim") as PassengerSim, grid):
		if person.global_position.distance_to(near) < best:
			best = person.global_position.distance_to(near)
			out["passenger"] = person
	_expect(out.has("passenger"), "no passenger to show")
	out["wall"] = _wall_point(grid, near)
	return out


## A world point on top of an interior wall, found with a down ray against the
## drawn wall meshes. Also the control that the sight colliders see walls.
func _wall_point(grid: BuildGrid, near: Vector3) -> Vector3:
	var holder := PlateSight.colliders(root, [_main.get_node("BuildMode/BuildView")], {})
	var space := root.get_world_3d().direct_space_state
	var best := Vector3.INF
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if not grid.is_indoor(cell):
				continue
			for side in [BuildGrid.Side.SOUTH]:
				if not grid.has_wall(cell, side):
					continue
				var mid := BuildView.wall_transform(grid, cell, side).origin
				var hit := space.intersect_ray(
					PhysicsRayQueryParameters3D.create(mid + Vector3(0, 10, 0), mid - Vector3.UP)
				)
				if hit.is_empty() or (hit["position"] as Vector3).y < 0.2:
					continue
				var top: Vector3 = hit["position"]
				if best == Vector3.INF or top.distance_to(near) < best.distance_to(near):
					best = top
	holder.free()
	print("PROBE wall_top=%s" % [best])
	_expect(best != Vector3.INF, "no wall top found by a down ray (control)")
	return best


func _shoot(shot: String, subjects: Dictionary) -> void:
	# Let the roof fade and the wall cutaway finish after the camera move
	# (anti-pattern 9a6c0290), so the first plate is not taken mid-fade.
	await _frames(240)
	var area := _check_subjects(shot, subjects)
	var bare: Image = null
	if shot.begins_with("max_zoom"):
		_sun.shadow_enabled = false
		await _frames(30)
		bare = root.get_texture().get_image()
		_sun.shadow_enabled = true
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var images := {}
	for name in ["before", "before_again"] + _variants.keys().slice(1):
		_beat("shot %s %s" % [shot, name])
		_set_variant("before" if name == "before_again" else name)
		await _frames(20)
		var gpu := 0.0
		for i in STILL_FRAMES:
			_beat()
			await process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := _out_dir.path_join("%s_%s.png" % [shot, name])
		print(
			(
				"PLATE %s err=%d size=%s still_gpu_ms=%.3f"
				% [path, img.save_png(path), img.get_size(), gpu / STILL_FRAMES]
			)
		)
		images[name] = img
		if name != "before_again":
			_crop(img, area, "%s_%s" % [shot, name])
		if bare != null:
			var shadow_px := _diff(bare, img, area)
			print("PLATE %s %s shadow_px=%d" % [shot, name, shadow_px])
			if name == "after":
				_expect(shadow_px > 0, "no cast shadows at the farthest zoom")
		if name == "before_again":
			DirAccess.remove_absolute(path)
		else:
			_plates.append(path)
	# The scene still moves a little while the clock is paused (idle clips,
	# birds), so the change must beat the noise of before against itself.
	var noise := _diff(images["before"], images["before_again"], area)
	var changed := _diff(images["before"], images["after"], area)
	print("PLATE %s before_vs_after changed_px=%d noise_px=%d" % [shot, changed, noise])
	if not shot.begins_with("max_zoom"):
		_expect(changed > 2 * noise + 500, "%s: after differs from noise too little" % shot)


## A 2x crop of the subjects area (3x at the far zoom), so a reader sees the
## shadow edges pixel for pixel.
func _crop(img: Image, area: Rect2, tag: String) -> void:
	var scale := img.get_height() / root.get_visible_rect().size.y
	var box := Rect2i(area.position * scale, area.size * scale).intersection(
		Rect2i(Vector2i.ZERO, img.get_size())
	)
	var part := img.get_region(box)
	var grow := 3 if box.size.x < 400 else 2
	part.resize(box.size.x * grow, box.size.y * grow, Image.INTERPOLATE_NEAREST)
	var path := _out_dir.path_join("crop_%s.png" % tag)
	print("PLATE crop %s err=%d box=%s" % [path, part.save_png(path), box])


## Pixels that differ inside `area` (layout pixels: the subjects and the floor
## between them, away from the planes and birds outside).
func _diff(a: Image, b: Image, area: Rect2) -> int:
	var scale := a.get_height() / root.get_visible_rect().size.y
	var box := Rect2i(area.position * scale, area.size * scale).intersection(
		Rect2i(Vector2i.ZERO, a.get_size())
	)
	var changed := 0
	for y in range(box.position.y, box.end.y, 2):
		for x in range(box.position.x, box.end.x, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.02:
				changed += 1
	return changed


## Each subject is inside the view by MARGIN_PX, and a sight line from the
## camera first lands on the subject's own mesh (a wall point: within 0.3 m).
func _check_subjects(shot: String, subjects: Dictionary) -> Rect2:
	var cam := root.get_camera_3d()
	var view := root.get_visible_rect().grow(-MARGIN_PX)
	var owners: Array[Node] = [_main.get_node("BuildMode/BuildView"), _views]
	var tagged := {}
	for tag in TAGS:
		if subjects[tag] is Node3D:
			tagged[subjects[tag]] = tag
	var holder := PlateSight.colliders(root, owners, tagged)
	var bounds: Dictionary = holder.get_meta("bounds")
	var space := root.get_world_3d().direct_space_state
	var from := cam.global_position
	var area := Rect2()
	for tag in TAGS:
		var box: AABB = bounds.get(tag, AABB())
		var target: Vector3 = subjects[tag] if tag == "wall" else box.get_center()
		var at := cam.unproject_position(target)
		area = Rect2(at, Vector2.ZERO) if tag == TAGS[0] else area.expand(at)
		var seen := false
		var hit_tag := ""
		var miss := INF
		if tag == "wall":
			var hit := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(
					from, target + (target - from).normalized() * 3.0
				)
			)
			miss = INF if hit.is_empty() else (hit["position"] as Vector3).distance_to(target)
			seen = miss < 0.3
		else:
			# Ten lines into the subject's own box; one that first hits the
			# subject's mesh shows it.
			var on := 0
			for p in _inner_points(box):
				var hit := space.intersect_ray(
					PhysicsRayQueryParameters3D.create(from, p + (p - from).normalized() * 3.0)
				)
				if (
					not hit.is_empty()
					and str((hit.collider as Node).get_meta("subject", "")) == tag
				):
					on += 1
			hit_tag = "%s:%d/10" % [tag, on]
			seen = on > 0
		# At the farthest zoom a subject is a few pixels; only the frame counts.
		seen = seen or shot.begins_with("max_zoom")
		var inside := view.has_point(at) and not cam.is_position_behind(target)
		print(
			(
				"SUBJECT %s %s world=%s screen=(%.0f,%.0f) in_frame=%s first_hit=%s miss_m=%.2f"
				% [shot, tag, target, at.x, at.y, inside, hit_tag, miss]
			)
		)
		_expect(inside and seen, "%s: the %s is not in frame or not visible" % [shot, tag])
	holder.free()
	print("SUBJECT %s diff_area=%s" % [shot, area])
	return area.grow(60.0)


## Ten points inside a box: a 3 x 3 grid at 30, 50 and 70 percent of its width
## and depth, at 30, 50 and 70 percent of its height, and the top middle.
func _inner_points(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 3:
		for j in 3:
			var f := Vector3(0.3 + 0.2 * i, 0.3 + 0.2 * j, 0.3 + 0.2 * ((i + j) % 3))
			out.append(box.position + box.size * f)
	# The middle of the top face, a little inside: an arch (the scanner) is
	# open in the middle, so oblique lines into its box pass through it.
	var c := box.get_center()
	out.append(Vector3(c.x, box.end.y - 0.05, c.z))
	return out


func _measure() -> void:
	_cam.set_angle_step(TycoonCamera.AngleStep.TOP_DOWN)
	_cam.go_home()
	await _settle()
	var vp := root.get_viewport_rid()
	for speed in [1, 3]:
		_clock.set_speed(speed)
		_clock.set_paused(false)
		for name in ["before"] + _variants.keys().slice(1):
			_beat("measure %dx %s" % [speed, name])
			_set_variant(name)
			await _frames(60)
			var gpu := 0.0
			var start := Time.get_ticks_usec()
			for i in MEASURE_FRAMES:
				_beat()
				await process_frame
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			var frame_ms := (Time.get_ticks_usec() - start) / 1000.0 / MEASURE_FRAMES
			print(
				(
					"FPS speed=%dx variant=%s frame_ms=%.2f fps=%.0f gpu_ms=%.3f tick=%d"
					% [speed, name, frame_ms, 1000.0 / frame_ms, gpu / MEASURE_FRAMES, _clock.tick]
				)
			)
		_clock.set_paused(true)


## The Home crops of `names` side by side, at half size, saved as `file`.
func _strip(names: Array[String], file: String) -> void:
	var parts: Array[Image] = []
	for name in names:
		var img := Image.load_from_file(_out_dir.path_join("crop_home_%s.png" % name))
		if img == null:
			_invalid("no crop for %s" % name)
			return
		img.convert(Image.FORMAT_RGB8)
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
		parts.append(img)
	var cell := parts[0].get_size()
	var strip := Image.create(cell.x * parts.size(), cell.y, false, Image.FORMAT_RGB8)
	for i in parts.size():
		strip.blit_rect(parts[i], Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, 0))
	var path := _out_dir.path_join(file)
	print("PLATE strip %s order=%s err=%d" % [path, names, strip.save_png(path)])


func _contact_sheet() -> void:
	if _plates.is_empty():
		return
	var cols := _variants.size()
	var cell := Vector2i(480, 270)
	var rows := ceili(_plates.size() / float(cols))
	var sheet := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGB8)
	for i in _plates.size():
		var img := Image.load_from_file(_plates[i])
		if img == null:
			continue
		img.convert(Image.FORMAT_RGB8)
		img.resize(cell.x, cell.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(
			img, Rect2i(Vector2i.ZERO, cell), Vector2i((i % cols) * cell.x, (i / cols) * cell.y)
		)
	var path := _out_dir.path_join("contact.png")
	print("PLATE contact %s err=%d" % [path, sheet.save_png(path)])
