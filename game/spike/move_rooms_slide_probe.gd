extends SceneTree
## Windowed frame strips of roller and bag visitors whose sofa, nap pod or
## shower is moved before they are fully seated (board 53b3fe84; decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, parts 4 to 6),
## in the real main scene with a new random seed (printed). The reference
## terminal, a gate desk and ActivityTestLayout's room of --type= (lounge,
## nap_pod or shower; default lounge), its piece at 22,3 against the room's
## north and west walls.
##
## Each case spawns a visitor, lets it stay SETTLE ticks after it starts to
## browse, moves the piece to 25,3 (or back) the way a room move moves it, and
## keeps a frame every STRIP_STEP_TICKS ticks until the visitor walks off. The
## drawn body may never come nearer its old seat than it was on the tick before
## (NEARER_M), and the share of its step onto the seat may never rise above what
## it was when the move came (SHARE_RISE). Every case prints those worst values.
## Cases "door5", "door14" (a roller visitor still standing at its slot cell
## setting the roller down), "sit5", "sit10" (5 and 10 ticks into the sit-down),
## and for the shower "nobag6" (a visitor with no bags 6 ticks into its step in).
## With --type=lounge the probe ends with orthographic plates of a seated
## visitor on the sofa against the wall: front, east side and top, to see
## whether its hips cut into the sofa arm.
##
## Proof before each frame: the visitor, the old piece and the new piece project
## inside the frame with a margin (printed), and no mesh outside the pieces, the
## ghosts and the passengers stands between the camera and the visitor.
## Otherwise PROBE_INVALID, exit 1. A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run at a time project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/move_rooms_slide_probe.gd -- --type=lounge [--out=<dir>]
##
## Plates go to tools/blender/out/move-rooms-slide/ unless --out names a directory.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/move-rooms-slide"
const MARGIN_PX := 8.0
const HANG_MS := 90000
const PIECE_AT := Vector2i(22, 3)
const PIECE_TO := Vector2i(25, 3)
const NEARER_M := 0.0005
const SHARE_RISE := 0.001
const STRIP_STEP_TICKS := 4
const DENSE_TICKS := 8
const AIM_SOUTH_M := 1.0
const MAX_FRAMES := 40
const LIMIT_TICKS := 1500
const CAM_UP_M := 8.0
const CAM_BACK_M := 3.0
const MAX_STEP_M := PassengerSim.WALK_MM / 1000.0 + 0.002
## Orthographic plate frame: metres across the short side.
const ORTHO_SIZE_M := 2.4
const SEAT_SETTLE_TICKS := 60

var _out_dir := ""
var _type := &"lounge"
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
var _piece := 0
var _at := PIECE_AT
var _frames_kept: Array[Image] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--type="):
			_type = StringName(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir, " type=", _type)
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
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_beat("build")
	var ids := ActivityTestLayout.build(_mode.grid, _type)
	_piece = ids["use"]
	if not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the gate desk was refused")
		_finish()
		return
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.shops.refresh()
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE piece=%d hired=%d opened tick=%d" % [_piece, hired, doors])
	if hired == 0 or doors < 0:
		_invalid("the staff were not hired and the airport did not open")
		_finish()
		return
	var seat_door := ActivityPoses.SEAT_DOOR_TICKS
	if _type == &"shower":
		await _case("door5", true, 5)
		await _case("door12", true, 12)
		await _case("nobag6", false, 6)
	else:
		await _case("door5", true, 5)
		await _case("door14", true, 14)
		await _case("sit5", true, seat_door + 5)
		await _case("sit10", true, seat_door + 10)
	if _type == &"lounge":
		await _ortho_plates()
	_finish()


func _offset() -> Vector2i:
	return ReferenceTerminal.offset_on(_mode.grid)


## The world centre of the piece's first two cells at `anchor`.
func _centre(anchor: Vector2i) -> Vector3:
	var a := _mode.grid.cell_to_world(anchor + _offset())
	var b := _mode.grid.cell_to_world(anchor + _offset() + Vector2i(1, 0))
	return (a + b) / 2.0


func _move_piece(anchor: Vector2i) -> bool:
	var record := _mode.grid.get_object(_piece)
	var place := BuildEdit.place_object(record["def"], anchor + _offset(), record["facing"])
	place.object_id = _piece
	place.paid = int(record.get("paid", 0))
	var ok := true
	for result in _mode.grid.apply_batch([BuildEdit.remove_object(_piece), place]):
		if not result.ok:
			_invalid("the move was refused: %s" % result.reason_text())
			ok = false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	return ok


## A calm airside passenger, bored, with one roller (`roller`) or no bags, whom
## the shop policy sends to the piece. A roller's kind is a hash of the id, so
## this spawns until it matches; the others never shop.
func _visitor(roller: bool) -> Passenger:
	var p: Passenger = null
	for attempt in 300:
		p = _sim.get_passenger(
			_sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		)
		if not roller or SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.shop_cooldown = 1000000
	ToiletTestLayout.calm(p)
	p.carry_on = 1 if roller else 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = ShopTestLayout.AIRSIDE_CELL + _offset()
	p.clear_path()
	p.boredom = BoredomSim.MAX
	p.shop_cooldown = 0
	p.mood = 50
	if NeedsPolicy.arbitrate(_sim, p) != NeedsPolicy.Need.BOREDOM:
		_invalid("the passenger did not start a shop visit")
		return null
	return p


## Steps the clock until `p` is browsing, then `settle` ticks more.
func _to_browse(p: Passenger, settle: int) -> bool:
	var until := _clock.tick + LIMIT_TICKS
	while p.stage != Passenger.Stage.SHOP_BROWSE and _clock.tick < until:
		_clock.advance(SimClock.STEP)
		if _clock.tick % 8 == 0:
			_beat("to piece %d" % _clock.tick)
			await process_frame
	if p.stage != Passenger.Stage.SHOP_BROWSE:
		_invalid("the visitor never started to browse")
		return false
	for i in settle:
		_clock.advance(SimClock.STEP)
		await process_frame
	return true


## Steps the clock until the visit of `p` is over.
func _until_gone(p: Passenger) -> bool:
	var until := _clock.tick + LIMIT_TICKS
	while _sim.shops.visit_of(p.id) != null and _clock.tick < until:
		_beat("visitor %d ends %d" % [p.id, _clock.tick])
		_clock.advance(SimClock.STEP)
		if _clock.tick % 8 == 0:
			await process_frame
	if _sim.shops.visit_of(p.id) != null:
		_invalid("visitor %d never finished its stay" % p.id)
		return false
	return true


func _case(label: String, roller: bool, settle: int) -> void:
	var p := _visitor(roller)
	if p == null or not await _to_browse(p, settle):
		return
	var to := PIECE_TO if _at == PIECE_AT else PIECE_AT
	await _strip("%s_%s" % [_type, label], p, _at, to)
	_at = to
	await _until_gone(p)


func _strip(case: String, p: Passenger, from: Vector2i, to: Vector2i) -> void:
	var old_centre := _centre(from)
	var new_centre := _centre(to)
	var mid := (old_centre + new_centre) / 2.0
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 45.0
		_main.add_child(_cam)
	var aim := mid + Vector3(0.0, 0.0, AIM_SOUTH_M)
	_cam.look_at_from_position(aim + Vector3(0.0, CAM_UP_M, CAM_BACK_M), aim)
	_cam.make_current()
	_frames_kept.clear()
	var seat := ActivityPoses.stay_frame(_sim, p).origin
	var away := _away(p, seat)
	var share_before := ActivityPoses.share(_sim, p)
	print(
		(
			"PRE %s tick=%d pose=%d share=%.3f away=%.3f roller=%s"
			% [
				case,
				_clock.tick,
				ActivityPoses.pose(_sim, p),
				share_before,
				away,
				ParkRecovery.has_roller(p)
			]
		)
	)
	if not _move_piece(to):
		return
	var move_tick := _clock.tick
	await _frames(2)
	print(
		(
			"MOVE %s tick=%d stage=%d sim_ghosts=%d drawn_ghosts=%d"
			% [case, move_tick, p.stage, Relocation.ghosts(_sim).size(), _views.ghosts.count()]
		)
	)
	var node := _views.node_for(p.id)
	var last_tick := _views.tick_position(p.id, true)
	var worst := 0.0
	var nearest := 0.0
	var rise := 0.0
	var share_at_move := -1.0
	var left_old := false
	var back := false
	var since_back := 0
	var seated_checked := 0
	while _clock.tick < move_tick + LIMIT_TICKS and _frames_kept.size() < MAX_FRAMES:
		_beat("%s strip %d" % [case, _clock.tick])
		_clock.advance(SimClock.STEP)
		await process_frame
		node = _views.node_for(p.id)
		var at_tick := _views.tick_position(p.id, true)
		var step := at_tick.distance_to(last_tick)
		last_tick = at_tick
		worst = maxf(worst, step)
		var jumped := step > MAX_STEP_M
		if jumped:
			print("JUMP %s tick=%d stage=%d step=%.3f" % [case, _clock.tick, p.stage, step])
		if p.stage == Passenger.Stage.SHOP_WALK:
			left_old = true
		if not left_old and p.stage == Passenger.Stage.SHOP_BROWSE:
			var share := ActivityPoses.share(_sim, p)
			if share_at_move < 0.0:
				share_at_move = share
			rise = maxf(rise, share - share_at_move)
			var now_away := _away(p, seat)
			nearest = maxf(nearest, away - now_away)
			seated_checked += 1
			print(
				(
					"EXIT %s tick=%d pose=%d clip=%d share=%.3f away=%.3f nearer=%.4f"
					% [
						case,
						_clock.tick,
						ActivityPoses.pose(_sim, p),
						ActivityPoses.clip_ticks(_sim, p),
						share,
						now_away,
						away - now_away,
					]
				)
			)
			away = now_away
		if left_old and p.stage == Passenger.Stage.SHOP_BROWSE:
			since_back += 1
			back = true
		var since := _clock.tick - move_tick
		var keep := since % STRIP_STEP_TICKS == 0 or since <= DENSE_TICKS
		if keep or jumped or (back and since_back == 1):
			await _keep_frame(case, p, old_centre, new_centre, step)
		if back and since_back >= STRIP_STEP_TICKS * 3:
			break
	print(
		(
			(
				"PROBE strip %s frames=%d exit_ticks=%d worst_step=%.3f nearest_step=%.4f"
				+ " share_before=%.3f share_at_move=%.3f share_rise=%.4f back=%s stage=%d"
			)
			% [
				case,
				_frames_kept.size(),
				seated_checked,
				worst,
				nearest,
				share_before,
				share_at_move,
				rise,
				back,
				p.stage
			]
		)
	)
	if seated_checked == 0:
		_invalid("%s: the visitor never exited at the old piece" % case)
	if not back:
		_invalid("%s: the visitor did not browse again at the moved piece" % case)
	if worst > MAX_STEP_M:
		_invalid("%s: the drawn visitor jumped %.3f m in one tick" % [case, worst])
	if nearest > NEARER_M:
		_invalid("%s: the visitor slid %.3f m into its old seat in one tick" % [case, nearest])
	if rise > SHARE_RISE:
		_invalid("%s: the step onto the seat rose %.3f during the exit" % [case, rise])
	if not _frames_kept.is_empty():
		_save(_sheet(_frames_kept), "move_rooms_slide_%s_strip.png" % case)


## The ground distance from the drawn body of `p` (the position the views
## recorded for this tick) to `spot`.
func _away(p: Passenger, spot: Vector3) -> float:
	var at := _views.tick_position(p.id, true)
	return Vector2(at.x, at.z).distance_to(Vector2(spot.x, spot.z))


func _keep_frame(
	case: String, p: Passenger, old_centre: Vector3, new_centre: Vector3, step: float
) -> void:
	var node := _views.node_for(p.id)
	var head := node.global_position + Vector3(0.0, 1.2, 0.0)
	var label := "%s_t%d" % [case, _clock.tick]
	for pair: Array in [["user", head], ["old_piece", old_centre], ["new_piece", new_centre]]:
		if not _in_frame(pair[1], "%s %s" % [label, pair[0]]):
			return
	if not _clear_sight(head, label):
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	print("FRAME %s stage=%d at=%s step=%.3f" % [label, p.stage, node.global_position, step])
	_save(img, "move_rooms_slide_%s.png" % label)
	_frames_kept.append(img)


func _in_frame(point: Vector3, label: String) -> bool:
	var frame := root.get_visible_rect().grow(-MARGIN_PX)
	var screen := _cam.unproject_position(point)
	var inside := frame.has_point(screen) and not _cam.is_position_behind(point)
	print("INFRAME %s screen=(%.0f,%.0f) ok=%s" % [label, screen.x, screen.y, inside])
	if not inside:
		_invalid("%s is outside the frame" % label)
	return inside


## The sight line from in front of the camera to `target` against the box of
## every visible mesh, except the build pieces, the ghosts and the passengers
## (the views) and any box that holds the target. A perspective ray starts at
## the camera; an orthographic one runs along the view direction. Prints the
## blockers.
func _clear_sight(target: Vector3, label: String) -> bool:
	var skip: Array[Node] = [_views, _mode.get_node("BuildView")]
	var from := _cam.global_position
	if _cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		from = target + _cam.global_transform.basis.z * 30.0
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
		if box.has_point(target):
			continue
		if box.intersects_segment(from, target) != null:
			blockers.append(String(mesh.get_path()))
	print("SIGHT %s blockers=%s" % [label, blockers])
	if not blockers.is_empty():
		_invalid("%s: the target is hidden by %s" % [label, blockers])
		return false
	return true


## Orthographic plates of a visitor sitting on the sofa against its walls: from
## the front, from the east and from above, true scale (a 1 m cube is not
## placed; the frame is ORTHO_SIZE_M across its short side).
func _ortho_plates() -> void:
	if _at != PIECE_AT:
		var back := PIECE_AT
		if not _move_piece(back):
			return
		_at = back
	await _frames(3)
	var p := _visitor(false)
	if p == null or not await _to_browse(p, SEAT_SETTLE_TICKS):
		return
	var seat := ActivityPoses.stay_frame(_sim, p).origin
	var node := _views.node_for(p.id)
	print(
		(
			"ORTHO seated tick=%d pose=%d share=%.2f seat=%s body=%s"
			% [
				_clock.tick,
				ActivityPoses.pose(_sim, p),
				ActivityPoses.share(_sim, p),
				seat,
				node.global_position
			]
		)
	)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ORTHO_SIZE_M
	var hips := seat + Vector3(0.0, 0.55, 0.0)
	var views := {
		"front": Vector3(0.0, 0.0, 5.0),
		"east": Vector3(5.0, 0.0, 0.0),
		"top": Vector3(0.0, 5.0, 0.01),
	}
	for key: String in views:
		_cam.look_at_from_position(hips + views[key], hips, Vector3.UP)
		_cam.make_current()
		await _frames(3)
		var label := "ortho_%s" % key
		if (
			not _in_frame(hips, label + " hips")
			or not _in_frame(seat + Vector3(0, 1.2, 0), label + " head")
		):
			continue
		if not _clear_sight(hips, label):
			continue
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		_save(img, "move_rooms_slide_lounge_%s.png" % label)


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
			OS.crash("move rooms slide probe hung")
