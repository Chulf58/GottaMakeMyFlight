extends SceneTree
## Windowed plates for the queue-full sign. Boots the real main scene with a
## new random sim seed (printed), builds ReferenceTerminal through the HUD's
## starter-terminal button, removes its east check-in desk so the one desk left
## overflows (as in the first playtest), and runs the default flight at 3x.
## Plates:
##   01 the full desk with its "Queue full" sign, at the default play zoom (80)
##   02 the same, near (distance 12)
##   03 the same far view after doors close: no sign left
## Every plate prints the screen rectangles it checked. A sign, caption or desk
## outside the frame, or a desk behind a blocker, prints PROBE_INVALID and the
## probe exits 1.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <repo>/game -s res://spike/miss_reasons_plates_probe.gd

const OUT_REL := "res://../tools/blender/out/miss-reasons"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
## A whole flight at 3x is 1900 ticks / 60 per second, about 32 s.
const WAIT_LIMIT_MS := 120000
const STALL_LIMIT_MS := 5000
const FAR := 80.0
const NEAR := 12.0
const CAPTION_OUTLINE_PX := 8.0
## World boxes that can hide a subject, as in passenger_plates_probe.gd: the
## Toon terminal and the parked plane's fuselage.
const BLOCKERS: Array[AABB] = [
	AABB(Vector3(-43.0, -0.1, -100.0), Vector3(86.0, 20.9, 60.0)),
	AABB(Vector3(-20.2, 0.0, -131.83), Vector3(4.4, 4.5, 29.52)),
]

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
	var desk_point := sign.position - Vector3(0.0, 1.7, 0.0)
	await _plate_sign(desk, desk_point, FAR, "01_queue_full_far.png")
	await _plate_sign(desk, desk_point, NEAR, "02_queue_full_near.png")
	await _plate_cleared(desk, desk_point)


func _plate_sign(desk: int, desk_point: Vector3, distance: float, name: String) -> void:
	_beat(name)
	_aim(desk_point, distance)
	await _frames(20)
	var sign := _markers.sign_for(desk)
	if sign == null or not sign.visible:
		_invalid("%s: no visible sign on desk %d" % [name, desk])
		return
	var anchor := _cam.unproject_position(sign.global_position)
	var icon := Rect2(
		anchor - Vector2(MissMarkers.SIGN_PX / 2.0, MissMarkers.SIGN_PX),
		Vector2.ONE * MissMarkers.SIGN_PX
	)
	var text := _markers.sign_text(desk)
	var size := ThemeDB.fallback_font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, MissMarkers.CAPTION_FONT
	)
	var lift := MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX + size.y
	var caption := Rect2(anchor + Vector2(-size.x / 2.0, -lift), size).grow(CAPTION_OUTLINE_PX)
	var body := desk_point + Vector3(0.0, 0.6, 0.0)
	print(
		(
			'PLATE %s tick=%d distance=%.0f sign_icon=%s caption=%s "%s" desk_px=%s hidden=%s'
			% [
				name,
				_clock.tick,
				distance,
				icon,
				caption,
				text,
				_cam.unproject_position(body),
				_hidden(body)
			]
		)
	)
	var ok := _rect_in_frame(icon) and _rect_in_frame(caption) and _in_frame(body)
	if ok and not _hidden(body) and not _cam.is_position_behind(sign.global_position):
		_save(name)
	else:
		_invalid("%s: sign, caption or desk out of frame or hidden" % name)


func _plate_cleared(desk: int, desk_point: Vector3) -> void:
	_hud.press_speed(3)
	if not await _wait_for("cleared", 1960, func() -> bool: return _clock.tick >= 1910):
		return
	_hud.press_speed(0)
	_aim(desk_point, FAR)
	await _frames(20)
	print(
		(
			"PLATE 03_cleared_far.png tick=%d missed=%d sign=%s lane=%d holding=%d"
			% [
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
		_save("03_cleared_far.png")
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


func _rect_in_frame(rect: Rect2) -> bool:
	return _frame_rect().encloses(rect)


func _in_frame(at: Vector3) -> bool:
	return not _cam.is_position_behind(at) and _frame_rect().has_point(_cam.unproject_position(at))


func _hidden(at: Vector3) -> bool:
	for box in BLOCKERS:
		if box.has_point(at) or box.intersects_segment(_cam.global_position, at) != null:
			return true
	return false


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join(name)
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
