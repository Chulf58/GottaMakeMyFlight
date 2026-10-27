extends SceneTree
## Windowed plate and benchmark probe for slice g (passengers). Boots the real main scene
## with a new random sim seed (printed), builds ReferenceTerminal through the HUD's
## starter-terminal button and runs the default flight GMF101 at 3x. Each plate is taken
## the first time its moment happens, with the camera on the subjects' centroid (from
## the plate's yaw, then the other three quarter turns until enough are shown):
##   01 passengers queuing at a desk or scanner
##   01b a passenger seated in the middle chair of a gate seat row, close, from the
##       front (01b_seated_close) and from three-quarters (01b_seated_side), once its
##       sit pose is on (the first sitter when no middle chair fills soon)
##   02 a late passenger running, with its thought bubble, followed from the HUD
##   03 passengers on the apron walking to the parked plane's door
##   04 the 300-passenger debug batch (a fresh scene), after a benchmark at 3x
## The HUD is on every plate; the build tool is cleared after each boot, so no build
## ghost follows the mouse into a plate.
##
## A passenger counts as shown when its drawn body is at least MIN_SUBJECT_PX tall, nine
## sight lines to its upper body (against every visible mesh of the shell, the build, the
## plane and the other passengers, skinned ones in the pose drawn) land on its own meshes
## at least once with no blocker, every landing point is in the frame with a margin, and the
## HUD covers none of them (the plate against a twin rendered with the HUD's canvas layers
## hidden). A plate with too few shown passengers prints PROBE_INVALID and the probe
## exits 1. A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide); --ui-scale overrides the content scale from
## project.godot, and the plate names carry the scale:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <repo>/game -s res://spike/passenger_plates_probe.gd -- --ui-scale=1.0
##
## Plates go to tools/blender/out/passengers/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/passengers"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const WAIT_LIMIT_MS := 120000
const STALL_LIMIT_MS := 5000
const BENCH_TICKS := 900
## GMF101's doors close at tick 1900 (FlightSim.PHASE_TICKS from tick 0).
const DOORS_TICK := 1900
## How long 01b waits for a middle-chair sitter after the first sitter.
const MIDDLE_WAIT_TICKS := 120
## Scene nodes whose visible meshes can hide a passenger.
const OCCLUDER_OWNERS: Array[String] = [
	"Airside/Terminal", "BuildMode", "PlaneView", "PassengerViews"
]
## A passenger drawn shorter than this (layout pixels) is too small to inspect.
const MIN_SUBJECT_PX := 16.0
## The benchmark plate checks at most this many of its in-frame passengers.
const BENCH_CHECKED := 320
## The debug batch stands in crowds (many spawn on the same cells), so few of
## its passengers are clear of every other one; this many must be.
const BENCH_SHOWN := 5

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
	var build := _main.get_node("BuildMode") as BuildMode
	build.set_tool(BuildMode.Tool.NONE)
	await _frames(2)
	var ghost := build.get_node("Ghost") as Node3D
	print("PROBE build_tool=%d ghost_visible=%s" % [build.tool, ghost.visible])
	if build.tool != BuildMode.Tool.NONE or ghost.visible:
		_invalid("the build tool or its ghost is still on after clearing it")
	print(
		"PROBE terminal objects=",
		_sim.grid.object_ids().size(),
		" seats=",
		_sim.layout.seats.size()
	)
	# An unstaffed desk or scanner is closed (StaffSim.is_open), so hire one
	# member per station; they walk to their stations like hired staff in play.
	var staff := _main.get_node("Staff") as StaffSim
	for desk in _sim.layout.desks:
		staff.hire(StaffMember.Role.CHECKIN)
	for scanner in _sim.layout.scanners:
		staff.hire(StaffMember.Role.SECURITY)
	print(
		(
			"PROBE staff hired checkin=%d security=%d"
			% [staff.count(StaffMember.Role.CHECKIN), staff.count(StaffMember.Role.SECURITY)]
		)
	)
	if staff.member_ids().is_empty():
		_invalid("no staff hired, so every station stays closed")
	_hud.press_speed(3)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


## Steps frames until `done` holds. Fails through _invalid() when the sim
## reaches `limit_tick` first, when the wait passes WAIT_LIMIT_MS, or when the
## clock has not advanced for STALL_LIMIT_MS.
func _until(stage: String, limit_tick: int, done: Callable) -> bool:
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
			_invalid("%s: clock stalled at tick %d" % [stage, last_tick])
			return false
		await process_frame
	return true


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance


func _run() -> void:
	await _boot()
	await _plate_queues()
	await _plate_seated()
	await _plate_late()
	await _plate_boarding()
	_main.queue_free()
	await _frames(5)
	await _benchmark()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	if not _saved.is_empty():
		_save(_sheet(), "contact_sheet")
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _plate_queues() -> void:
	if not await _until("queues", DOORS_TICK, func() -> bool: return _count(_queued) >= 2):
		return
	_hud.press_speed(0)
	await _plate("01_queues", _ids(_queued), 26.0, 0.0, 2)
	_hud.press_speed(3)


func _plate_seated() -> void:
	# A middle-chair sitter is preferred (the chair the old drawing missed); if
	# none sits within MIDDLE_WAIT_TICKS of the first sitter, the plate takes the
	# first one seated, and the SITTER line names its cell index.
	var first_seen := [-1]
	var ready := func() -> bool:
		if _count(_seated_middle) >= 1:
			return true
		if _count(_seated_posed) == 0:
			return false
		if first_seen[0] < 0:
			first_seen[0] = _clock.tick
		return _clock.tick - first_seen[0] >= MIDDLE_WAIT_TICKS
	if not await _until("seated", DOORS_TICK, ready):
		return
	_hud.press_speed(0)
	var middle := _ids(_seated_middle)
	var only: Array[int] = [middle[0] if not middle.is_empty() else _ids(_seated_posed)[0]]
	await _frames(5)
	_check_sitter(only[0])
	# Both views at their own yaw only: the front view is the one that read as standing.
	await _plate("01b_seated_close", only, 7.0, 0.0, 1, 1)
	await _plate("01b_seated_side", only, 7.0, PI * 0.3, 1, 1)
	_hud.press_speed(3)


## Where the sitter's evaluated pose puts its hips against its chair: sideways
## and forward in the seat row's frame from the chair's point on the row's
## centre line (x from the cell centre plus PassengerSim.GATE_CHAIR_OFFSET_M),
## and their height. The pan spans forward -0.18 to 0.32 m with its top at
## 0.53 m, and a standing pose has its hips near 1.1 m, so hips that are not
## low, over the pan and within a pan's half width fail the probe.
func _check_sitter(id: int) -> void:
	var p := _sim.get_passenger(id)
	var record := _sim.grid.get_object(p.seat_object)
	var cells := BuildCatalog.get_def(record["def"]).footprint(record["anchor"], record["facing"])
	var index := cells.find(p.seat_cell)
	var frame := BuildView.object_transform(_sim.grid, cells, record["facing"])
	var pan := frame * Vector3((index - 1) + PassengerSim.GATE_CHAIR_OFFSET_M[index], 0.0, 0.0)
	var node := _views.node_for(id)
	var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hips := (
		(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hips")))
		. origin
	)
	print(
		(
			(
				"SITTER id=%d stage=%d clip=%s cell=%s index=%d node=%s hips=%s"
				+ " hips_sideways=%.3f hips_forward=%.3f hips_up=%.3f"
			)
			% [
				id,
				p.stage,
				node.get_meta(&"clip"),
				p.seat_cell,
				index,
				node.global_position,
				hips,
				(hips - pan).dot(frame.basis.x),
				(hips - pan).dot(frame.basis.z),
				hips.y - _sim.grid.origin.y
			]
		)
	)
	var sideways := absf((hips - pan).dot(frame.basis.x))
	var forward := (hips - pan).dot(frame.basis.z)
	var up := hips.y - _sim.grid.origin.y
	if sideways > 0.2 or forward < -0.18 or forward > 0.32 or up < 0.55 or up > 0.9:
		_invalid("01b: sitter %d's hips are not on its chair" % id)


func _plate_late() -> void:
	var late := [0]
	var entrance := _sim.grid.cell_to_world(ReferenceTerminal.ENTRANCE_CELL)
	var running := func(p: Passenger) -> bool:
		var away := _sim.world_position(p).distance_to(entrance) > 3.0
		return p.late and p.stage < Passenger.Stage.TO_EXIT and p.is_moving() and away
	var found: bool = await _until(
		"late",
		DOORS_TICK,
		func() -> bool:
			late[0] = _first(running)
			return late[0] != 0
	)
	if not found:
		return
	_hud.press_speed(0)
	var p := _sim.get_passenger(late[0])
	_views.selected_id = p.id
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
	if node.get_meta(&"clip") != "run":
		_invalid("plate 2 runner %d is not playing the run clip" % p.id)
	else:
		var only: Array[int] = [p.id]
		await _plate("02_late_runner", only, 14.0, 0.0, 1)
	_views.selected_id = 0
	_hud.press_speed(3)


func _plate_boarding() -> void:
	var near_plane := func(p: Passenger) -> bool:
		return p.stage == Passenger.Stage.APRON and _sim.world_position(p).z < -100.5
	var ok: bool = await _until(
		"boarding", DOORS_TICK, func() -> bool: return _count(near_plane) >= 2
	)
	if ok:
		_hud.press_speed(0)
		await _plate("03_boarding_at_stand", _ids(near_plane), 24.0, PI * 0.8, 1)
		_hud.press_speed(3)
	await _until("doors", DOORS_TICK + 10, func() -> bool: return _clock.tick >= DOORS_TICK + 1)
	print("OUTCOME made=%d missed=%d" % [_sim.made_count(), _sim.missed_count()])


## Aims at the centroid of `ids` from `yaw`, then from the next quarter turns
## (`turns` views in all, so 1 keeps the given yaw only), and saves the first
## plate where at least `need` of them are shown. When no view shows enough,
## the last view is saved with an _INVALID suffix (left out of the contact
## sheet) for diagnosis.
func _plate(
	name: String, ids: Array[int], distance: float, yaw: float, need: int, turns := 4
) -> void:
	_beat(name)
	var centre := Vector3.ZERO
	for id in ids:
		centre += _views.node_for(id).position
	centre /= ids.size()
	var result := {}
	for turn in turns:
		var view_yaw := wrapf(yaw + turn * PI / 2.0, -PI, PI)
		_aim(centre, distance, view_yaw)
		await _frames(20)
		print(
			(
				"PLATE %s%s tick=%d candidates=%d centroid=%s distance=%.0f yaw=%.2f"
				% [name, _scale_tag, _clock.tick, ids.size(), centre, distance, view_yaw]
			)
		)
		result = await _shown(ids)
		print("SHOWN %s%s shown=%d need=%d" % [name, _scale_tag, result["shown"], need])
		if result["shown"] >= need:
			_save(result["image"], name)
			return
	_invalid("%s: fewer than %d of %d passengers shown from any side" % [name, need, ids.size()])
	_save(result["image"], name + "_INVALID", false)


## Freezes the scene, grabs the plate and checks each of `ids` (see the file
## comment). Returns {shown: int, image: Image}.
func _shown(ids: Array[int]) -> Dictionary:
	paused = true
	var img: Image = await PlateSight.grab(self)
	var subjects := {}
	for id in ids:
		subjects[_views.node_for(id)] = str(id)
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	var holder := PlateSight.colliders(root, owners, subjects)
	var unbaked: Array = holder.get_meta("unbaked")
	var bounds: Dictionary = holder.get_meta("bounds")
	print("PROBE occluder bodies=%d unbaked=%d" % [holder.get_child_count(), unbaked.size()])
	await physics_frame
	await physics_frame
	var twin: Dictionary = await PlateSight.hud_twin(self, _main)
	var bare: Image = twin["image"]
	var changed := PlateSight.differing(img, bare, Rect2i(Vector2i.ZERO, img.get_size()), 4)
	print("HUD layers_hidden=%d plate_px_changed=%d" % [twin["layers"], changed])
	var shown := 0
	for id in ids:
		var box: AABB = bounds.get(str(id), AABB())
		var seen := PlateSight.person_shown(
			_cam, box, str(id), _frame_rect(), img, bare, MIN_SUBJECT_PX
		)
		print(
			(
				(
					"VISIBLE passenger=%d node_at=%s drawn=%s px=%s height_px=%.0f lines=9 on=%d"
					+ " past=%d blockers=%s in_frame=%s hud_px=%d ok=%s"
				)
				% [
					id,
					_views.node_for(id).position,
					box,
					seen.get("px"),
					seen.get("height_px", 0.0),
					seen["on"],
					seen["past"],
					seen["blockers"],
					seen.get("in_frame"),
					seen.get("hud_px", 0),
					seen["ok"]
				]
			)
		)
		shown += int(seen["ok"])
	holder.free()
	paused = false
	if not unbaked.is_empty():
		_invalid("skinned meshes not baked: %s" % [unbaked])
		shown = 0
	if changed == 0:
		_invalid("hiding the HUD changed no pixel, so the HUD check proves nothing")
		shown = 0
	return {"shown": shown, "image": img}


func _benchmark() -> void:
	_stage = "bench"
	await _boot()
	await _frames(10)
	_hud.press_debug_spawn()
	_aim(_sim.grid.cell_to_world(ReferenceTerminal.ENTRANCE_CELL), 40.0, 0.0)
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
	var everyone := _ids(func(_p: Passenger) -> bool: return true)
	var centre := Vector3.ZERO
	for id in everyone:
		centre += _views.node_for(id).position
	_aim(centre / maxi(everyone.size(), 1), 40.0, 0.0)
	await _frames(20)
	if peak < PassengerHud.DEBUG_BATCH:
		_invalid(
			"04: views peaked at %d, under the debug batch of %d" % [peak, PassengerHud.DEBUG_BATCH]
		)
	var in_frame: Array[int] = []
	for id in everyone:
		var at := _views.node_for(id).position + Vector3(0.0, 1.0, 0.0)
		if in_frame.size() < BENCH_CHECKED and _in_frame(at):
			in_frame.append(id)
	_beat("04_benchmark_300")
	print(
		(
			"PLATE 04_benchmark_300%s tick=%d candidates=%d"
			% [_scale_tag, _clock.tick, in_frame.size()]
		)
	)
	var result := await _shown(in_frame)
	var shown: int = result["shown"]
	print("SHOWN 04_benchmark_300%s shown=%d need=%d" % [_scale_tag, shown, BENCH_SHOWN])
	if shown >= BENCH_SHOWN:
		_save(result["image"], "04_benchmark_300")
	else:
		_invalid("04: %d passengers shown, need %d" % [shown, BENCH_SHOWN])
		_save(result["image"], "04_benchmark_300_INVALID", false)


func _queued(p: Passenger) -> bool:
	return p.stage in [Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.SECURITY_QUEUE]


## Seated at a gate seat, with the sit pose on (its view plays sit_idle).
func _seated_posed(p: Passenger) -> bool:
	if p.stage != Passenger.Stage.SEATED or p.seat_object == 0:
		return false
	return _views.node_for(p.id).get_meta(&"clip", "") == "sit_idle"


## _seated_posed() in a seat row's middle cell.
func _seated_middle(p: Passenger) -> bool:
	if not _seated_posed(p):
		return false
	var record := _sim.grid.get_object(p.seat_object)
	var cells := BuildCatalog.get_def(record["def"]).footprint(record["anchor"], record["facing"])
	return cells.find(p.seat_cell) == 1


func _count(test: Callable) -> int:
	return _ids(test).size()


## Passengers passing `test` that have a drawn node.
func _ids(test: Callable) -> Array[int]:
	var ids: Array[int] = []
	for id in _sim.passenger_ids():
		if _views.node_for(id) != null and test.call(_sim.get_passenger(id)):
			ids.append(id)
	return ids


func _first(test: Callable) -> int:
	var ids := _ids(test)
	return 0 if ids.is_empty() else ids[0]


func _frame_rect() -> Rect2:
	return Rect2(
		Vector2.ONE * MARGIN_PX, root.get_visible_rect().size - Vector2.ONE * MARGIN_PX * 2
	)


func _in_frame(at: Vector3) -> bool:
	return not _cam.is_position_behind(at) and _frame_rect().has_point(_cam.unproject_position(at))


func _save(img: Image, name: String, sheet := true) -> void:
	var path := _out_dir.path_join(name + _scale_tag + ".png")
	var err := img.save_png(path)
	if err != OK:
		_invalid("could not save %s (error %d)" % [path, err])
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
	if sheet:
		_saved.append(img)


## Every saved plate at a third size, three to a row.
func _sheet() -> Image:
	var w := _saved[0].get_width() / 3
	var h := _saved[0].get_height() / 3
	var rows := (_saved.size() + 2) / 3
	var sheet := Image.create(w * 3, h * rows, false, Image.FORMAT_RGBA8)
	for i in _saved.size():
		var small := _saved[i].duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 3), h * (i / 3)))
	return sheet
