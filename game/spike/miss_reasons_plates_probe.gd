extends SceneTree
## Windowed plates for the miss markers. Boots the real main scene with a new
## random sim seed (printed), builds ReferenceTerminal through the HUD's
## starter-terminal button, removes its east check-in desk so the one desk left
## overflows (as in the first playtest), and runs the default flight at 3x.
## Plates, each at the default play zoom (distance 80) and near (distance 12):
##   01/02 the full desk with its "Queue full" sign and caption
##   03/04 late passengers in at least four places, each with its badge; badges
##         of passengers APART_M or more apart must not overlap by half
##   05 the same view after doors close: no sign and no badges left
## Every plate prints the screen rectangles it checked. A sign, caption, badge or
## subject outside the frame, or a subject behind a blocker, prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <repo>/game -s res://spike/miss_reasons_plates_probe.gd

const OUT_REL := "res://../tools/blender/out/miss-reasons"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const FAR := 80.0
const NEAR := 12.0
const MIN_LATE := 3
## Late passengers at least this far apart must show separate badges.
const APART_M := 0.9
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
	_beat("overflow")
	while _clock.tick < 1850:
		var held: int = MissSignals.full_stations(_sim).get(desk, 0)
		if held >= 2 and _badge_ids().size() >= MIN_LATE:
			break
		await process_frame
	_hud.press_speed(0)
	await _frames(5)
	var full := MissSignals.full_stations(_sim)
	print(
		(
			"PROBE paused tick=%d full=%s lane=%d holding=%d late=%d badges=%d"
			% [
				_clock.tick,
				full,
				_sim.queue_of(desk).size(),
				_sim.holding_of(desk).size(),
				MissSignals.late_ids(_sim).size(),
				_badge_ids().size()
			]
		)
	)
	if not full.has(desk) or full[desk] < 2 or _badge_ids().size() < MIN_LATE:
		_invalid("no overflow with %d late passengers by tick %d" % [MIN_LATE, _clock.tick])
		return
	var desk_point := _markers.sign_for(desk).position - Vector3(0.0, 1.7, 0.0)
	await _plate_sign(desk, desk_point, FAR, "01_queue_full_far.png")
	await _plate_sign(desk, desk_point, NEAR, "02_queue_full_near.png")
	# Late passengers spread over at least MIN_LATE + 1 places, not one holding cell.
	_hud.press_speed(3)
	_beat("late spread")
	while _clock.tick < 1850 and _spread().size() <= MIN_LATE:
		await process_frame
	_hud.press_speed(0)
	await _frames(5)
	var spread := _spread()
	print(
		"PROBE late tick=%d badges=%d places=%d" % [_clock.tick, _badge_ids().size(), spread.size()]
	)
	if spread.size() <= MIN_LATE:
		_invalid("late passengers never spread over %d places" % (MIN_LATE + 1))
		return
	var late_centre := Vector3.ZERO
	for at in spread:
		late_centre += at
	late_centre /= spread.size()
	await _plate_late(late_centre, FAR, "03_late_far.png")
	await _plate_late(late_centre, NEAR, "04_late_near.png")
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


func _plate_late(centre: Vector3, distance: float, name: String) -> void:
	_beat(name)
	_aim(centre, distance)
	await _frames(20)
	var rects: Array[Rect2] = []
	var feet: Array[Vector3] = []
	var shown := 0
	for id in _badge_ids():
		var badge := _markers.badge_for(id)
		var torso := _views.node_for(id).position + Vector3(0.0, 1.0, 0.0)
		var px := MissMarkers.badge_px(
			-(_cam.global_transform.affine_inverse() * badge.global_position).z,
			_cam.fov,
			root.get_visible_rect().size.y
		)
		var anchor := _cam.unproject_position(badge.global_position)
		var rect := Rect2(anchor - Vector2(px / 2.0, px), Vector2.ONE * px)
		if _cam.is_position_behind(badge.global_position) or not _rect_in_frame(rect):
			continue
		if not _in_frame(torso) or _hidden(torso):
			continue
		shown += 1
		rects.append(rect)
		feet.append(_views.node_for(id).position)
	var overlaps := 0
	var apart_overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var area := rects[i].intersection(rects[j]).get_area()
			if area > rects[i].get_area() * 0.5:
				overlaps += 1
				if feet[i].distance_to(feet[j]) >= APART_M:
					apart_overlaps += 1
	var first := rects[0] if not rects.is_empty() else Rect2()
	print(
		(
			(
				"PLATE %s tick=%d distance=%.0f late=%d badges_shown=%d first_badge=%s"
				+ " overlap_pairs=%d overlap_pairs_apart=%d"
			)
			% [
				name,
				_clock.tick,
				distance,
				_badge_ids().size(),
				shown,
				first,
				overlaps,
				apart_overlaps
			]
		)
	)
	if apart_overlaps > 0:
		_invalid("%s: badges of passengers %.1f m apart overlap" % [name, APART_M])
	elif shown >= MIN_LATE:
		_save(name)
	else:
		_invalid("%s: only %d late badges in frame over visible passengers" % [name, shown])


func _plate_cleared(desk: int, desk_point: Vector3) -> void:
	_hud.press_speed(3)
	_beat("cleared")
	while _clock.tick < 1910:
		await process_frame
	_hud.press_speed(0)
	_aim(desk_point, FAR)
	await _frames(20)
	print(
		(
			"PLATE 05_cleared_far.png tick=%d missed=%d sign=%s badges=%d lane=%d holding=%d"
			% [
				_clock.tick,
				_sim.missed_count(),
				_markers.sign_for(desk),
				_badge_ids().size(),
				_sim.queue_of(desk).size(),
				_sim.holding_of(desk).size()
			]
		)
	)
	var clear := _markers.sign_for(desk) == null and _badge_ids().is_empty()
	if clear and _sim.missed_count() > 0 and _in_frame(desk_point):
		_save("05_cleared_far.png")
	else:
		_invalid("05: markers still shown after doors close, or nobody missed")


## Drawn positions of the badged passengers, one per place: passengers closer
## than APART_M to an earlier one count once.
func _spread() -> Array[Vector3]:
	var places: Array[Vector3] = []
	for id in _badge_ids():
		var at := _views.node_for(id).position
		var near := false
		for place in places:
			near = near or place.distance_to(at) < APART_M
		if not near:
			places.append(at)
	return places


func _badge_ids() -> Array[int]:
	var out: Array[int] = []
	for id in _sim.passenger_ids():
		var badge := _markers.badge_for(id)
		if badge != null and badge.visible:
			out.append(id)
	return out


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
