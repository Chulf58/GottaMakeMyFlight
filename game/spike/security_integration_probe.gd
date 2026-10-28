extends SceneTree
## Security 8/8 integration probe: boots main.tscn, builds the hand-built terminal
## (HandBuiltTerminal) with one security checkpoint, hires real officers, accepts
## one scheduled flight of N passengers, runs it to its result and prints made,
## missed, the longest security queue and the longest wait for the checkpoint.
##   Godot_v4.7.2-stable_win64_console.exe --path game --audio-driver Dummy \
##     -s res://spike/security_integration_probe.gd -- lane pax=30 seed=7 plates
## User args: `lane` or `basic` (the checkpoint, default lane); `pax=N`
## (default 30); `seed=N` (default random, printed); `plates` (windowed only:
## plates of the lane under tools/blender/out/security-8-8/).
## The sim clock is driven here tick by tick (its own _process is off), so a
## seed replays the same flight. The airport is opened by this probe at the
## moment the staff are on duty, with the contract of N passengers as its
## flight; AirportGate's own starter is not used.
## A guard thread prints PROBE_INVALID and crashes when the main thread stalls.

const OUT_REL := "res://../tools/blender/out/security-8-8"
const DIVIDER_Y := HandBuiltTerminal.DIVIDER_Y
const SCANNER_XS := HandBuiltTerminal.SCANNER_XS
const ARCH_CELL := Vector2i(18, 8)
const CONTRACT_ID := "GMF30"
const MARGIN_PX := 8.0
const GLASS := "res://assets/materials/tp_glass.tres"
const BUILD_TICK := 200
const TOP_UP := 20000
const OPEN_TICK := 800
const STAFF_LIMIT_TICKS := 3000
const RUN_LIMIT_TICKS := 40000
const HANG_MS := 60000

var _lane := true
var _pax := 30
var _seed := 0
var _plates := false
var _failed := false
## True while a candidate camera view is judged: a failing point then rejects
## the view instead of failing the probe.
var _probing := false
var _view_bad := false
var _main: Node
var _mode: BuildMode
var _sim: PassengerSim
var _clock: SimClock
var _flights: FlightSim
var _staff: StaffSim
var _station := 0
var _out_dir := ""
var _joined := {}
var _admitted := {}
var _cleared := {}
var _max_queue := 0
var _traits := {"bags": [0, 0, 0], "liquids": 0, "alarm": 0}
var _phases_seen := {}
var _plated := {}
var _flight_id := ""
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stop := false
var _stage := "boot"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "basic":
			_lane = false
		elif arg == "lane":
			_lane = true
		elif arg == "plates":
			_plates = DisplayServer.get_name() != "headless"
		elif arg.begins_with("pax="):
			_pax = arg.substr(4).to_int()
		elif arg.begins_with("seed="):
			_seed = arg.substr(5).to_int()
	if _seed == 0:
		_seed = randi()
	print(
		(
			"PROBE seed=%d checkpoint=%s pax=%d plates=%s"
			% [_seed, "lane" if _lane else "basic", _pax, _plates]
		)
	)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	if _plates:
		DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
	_clock.set_process(false)
	root.add_child(_main)
	_mode = _main.get_node("BuildMode") as BuildMode
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_flights = _main.get_node("FlightSim") as FlightSim
	_staff = _main.get_node("Staff") as StaffSim
	_sim.stage_changed.connect(_on_stage)
	_sim.passenger_spawned.connect(_on_spawned)
	_clock.ticked.connect(_on_tick)
	_run.call_deferred()


func _run() -> void:
	await _frames(3)
	_run_to(BUILD_TICK)
	_beat("build")
	_build()
	_flights.gate = null
	_hire()
	_beat("staff")
	var limit := _clock.tick + STAFF_LIMIT_TICKS
	while not _staffed() and _clock.tick < limit:
		_run_to(_clock.tick + 20)
	if not _staffed():
		_invalid("the staff were not on duty within %d ticks" % STAFF_LIMIT_TICKS)
	print(
		(
			"STAFF tick=%d station=%d primary=%s helper=%s checkin_on_duty=%d security_on_duty=%d"
			% [
				_clock.tick,
				_station,
				_staff.is_staffed(_station),
				_staff.is_staffed(_station, StaffMember.Slot.HELPER),
				_staff.on_duty_count(StaffMember.Role.CHECKIN),
				_staff.on_duty_count(StaffMember.Role.SECURITY),
			]
		)
	)
	if _plates and _lane:
		await _plate("lane_staffed", 0)
	# Both checkpoints open the flight on the same tick, so one seed gives
	# them the same arrivals.
	_run_to(OPEN_TICK)
	_open_flight()
	_beat("run")
	var results := {}
	limit = _clock.tick + RUN_LIMIT_TICKS
	while results.is_empty() and _clock.tick < limit:
		_run_to(_clock.tick + 10)
		if _plates and _lane:
			var moment := _plate_moment()
			if moment != "":
				await _plate(moment, _tracked_passenger(moment))
		results = _result()
		if not results.is_empty() and _accounted(results) < _pax:
			results = {}
	_report(results)
	_stop_guard()
	quit(1 if _failed else 0)


# ---------------------------------------------------------------- building


func _build() -> void:
	# The hand-built terminal spends most of the starting budget on floor, so
	# both variants get the same top-up and a whole lane can be bought.
	var wallet := (_main.get_node("Finances") as Finances).wallet
	wallet.credit(TOP_UP, Wallet.Category.OPENING)
	print("WALLET balance=%d after a top-up of %d" % [wallet.balance, TOP_UP])
	var builder := HandBuiltTerminal.new(_mode)
	builder.on_edit = func() -> void: _beat(_stage)
	builder.build()
	print(
		(
			"BUILD hand-built terminal applied=%d refused=%d"
			% [builder.applied, builder.refused.size()]
		)
	)
	for line in builder.refused:
		_invalid("hand-built terminal refused %s" % line)
	var grid := _mode.grid
	_remove_object_at(Vector2i(SCANNER_XS[0], DIVIDER_Y - 1))
	_remove_object_at(Vector2i(SCANNER_XS[1], DIVIDER_Y - 1))
	if _lane:
		_must(
			grid.apply(
				BuildEdit.remove_wall(Vector2i(ARCH_CELL.x, DIVIDER_Y), BuildGrid.Side.NORTH)
			),
			"divider gap"
		)
		var lane := SecurityLanes.geometry(ARCH_CELL, 0, SecurityLanes.RIGHT)
		_tool(BuildMode.Tool.ARCH)
		_use(ARCH_CELL)
		var tools := {
			SecurityLanes.TRAY_TABLE: BuildMode.Tool.TRAY_TABLE,
			SecurityLanes.XRAY_BELT: BuildMode.Tool.XRAY_BELT,
			SecurityLanes.PICKUP_TABLE: BuildMode.Tool.PICKUP_TABLE,
		}
		for part in tools:
			_tool(tools[part])
			_use(lane[part])
	else:
		_tool(BuildMode.Tool.SCANNER)
		_use(Vector2i(SCANNER_XS[0], DIVIDER_Y - 1))
		for x in [SCANNER_XS[1]]:
			_must(
				grid.apply(BuildEdit.place_wall(Vector2i(x, DIVIDER_Y), BuildGrid.Side.NORTH)),
				"wall over the removed scanner"
			)
	_mode.set_tool(BuildMode.Tool.NONE)
	_run_to(_clock.tick + 2)
	var scanners: Array[int] = _sim.layout.scanners
	print(
		(
			"LAYOUT scanners=%s desks=%d entrances=%d exits=%d"
			% [
				scanners,
				_sim.layout.desks.size(),
				_sim.layout.entrances.size(),
				_sim.layout.open_exits(grid).size()
			]
		)
	)
	if scanners.size() != 1:
		_invalid("expected exactly one security station, found %d" % scanners.size())
		return
	_station = scanners[0]
	if _lane:
		var lanes := _sim.layout.security_lanes
		print("LANE arch=%d status=%s" % [_station, lanes.status_text(_station)])
		if not lanes.is_complete(_station):
			_invalid("the lane is not whole: %s" % lanes.status_text(_station))


func _remove_object_at(cell: Vector2i) -> void:
	var id := _mode.grid.object_at(cell)
	if id == 0:
		_invalid("no scanner at %s to remove" % cell)
		return
	_must(_mode.grid.apply(BuildEdit.remove_object(id)), "remove scanner at %s" % cell)


func _tool(tool: BuildMode.Tool) -> void:
	_mode.set_tool(tool)
	while _mode.facing != 0:
		_mode.rotate_facing()


func _use(cell: Vector2i) -> void:
	var result := _mode.apply_at(_mode.grid.cell_to_world(cell))
	if result == null or not result.ok:
		_invalid(
			(
				"tool %s at %s: %s"
				% [_mode.tool, cell, "no edit" if result == null else result.reason_text()]
			)
		)


func _must(result: BuildResult, what: String) -> void:
	if not result.ok:
		_invalid("%s refused: %s" % [what, result.reason_text()])


func _hire() -> void:
	for i in _sim.layout.desks.size():
		_staff.hire(StaffMember.Role.CHECKIN)
	for i in 2 if _lane else 1:
		_staff.hire(StaffMember.Role.SECURITY)
	print(
		(
			"HIRED checkin=%d security=%d"
			% [_staff.count(StaffMember.Role.CHECKIN), _staff.count(StaffMember.Role.SECURITY)]
		)
	)


func _staffed() -> bool:
	if _station == 0 or _staff.on_duty_count(StaffMember.Role.CHECKIN) < _sim.layout.desks.size():
		return false
	if not _staff.is_staffed(_station):
		return false
	return not _lane or _staff.is_staffed(_station, StaffMember.Slot.HELPER)


## Accepts the N-passenger contract and opens the airport at once, so the flight
## departs ISSUE_LEAD_TICKS plus the pre-departure states from now.
func _open_flight() -> void:
	var terms := FlightSim.starter_terms(_flights.tick)
	terms["id"] = CONTRACT_ID
	terms["booked_passengers"] = _pax
	var problem := _flights.accept_problem(terms)
	if problem != "":
		_invalid("the contract is refused: %s" % problem)
		return
	_flights.accept_contract(terms)
	if not _flights.open_airport():
		_invalid("the airport did not open")
	print(
		(
			"FLIGHT accepted %s pax=%d departure_minute=%d opened_tick=%d"
			% [CONTRACT_ID, _pax, terms["departure_minute"], _flights.opened_tick]
		)
	)


## Passengers of the flight with an outcome: made, missed, or never arrived.
func _accounted(results: Dictionary) -> int:
	var no_shows: Dictionary = _sim.no_shows.get(_flight_id, {})
	return (
		int(results.get("made", 0))
		+ int(results.get("missed", 0))
		+ int(no_shows.get("no_entrance", 0))
		+ int(no_shows.get("late", 0))
	)


func _result() -> Dictionary:
	for key in _sim.flight_results:
		if str(key).begins_with(CONTRACT_ID):
			_flight_id = str(key)
			return _sim.flight_results[key]
	return {}


# ---------------------------------------------------------------- observing


func _on_spawned(id: int) -> void:
	var p := _sim.get_passenger(id)
	if not p.flight_id.begins_with(CONTRACT_ID):
		return
	_traits["bags"][p.carry_on] += 1
	_traits["liquids"] += int(p.liquids)
	_traits["alarm"] += int(p.alarm)


func _on_stage(id: int, stage: Passenger.Stage) -> void:
	var tick := _sim.tick
	if stage == Passenger.Stage.SECURITY_QUEUE and not _joined.has(id):
		_joined[id] = tick
	elif stage == Passenger.Stage.SECURITY and not _admitted.has(id):
		_admitted[id] = tick
	elif stage == Passenger.Stage.TO_GATE and not _cleared.has(id):
		_cleared[id] = tick


func _on_tick(_tick: int) -> void:
	if _station == 0:
		return
	_max_queue = maxi(_max_queue, _sim.queue_of(_station).size() + _sim.holding_of(_station).size())
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.stage == Passenger.Stage.SECURITY:
			_phases_seen[p.security_phase] = int(_phases_seen.get(p.security_phase, 0)) + 1


func _report(results: Dictionary) -> void:
	var waits: Array[int] = []
	var queue_waits: Array[int] = []
	for id in _cleared:
		if _joined.has(id):
			waits.append(_cleared[id] - _joined[id])
		if _joined.has(id) and _admitted.has(id):
			queue_waits.append(_admitted[id] - _joined[id])
	var max_wait: int = 0 if waits.is_empty() else waits.max()
	var max_queue_wait: int = 0 if queue_waits.is_empty() else queue_waits.max()
	var made: int = results.get("made", 0)
	var missed: int = results.get("missed", 0)
	var no_shows: Dictionary = _sim.no_shows.get(_flight_id, {})
	var names := {}
	for phase in _phases_seen:
		names[SecurityRuntime.Phase.keys()[phase]] = _phases_seen[phase]
	print(
		(
			"TRAITS bags_0_1_2=%s liquids=%d alarm=%d"
			% [_traits["bags"], _traits["liquids"], _traits["alarm"]]
		)
	)
	print("PHASE_TICKS_SEEN %s" % [names])
	print(
		(
			"RESULT seed=%d checkpoint=%s flight=%s booked=%d made=%d missed=%d no_shows=%s"
			% [_seed, "lane" if _lane else "basic", _flight_id, _pax, made, missed, no_shows]
		)
	)
	print(
		(
			(
				"RESULT max_queue=%d max_wait_ticks=%d (%.1f s) "
				+ "max_queue_wait_ticks=%d (%.1f s) cleared=%d tick=%d"
			)
			% [
				_max_queue,
				max_wait,
				max_wait / 20.0,
				max_queue_wait,
				max_queue_wait / 20.0,
				_cleared.size(),
				_clock.tick
			]
		)
	)
	if results.is_empty():
		_invalid("the flight had no result within %d ticks" % RUN_LIMIT_TICKS)
	if made + missed + int(no_shows.get("no_entrance", 0)) + int(no_shows.get("late", 0)) != _pax:
		_invalid("made + missed + no-shows is not the booked %d" % _pax)
	if (
		_lane
		and not (
			_phases_seen.has(SecurityRuntime.Phase.UNPACK)
			and _phases_seen.has(SecurityRuntime.Phase.ARCH)
		)
	):
		_invalid("no passenger was seen unpacking and in the arch")
	print("PROBE result: ", "FAIL" if _failed else "pass")


# ------------------------------------------------------------------- plates


## The name of a plate due now, or "". Each moment is plated once.
func _plate_moment() -> String:
	var record := _sim.security.record_of(_station)
	if record.is_empty():
		return ""
	if (
		not _plated.has("lane_working")
		and int(record["main"]) != 0
		and _sim.queue_of(_station).size() >= 1
	):
		return "lane_working"
	if not _plated.has("lane_repack") and int(record["berth"]) != 0:
		var p := _sim.get_passenger(int(record["berth"]))
		if p.security_phase == SecurityRuntime.Phase.REPACK:
			return "lane_repack"
	return ""


func _tracked_passenger(moment: String) -> int:
	var record := _sim.security.record_of(_station)
	return int(record["berth"]) if moment == "lane_repack" else int(record["main"])


func _plate(name: String, passenger_id: int) -> void:
	_plated[name] = true
	_beat("plate_" + name)
	var grid := _mode.grid
	var lane := _sim.layout.security_lanes.lane(_station)
	var points := {
		"arch": grid.cell_to_world(lane["arch"]) + Vector3(0, 1.0, 0),
		"primary_officer": grid.cell_to_world(lane["primary_spot"]) + Vector3(0, 1.4, 0),
		"helper_officer": grid.cell_to_world(lane["helper_spot"]) + Vector3(0, 1.4, 0),
		"berth": grid.cell_to_world(lane["berth"]) + Vector3(0, 1.0, 0),
		"queue_entry": grid.cell_to_world(lane["queue_entry"]) + Vector3(0, 1.0, 0),
	}
	if passenger_id != 0:
		var p := _sim.get_passenger(passenger_id)
		var phase: String = SecurityRuntime.Phase.keys()[p.security_phase]
		var key := "passenger_%d_phase_%s" % [passenger_id, phase]
		points[key] = grid.cell_to_world(p.at) + Vector3(0, 1.0, 0)
	var rig: Node3D = _main.get_node("TycoonCamera")
	var cam: Camera3D = rig.get_node("Camera3D")
	cam.make_current()
	rig.position = grid.cell_to_world(lane["arch"]) + Vector3(-0.5, 0, 0)
	rig.distance = 12.0
	var view: BuildView = _mode.get_node("BuildView")
	# The first of four views that shows every point is the plate's.
	var ok := false
	for yaw in [0.7, 0.7 + PI / 2.0, 0.7 + PI, 0.7 - PI / 2.0]:
		rig.yaw = yaw
		rig.zoom(1.0)
		await _settle(cam)
		var holder := _view_colliders(view)
		await physics_frame
		await physics_frame
		print(
			(
				"PLATE %s seed=%d tick=%d yaw=%.2f camera=%s"
				% [name, _seed, _clock.tick, yaw, cam.global_position]
			)
		)
		_probing = true
		_view_bad = false
		ok = true
		for key in points:
			ok = _prove_in_frame(cam, "%s/%s" % [name, key], points[key]) and ok
			ok = _prove_unoccluded(cam, "%s/%s" % [name, key], points[key]) and ok
		holder.free()
		ok = ok and not _view_bad
		_probing = false
		if ok:
			break
	if not ok:
		_invalid("%s: none of the four views shows every point unoccluded" % name)
	else:
		var proven := cam.global_position
		var img := await _grab()
		var moved := cam.global_position.distance_to(proven)
		print("PLATE %s camera moved %.4f m between the proof and the grab" % [name, moved])
		if moved > 0.001:
			_invalid("%s: the camera moved after the in-frame proof" % name)
		_save_marked(img, cam, points, name)
		var path := _out_dir.path_join("%s_%s_seed%d.png" % [name, "lane", _seed])
		if img.save_png(path) != OK:
			_invalid("could not save %s" % path)
		else:
			print("PLATE saved %s size=%s" % [path, img.get_size()])


func _prove_in_frame(cam: Camera3D, label: String, point: Vector3) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	if cam.is_position_behind(point):
		_invalid("%s: behind the camera" % label)
		return false
	var s := cam.unproject_position(point)
	var ok := rect.has_point(s)
	print("INFRAME %s screen=(%.0f,%.0f) ok=%s" % [label, s.x, s.y, ok])
	if not ok:
		_invalid("%s: projects outside the viewport" % label)
	return ok


## A ray from the camera to the point must meet no collider first. The
## colliders are the view's floors, walls and objects.
func _prove_unoccluded(cam: Camera3D, label: String, point: Vector3) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, point)
	var hit := space.intersect_ray(query)
	var gap: float = 0.0 if hit.is_empty() else hit["position"].distance_to(point)
	var ok: bool = hit.is_empty() or gap < 0.35
	print("VISIBLE %s first_hit_gap_m=%.2f ok=%s" % [label, gap, ok])
	if not ok:
		_invalid("%s: occluded by %s" % [label, hit["collider"]])
	return ok


func _view_colliders(view: BuildView) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ProbeColliders"
	_main.add_child(holder)
	for child in view.get_children():
		if child is MultiMeshInstance3D:
			var multimesh := (child as MultiMeshInstance3D).multimesh
			var local_faces := _opaque_faces(multimesh.mesh)
			if local_faces.is_empty():
				continue
			for i in multimesh.instance_count:
				var at: Transform3D = (
					(child as Node3D).global_transform * multimesh.get_instance_transform(i)
				)
				var faces := PackedVector3Array()
				for p in local_faces:
					faces.append(at * p)
				holder.add_child(_body(faces))
	for child in view.get_children():
		if child.has_meta("record"):
			for mi in child.find_children("*", "MeshInstance3D", true, false):
				var faces := _opaque_faces((mi as MeshInstance3D).mesh)
				if faces.is_empty():
					continue
				var at: Transform3D = (mi as Node3D).global_transform
				var world := PackedVector3Array()
				for p in faces:
					world.append(at * p)
				holder.add_child(_body(world))
	return holder


func _body(faces: PackedVector3Array) -> StaticBody3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var body := StaticBody3D.new()
	body.add_child(shape_node)
	return body


func _opaque_faces(mesh: Mesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat != null and mat.resource_path == GLASS:
			continue
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			faces.append_array(verts)
		else:
			for k in index:
				faces.append(verts[k])
	return faces


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


## A copy of the plate with a square on each proven point, so the plate shows
## what the in-frame proof measured. The legend is printed in order.
func _save_marked(img: Image, cam: Camera3D, points: Dictionary, name: String) -> void:
	var marked := img.duplicate() as Image
	var scale := Vector2(marked.get_size()) / root.get_visible_rect().size
	var colors := [Color.RED, Color.YELLOW, Color.CYAN, Color.MAGENTA, Color.GREEN, Color.ORANGE]
	var index := 0
	print(
		(
			"MARKED viewport=%s image=%s scale=%s"
			% [root.get_visible_rect().size, marked.get_size(), scale]
		)
	)
	for key in points:
		var s := cam.unproject_position(points[key]) * scale
		var color: Color = colors[index % colors.size()]
		for dx in range(-7, 8):
			for dy in range(-7, 8):
				if maxi(absi(dx), absi(dy)) >= 5:
					marked.set_pixelv(Vector2i(s) + Vector2i(dx, dy), color)
		print("MARKED %s %s at (%.0f,%.0f)" % [color.to_html(false), key, s.x, s.y])
		index += 1
	marked.save_png(_out_dir.path_join("%s_lane_seed%d_marked.png" % [name, _seed]))


## Frames until the camera's position holds still for five frames in a row (the
## rig eases toward its target).
func _settle(cam: Camera3D) -> void:
	var still := 0
	var last := cam.global_position
	for i in 240:
		await process_frame
		still = still + 1 if cam.global_position.distance_to(last) < 0.0005 else 0
		last = cam.global_position
		if still >= 5:
			break
	if still < 5:
		_invalid("the camera never settled")
	await _frames(2)


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


# ------------------------------------------------------------ run and guard


func _run_to(target: int) -> void:
	while _clock.tick < target:
		_clock.advance(SimClock.STEP)
		if _clock.tick % 50 == 0:
			_beat(_stage)


func _invalid(msg: String) -> void:
	if _probing:
		print("VIEW_REJECTED ", msg)
		_view_bad = true
		return
	print("PROBE_INVALID ", msg)
	_failed = true


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _stop_guard() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("security_integration_probe: main thread stalled in %s" % stage)
