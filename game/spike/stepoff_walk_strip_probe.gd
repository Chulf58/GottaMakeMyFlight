extends SceneTree
## Windowed frame strips of a passenger with a roller stepping off its seat
## after it has stood up and picked the roller up (board c0707a22 part 3): a
## cafe guest's last CafeSim.SHUFFLE_TICKS of CAFE_STANDING_UP and a lounge
## sofa visitor's step off in its ActivityPoses.up_tail(). The body should walk
## (the walk clip at the drawn step's speed), not slide under a held stand_up
## or an idle clip.
## For each subject the probe boots main.tscn, builds the reference terminal
## with a cafe (CafeTestLayout) or a ready lounge room (ActivityTestLayout),
## opens the airport and sends one passenger with one roller to it. The clock
## is stepped fast to shortly before the stand-up, then a third of a tick a
## frame (60 frames a second, as in the game).
## Each strip frame is taken on a whole tick: STRIP_TICKS from the first tick
## the drawn body moves after its stand-up began (the hold's end), cropped
## around the step. Before a frame is kept, the feet and the head project
## inside the frame with a margin and a twin with the body hidden differs from
## it (in frame is not visible); otherwise PROBE_INVALID, exit 1. Per frame it
## prints the clip, its speed, the drawn step and the angle between the body's
## facing and its step (pass values are positives: frames kept, steps drawn).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/stepoff_walk_strip_probe.gd \
##     [-- --seed=N --label=after]
##
## Strips go to tools/blender/out/stepoff-walk/<label>_<subject>_strip.png.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/stepoff-walk"
const SUBJECTS: Array[String] = ["cafe", "lounge"]
const MARGIN_PX := 8.0
const MIN_BODY_PX := 150.0
const MIN_DIFF_PX := 1500
const LIMIT_TICKS := 6000
const LEAD_TICKS := 6
## Strip frames, in ticks from the first tick the body moves after its hold.
const STRIP_TICKS: Array[int] = [-2, 0, 2, 4, 6, 8, 10, 13]
const CROP := Vector2i(820, 620)
const CROP_MARGIN_PX := 70.0

var _seed := 0
var _label := "after"
var _out_dir := ""
var _failed := false
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _cam: Camera3D
var _strips := 0


func _initialize() -> void:
	Engine.max_fps = SimClock.TICK_RATE * 3
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		if arg.begins_with("--label="):
			_label = arg.get_slice("=", 1)
	print("PROBE sim_seed=%d label=%s out_dir=%s" % [_seed, _label, _out_dir])
	_run.call_deferred()


func _run() -> void:
	for subject in SUBJECTS:
		if await _boot(subject):
			await _watch(subject)
		_main.queue_free()
		_cam = null
		await _frames(3)
	print("PROBE done strips=%d failed=%s" % [_strips, _failed])
	quit(1 if _failed or _strips < SUBJECTS.size() else 0)


func _boot(subject: String) -> bool:
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
	if subject == "cafe":
		CafeTestLayout.build(_mode.grid)
	else:
		ActivityTestLayout.build(_mode.grid, &"lounge")
	if not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("%s: the gate desk was refused" % subject)
		return false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.cafes.refresh()
	_sim.shops.refresh()
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE %s hired=%d opened tick=%d" % [subject, hired, _clock.tick])
	if hired == 0 or doors < 0:
		_invalid("%s: the airport did not open" % subject)
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	return true


## One passenger with one roller, airside on its way to the gate, committed to
## the cafe (hungry) or to the sofa (bored).
func _visitor(subject: String) -> Passenger:
	var p: Passenger = null
	for attempt in 200:
		p = _sim.get_passenger(
			_sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
		)
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(_mode.grid)
	p.clear_path()
	p.shop_cooldown = 0
	if subject == "cafe":
		p.boredom = 0
		_sim.cafes.try_visit(p)
	else:
		p.hunger = 0
		p.boredom = 80
		NeedsPolicy.arbitrate(_sim, p)
	var committed := (
		_sim.cafes.visit_of(p.id) != null
		if subject == "cafe"
		else _sim.shops.visit_of(p.id) != null
	)
	print(
		(
			"VISITOR %s id=%d roller=%s committed=%s late=%s"
			% [subject, p.id, ParkRecovery.has_roller(p), committed, p.late]
		)
	)
	if not committed or not ParkRecovery.has_roller(p):
		_invalid("%s: passenger %d did not commit to the visit with a roller" % [subject, p.id])
		return null
	return p


## Ticks until `p` starts to stand up (LIMIT when unknown).
func _ticks_to_up(p: Passenger) -> int:
	if p.stage == Passenger.Stage.CAFE_SEATED:
		return _sim.cafes.visit_of(p.id).dwell_end - _clock.tick
	if (
		p.stage == Passenger.Stage.SHOP_BROWSE
		and ActivityPoses.pose(_sim, p) == StageKinds.Pose.SEATED
	):
		var visit := _sim.shops.visit_of(p.id)
		var type := RoomTypes.get_type(_sim.grid.get_room(visit.room)["type"])
		var end := mini(p.stage_tick + ShopSim.stay_ticks(visit, type), visit.deadline)
		var up := end - PassengerSim.STAND_UP_TICKS - ActivityPoses.up_tail(_sim, p)
		return up - _clock.tick
	return LIMIT_TICKS


## Where the step off goes: [from (the seat root), to (where it steps to)].
func _step_ends(subject: String, p: Passenger) -> Array[Vector3]:
	if subject == "cafe":
		var visit := _sim.cafes.visit_of(p.id)
		var approach := _sim.grid.cell_to_world(visit.seat["approach"])
		return [BuildObjectDef.seat_root_world(_sim.grid, visit.seat), approach]
	return [_sim.world_position(p) + ActivityPoses.offset(_sim, p), _sim.world_position(p)]


func _watch(subject: String) -> void:
	var p := _visitor(subject)
	if p == null:
		return
	var until := _clock.tick + LIMIT_TICKS
	while _clock.tick < until and _ticks_to_up(p) > LEAD_TICKS:
		_clock.advance(SimClock.STEP)
		if _clock.tick % 10 == 0:
			await process_frame
	if _ticks_to_up(p) > LEAD_TICKS or _ticks_to_up(p) < 0:
		_invalid("%s: never seated before the stand-up (%d)" % [subject, _ticks_to_up(p)])
		return
	var ends := _step_ends(subject, p)
	var up_at := _clock.tick + _ticks_to_up(p)
	print(
		(
			"PROBE %s seated, stand-up at tick %d, step from %s to %s (%.3f m)"
			% [subject, up_at, ends[0], ends[1], ends[0].distance_to(ends[1])]
		)
	)
	# The strip counts from the hold's end, where the step off should begin;
	# the first tick the drawn body really moves after the rise is printed
	# beside it (STEP_START).
	var hold := ParkRecovery.UP_HOLD_TICKS if subject == "cafe" else ActivityPoses.SEAT_HOLD_TICKS
	var start := up_at + PassengerSim.STAND_UP_TICKS + hold
	_place_camera(ends)
	var moved_at := -1
	var moves := 0
	var frames: Array[Image] = []
	var rows: Array[String] = []
	var last_tick := -1
	var stop := start + STRIP_TICKS[STRIP_TICKS.size() - 1]
	while _clock.tick < stop:
		await _step()
		var body := _views.node_for(p.id)
		if body == null:
			break
		if _clock.tick == last_tick:
			continue
		last_tick = _clock.tick
		var step := _views.tick_position(p.id, true) - _views.tick_position(p.id, false)
		var mm := roundi(step.length() * 1000.0)
		if _clock.tick >= up_at + PassengerSim.STAND_UP_TICKS and mm > 0:
			moves += 1
			if moved_at < 0:
				moved_at = _clock.tick
		var at := _clock.tick - start
		if at in STRIP_TICKS:
			var row := _row(p, body, step, mm)
			var shot := await _frame(subject, at, p, body, ends)
			if shot == null:
				return
			frames.append(shot)
			rows.append("%+d %s" % [at, row])
	for line in rows:
		print("STRIP %s %s %s" % [_label, subject, line])
	print(
		(
			"STEP_START %s hold end tick %d, first drawn step after the rise tick %d, %d ticks moved (> 0)"
			% [subject, start, moved_at, moves]
		)
	)
	if moves == 0 or frames.size() < STRIP_TICKS.size():
		_invalid("%s: strip incomplete (%d moves, %d frames)" % [subject, moves, frames.size()])
		return
	_save(_strip(frames), "%s_%s_strip.png" % [_label, subject])
	_strips += 1


## The clip, its speed and position, the drawn step and the facing.
func _row(p: Passenger, body: Node3D, step: Vector3, mm: int) -> String:
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	var ahead := body.global_transform.basis.z
	var off := 0.0
	if mm > 0:
		off = rad_to_deg(Vector2(ahead.x, ahead.z).angle_to(Vector2(step.x, step.z)))
	return (
		"tick %d stage %d clip %s pos %.2f base %.3f step %d mm facing-to-step %.0f deg"
		% [
			_clock.tick,
			p.stage,
			player.current_animation,
			player.current_animation_position,
			body.get_meta(&"base_speed", 0.0),
			mm,
			off,
		]
	)


## A camera side-on to the step, a little above and behind it, kept.
func _place_camera(ends: Array[Vector3]) -> void:
	var along := ends[1] - ends[0]
	along.y = 0.0
	along = along.normalized()
	var side := along.cross(Vector3.UP)
	var target := (ends[0] + ends[1]) * 0.5 + Vector3.UP * 0.8
	var away := (side * 1.0 - along * 0.25).normalized()
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_main.add_child(_cam)
	_cam.look_at_from_position(target + away * 5.6 + Vector3.UP * 1.8, target, Vector3.UP)
	_cam.current = true


## One strip frame of `body`, proven in frame and visible, cropped.
func _frame(subject: String, at: int, p: Passenger, body: Node3D, ends: Array[Vector3]) -> Image:
	await _frames(1)
	var img := root.get_texture().get_image()
	var size := Vector2(img.get_size())
	var inside := Rect2(Vector2.ONE * MARGIN_PX, size - Vector2.ONE * 2.0 * MARGIN_PX)
	var feet := body.global_position
	var head := feet + Vector3.UP * 1.7
	var flat := {}
	for name: String in {"feet": feet, "head": head}:
		var point: Vector3 = feet if name == "feet" else head
		var px := _cam.unproject_position(point)
		flat[name] = px
		if _cam.is_position_behind(point) or not inside.has_point(px):
			_invalid("%s %+d: %s at %s is out of frame %s" % [subject, at, name, px, size])
			return null
	var tall := (flat["feet"] as Vector2).distance_to(flat["head"])
	body.visible = false
	await _frames(2)
	var no_body := root.get_texture().get_image()
	body.visible = true
	await _frames(1)
	var body_px := _diff(img, no_body)
	print(
		(
			"FRAME %s %+d tick %d stage %d feet=%s head=%s body_px=%.0f body_diff=%d"
			% [subject, at, _clock.tick, p.stage, flat["feet"], flat["head"], tall, body_px]
		)
	)
	if tall < MIN_BODY_PX or body_px < MIN_DIFF_PX:
		_invalid("%s %+d: body %.0f px tall, %d px from the body" % [subject, at, tall, body_px])
		return null
	var mid := _cam.unproject_position(ends[0].lerp(ends[1], 0.65) + Vector3.UP * 0.85)
	var corner := Vector2i(mid) - CROP / 2
	corner.x = clampi(corner.x, 0, img.get_width() - CROP.x)
	corner.y = clampi(corner.y, 0, img.get_height() - CROP.y)
	# The body's half width and its arms swing past the feet and head points.
	var kept := Rect2(Vector2(corner), Vector2(CROP)).grow(-CROP_MARGIN_PX)
	if not kept.has_point(flat["feet"]) or not kept.has_point(flat["head"]):
		_invalid("%s %+d: feet or head outside the crop %s" % [subject, at, kept])
		return null
	var crop := img.get_region(Rect2i(corner, CROP))
	crop.convert(Image.FORMAT_RGBA8)
	return crop


func _strip(frames: Array[Image]) -> Image:
	var gap := 4
	var strip := Image.create(
		(CROP.x + gap) * frames.size() - gap, CROP.y, false, Image.FORMAT_RGBA8
	)
	strip.fill(Color(0.1, 0.1, 0.1))
	for i in frames.size():
		strip.blit_rect(frames[i], Rect2i(Vector2i.ZERO, CROP), Vector2i((CROP.x + gap) * i, 0))
	return strip


func _step() -> void:
	_clock.advance(SimClock.STEP / 3.0)
	await _frames(1)


func _diff(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				count += 4
	return count


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
