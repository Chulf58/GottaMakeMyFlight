extends SceneTree
## Windowed plates of the line outside the entrance (board 814a5cfd): waiters
## standing in it face the door, the way the line moves. Boots main.tscn as
## entrance_line_probe.gd does, books extra passengers until at least
## MIN_WAITERS stand in the line, freezes the clock, then takes an oblique and
## a top-down plate of them with the HUD hidden. Before each plate every
## standing waiter's head must project inside the viewport with a margin, and
## its drawn yaw must face the door; otherwise PROBE_INVALID is printed and
## the probe exits 1. Env: PROBE_OUT (plate folder, required), PROBE_SEED.
## Run windowed: --display-driver windows --rendering-driver vulkan.
const StarterFlight := preload("res://spike/starter_flight.gd")
const MIN_WAITERS := 6
const BOOKED := 150
const HEAD_M := 1.7
const MARGIN_PX := 40.0
const FACE_TOLERANCE := 0.05

var _main: Node
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _rig: TycoonCamera
var _cam: Camera3D
var _out_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_out_dir = OS.get_environment("PROBE_OUT")
	if _out_dir == "":
		_invalid("PROBE_OUT is not set")
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var seed := randi()
	if OS.has_environment("PROBE_SEED"):
		seed = OS.get_environment("PROBE_SEED").to_int()
	print("ENTRANCE_FACING seed=%d" % seed)
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
	_views = _main.get_node("PassengerViews")
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	NeedFacilityKit.build(mode.grid)
	StarterFlight.add_gate_desk(mode.grid)
	StarterFlight.hire_per_station(_sim, _main.get_node("Staff") as StaffSim)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim"), _main.get_node("Staff") as StaffSim
	)
	_sim.arrivals.schedule(StarterFlight.first_flight(), BOOKED)
	var waiters: Array[Passenger] = []
	var most := 0
	while _clock.tick < doors and waiters.size() < MIN_WAITERS:
		_clock.advance(SimClock.STEP)
		waiters = _standing()
		most = maxi(most, _sim.entrance.order.size())
	await process_frame
	_clock.set_process(false)
	print(
		(
			"ENTRANCE_FACING tick=%d standing=%d line=%d most=%d"
			% [_clock.tick, waiters.size(), _sim.entrance.order.size(), most]
		)
	)
	if waiters.size() < MIN_WAITERS:
		_invalid("only %d waiters stand in the line" % waiters.size())
		return
	# Let the turns finish, then freeze the camera rig on the waiters.
	for i in PassengerTurns.TURN_TICKS * 2:
		_clock.advance(SimClock.STEP)
	waiters = _standing()
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var mid := Vector3.ZERO
	for p in waiters:
		mid += _sim.world_position(p)
	mid /= waiters.size()
	_cam.make_current()
	var shots := [
		["oblique", TycoonCamera.AngleStep.LOW, 18.0],
		["top", TycoonCamera.AngleStep.TOP_DOWN, 26.0]
	]
	for shot: Array in shots:
		_rig.set_process(true)
		_rig.set_angle_step(shot[1])
		_rig.position = mid
		_rig.distance = shot[2]
		_rig.yaw = 0.0
		_rig.zoom(1.0)
		for i in 30:
			await process_frame
		_rig.set_process(false)
		_views.draw()
		await RenderingServer.frame_post_draw
		if not _prove(str(shot[0]), waiters):
			return
		var img := root.get_texture().get_image()
		var path := _out_dir.path_join("entrance_facing_%s.png" % shot[0])
		if img.save_png(path) != OK:
			_invalid("could not save %s" % path)
			return
		print("PLATE saved %s size=%s" % [path, img.get_size()])
	quit(0)


## The passengers of the line standing on their places.
func _standing() -> Array[Passenger]:
	var out: Array[Passenger] = []
	for id in _sim.entrance.order:
		var p := _sim.get_passenger(id)
		if p.stage == Passenger.Stage.SPAWNED and p.apron_mm >= p.apron_total_mm():
			out.append(p)
	return out


func _prove(label: String, waiters: Array[Passenger]) -> bool:
	var rect := root.get_visible_rect().grow(-MARGIN_PX)
	var door := EntranceLooks.face(_sim, waiters[0])
	var want := atan2(door.x, door.y)
	for p in waiters:
		var head := _sim.world_position(p) + Vector3(0.0, HEAD_M, 0.0)
		var feet := _sim.world_position(p)
		var yaw := _views.node_for(p.id).rotation.y
		var at := _cam.unproject_position(head)
		var low := _cam.unproject_position(feet)
		print(
			(
				"PROVE %s id=%d head=(%.0f,%.0f) feet=(%.0f,%.0f) yaw=%.3f want=%.3f"
				% [label, p.id, at.x, at.y, low.x, low.y, yaw, want]
			)
		)
		if _cam.is_position_behind(head) or not rect.has_point(at) or not rect.has_point(low):
			_invalid("%s: waiter %d is not inside the frame" % [label, p.id])
			return false
		if absf(angle_difference(yaw, want)) > FACE_TOLERANCE:
			_invalid("%s: waiter %d does not face the door" % [label, p.id])
			return false
	return true


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	quit(1)
