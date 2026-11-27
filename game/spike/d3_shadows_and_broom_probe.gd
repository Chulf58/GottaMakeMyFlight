extends SceneTree
## Windowed Vulkan verification probe for D3 shadow tuning (1f9c6d7e) and
## cleaner broom walk carry (af5c717a).
## Run with -- --before for pre-fix shadow plate, or default for after shadow
## plates + 4-frame cleaner patrol walk strip.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_SHADOWS := "C:/Users/chulf/Gotta-make-my-flight/tools/blender/out/d3-shadows"
const OUT_BROOM := "C:/Users/chulf/Gotta-make-my-flight/tools/blender/out/d3-cleaner-broom"
const MAIN_SCENE := "res://main/main.tscn"
const SETTINGS := "user://d3_probe_settings.cfg"
const SIZE := Vector2i(1920, 1080)
const MARGIN_PX := 20.0
const CLOSE_DISTANCE := 10.5
const WIDE_DISTANCE := 155.0
const MIN_PASSENGERS := 3
const TICK_CAP := 9000
const STRIP_FRAMES := 4
const WALK_TICKS_PER_FRAME := 3
const BROOM_CAM_DIST := 5.8
const BROOM_CAM_PITCH := 38.0

var _before_only := OS.get_cmdline_user_args().has("--before")
var _failed := false
var _main: Node
var _clock: SimClock
var _cam: TycoonCamera
var _views: Node
var _staff: StaffSim
var _chars: StaffCharacters
var _sun: DirectionalLight3D


func _initialize() -> void:
	var probe_seed := randi()
	seed(probe_seed)
	print("PROBE probe_seed=", probe_seed)
	DirAccess.make_dir_recursive_absolute(OUT_SHADOWS)
	DirAccess.make_dir_recursive_absolute(OUT_BROOM)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_invalid(msg)


func _frames(count: int) -> void:
	for _i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	DisplayServer.window_set_size(SIZE)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _frames(6)
	await _boot()
	if not _failed:
		await _capture_shadows()
	if not _failed and not _before_only:
		await _capture_cleaner_walk()
	if is_instance_valid(_main):
		_main.queue_free()
		await _frames(3)
	DirAccess.remove_absolute(SETTINGS)
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> void:
	DirAccess.remove_absolute(SETTINGS)
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	var sim_seed := randi()
	_clock.seed_rng(sim_seed)
	print("PROBE sim_seed=", sim_seed)
	var hud := _main.get_node("PassengerHud") as PassengerHud
	hud.alert_settings_path = SETTINGS
	hud.departures_settings_path = SETTINGS
	(_main.get_node("MoodOverlay") as MoodOverlay).settings_path = SETTINGS
	_cam = _main.get_node("TycoonCamera") as TycoonCamera
	_cam.settings_path = SETTINGS
	root.add_child(_main)
	_clock.set_paused(true)
	_views = _main.get_node("PassengerViews")
	_staff = _main.get_node("Staff") as StaffSim
	_chars = _main.get_node("StaffCharacters") as StaffCharacters
	_sun = _main.get_node("Sun") as DirectionalLight3D
	print(
		(
			"PROBE sun bias=%.3f normal_bias=%.3f blur=%.3f splits=(%.2f,%.2f,%.2f) max_dist=%.1f"
			% [
				_sun.shadow_bias,
				_sun.shadow_normal_bias,
				_sun.shadow_blur,
				_sun.directional_shadow_split_1,
				_sun.directional_shadow_split_2,
				_sun.directional_shadow_split_3,
				_sun.directional_shadow_max_distance,
			]
		)
	)
	await _frames(20)
	hud.press_starter_terminal()
	(_main.get_node("BuildMode") as BuildMode).set_tool(BuildMode.Tool.NONE)
	await _frames(10)
	StaffTestKit.staff_all(_staff)
	if _find_cleaner() == 0:
		_staff.hire(StaffMember.Role.CLEANER)
	await _fill_terminal()
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await _frames(4)


func _find_cleaner() -> int:
	for id in _staff.member_ids():
		var m := _staff.get_member(id)
		if m.role == StaffMember.Role.CLEANER:
			return id
	return 0


func _fill_terminal() -> void:
	var sim := _main.get_node("PassengerSim") as PassengerSim
	var grid: BuildGrid = (_main.get_node("BuildMode") as BuildMode).grid
	_clock.set_paused(false)
	var ticks := 0
	var inside := 0
	while ticks < TICK_CAP:
		for _i in 20:
			_clock.advance(SimClock.STEP)
		ticks += 20
		await _frames(1)
		inside = _inside(sim, grid).size()
		if inside >= MIN_PASSENGERS:
			break
	_clock.set_paused(true)
	await _frames(8)
	print("PROBE fill ticks=%d tick=%d inside=%d" % [ticks, _clock.tick, inside])
	_expect(inside >= MIN_PASSENGERS, "only %d passengers inside" % inside)


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


func _settle_cam() -> void:
	var still := 0
	var last := Transform3D()
	for _i in 300:
		await _frames(1)
		var now := root.get_camera_3d().global_transform
		still = still + 1 if now.is_equal_approx(last) and not _cam.is_gliding() else 0
		last = now
		if still >= 6:
			break
	await _frames(40)


func _capture_shadows() -> void:
	var grid: BuildGrid = (_main.get_node("BuildMode") as BuildMode).grid
	var subjects := _shadow_subjects(grid)
	if _failed:
		return
	_cam.set_angle_step(TycoonCamera.AngleStep.MEDIUM)
	_cam.go_home()
	await _settle_cam()
	if _before_only:
		_check_shadow_subjects("before", subjects)
		_save_plate(OUT_SHADOWS.path_join("before.png"))
		return
	_check_shadow_subjects("after_mid", subjects)
	_save_plate(OUT_SHADOWS.path_join("after_mid.png"))

	var first: Vector3 = (subjects["desk"] as Node3D).global_position
	var box := Rect2(Vector2(first.x, first.z), Vector2.ZERO)
	for tag in ["scanner", "seats", "passenger"]:
		var p: Vector3 = (subjects[tag] as Node3D).global_position
		box = box.expand(Vector2(p.x, p.z))
	var fit := _cam.framing_for(box.grow(1.8))
	_cam.position = fit["position"]
	_cam.distance = clampf(fit["distance"], 11.0, 15.5)
	await _settle_cam()
	_check_shadow_subjects("after_close", subjects)
	_save_plate(OUT_SHADOWS.path_join("after_close.png"))

	_cam.set_angle_step(TycoonCamera.AngleStep.MEDIUM)
	_cam.go_home()
	await _settle_cam()
	_cam.distance = WIDE_DISTANCE
	await _settle_cam()
	_check_shadow_subjects("after_wide", subjects)
	_save_plate(OUT_SHADOWS.path_join("after_wide.png"))


func _shadow_subjects(grid: BuildGrid) -> Dictionary:
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
		_expect(out.has(tag), "missing subject %s" % tag)
	if _failed:
		return out
	var near := (
		((out["desk"] as Node3D).global_position + (out["scanner"] as Node3D).global_position) / 2.0
	)
	var best := INF
	for person in _inside(_main.get_node("PassengerSim") as PassengerSim, grid):
		if person.global_position.distance_to(near) < best:
			best = person.global_position.distance_to(near)
			out["passenger"] = person
	_expect(out.has("passenger"), "missing indoor passenger")
	return out


func _check_shadow_subjects(shot: String, subjects: Dictionary) -> void:
	var cam := root.get_camera_3d()
	var view := root.get_visible_rect().grow(-MARGIN_PX)
	var owners: Array[Node] = [_main.get_node("BuildMode/BuildView"), _views]
	var tagged := {}
	for tag in subjects:
		tagged[subjects[tag]] = tag
	var holder := PlateSight.colliders(root, owners, tagged)
	var bounds: Dictionary = holder.get_meta("bounds")
	var space := root.get_world_3d().direct_space_state
	var from := cam.global_position
	for tag in subjects:
		var box: AABB = bounds.get(tag, AABB())
		var target := box.get_center()
		var at := cam.unproject_position(target)
		var inside := view.has_point(at) and not cam.is_position_behind(target)
		var on := 0
		if shot != "after_wide":
			for p in _inner_points(box):
				var hit := space.intersect_ray(
					PhysicsRayQueryParameters3D.create(from, p + (p - from).normalized() * 3.0)
				)
				if (
					not hit.is_empty()
					and str((hit.collider as Node).get_meta("subject", "")) == tag
				):
					on += 1
		else:
			on = 1
		print(
			(
				"SUBJECT %s %s screen=(%.0f,%.0f) in_frame=%s hits=%d"
				% [shot, tag, at.x, at.y, inside, on]
			)
		)
		_expect(inside and on > 0, "%s %s not in frame or occluded" % [shot, tag])
	holder.free()


func _inner_points(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 3:
		for j in 3:
			var f := Vector3(0.3 + 0.2 * i, 0.3 + 0.2 * j, 0.3 + 0.2 * ((i + j) % 3))
			out.append(box.position + box.size * f)
	return out


func _capture_cleaner_walk() -> void:
	var cid := _find_cleaner()
	_expect(cid != 0, "no cleaner hired")
	if _failed:
		return
	var m := _staff.get_member(cid)
	var grid: BuildGrid = (_main.get_node("BuildMode") as BuildMode).grid
	_clock.set_paused(false)
	var ticks := 0
	var walking := false
	while ticks < 2400:
		_clock.advance(SimClock.STEP)
		ticks += 1
		await _frames(1)
		if (
			not m.in_pool()
			and m.state == StaffMember.State.IDLE
			and m.is_moving()
			and m.path.size() - m.path_index >= 4
			and grid.is_indoor(m.at)
		):
			walking = true
			break
	_expect(walking, "cleaner never started indoor patrol")
	if _failed:
		return
	var strip_imgs: Array[Image] = []
	_cam.stop_follow()
	_cam.set_pitch_degrees(BROOM_CAM_PITCH, false)
	for frame_idx in STRIP_FRAMES:
		if frame_idx > 0:
			_clock.set_paused(false)
			var target_tick := _clock.tick + WALK_TICKS_PER_FRAME
			while _clock.tick < target_tick and m.is_moving():
				await _frames(1)
		_clock.set_paused(true)
		var cnode := _chars.node_for(cid)
		_expect(cnode != null and m.is_moving(), "cleaner stopped at strip %d" % frame_idx)
		if _failed:
			return
		var pos := cnode.global_position
		_cam.position = Vector3(pos.x, 0.0, pos.z)
		_cam.yaw = wrapf(cnode.rotation.y + 1.15, -PI, PI)
		_cam.distance = BROOM_CAM_DIST
		await _frames(90 if frame_idx == 0 else 18)
		_log_broom_metrics(frame_idx, cid, cnode)
		_check_cleaner_in_frame(frame_idx, cnode)
		var path := OUT_BROOM.path_join("walk_%d.png" % frame_idx)
		strip_imgs.append(_save_plate(path))
	if strip_imgs.size() == STRIP_FRAMES:
		_save_strip(strip_imgs, OUT_BROOM.path_join("walk_strip.png"))


func _log_broom_metrics(frame_idx: int, cid: int, cnode: Node3D) -> void:
	var sk := cnode.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hand_idx := sk.find_bone("Hand.R")
	var hand_w := (sk.global_transform * sk.get_bone_global_pose(hand_idx)).origin
	var broom := StaffHandProps.prop_node(cnode, StaffHandProps.PropKind.BROOM)
	var min_y := INF
	var max_y := -INF
	var pole_deg := 0.0
	if broom != null and broom.visible:
		var pole_dir := (broom.global_transform.basis * Vector3.UP).normalized()
		pole_deg = rad_to_deg(acos(clampf(absf(pole_dir.dot(Vector3.UP)), 0.0, 1.0)))
		for mi: MeshInstance3D in broom.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			for v in mi.mesh.get_faces():
				var wv := mi.global_transform * v
				min_y = minf(min_y, wv.y)
				max_y = maxf(max_y, wv.y)
	print(
		(
			"BROOM frame=%d prop=%d hand_y=%.3f min_y=%.3f max_y=%.3f tilt_deg=%.1f"
			% [frame_idx, _chars.hand_prop_of(cid), hand_w.y, min_y, max_y, pole_deg]
		)
	)
	_expect(
		_chars.hand_prop_of(cid) == StaffHandProps.PropKind.BROOM,
		"broom hidden at walk frame %d" % frame_idx
	)
	_expect(min_y >= 0.02, "broom clipped floor min_y=%.3f at frame %d" % [min_y, frame_idx])


func _check_cleaner_in_frame(frame_idx: int, cnode: Node3D) -> void:
	var cam := root.get_camera_3d()
	var view := root.get_visible_rect().grow(-MARGIN_PX)
	var target := cnode.global_position + Vector3(0.0, 0.9, 0.0)
	var at := cam.unproject_position(target)
	var inside := view.has_point(at) and not cam.is_position_behind(target)
	var owners: Array[Node] = [_main.get_node("BuildMode/BuildView"), _chars]
	var holder := PlateSight.colliders(root, owners, {cnode: "cleaner"})
	var space := root.get_world_3d().direct_space_state
	var box: AABB = (holder.get_meta("bounds") as Dictionary).get("cleaner", AABB())
	var hits := 0
	for p in _inner_points(box):
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(
				cam.global_position, p + (p - cam.global_position).normalized() * 3.0
			)
		)
		if not hit.is_empty() and str((hit.collider as Node).get_meta("subject", "")) == "cleaner":
			hits += 1
	holder.free()
	print(
		(
			"SUBJECT walk_%d cleaner screen=(%.0f,%.0f) in_frame=%s hits=%d"
			% [frame_idx, at.x, at.y, inside, hits]
		)
	)
	_expect(inside and hits > 0, "cleaner not visible at walk_%d" % frame_idx)


func _save_plate(path: String) -> Image:
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("PLATE %s err=%d size=%s" % [path, err, img.get_size()])
	_expect(err == OK, "failed saving %s" % path)
	return img


func _save_strip(imgs: Array[Image], path: String) -> void:
	var w := 640
	var h := 360
	var strip := Image.create(w * imgs.size(), h, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		var im := imgs[i].duplicate() as Image
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	var err := strip.save_png(path)
	print("PLATE %s err=%d" % [path, err])
	_expect(err == OK, "failed saving %s" % path)
