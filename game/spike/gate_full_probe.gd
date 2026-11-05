extends SceneTree
## Windowed probe of a full gate (board 4b9d1a4e, decision gate-full-design-
## passengers-reserve-a-gate-seat-or-standing; spacing ruling gate-standing-
## spacing-standing-passengers-keep-wider-apart-o). It boots main.tscn, builds
## the reference terminal with its gate desk and no gate seats, opens the
## airport, leaves only the FREE_SPOTS standing spots nearest the scanner exit
## free (the rest are claimed by ids no passenger has), and sends SENT
## passengers of the first flight to security, each with its one bag when that
## is a roller and none otherwise. One tick a frame.
##
## Measured each tick (node transforms, valid headless too):
##   SPACING: the least body-to-roller distance between two passengers
##     standing still on spots for STOOD_TICKS (QueueSpacing.pair()), and the
##     least spot gap where either holder has a roller (it must be at least
##     StandingSpots.ROLLER_CLEAR_MM). Control: roller pairs measured > 0.
##   HELD: GateCapacity.shortage() passengers and the cells they stand on;
##     distinct cells must equal the count. Control: a front stuck GATE_FULL
##     was seen, else PROBE_INVALID.
## Plates (tools/blender/out/gate-full/): gate_area (the stander nearest the
## standers' middle as subject) and security_front (the GATE_FULL front). Each
## proves its subject in frame (unproject with a margin) and in sight
## (PlateSight.person_shown(), sight lines against the drawn meshes) before
## the save; otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/gate_full_probe.gd [-- --seed=N]

const StarterFlight := preload("res://spike/starter_flight.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const QueueSpacing := preload("res://spike/queue_spacing.gd")
const OUT_REL := "res://../tools/blender/out/gate-full"
const FREE_SPOTS := 24
const SENT := 22
const SEND_GAP := 10
## Ticks a stander stands still before its pair is measured (its roller is
## stood up by then, RollerPark).
const STOOD_TICKS := 15
## Ticks the front is held GATE_FULL before the plates.
const HOLD_TICKS := 120
const LIMIT_TICKS := 2500
const MARGIN_PX := 12.0
const MIN_BODY_PX := 60.0
const TAG := "subject"

var _seed := 0
var _out_dir := ""
var _failed := false
var _plates := 0
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _cam: Camera3D
var _least_roller := INF
var _least_roller_at := ""
var _roller_frames := 0
var _least_gap := INF
var _held_max := 0
var _held_cells_bad := 0


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
	print("PROBE sim_seed=%d out_dir=%s" % [_seed, _out_dir])
	_run.call_deferred()


func _run() -> void:
	if await _boot():
		var front := await _fill_and_hold()
		if front != null:
			await _plate_gate_area()
			await _plate_front(front)
	print(
		(
			(
				"SPACING least body to roller %.3f m (%s) over %d roller pair frames; "
				% [_least_roller, _least_roller_at, _roller_frames]
			)
			+ (
				"least spot gap beside a roller %.0f mm (clear %d)"
				% [_least_gap, StandingSpots.ROLLER_CLEAR_MM]
			)
		)
	)
	print(
		"HELD most %d, ticks with held passengers sharing a cell %d" % [_held_max, _held_cells_bad]
	)
	if _roller_frames == 0:
		_invalid("no standing roller pair was measured")
	if _held_cells_bad > 0 or _least_gap < StandingSpots.ROLLER_CLEAR_MM:
		_failed = true
	print(
		(
			"RESULT made=%d missed=%d plates=%d failed=%s"
			% [_sim.made_count(), _sim.missed_count(), _plates, _failed]
		)
	)
	quit(1 if _failed or _plates < 2 else 0)


func _boot() -> bool:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(3)
	_mode = _main.get_node("BuildMode") as BuildMode
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.NONE)
	(_mode.get_node("Ghost") as Node3D).visible = false
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_views = _main.get_node("PassengerViews") as PassengerViews
	if not ReferenceTerminal.build(_mode.grid) or not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the reference terminal or its gate desk was refused")
		return false
	for id: int in ReferenceTerminal.object_ids(_mode.grid)["seats"]:
		_mode.grid.apply(BuildEdit.remove_object(id))
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	if hired == 0 or doors < 0:
		_invalid("the airport did not open")
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	# The spots left free: the FREE_SPOTS nearest the first scanner's exit.
	_sim.standing.rebuild(_sim)
	var exit := _sim.security.exit_cell(_sim.layout.scanners[0])
	var keep := {}
	for spot in _sim.standing.free_nearest(exit).slice(0, FREE_SPOTS):
		keep[spot] = true
	var fake := 900000
	for spot: int in _sim.standing.spots:
		if not keep.has(spot):
			_sim.standing.claim(fake, spot)
			fake += 1
	print(
		(
			"PROBE opened tick=%d doors=%d spots=%d free=%d hired=%d"
			% [_clock.tick, doors, _sim.standing.spots.size(), keep.size(), hired]
		)
	)
	return true


## Sends SENT passengers to security and plays until a front has been held
## GATE_FULL for HOLD_TICKS; returns it, or null.
func _fill_and_hold() -> Passenger:
	var entrance := _sim.layout.door_cell(_mode.grid, _sim.layout.entrances[0])
	var sent := 0
	var held_since := -1
	var front: Passenger = null
	var stop := _clock.tick + LIMIT_TICKS
	while _clock.tick < stop:
		if sent < SENT and _clock.tick % SEND_GAP == 0:
			_send(entrance)
			sent += 1
		await _step()
		_measure()
		var now := _held_front()
		if now == null:
			held_since = -1
		elif front != now or held_since < 0:
			front = now
			held_since = _clock.tick
		elif _clock.tick - held_since >= HOLD_TICKS:
			var boarding := front.boarding_tick
			print(
				(
					"HOLD front %d at %s stuck GATE_FULL since %d, now %d, boarding %d, standing %d"
					% [front.id, front.at, held_since, _clock.tick, boarding, _standers().size()]
				)
			)
			return front
	_invalid("no front was held GATE_FULL for %d ticks" % HOLD_TICKS)
	return null


## One calm passenger of the first flight at the entrance, on its way to
## security; its one bag is kept when it is a roller, else it carries none.
func _send(entrance: Vector2i) -> void:
	var p := _sim.get_passenger(_sim.spawn_now(StarterFlight.first_flight()))
	ToiletTestLayout.calm(p)
	p.carry_on = 1 if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER else 0
	p.liquids = false
	p.alarm = false
	p.shop_cooldown = 1000000
	p.boredom = 0
	p.apron = []
	p.apron_mm = 0
	p.stage = Passenger.Stage.TO_SECURITY
	p.at = entrance
	p.clear_path()


func _held_front() -> Passenger:
	for station in _sim.layout.scanners:
		var lane := _sim.queue_of(station)
		if not lane.is_empty():
			var p := _sim.get_passenger(lane[0])
			if p.stuck == Passenger.Stuck.GATE_FULL:
				return p
	return null


func _standers() -> Array[Passenger]:
	var out: Array[Passenger] = []
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.stage == Passenger.Stage.STANDING:
			out.append(p)
	return out


func _measure() -> void:
	var still := _standers().filter(
		func(p: Passenger) -> bool: return _clock.tick - p.stage_tick >= STOOD_TICKS
	)
	var spots := _sim.standing
	for a in still.size():
		for b in range(a + 1, still.size()):
			var pa: Passenger = still[a]
			var pb: Passenger = still[b]
			if not (ParkRecovery.has_roller(pa) or ParkRecovery.has_roller(pb)):
				continue
			var d: Vector2i = (
				spots.spots[spots.spot_of(pa.id)]["mm"] - spots.spots[spots.spot_of(pb.id)]["mm"]
			)
			_least_gap = minf(_least_gap, Vector2(d).length())
			var pair := QueueSpacing.pair(_views, _sim, pa.id, pb.id)
			if pair.is_empty() or pair["roller"] == INF:
				continue
			_roller_frames += 1
			if pair["roller"] < _least_roller:
				_least_roller = pair["roller"]
				_least_roller_at = "t%d %d-%d" % [_clock.tick, pa.id, pb.id]
	var held := _sim.gates.shortage(_sim)
	var cells := {}
	for id in held:
		cells[_sim.get_passenger(id).at] = true
	_held_max = maxi(_held_max, held.size())
	if cells.size() != held.size():
		_held_cells_bad += 1


func _plate_gate_area() -> void:
	var standers := _standers()
	if standers.is_empty():
		_invalid("GATE nobody stands")
		return
	var middle := Vector3.ZERO
	for p in standers:
		middle += _sim.world_position(p)
	middle /= standers.size()
	# Nearest the middle first; each tried from far and low, then from high
	# above the crowd, until one is in sight.
	standers.sort_custom(
		func(x: Passenger, y: Passenger) -> bool:
			return (
				_sim.world_position(x).distance_to(middle)
				< _sim.world_position(y).distance_to(middle)
			)
	)
	print("GATE standers %d, middle %s" % [standers.size(), middle])
	for subject in standers.slice(0, 3):
		for reach in [[10.0, 7.0], [4.0, 10.0]]:
			if await _plate("gate_area", subject, middle, reach):
				return
	_invalid("gate_area: no view showed any of the three middle standers")


func _plate_front(front: Passenger) -> void:
	if not await _plate("security_front", front, _sim.world_position(front), [5.0, 3.5]):
		_invalid("security_front: no view showed front %d" % front.id)


## Tries eight directions round `target` at `reach` = [distance, height] and
## saves the first view where `subject` is in frame and in sight; returns
## whether one was saved.
func _plate(shot: String, subject: Passenger, target: Vector3, reach: Array) -> bool:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		_main.add_child(_cam)
	var body := _views.node_for(subject.id)
	if body == null:
		print("%s: subject %d is not drawn" % [shot, subject.id])
		return false
	var owners: Array[Node] = [_views, _mode.get_node("BuildView")]
	var holder := PlateSight.colliders(root, owners, {body: TAG})
	await physics_frame
	await physics_frame
	var box: AABB = (holder.get_meta("bounds") as Dictionary).get(TAG, AABB())
	var size := root.get_visible_rect().size
	var frame := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	for k in 8:
		var away := Vector3(sin(k * PI / 4.0 + PI), 0.0, cos(k * PI / 4.0 + PI))
		var from: Vector3 = target + away * float(reach[0]) + Vector3.UP * float(reach[1])
		_cam.look_at_from_position(from, target + Vector3.UP * 0.8, Vector3.UP)
		_cam.current = true
		await _frames(2)
		var img := root.get_texture().get_image()
		var feet := _cam.unproject_position(body.global_position)
		var head := _cam.unproject_position(body.global_position + Vector3.UP * 1.7)
		var shown := PlateSight.person_shown(_cam, box, TAG, frame, img, img, MIN_BODY_PX)
		print(
			(
				"INFRAME %s view %d subject %d feet=%s head=%s inside=%s on=%d blockers=%s height_px=%.0f"
				% [
					shot,
					k,
					subject.id,
					feet.round(),
					head.round(),
					frame.has_point(feet) and frame.has_point(head),
					shown["on"],
					shown["blockers"],
					shown.get("height_px", 0.0)
				]
			)
		)
		if shown["ok"] and frame.has_point(feet) and frame.has_point(head):
			_save(img, shot + ".png")
			_plates += 1
			holder.free()
			return true
	holder.free()
	return false


func _step() -> void:
	_clock.advance(SimClock.STEP)
	await _frames(1)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
