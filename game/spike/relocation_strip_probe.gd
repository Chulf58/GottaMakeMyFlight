extends SceneTree
## Windowed frame strip of a toilet user whose stall is moved while they sit
## (move rooms 3/3, visitor relocation, board 8f3bba04), in the real main scene
## with a new random seed (printed). ToiletTestLayout with one stall per room
## (the landside stall at 23,10), the reference terminal and a gate desk. One
## landside passenger is sent to the stall as test_room_move_toilet.gd does;
## once seated (TOILET_USE) the stall is moved to 25,10 the way a room move
## moves it (removed, placed again under its id with its paid, one batch).
## From the move until the user sits down again in the moved stall, the clock
## is stepped one tick per frame and a frame is kept every STRIP_STEP_TICKS,
## from a steep camera that holds the old and the new stall. Each frame prints
## the stage, the drawn position, the largest jump since the last tick, the
## sim's ghost count and the drawn ghost count; at the end the probe prints the
## largest jump over the strip and the seated user's distance from the moved
## stall's use point.
## Proof before each frame: the user, the old stall and the new stall project
## inside the frame with a margin (printed), and no mesh outside the toilet
## pieces, the ghosts and the passengers stands between the camera and the
## user. Otherwise PROBE_INVALID, exit 1. A guard thread calls OS.crash() on
## a stall.
##
## With `-- --case=gate` it draws the gate-seat case instead (move rooms 3b,
## board fee68e85, GateRelocation): a cleared passenger is sent to a gate seat
## and, once SEATED, its seat row is moved to GATE_MOVED_TO the way a room move
## moves it. From the move until the passenger sits down again, one tick per
## frame, a frame every STRIP_STEP_TICKS from a steep camera holding the old
## row, the new row and the passenger, with the same in-frame, in-sight and
## largest-jump checks (the row's meshes, its ghost and the passengers are the
## pieces allowed between the camera and the passenger).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/relocation_strip_probe.gd [-- --case=gate] [--out=<dir>]
##
## Plates go to tools/blender/out/relocation/ (the gate case: tools/blender/out/
## move-rooms-gate-seats/) unless --out names a directory.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/relocation"
const GATE_OUT_REL := "res://../tools/blender/out/move-rooms-gate-seats"
## Where the gate case sets the passenger's seat row down (terminal cells): east
## of the reference rows, beside the gate desk, clear of its chair fronts.
const GATE_MOVED_TO := Vector2i(17, 6)
const MARGIN_PX := 8.0
const HANG_MS := 90000
const MOVED_TO := Vector2i(25, 10)
const STRIP_STEP_TICKS := 4
const MAX_FRAMES := 60
const LIMIT_TICKS := 1500
## Largest drawn step a tick may take, as in test_room_move_toilet.gd: one
## walking step. Measured on the position the views record for each tick
## (PassengerViews.tick_position()), not on the node, which a frame draws
## between two ticks; a frame is kept on every tick that takes more.
const MAX_STEP_M := PassengerSim.WALK_MM / 1000.0 + 0.002
const CAM_UP_M := 7.0
const CAM_BACK_M := 3.0

var _out_dir := ""
var _gate := false
var _cam_up := CAM_UP_M
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false

var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _mode: BuildMode
var _views: PassengerViews
var _cam: Camera3D
var _ids := {}
var _frames_kept: Array[Image] = []


func _initialize() -> void:
	_gate = OS.get_cmdline_user_args().has("--case=gate")
	var rel := GATE_OUT_REL if _gate else OUT_REL
	_out_dir = ProjectSettings.globalize_path(rel).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	var world_seed := randi()
	seed(world_seed)
	_clock.seed_rng(world_seed)
	print("PROBE world_seed=", world_seed)
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
	_beat("build")
	_ids = ToiletTestLayout.build(_mode.grid, 1)
	if not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the gate desk was refused")
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.toilets.refresh()
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE ids=%s hired=%d opened tick=%d" % [_ids, hired, _clock.tick])
	if hired == 0 or doors < 0:
		_invalid("the staff were not hired and the airport did not open")
		_finish()
		return
	if _gate:
		await _gate_strip()
	else:
		await _strip()
	_finish()


func _offset() -> Vector2i:
	return ReferenceTerminal.offset_on(_mode.grid)


func _stall() -> int:
	return _ids["land_stalls"][0]


## The world centre of the stall's footprint at `anchor` (a 1 x 2 stall).
func _stall_centre(anchor: Vector2i) -> Vector3:
	var a := _mode.grid.cell_to_world(anchor + _offset())
	var b := _mode.grid.cell_to_world(anchor + _offset() + Vector2i(0, 1))
	return (a + b) / 2.0


## A landside passenger sent to the stall, run until seated.
func _user() -> Passenger:
	var p := _sim.get_passenger(
		_sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
	)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _clock.tick
	p.at = Vector2i(20, 14) + _offset()
	p.clear_path()
	p.toilet_need = 90
	if not _sim.toilets.try_visit(p):
		_invalid("the passenger could not start a toilet visit")
		return null
	var until := _clock.tick + LIMIT_TICKS
	while p.stage != Passenger.Stage.TOILET_USE and _clock.tick < until:
		_clock.advance(SimClock.STEP)
		if _clock.tick % 8 == 0:
			_beat("to stall %d" % _clock.tick)
			await process_frame
	print("PROBE user=%d stage=%d tick=%d" % [p.id, p.stage, _clock.tick])
	if p.stage != Passenger.Stage.TOILET_USE:
		_invalid("the user never sat down in the stall")
		return null
	return p


func _move_stall() -> bool:
	var record := _mode.grid.get_object(_stall())
	var place := BuildEdit.place_object(record["def"], MOVED_TO + _offset(), record["facing"])
	place.object_id = _stall()
	place.paid = int(record.get("paid", 0))
	var ok := true
	for result in _mode.grid.apply_batch([BuildEdit.remove_object(_stall()), place]):
		if not result.ok:
			_invalid("the stall move was refused: %s" % result.reason_text())
			ok = false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	return ok


func _strip() -> void:
	var p: Passenger = await _user()
	if p == null:
		return
	# Let the drawn user settle on the seat before the move.
	for i in 8:
		_clock.advance(SimClock.STEP)
		await process_frame
	var old_centre := _stall_centre(Vector2i(ToiletTestLayout.STALL_X, 10))
	var new_centre := _stall_centre(MOVED_TO)
	var mid := (old_centre + new_centre) / 2.0
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_main.add_child(_cam)
	_cam.look_at_from_position(mid + Vector3(0.0, _cam_up, CAM_BACK_M), mid)
	_cam.make_current()
	if not _move_stall():
		return
	var move_tick := _clock.tick
	await _frames(2)
	print(
		(
			"MOVE tick=%d stall=%d stage=%d sim_ghosts=%d drawn_ghosts=%d"
			% [move_tick, _stall(), p.stage, Relocation.ghosts(_sim).size(), _views.ghosts.count()]
		)
	)
	var node := _views.node_for(p.id)
	var last := node.global_position
	var last_tick := _views.tick_position(p.id, true)
	var worst := 0.0
	var left_old := false
	var resat := false
	var since_sat := 0
	while _clock.tick < move_tick + LIMIT_TICKS and _frames_kept.size() < MAX_FRAMES:
		_beat("strip %d" % _clock.tick)
		_clock.advance(SimClock.STEP)
		await process_frame
		node = _views.node_for(p.id)
		last = node.global_position
		var at_tick := _views.tick_position(p.id, true)
		var step := at_tick.distance_to(last_tick)
		last_tick = at_tick
		worst = maxf(worst, step)
		var jumped := step > MAX_STEP_M
		if jumped:
			print("JUMP tick=%d stage=%d step=%.3f at=%s" % [_clock.tick, p.stage, step, at_tick])
		var ghosts := Relocation.ghosts(_sim).size()
		if ghosts == 0:
			left_old = true
		if left_old and p.stage == Passenger.Stage.TOILET_USE:
			since_sat += 1
			resat = true
		var keep := (_clock.tick - move_tick) % STRIP_STEP_TICKS == 0
		if keep or jumped or (resat and since_sat == 1):
			await _keep_frame(p, old_centre, new_centre, step, ghosts)
		if resat and since_sat >= STRIP_STEP_TICKS * 3:
			break
	var use: Vector3 = (
		_sim.toilets.visit_of(p.id).stall["use"]
		if _sim.toilets.visit_of(p.id) != null
		else Vector3.INF
	)
	print(
		(
			(
				"PROBE strip frames=%d worst_step=%.3f resat=%s stage=%d seat_gap_m=%.3f"
				+ " user_at=%s new_stall_centre=%s"
			)
			% [
				_frames_kept.size(),
				worst,
				resat,
				p.stage,
				Vector2(last.x - use.x, last.z - use.z).length(),
				last,
				new_centre
			]
		)
	)
	if not resat:
		_invalid("the user did not sit down again in the moved stall")
	if worst > MAX_STEP_M:
		_invalid("the drawn user jumped %.3f m in one tick" % worst)
	if not _frames_kept.is_empty():
		_save(_sheet(_frames_kept), "relocation_strip.png")


func _keep_frame(
	p: Passenger, old_centre: Vector3, new_centre: Vector3, step: float, ghosts: int
) -> void:
	var node := _views.node_for(p.id)
	var head := node.global_position + Vector3(0.0, 1.2, 0.0)
	var label := "t%d" % _clock.tick
	for pair: Array in [["user", head], ["old_piece", old_centre], ["new_piece", new_centre]]:
		if not _in_frame(pair[1], "%s %s" % [label, pair[0]]):
			return
	if not _clear_sight(head, label):
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	print(
		(
			"FRAME %s stage=%d at=%s step=%.3f sim_ghosts=%d drawn_ghosts=%d"
			% [label, p.stage, node.global_position, step, ghosts, _views.ghosts.count()]
		)
	)
	_save(img, "%s_%s.png" % ["gate_seat" if _gate else "relocation", label])
	_frames_kept.append(img)


func _in_frame(point: Vector3, label: String) -> bool:
	var frame := root.get_visible_rect().grow(-MARGIN_PX)
	var screen := _cam.unproject_position(point)
	var inside := frame.has_point(screen) and not _cam.is_position_behind(point)
	print("INFRAME %s screen=(%.0f,%.0f) ok=%s" % [label, screen.x, screen.y, inside])
	if not inside:
		_invalid("%s is outside the frame" % label)
	return inside


## A cleared passenger sent to a gate seat, run until SEATED.
func _sitter() -> Passenger:
	var p := _sim.get_passenger(
		_sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
	)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.boarding_tick = _clock.tick + 100000
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = Vector2i(15, 5) + _offset()
	p.clear_path()
	var until := _clock.tick + LIMIT_TICKS
	while p.stage != Passenger.Stage.SEATED and _clock.tick < until:
		_clock.advance(SimClock.STEP)
		if _clock.tick % 8 == 0:
			_beat("to seat %d" % _clock.tick)
			await process_frame
	print(
		(
			"PROBE sitter=%d stage=%d tick=%d seat_object=%d"
			% [p.id, p.stage, _clock.tick, p.seat_object]
		)
	)
	if p.stage != Passenger.Stage.SEATED:
		_invalid("the passenger never sat down at a gate seat")
		return null
	return p


## The world centre of the footprint of seat row `id` at `anchor`.
func _row_centre(id: int, anchor: Vector2i) -> Vector3:
	var record := _mode.grid.get_object(id)
	var def := BuildCatalog.get_def(record["def"])
	var sum := Vector3.ZERO
	var cells := def.footprint(anchor, record["facing"])
	for cell in cells:
		sum += _mode.grid.cell_to_world(cell)
	return sum / cells.size()


func _move_row(id: int) -> bool:
	var record := _mode.grid.get_object(id)
	var place := BuildEdit.place_object(record["def"], GATE_MOVED_TO + _offset(), record["facing"])
	place.object_id = id
	place.paid = int(record.get("paid", 0))
	var ok := true
	for result in _mode.grid.apply_batch([BuildEdit.remove_object(id), place]):
		if not result.ok:
			_invalid("the seat row move was refused: %s" % result.reason_text())
			ok = false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	return ok


func _gate_strip() -> void:
	var p: Passenger = await _sitter()
	if p == null:
		return
	for i in 8:
		_clock.advance(SimClock.STEP)
		await process_frame
	var row := p.seat_object
	var old_centre := _row_centre(row, _mode.grid.get_object(row)["anchor"])
	var new_centre := _row_centre(row, GATE_MOVED_TO + _offset())
	var mid := (old_centre + new_centre) / 2.0
	_cam_up = 9.0
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_main.add_child(_cam)
	_cam.look_at_from_position(mid + Vector3(0.0, _cam_up, CAM_BACK_M), mid)
	_cam.make_current()
	await _frames(2)
	# The camera in use and where it puts the strip's centre (the view centre).
	print(
		(
			"CAMCHECK current=%s size=%s visible=%s mid_screen=%s"
			% [_cam.current, root.size, root.get_visible_rect(), _cam.unproject_position(mid)]
		)
	)
	var seated_at := _views.node_for(p.id).global_position
	if not _move_row(row):
		return
	var move_tick := _clock.tick
	await _frames(2)
	print(
		(
			"MOVE tick=%d row=%d stage=%d seated_at=%s sim_ghosts=%d drawn_ghosts=%d"
			% [
				move_tick,
				row,
				p.stage,
				seated_at,
				Relocation.ghosts(_sim).size(),
				_views.ghosts.count()
			]
		)
	)
	var last_tick := _views.tick_position(p.id, true)
	var worst := 0.0
	var left_old := false
	var resat := false
	var since_sat := 0
	var stages: Array[int] = []
	var was_late := p.late
	var over := 0.0
	while _clock.tick < move_tick + LIMIT_TICKS and _frames_kept.size() < MAX_FRAMES:
		_beat("gate strip %d" % _clock.tick)
		_clock.advance(SimClock.STEP)
		await process_frame
		if stages.is_empty() or stages[-1] != p.stage:
			stages.append(p.stage)
		var at_tick := _views.tick_position(p.id, true)
		var step := at_tick.distance_to(last_tick)
		last_tick = at_tick
		worst = maxf(worst, step)
		# A late passenger runs (PassengerSim.RUN_MM); it may have turned late
		# on the tick before.
		var cap := (PassengerSim.RUN_MM if p.late or was_late else PassengerSim.WALK_MM) / 1000.0
		was_late = p.late
		over = maxf(over, step - (cap + 0.002))
		var jumped := step > cap + 0.002
		if jumped:
			print("JUMP tick=%d stage=%d step=%.3f at=%s" % [_clock.tick, p.stage, step, at_tick])
		var ghosts := Relocation.ghosts(_sim).size()
		if ghosts == 0:
			left_old = true
		var sitting := p.stage == Passenger.Stage.SITTING_DOWN or p.stage == Passenger.Stage.SEATED
		if left_old and sitting:
			since_sat += 1
			resat = true
		var keep := (_clock.tick - move_tick) % STRIP_STEP_TICKS == 0
		if keep or jumped or (resat and since_sat == 1):
			await _keep_frame(p, old_centre, new_centre, step, ghosts)
		if resat and since_sat >= STRIP_STEP_TICKS * 3:
			break
	print(
		(
			"PROBE gate strip frames=%d worst_step=%.3f resat=%s stage=%d stages=%s seat_object=%d"
			% [_frames_kept.size(), worst, resat, p.stage, stages, p.seat_object]
		)
	)
	if not resat:
		_invalid("the passenger did not sit down again after the move")
	if over > 0.0:
		_invalid("the drawn passenger jumped %.3f m in one tick" % worst)
	if not stages.has(Passenger.Stage.STANDING_UP):
		_invalid("the passenger never got up at the old seat (control)")
	if not _frames_kept.is_empty():
		_save(_sheet(_frames_kept), "gate_seat_strip.png")


## The sight line from the camera to the user's head against the box of every
## visible mesh, except the toilet pieces, the ghosts, the passengers and the
## ground (a box that holds the head). Prints the blockers.
func _clear_sight(head: Vector3, label: String) -> bool:
	var skip: Array[Node] = [_views, _mode.get_node("BuildView")]
	var blockers: Array[String] = []
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var skipped := false
		for owner_node in skip:
			if owner_node.is_ancestor_of(mesh):
				skipped = true
		if skipped:
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		if box.has_point(head):
			continue
		if box.intersects_segment(_cam.global_position, head) != null:
			blockers.append(String(mesh.get_path()))
	print("SIGHT %s blockers=%s" % [label, blockers])
	if not blockers.is_empty():
		_invalid("%s: the user is hidden by %s" % [label, blockers])
		return false
	return true


## The frames in rows of five, each scaled to a quarter.
func _sheet(frames: Array[Image]) -> Image:
	var w := frames[0].get_width() / 4
	var h := frames[0].get_height() / 4
	var cols := mini(5, frames.size())
	var rows := ceili(frames.size() / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var small := frames[i].duplicate() as Image
		small.resize(w, h)
		sheet.blit_rect(
			small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i(i % cols * w, i / cols * h)
		)
	return sheet


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
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var idle := Time.get_ticks_msec() - _beat_ms
		var stage := _stage
		_lock.unlock()
		if stop:
			return
		if idle > HANG_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle])
			OS.crash("relocation strip probe hung")
