extends SceneTree
## Windowed plate of the line outside the entrance under load (board 66be00a0,
## decision arrivals-wait-in-a-tidy-line-outside-the-entrance-when-check): the
## starter terminal with PROBE_N extra booked (default 150) through the real
## landside path, run until the line holds at least MIN_WAITING, then one shot
## from beside the line with the HUD hidden. Every waiting passenger must be in
## frame and not hidden behind a mesh, or it prints PROBE_INVALID and exits 1.
## Env: PROBE_N, PROBE_SEED (random when unset), PROBE_OUT (the plate folder).
## Run windowed: --display-driver windows --rendering-driver vulkan.
const StarterFlight := preload("res://spike/starter_flight.gd")
const MIN_WAITING := 10
const MARGIN_PX := 30.0
## Head height above a passenger's feet for the in-frame and ray checks.
const HEAD_M := 1.5
const VIEW_OFFSET := Vector3(9.0, 7.5, 3.0)

var _main: Node
var _clock: SimClock
var _sim: PassengerSim


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var n := 150
	if OS.has_environment("PROBE_N"):
		n = OS.get_environment("PROBE_N").to_int()
	var seed := randi()
	if OS.has_environment("PROBE_SEED"):
		seed = OS.get_environment("PROBE_SEED").to_int()
	var out_dir := OS.get_environment("PROBE_OUT")
	if out_dir == "":
		_invalid("PROBE_OUT (the plate folder) is not set")
		return
	_main = load("res://main/main.tscn").instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	for i in 3:
		await process_frame
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	_sim = _main.get_node("PassengerSim")
	NeedFacilityKit.build(mode.grid)
	StarterFlight.add_gate_desk(mode.grid)
	var staff := _main.get_node("Staff") as StaffSim
	StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	var flight := StarterFlight.first_flight()
	_sim.arrivals.schedule(flight, n)
	print("PLATE seed=%d n=%d" % [seed, n])
	while _clock.tick < doors and _standing().size() < MIN_WAITING:
		_clock.advance(SimClock.STEP)
	# A few more ticks so the line has settled on its places.
	for i in 40:
		_clock.advance(SimClock.STEP)
	for fleet in _main.find_children("*", "PlaneFleet", true, false):
		(fleet as PlaneFleet).update_views()
	var waiting := _standing()
	print(
		(
			"PLATE tick=%d waiting=%d line=%d"
			% [_clock.tick, waiting.size(), _sim.entrance.order.size()]
		)
	)
	if waiting.size() < MIN_WAITING:
		_invalid("only %d waiting outside" % waiting.size())
		return
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var tycoon := _main.get_node("TycoonCamera")
	tycoon.set_process(false)
	var cam: Camera3D = _main.get_node("TycoonCamera/Camera3D")
	var mid := Vector3.ZERO
	for at in waiting:
		mid += at
	mid /= waiting.size()
	cam.look_at_from_position(mid + VIEW_OFFSET, mid, Vector3.UP)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var frame := Rect2(Vector2.ZERO, Vector2(root.size)).grow(-MARGIN_PX)
	var space := cam.get_world_3d().direct_space_state
	for at in waiting:
		var head := at + Vector3.UP * HEAD_M
		var screen := cam.unproject_position(head)
		print("PLATE subject %s screen=%s" % [at, screen])
		if cam.is_position_behind(head) or not frame.has_point(screen):
			_invalid("waiting passenger at %s is out of frame (%s)" % [at, screen])
			return
		var ray := PhysicsRayQueryParameters3D.create(cam.global_position, head)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			var gap: float = cam.global_position.distance_to(head)
			var near: float = cam.global_position.distance_to(hit["position"])
			if near < gap - 0.4:
				_invalid("waiting passenger at %s is hidden by %s" % [at, hit.get("collider")])
				return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join("entrance_line_load.png")
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	quit(0)


## Where each passenger waiting outside stands, at the end of its walk.
func _standing() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for id in _sim.entrance.order:
		var p := _sim.get_passenger(id)
		if not p.apron.is_empty() and p.apron_mm >= p.apron_total_mm():
			out.append(p.apron_position())
	return out


func _invalid(why: String) -> void:
	print("PROBE_INVALID: %s" % why)
	quit(1)
