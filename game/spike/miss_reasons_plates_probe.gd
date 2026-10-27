extends SceneTree
## Windowed plates for the queue-full sign. Boots the real main scene with a
## new random sim seed (printed), builds ReferenceTerminal through the HUD's
## starter-terminal button, removes its east check-in desk so the one desk left
## overflows (as in the first playtest), and runs the default flight at 3x.
## Plates:
##   01 the full desk with its "Queue full" sign, at the default play zoom (80)
##   02 the same, near (distance 12)
##   03 the same far view after doors close: no sign left
## Every plate prints the screen rectangles it checked, in layout (canvas)
## pixels, which is what unproject_position returns. Each fails with
## PROBE_INVALID and exit 1 when the sign, caption or desk leaves the frame;
## when the HUD draws over any of them (the plate against a twin rendered with
## the HUD's canvas layers hidden); when the desk is not seen (sight lines
## against every visible mesh of the shell, the build and the plane must land
## on the desk's own meshes with no blocker); or when the sign's red fill
## measured in the plate is not SIGN_PX on screen.
##
## Run (one windowed Godot run project-wide); --ui-scale overrides the content
## scale from project.godot, and the plate names carry the scale:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <repo>/game -s res://spike/miss_reasons_plates_probe.gd \
##     -- --ui-scale=1.0

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/miss_reasons"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
## A whole flight at 3x is 1900 ticks / 60 per second, about 32 s.
const WAIT_LIMIT_MS := 120000
const STALL_LIMIT_MS := 5000
const FAR := 80.0
const NEAR := 12.0
const CAPTION_OUTLINE_PX := 8.0
## Scene nodes whose visible meshes can hide the desk.
const OCCLUDER_OWNERS: Array[String] = ["Airside/Terminal", "BuildMode", "PlaneView"]
## How far the measured red fill may be from SIGN_PX scale, in screen pixels
## (linear mipmap filtering blurs each edge by about one pixel).
const SIZE_TOLERANCE_PX := 2.0
## How close a plate pixel must be to the sampled fill colour to count.
const FILL_TOLERANCE := 0.1

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _markers: MissMarkers
var _hud: PassengerHud
var _scale_tag := ""
var _saved: Array[Image] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			root.content_scale_factor = float(arg.get_slice("=", 1))
	_scale_tag = "_s%.2f" % root.content_scale_factor
	print("PROBE ui_scale=%.2f" % root.content_scale_factor)
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
			OS.crash("miss reasons plates probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	var desk := await _boot()
	if desk != 0:
		await _plates(desk)
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	if not _saved.is_empty():
		_save(_sheet(), "contact_sheet")
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


## Boots the scene with one check-in desk. Returns the desk id, or 0.
func _boot() -> int:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(_main)
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_markers = _views.get_node("MissMarkers")
	_hud = _main.get_node("PassengerHud")
	await _frames(5)
	_hud.press_starter_terminal()
	var desks: Array = ReferenceTerminal.object_ids(_sim.grid)["desks"]
	if desks.size() != 2:
		_invalid("starter terminal has %d desks, expected 2" % desks.size())
		return 0
	var removed := _sim.grid.apply(BuildEdit.remove_object(desks[1]))
	if not removed.ok:
		_invalid("could not remove the east desk: %s" % removed.reason_text())
		return 0
	(_main.get_node("BuildMode/BuildView") as BuildView).refresh(_sim.grid)
	print("PROBE one desk=%d lane_cells=%d" % [desks[0], _sim.layout.lanes[desks[0]].size()])
	_hud.press_speed(3)
	return desks[0]


func _plates(desk: int) -> void:
	var overflowed := func() -> bool: return MissSignals.full_stations(_sim).get(desk, 0) >= 2
	if not await _wait_for("overflow", 1850, overflowed):
		return
	_hud.press_speed(0)
	await _frames(5)
	var full := MissSignals.full_stations(_sim)
	print(
		(
			"PROBE paused tick=%d full=%s lane=%d holding=%d"
			% [_clock.tick, full, _sim.queue_of(desk).size(), _sim.holding_of(desk).size()]
		)
	)
	if not full.has(desk) or full[desk] < 2:
		_invalid("no overflow of 2 at desk %d by tick %d" % [desk, _clock.tick])
		return
	var sign := _markers.sign_for(desk)
	if sign == null or not sign.visible:
		_invalid("desk %d is full but has no visible sign" % desk)
		return
	var bounds := _desk_bounds(desk)
	if bounds.size == Vector3.ZERO:
		_invalid("desk %d has no visible mesh" % desk)
		return
	print("PROBE desk_bounds=%s" % bounds)
	await _plate_sign(desk, bounds, FAR, "01_queue_full_far")
	await _plate_sign(desk, bounds, NEAR, "02_queue_full_near")
	await _plate_cleared(desk, bounds.get_center())


## The union of the desk's visible meshes in world space, or a zero box.
func _desk_bounds(desk: int) -> AABB:
	var node := _build_view().object_node(desk)
	var bounds := AABB()
	if node == null:
		return bounds
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _build_view() -> BuildView:
	return _main.get_node("BuildMode/BuildView") as BuildView


func _plate_sign(desk: int, bounds: AABB, distance: float, name: String) -> void:
	_beat(name)
	_aim(bounds.get_center(), distance)
	await _frames(20)
	var sign := _markers.sign_for(desk)
	if sign == null or not sign.visible or _cam.is_position_behind(sign.global_position):
		_invalid("%s: no visible sign in front of the camera on desk %d" % [name, desk])
		return
	# Freeze animation, so the plate and its HUD-less twin differ only by the HUD.
	paused = true
	var img := await _grab()
	# unproject_position returns layout pixels; the content scale draws one
	# layout pixel over 1 / per_screen screen pixels of the rendered plate.
	var per_screen := root.get_visible_rect().size.y / float(img.get_height())
	var sign_px := MissMarkers.SIGN_PX * per_screen
	var anchor := _cam.unproject_position(sign.global_position)
	var icon := Rect2(anchor - Vector2(sign_px / 2.0, sign_px), Vector2.ONE * sign_px)
	var text := _markers.sign_text(desk)
	var size := (
		ThemeDB.fallback_font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, MissMarkers.CAPTION_FONT
		)
		* per_screen
	)
	var lift := (MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX) * per_screen + size.y
	var caption := Rect2(anchor + Vector2(-size.x / 2.0, -lift), size).grow(
		CAPTION_OUTLINE_PX * per_screen
	)
	var desk_px := _cam.unproject_position(bounds.get_center())
	print(
		(
			(
				"PLATE %s%s tick=%d distance=%.0f plate=%s per_screen=%.3f"
				+ ' sign_icon=%s caption=%s "%s" desk_px=%s'
			)
			% [
				name,
				_scale_tag,
				_clock.tick,
				distance,
				img.get_size(),
				per_screen,
				icon,
				caption,
				text,
				desk_px
			]
		)
	)
	var ok := _framed("sign", icon)
	ok = _framed("caption", caption) and ok
	ok = _framed("desk", Rect2(desk_px, Vector2.ZERO)) and ok
	var seen := await _desk_seen(desk, bounds)
	ok = not seen.is_empty() and ok
	# The HUD check covers the desk where the sight lines landed on it.
	var subjects: Array[Rect2] = [icon, caption]
	for at in seen:
		subjects.append(Rect2(_cam.unproject_position(at) - Vector2.ONE * 3.0, Vector2.ONE * 6.0))
	ok = await _clear_of_hud(img, subjects, per_screen) and ok
	ok = _sign_size_ok(img, icon, per_screen) and ok
	paused = false
	if ok:
		_save(img, name)
	else:
		_invalid("%s: sign, caption or desk out of frame, under the HUD, hidden or off size" % name)


## In the frame with a margin, in layout pixels.
func _framed(label: String, rect: Rect2) -> bool:
	var inside := _frame_rect().encloses(rect)
	print("INFRAME %s rect=%s in_frame=%s" % [label, rect, inside])
	return inside


## The HUD over a subject, measured: the plate again with every canvas layer of
## the scene hidden, compared pixel by pixel inside each subject rect (layout
## rects, read in screen pixels and rounded outward). The control is the whole
## plate: hiding the layers must change it, or the comparison proves nothing.
func _clear_of_hud(img: Image, rects: Array[Rect2], per_screen: float) -> bool:
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var plate := Rect2i(Vector2i.ZERO, img.get_size())
	var changed := PlateSight.differing(img, bare, plate, 4)
	var ok := changed > 0
	var under: Array[int] = []
	for rect in rects:
		var lo := Vector2i((rect.position / per_screen).floor())
		var hi := Vector2i((rect.end / per_screen).ceil())
		var screen := Rect2i(lo, hi - lo)
		var count := PlateSight.differing(img, bare, screen.intersection(plate), 1)
		under.append(count)
		ok = ok and count == 0
	print(
		(
			"HUD layers_hidden=%d plate_px_changed=%d sign_caption_deskhits_px_under_hud=%s ok=%s"
			% [twin["layers"], changed, under, ok]
		)
	)
	return ok


## Nine sight lines from the camera to a grid of points just under the top of
## the desk's bounds, each run on 3 m past its point. A first hit on the desk's
## own meshes sees the desk. A first hit on anything else before the point is a
## blocker. A line that passes its point without touching anything (the point
## was in the air between the desk's parts) proves nothing either way. Passes
## with no blocker and at least one line on the desk, so a hidden desk, a wall
## in front or an occluder set without the desk all fail. Returns the points
## where lines landed on the desk, or none when the check fails.
func _desk_seen(desk: int, bounds: AABB) -> Array[Vector3]:
	var occluders := _colliders(_build_view().object_node(desk))
	await physics_frame
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	var from := _cam.global_position
	var targets: Array[Vector3] = []
	for i in 3:
		for j in 3:
			var at := (
				bounds.position
				+ Vector3(
					(i + 0.5) / 3.0 * bounds.size.x,
					bounds.size.y - 0.02,
					(j + 0.5) / 3.0 * bounds.size.z
				)
			)
			targets.append(at)
	var lines := PlateSight.sight_lines(space, from, targets, "desk")
	var on_desk: Array[Vector3] = lines["on_subject"]
	var neutral: int = lines["past"]
	var blockers: Array[String] = lines["blockers"]
	occluders.free()
	var ok := not on_desk.is_empty() and blockers.is_empty()
	print(
		(
			"VISIBLE desk lines=9 on_desk=%d past_the_point=%d blockers=%s ok=%s"
			% [on_desk.size(), neutral, blockers, ok]
		)
	)
	if not ok:
		on_desk.clear()
	return on_desk


## The sign's red fill measured in the plate (screen pixels) against the icon's
## fill scaled to SIGN_PX: the connected region of the fill colour around a
## pixel a quarter in from the icon's left edge (clear of the white glyph).
func _sign_size_ok(img: Image, icon: Rect2, per_screen: float) -> bool:
	var screen := Rect2(icon.position / per_screen, icon.size / per_screen)
	var box := Rect2i(screen.grow(12.0)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var start := Vector2i(screen.position + screen.size * Vector2(0.25, 0.5))
	var fill := img.get_pixelv(start)
	var lo := start
	var hi := start
	var seen := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		lo = lo.min(p)
		hi = hi.max(p)
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var q := p + step
			if box.has_point(q) and not seen.has(q) and _near(img.get_pixelv(q), fill):
				seen[q] = true
				todo.append(q)
	var measured := Vector2(hi - lo + Vector2i.ONE)
	var expected := _fill_texels() * MissMarkers.SIGN_PX / MarkerIcons.SIZE
	var red := fill.r > fill.g + 0.3 and fill.r > fill.b + 0.3
	var ok := (
		red
		and absf(measured.x - expected.x) <= SIZE_TOLERANCE_PX
		and absf(measured.y - expected.y) <= SIZE_TOLERANCE_PX
	)
	print(
		(
			"SIZE fill_colour=%s fill_px=%d fill_bbox_screen_px=%s expected=%s sign_px=%.1f ok=%s"
			% [fill, seen.size(), measured, expected, MissMarkers.SIGN_PX, ok]
		)
	)
	return ok


## The icon texture's red fill extent, in texels.
func _fill_texels() -> Vector2:
	var tex := MarkerIcons.queue_full().get_image()
	var lo := tex.get_size()
	var hi := -Vector2i.ONE
	for y in tex.get_height():
		for x in tex.get_width():
			var c := tex.get_pixel(x, y)
			if c.a > 0.99 and _near(c, MarkerIcons.QUEUE_FILL):
				lo = lo.min(Vector2i(x, y))
				hi = hi.max(Vector2i(x, y))
	return Vector2(hi - lo + Vector2i.ONE)


func _near(a: Color, b: Color) -> bool:
	return (
		absf(a.r - b.r) < FILL_TOLERANCE
		and absf(a.g - b.g) < FILL_TOLERANCE
		and absf(a.b - b.b) < FILL_TOLERANCE
	)


## One static body per visible mesh of the occluder owners, in world space,
## for the sight lines (PlateSight). Bodies from the desk's own meshes carry
## the "desk" subject tag.
func _colliders(desk_node: Node3D) -> Node3D:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var subjects := {}
	if desk_node != null:
		subjects[desk_node] = "desk"
	var holder := PlateSight.colliders(root, owners, subjects)
	var unbaked: Array = holder.get_meta("unbaked")
	if not unbaked.is_empty():
		_invalid("skinned meshes not baked: %s" % [unbaked])
	print("PROBE occluder bodies=%d" % holder.get_child_count())
	return holder


func _grab() -> Image:
	return await PlateSight.grab(self)


func _plate_cleared(desk: int, desk_point: Vector3) -> void:
	_hud.press_speed(3)
	if not await _wait_for("cleared", 1960, func() -> bool: return _clock.tick >= 1910):
		return
	_hud.press_speed(0)
	_aim(desk_point, FAR)
	await _frames(20)
	print(
		(
			"PLATE 03_cleared_far%s tick=%d missed=%d sign=%s lane=%d holding=%d"
			% [
				_scale_tag,
				_clock.tick,
				_sim.missed_count(),
				_markers.sign_for(desk),
				_sim.queue_of(desk).size(),
				_sim.holding_of(desk).size()
			]
		)
	)
	var clear := _markers.sign_for(desk) == null
	if clear and _sim.missed_count() > 0 and _in_frame(desk_point):
		_save(await _grab(), "03_cleared_far")
	else:
		_invalid("03: sign still shown after doors close, or nobody missed")


## Steps frames until `done` holds. Fails through _invalid() when the sim
## reaches `limit_tick` first, when the wait passes WAIT_LIMIT_MS, or when the
## clock has not advanced for STALL_LIMIT_MS (the heartbeat in _process keeps
## the guard thread quiet, so it cannot catch a stalled clock).
func _wait_for(stage: String, limit_tick: int, done: Callable) -> bool:
	_beat(stage)
	var start_ms := Time.get_ticks_msec()
	var moved_ms := start_ms
	var last_tick := _clock.tick
	while not done.call():
		var now_ms := Time.get_ticks_msec()
		if _clock.tick != last_tick:
			last_tick = _clock.tick
			moved_ms = now_ms
		if _clock.tick >= limit_tick:
			_invalid("%s: not met by tick %d" % [stage, limit_tick])
			return false
		if now_ms - start_ms > WAIT_LIMIT_MS:
			_invalid("%s: not met in %d ms (tick %d)" % [stage, WAIT_LIMIT_MS, _clock.tick])
			return false
		if now_ms - moved_ms > STALL_LIMIT_MS:
			_invalid(
				"%s: clock stalled at tick %d for %d ms" % [stage, last_tick, now_ms - moved_ms]
			)
			return false
		await process_frame
	return true


func _aim(at: Vector3, distance: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = 0.0
	_rig.distance = distance


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _frame_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)


func _in_frame(at: Vector3) -> bool:
	return not _cam.is_position_behind(at) and _frame_rect().has_point(_cam.unproject_position(at))


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name + _scale_tag + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	_saved.append(img)


## Every saved plate at half size, side by side in plate order.
func _sheet() -> Image:
	var w := _saved[0].get_width() / 2
	var h := _saved[0].get_height() / 2
	var sheet := Image.create(w * _saved.size(), h, false, Image.FORMAT_RGBA8)
	for i in _saved.size():
		var small := _saved[i].duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	return sheet
