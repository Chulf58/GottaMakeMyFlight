extends SceneTree
## Windowed frame strips of shop and activity visitors whose piece is moved
## while they use it (move rooms 3b, board a018022c; decision move-rooms-
## technical-design-roommove-plan-of-existing-edits, parts 4 to 6), in the real
## main scene with a new random seed (printed). The reference terminal, a gate
## desk, ShopTestLayout's landside kiosk (one display stand at 25,10) and a
## lounge in its airside room (one sofa at 22,3).
##
## Case "lounge": an airside passenger sits on the sofa for LOUNGE_SETTLE_TICKS,
## then the sofa is moved to 25,3 the way a room move moves it (removed, placed
## again under its id with its paid, one batch). From the move until the
## visitor sits on the moved sofa, the clock is stepped one tick per frame and
## a frame is kept every STRIP_STEP_TICKS: stand-up at the old sofa under its
## ghost, the walk, the sit-down at the new one.
## Cases "lounge_early" and "lounge_deep": the sofa moved again, each time
## under a new visitor still sitting down, EARLY_SETTLE_TICKS and
## DEEP_SETTLE_TICKS into its stay (board 23ddd6bc). It stands up from where
## its sit-down had got to, and its drawn body must never come nearer the old
## seat than it was on the tick before (NEARER_M) until it walks off.
## Case "kiosk": a landside passenger browses the display stand, which is moved
## to 25,13; the browser turns away at once and walks to the stand at its new
## spot.
##
## Each frame prints the stage, the drawn position, the largest drawn step
## since the last tick, the sim's ghost count and the drawn ghost count; at the
## end of a case the probe prints the largest step over the strip.
## Proof before each frame: the visitor, the old piece and the new piece
## project inside the frame with a margin (printed), and no mesh outside the
## pieces, the ghosts and the passengers stands between the camera and the
## visitor. Otherwise PROBE_INVALID, exit 1. A guard thread calls OS.crash() on
## a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/shop_relocation_strip_probe.gd [-- --out=<dir>]
##
## Plates go to tools/blender/out/relocation/ unless --out names a directory.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/relocation"
const MARGIN_PX := 8.0
const HANG_MS := 90000
const SOFA_AT := Vector2i(22, 3)
const SOFA_TO := Vector2i(25, 3)
const DISPLAY_AT := Vector2i(25, 10)
const DISPLAY_TO := Vector2i(25, 13)
const LOUNGE_SETTLE_TICKS := 60
const KIOSK_SETTLE_TICKS := 20
## A visitor this far into the stay is still sitting down (SIT_DOWN_TICKS 24).
const EARLY_SETTLE_TICKS := 5
const DEEP_SETTLE_TICKS := 18
## How much nearer its old seat a sitter's drawn body may come on one tick of
## its exit: float noise only. A slide into the seat is a walking step a tick.
const NEARER_M := 0.0005
const STRIP_STEP_TICKS := 4
## Every tick is kept this long after the move: a pose jump shows in it.
const DENSE_TICKS := 14
## The camera aims this far south of the pieces' middle, to hold the approach cells.
const AIM_SOUTH_M := 1.0
const MAX_FRAMES := 60
const LIMIT_TICKS := 1500
## Largest drawn step a tick may take: one walking step, measured on the
## position the views record for each tick (PassengerViews.tick_position()).
const MAX_STEP_M := PassengerSim.WALK_MM / 1000.0 + 0.002
const CAM_UP_M := 8.0
const CAM_BACK_M := 3.0

var _out_dir := ""
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
var _sofa := 0
var _display := 0
var _frames_kept: Array[Image] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
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
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_beat("build")
	if not _build():
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
	print(
		"PROBE sofa=%d display=%d hired=%d opened tick=%d" % [_sofa, _display, hired, _clock.tick]
	)
	if hired == 0 or doors < 0:
		_invalid("the staff were not hired and the airport did not open")
		_finish()
		return
	await _strip_lounge()
	await _strip_kiosk()
	_finish()


func _offset() -> Vector2i:
	return ReferenceTerminal.offset_on(_mode.grid)


func _build() -> bool:
	var grid := _mode.grid
	var kiosk := ShopTestLayout.build(grid, ["land"], 1)
	var lounge := Rect2i(ShopTestLayout.AIRSIDE_ROOM.position + _offset(), Vector2i(6, 6))
	var room := grid.apply(BuildEdit.place_room(lounge, &"lounge"))
	var sofa := grid.apply(BuildEdit.place_object(&"lounge_sofa", SOFA_AT + _offset(), 0))
	if not room.ok or not sofa.ok:
		_invalid("the lounge was refused: %s %s" % [room.reason_text(), sofa.reason_text()])
		return false
	_sofa = sofa.object_id
	_display = kiosk["land_displays"][0]
	if not StarterFlight.add_gate_desk(grid):
		_invalid("the gate desk was refused")
		return false
	return true


## The world centre of a 2 x 1 piece's footprint at `anchor`.
func _centre(anchor: Vector2i) -> Vector3:
	var a := _mode.grid.cell_to_world(anchor + _offset())
	var b := _mode.grid.cell_to_world(anchor + _offset() + Vector2i(1, 0))
	return (a + b) / 2.0


func _move_piece(id: int, anchor: Vector2i) -> bool:
	var record := _mode.grid.get_object(id)
	var place := BuildEdit.place_object(record["def"], anchor + _offset(), record["facing"])
	place.object_id = id
	place.paid = int(record.get("paid", 0))
	var ok := true
	for result in _mode.grid.apply_batch([BuildEdit.remove_object(id), place]):
		if not result.ok:
			_invalid("the move was refused: %s" % result.reason_text())
			ok = false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	return ok


## A calm passenger with no bags, bored, who the shop policy sends to a piece.
func _visitor(landside: bool) -> Passenger:
	var p := _sim.get_passenger(
		_sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
	)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = not landside
	p.stage = Passenger.Stage.TO_SECURITY if landside else Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = (Vector2i(20, 14) if landside else ShopTestLayout.AIRSIDE_CELL) + _offset()
	p.clear_path()
	p.boredom = BoredomSim.MAX
	p.shop_cooldown = 0
	p.mood = 60
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


func _strip_lounge() -> void:
	var p := _visitor(false)
	if p == null or not await _to_browse(p, LOUNGE_SETTLE_TICKS):
		return
	await _strip("lounge", p, _sofa, SOFA_AT, SOFA_TO)
	# Let the first visitor finish its stay, then move the sofa back under a
	# visitor still sitting down (the stand-up pose may jump from there).
	var until := _clock.tick + LIMIT_TICKS
	while _sim.shops.visit_of(p.id) != null and _clock.tick < until:
		_beat("first visitor ends %d" % _clock.tick)
		_clock.advance(SimClock.STEP)
		if _clock.tick % 8 == 0:
			await process_frame
	var early := _visitor(false)
	if early == null or not await _to_browse(early, EARLY_SETTLE_TICKS):
		return
	await _strip("lounge_early", early, _sofa, SOFA_TO, SOFA_AT)
	if not await _until_gone(early):
		return
	var deep := _visitor(false)
	if deep == null or not await _to_browse(deep, DEEP_SETTLE_TICKS):
		return
	await _strip("lounge_deep", deep, _sofa, SOFA_AT, SOFA_TO)


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


func _strip_kiosk() -> void:
	var p := _visitor(true)
	if p == null or not await _to_browse(p, KIOSK_SETTLE_TICKS):
		return
	await _strip("kiosk", p, _display, DISPLAY_AT, DISPLAY_TO)


func _strip(case: String, p: Passenger, id: int, from: Vector2i, to: Vector2i) -> void:
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
	# A sitter's old seat: its drawn body may only move away from it until it
	# walks off.
	var seated := ActivityPoses.kind(_sim, p) != ActivityPoses.Kind.NONE
	var seat := ActivityPoses.stay_frame(_sim, p).origin
	var away := _away(p, seat)
	var nearest := 0.0
	print(
		(
			"PRE %s tick=%d pose=%d clip=%d share=%.3f away=%.3f"
			% [
				case,
				_clock.tick,
				ActivityPoses.pose(_sim, p),
				ActivityPoses.clip_ticks(_sim, p),
				ActivityPoses.share(_sim, p),
				away,
			]
		)
	)
	if not _move_piece(id, to):
		return
	var move_tick := _clock.tick
	await _frames(2)
	print(
		(
			"MOVE %s tick=%d piece=%d stage=%d sim_ghosts=%d drawn_ghosts=%d"
			% [case, move_tick, id, p.stage, Relocation.ghosts(_sim).size(), _views.ghosts.count()]
		)
	)
	var node := _views.node_for(p.id)
	var last_tick := _views.tick_position(p.id, true)
	var worst := 0.0
	var left_old := false
	var back := false
	var since_back := 0
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
		var ghosts := Relocation.ghosts(_sim).size()
		if p.stage == Passenger.Stage.SHOP_WALK:
			left_old = true
		if seated and not left_old and p.stage == Passenger.Stage.SHOP_BROWSE:
			var now_away := _away(p, seat)
			nearest = maxf(nearest, away - now_away)
			print(
				(
					"EXIT %s tick=%d pose=%d clip=%d away=%.3f nearer=%.4f"
					% [
						case,
						_clock.tick,
						ActivityPoses.pose(_sim, p),
						ActivityPoses.clip_ticks(_sim, p),
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
			await _keep_frame(case, p, old_centre, new_centre, step, ghosts)
		if back and since_back >= STRIP_STEP_TICKS * 3:
			break
	print(
		(
			"PROBE strip %s frames=%d worst_step=%.3f back=%s stage=%d user_at=%s new_centre=%s"
			% [case, _frames_kept.size(), worst, back, p.stage, node.global_position, new_centre]
		)
	)
	if not back:
		_invalid("%s: the visitor did not browse again at the moved piece" % case)
	if worst > MAX_STEP_M:
		_invalid("%s: the drawn visitor jumped %.3f m in one tick" % [case, worst])
	if seated:
		print("PROBE %s nearest_step_to_old_seat=%.4f" % [case, nearest])
		if nearest > NEARER_M:
			_invalid("%s: the sitter slid %.3f m into its old seat in one tick" % [case, nearest])
	if not _frames_kept.is_empty():
		_save(_sheet(_frames_kept), "shop_relocation_%s_strip.png" % case)


## The ground distance from the drawn body of `p` (the position the views
## recorded for this tick) to `spot`.
func _away(p: Passenger, spot: Vector3) -> float:
	var at := _views.tick_position(p.id, true)
	return Vector2(at.x, at.z).distance_to(Vector2(spot.x, spot.z))


func _keep_frame(
	case: String, p: Passenger, old_centre: Vector3, new_centre: Vector3, step: float, ghosts: int
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
	print(
		(
			"FRAME %s stage=%d at=%s step=%.3f sim_ghosts=%d drawn_ghosts=%d"
			% [label, p.stage, node.global_position, step, ghosts, _views.ghosts.count()]
		)
	)
	_save(img, "shop_relocation_%s.png" % label)
	_frames_kept.append(img)


func _in_frame(point: Vector3, label: String) -> bool:
	var frame := root.get_visible_rect().grow(-MARGIN_PX)
	var screen := _cam.unproject_position(point)
	var inside := frame.has_point(screen) and not _cam.is_position_behind(point)
	print("INFRAME %s screen=(%.0f,%.0f) ok=%s" % [label, screen.x, screen.y, inside])
	if not inside:
		_invalid("%s is outside the frame" % label)
	return inside


## The sight line from the camera to the visitor's head against the box of
## every visible mesh, except the build pieces, the ghosts and the passengers
## (the views) and any box that holds the head. Prints the blockers.
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
		_invalid("%s: the visitor is hidden by %s" % [label, blockers])
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
			OS.crash("shop relocation strip probe hung")
