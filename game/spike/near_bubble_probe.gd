extends SceneTree
## Headless probe of the speech bubble declutter with a bubble just in front of
## the camera plane (board "The game now froze", playtest 2026-11-03). A
## passenger walking under the tycoon camera passes through depth zero beside
## it; PassengerViews measures that off-screen bubble at pixel_size / depth, so
## its screen rectangle grows without bound as the depth shrinks.
##
## Run:
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --headless \
##     --audio-driver Dummy --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/near_bubble_probe.gd
##
## It boots main.tscn with a new random world seed (printed), builds the
## starter terminal, opens the airport and steps the clock until a passenger
## shows a bubble. Then it stops the clock, puts its own camera DEPTHS[i] in
## front of that bubble and 3 m to its side, and draws FRAMES_PER_DEPTH frames
## at each depth. Per depth it prints the bubble's measured rectangle, the
## slowest frame and the static memory peak. The pass values are positives:
## the passenger with a bubble, its rectangle's size and the frames drawn. A
## guard thread prints PROBE_INVALID and calls OS.crash on a hang (anti-pattern
## a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const MAIN := "res://main/main.tscn"
const StarterFlight := preload("res://spike/starter_flight.gd")
const DEPTHS: Array[float] = [0.1, 0.01, 0.005, 0.002, 0.0001, 0.000001]
const FRAMES_PER_DEPTH := 3
const BUBBLE_LIMIT_TICKS := 40000
const HANG_LIMIT_MS := 60000
## The guard thread also ends the run past this much static memory, so a
## runaway allocation cannot take the machine's memory.
const MEMORY_LIMIT := 3 * 1024 * 1024 * 1024

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _sim: PassengerSim
var _staff: StaffSim
var _views: PassengerViews
var _camera: Camera3D
var _phase := 0
var _bubble: Label3D
var _depth_at := 0
var _frame := 0
var _slowest_ms := 0.0
var _frame_start := 0


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	_views = _main.get_node("PassengerViews")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)


func _process(_delta: float) -> bool:
	_beat("phase %d tick %d depth %d frame %d" % [_phase, _clock.tick, _depth_at, _frame])
	if _done:
		return true
	match _phase:
		0:
			_start()
		1:
			_find_bubble()
		2:
			_near_frames()
	return _done


func _start() -> void:
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var hired := StarterFlight.hire_per_station(_sim, _staff)
	var open_tick := StarterFlight.advance_until_open(_clock, _flights, _staff)
	print("PROBE started hired=%d open_tick=%d" % [hired, open_tick])
	if open_tick < 0:
		_fail("the airport did not open")
		return
	_phase = 1


func _find_bubble() -> void:
	var limit := _clock.tick + BUBBLE_LIMIT_TICKS
	var has_bubble := func() -> bool: return _bubble_label() != null
	StarterFlight.advance_until(_clock, has_bubble, limit - _clock.tick)
	_bubble = _bubble_label()
	if _bubble == null:
		_fail("no passenger showed a bubble in %d ticks" % BUBBLE_LIMIT_TICKS)
		return
	print("PROBE bubble tick=%d text='%s'" % [_clock.tick, _bubble.text])
	_camera = Camera3D.new()
	_camera.fov = 55.0
	root.add_child(_camera)
	_camera.make_current()
	_frame_start = Time.get_ticks_usec()
	_phase = 2


## The Bubble label of a drawn passenger whose sim shows a bubble, or null.
func _bubble_label() -> Label3D:
	_views.sync()
	var nodes: Dictionary = _views.get("_nodes")
	for node: Node3D in nodes.values():
		var bubble := node.get_node_or_null("Bubble") as Label3D
		if bubble != null and bubble.text != "":
			return bubble
	return null


func _near_frames() -> void:
	var now := Time.get_ticks_usec()
	if _frame > 0:
		_slowest_ms = maxf(_slowest_ms, (now - _frame_start) / 1000.0)
	if _frame == FRAMES_PER_DEPTH:
		_report_depth()
		_depth_at += 1
		_frame = 0
		_slowest_ms = 0.0
		if _depth_at == DEPTHS.size():
			print("PROBE_DONE")
			_finish(0)
			return
	# Looking along -Z from DEPTHS[_depth_at] in front of the bubble, 3 m to its side.
	var at := _bubble.global_position
	_camera.global_transform = Transform3D(
		Basis.IDENTITY, at + Vector3(-3.0, 0.0, DEPTHS[_depth_at])
	)
	_frame += 1
	_frame_start = Time.get_ticks_usec()


func _report_depth() -> void:
	var view := root.get_visible_rect().size
	var unit := NeedIcons.unit_of(root, _camera)
	var depth := (_bubble.global_position - _camera.global_position).dot(-_camera.global_basis.z)
	var rect := BubbleDeclutter.rect_of(
		Vector2.ZERO,
		_bubble.text,
		_bubble.font_size,
		_bubble.outline_size,
		_bubble.pixel_size / (depth * unit)
	)
	print(
		(
			"PROBE depth=%.6f view=%s rect_px=%.0fx%.0f slowest_frame_ms=%.1f mem_mb=%.1f peak_mb=%.1f"
			% [
				depth,
				view,
				rect.size.x,
				rect.size.y,
				_slowest_ms,
				OS.get_static_memory_usage() / 1048576.0,
				OS.get_static_memory_peak_usage() / 1048576.0,
			]
		)
	)


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null:
		_main.queue_free()
	if _camera != null:
		_camera.queue_free()
	quit(code)


func _beat(stage: String) -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_stage = stage
	_mutex.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var beat := _beat_ms
		var stage := _stage
		_mutex.unlock()
		if done:
			return
		var now := Time.get_ticks_msec()
		var memory := OS.get_static_memory_usage()
		if now - beat > HANG_LIMIT_MS or memory > MEMORY_LIMIT:
			print(
				(
					"PROBE_INVALID hang in stage '%s': %d ms since the last beat, mem_mb=%.1f"
					% [stage, now - beat, memory / 1048576.0]
				)
			)
			OS.crash("near bubble probe hung")
