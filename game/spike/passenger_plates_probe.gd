extends SceneTree
## Windowed plate and benchmark probe for slice g (passengers). Boots the real main scene
## with a new random sim seed (printed), builds ReferenceTerminal through the HUD's
## starter-terminal button and runs the default flight at 3x. Plates:
##   1 passengers queuing at the desks and scanners and seated at the gate
##   2 a late passenger running, with its thought bubble, followed from the HUD
##   3 the plane at the stand with passengers walking to its door
## The HUD is on every plate. Then a fresh scene spawns the 300-passenger debug batch and
## runs at 3x, printing frame and tick times.
##
## Run (one windowed Godot run project-wide; hold game/.godot/windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/passenger_plates_probe.gd
##
## Plates go to tools/blender/out/passengers/. A subject that is not in frame or is hidden
## prints PROBE_INVALID and the probe exits 1.

const OUT_REL := "res://../tools/blender/out/passengers"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const BENCH_TICKS := 900
## World boxes that can hide a passenger: the Toon terminal (measured by
## passenger_measure_probe.gd) and the parked plane's fuselage. The plane's measured box
## (x -32.2 to -3.8) includes the wings, so the fuselage width here is an estimate.
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
			OS.crash("passenger plates probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _boot() -> void:
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
	_hud = _main.get_node("PassengerHud")
	await _frames(5)
	_hud.press_starter_terminal()
	print(
		"PROBE terminal objects=",
		_sim.grid.object_ids().size(),
		" seats=",
		_sim.layout.seats.size()
	)
	_hud.press_speed(3)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _until(stage: String, limit_tick: int, done: Callable) -> bool:
	_beat(stage)
	while _clock.tick < limit_tick:
		if done.call():
			return true
		await process_frame
	_invalid("%s: condition not met by tick %d" % [stage, limit_tick])
	return false


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = at
	_rig.yaw = yaw
	_rig.distance = distance


func _run() -> void:
	await _boot()
	await _plate_queues()
	await _plate_late()
	await _plate_boarding()
	_main.queue_free()
	await _frames(5)
	await _benchmark()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _plate_queues() -> void:
	var ok: bool = await _until(
		"queues", 1200, func() -> bool: return _count(_queued) >= 2 and _count(_seated) >= 2
	)
	_hud.press_speed(0)
	_aim(Vector3(-16.0, 0.0, -21.0), 26.0, 0.0)
	await _frames(20)
	print("PLATE1 tick=%d queued=%d seated=%d" % [_clock.tick, _count(_queued), _count(_seated)])
	if ok and _visible(_queued) >= 2 and _visible(_seated) >= 2:
		_save("01_queues_and_seated.png")
	else:
		_invalid("plate 1 subjects not visible")
	_aim(Vector3(-17.0, 0.0, -27.0), 7.0, 0.0)
	await _frames(20)
	print("PLATE1b seated_visible=%d" % _visible(_seated))
	if _visible(_seated) >= 1:
		_save("01b_seated_close.png")
	else:
		_invalid("plate 1b seated passengers not visible")
	_hud.press_speed(3)


func _plate_late() -> void:
	var late := [0]
	var entrance := _sim.grid.cell_to_world(ReferenceTerminal.ENTRANCE_CELL)
	var running := func(p: Passenger) -> bool:
		var away := _sim.world_position(p).distance_to(entrance) > 3.0
		return p.late and p.stage < Passenger.Stage.TO_EXIT and p.is_moving() and away
	var found: bool = await _until(
		"late",
		1850,
		func() -> bool:
			late[0] = _first(running)
			return late[0] != 0
	)
	if not found:
		return
	_hud.press_speed(0)
	var p := _sim.get_passenger(late[0])
	_aim(_views.node_for(p.id).position, 14.0, 0.0)
	_views.selected_id = p.id
	await _frames(20)
	var node := _views.node_for(p.id)
	print(
		(
			'PLATE2 tick=%d id=%d stage=%d bubble="%s" clip=%s at=%s'
			% [
				_clock.tick,
				p.id,
				p.stage,
				_sim.bubble_text(p),
				node.get_meta(&"clip"),
				node.position
			]
		)
	)
	if _in_frame(node.position + Vector3(0, 1, 0)) and node.get_meta(&"clip") == "run":
		_save("02_late_runner.png")
	else:
		_invalid("plate 2 runner not in frame or not running")
	_views.selected_id = 0
	_hud.press_speed(3)


func _plate_boarding() -> void:
	var near_plane := func(p: Passenger) -> bool:
		return p.stage == Passenger.Stage.APRON and _sim.world_position(p).z < -100.5
	var ok: bool = await _until("boarding", 1900, func() -> bool: return _count(near_plane) >= 2)
	_hud.press_speed(0)
	_aim(Vector3(-15.0, 0.0, -106.0), 24.0, PI * 0.8)
	await _frames(20)
	var shown := _visible(near_plane)
	print(
		(
			"PLATE3 tick=%d near_plane=%d visible=%d made=%d"
			% [_clock.tick, _count(near_plane), shown, _sim.made_count()]
		)
	)
	if ok and shown >= 1:
		_save("03_boarding_at_stand.png")
	else:
		_invalid("plate 3 boarding passengers not visible")
	_hud.press_speed(3)
	await _until("doors", 1910, func() -> bool: return _clock.tick >= 1901)
	print("OUTCOME made=%d missed=%d" % [_sim.made_count(), _sim.missed_count()])


func _benchmark() -> void:
	_stage = "bench"
	await _boot()
	await _frames(10)
	_hud.press_debug_spawn()
	_aim(Vector3(-16.0, 0.0, -20.0), 40.0, 0.0)
	var start_tick := _clock.tick
	_sim.tick_usec_max = 0
	_sim.tick_usec_total = 0
	_sim.ticks_measured = 0
	var frames: Array[int] = []
	var peak := 0
	var last := Time.get_ticks_usec()
	while _clock.tick - start_tick < BENCH_TICKS:
		await process_frame
		_beat("bench")
		var now := Time.get_ticks_usec()
		frames.append(now - last)
		last = now
		peak = maxi(peak, _views.active_count())
	frames.sort()
	var total := 0
	for f in frames:
		total += f
	print(
		(
			"BENCH speed=%dx ticks=%d frames=%d frame_ms avg=%.2f p50=%.2f p95=%.2f max=%.2f"
			% [
				_clock.speed,
				_clock.tick - start_tick,
				frames.size(),
				total / 1000.0 / frames.size(),
				frames[frames.size() / 2] / 1000.0,
				frames[int(frames.size() * 0.95)] / 1000.0,
				frames[frames.size() - 1] / 1000.0
			]
		)
	)
	print(
		(
			"BENCH tick_us avg=%.0f max=%d views_peak=%d passengers=%d seed=%d"
			% [
				_sim.tick_usec_total / float(maxi(_sim.ticks_measured, 1)),
				_sim.tick_usec_max,
				peak,
				_sim.passenger_ids().size(),
				_sim.last_batch_seed
			]
		)
	)
	_hud.press_speed(0)
	await _frames(5)
	_save("04_benchmark_300.png")


func _queued(p: Passenger) -> bool:
	return p.stage in [Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.SECURITY_QUEUE]


func _seated(p: Passenger) -> bool:
	return p.stage == Passenger.Stage.SEATED


func _count(test: Callable) -> int:
	var n := 0
	for id in _sim.passenger_ids():
		n += int(test.call(_sim.get_passenger(id)))
	return n


func _first(test: Callable) -> int:
	for id in _sim.passenger_ids():
		if test.call(_sim.get_passenger(id)):
			return id
	return 0


## Subjects passing `test` whose drawn node is in frame and not behind a blocker.
func _visible(test: Callable) -> int:
	var n := 0
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null or not test.call(_sim.get_passenger(id)):
			continue
		var at := node.position + Vector3(0.0, 1.0, 0.0)
		if _in_frame(at) and not _hidden(at):
			n += 1
	return n


func _in_frame(at: Vector3) -> bool:
	var rect := Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)
	var screen := _cam.unproject_position(at)
	return not _cam.is_position_behind(at) and rect.has_point(screen)


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
