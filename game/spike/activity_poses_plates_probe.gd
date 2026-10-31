extends SceneTree
## Windowed plates of the activity poses (ActivityPoses; decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod) in the real
## main scene. For each of the lounge, the nap pod and the shower the probe
## boots main.tscn, builds the reference terminal on the shell with a ready
## room of that type (ActivityTestLayout, the piece in the room's north-west
## corner facing south), opens the airport and sends bored passengers with no
## bags into the room, stepping the clock by hand. A 1 m reference cube stands
## on the floor beside the piece.
##
## Plates (true scale: the orthographic ones are 3 m tall):
##   lounge_front, lounge_side, lounge_top, lounge_game: two visitors seated
##   lounge_strip_sit, lounge_strip_up: a visitor sitting down and standing up,
##     every third tick (the clip sought to the tick, the clock frozen)
##   pod_front, pod_section (side view, the near shell cut away), pod_game
##   shower_front, shower_side, shower_top, shower_game (icons over the foam)
##   distance: the shower room from 12 m
## The shower's foam, steam and need icon are each proven by a twin.
## Proofs before a save: each subject point (feet and chest) projects inside
## the frame with a margin, and a twin with the subject hidden differs from the
## plate by at least MIN_DIFF_PX pixels, so the subject is drawn and not hidden
## (glass and pod shells make a ray test meaningless here). The foam, the
## recline and the shower icons are each proven the same way by a twin with
## only that part hidden or switched off. Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/activity_poses_plates_probe.gd
##
## Plates go to tools/blender/out/activity_poses/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/activity_poses"
const MARGIN_PX := 8.0
const MIN_DIFF_PX := 300
const MIN_PART_PX := 40
const ORTHO_M := 3.0
const HANG_MS := 120000
const CUBE_CELL := Vector2i(24, 5)
const STRIP_FRAMES := 9
const STRIP_STEP := 3
const LIMIT_TICKS := 3000
## Where the pod section view cuts, out from the pod's middle.
const SECTION_M := 0.34

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false
var _seed := 0

var _main: Node3D
var _sim: PassengerSim
var _clock: SimClock
var _mode: BuildMode
var _views: PassengerViews
var _ids := {}
var _sheet: Array[Image] = []
## Passenger id -> [clip, ticks since it started], to seek clips while frozen.
var _clips := {}


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_seed = randi()
	print("PROBE sim_seed=%d out_dir=%s" % [_seed, _out_dir])
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	for type: StringName in [&"lounge", &"nap_pod", &"shower"]:
		if not await _boot(type):
			continue
		match type:
			&"lounge":
				await _lounge()
			&"nap_pod":
				await _pod()
			&"shower":
				await _shower()
		_main.queue_free()
		await _frames(3)
	if not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "contact_sheet.png")
	print("PROBE done plates=%d failed=%s" % [_sheet.size(), _failed])
	_finish()
	quit(1 if _failed else 0)


func _boot(type: StringName) -> bool:
	_beat("boot " + type)
	_clips.clear()
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(_seed)
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
	_ids = ActivityTestLayout.build(_mode.grid, type, _mode.shell)
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.shops.refresh()
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE %s ids=%s hired=%d opened tick=%d" % [type, _ids, hired, _clock.tick])
	if hired == 0 or doors < 0:
		_invalid("%s: the airport did not open" % type)
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var cube := MeshInstance3D.new()
	var box := BoxMesh.new()
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.55, 0.55, 0.6)
	box.material = grey
	cube.mesh = box
	cube.position = _mode.grid.cell_to_world(CUBE_CELL) + Vector3(0.0, 0.5, 0.0)
	_main.add_child(cube)
	return true


## A bored passenger with no bags that commits to the room's piece.
func _visitor() -> Passenger:
	var id := _sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
	var p := _sim.get_passenger(id)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = ShopTestLayout.AIRSIDE_CELL
	p.clear_path()
	p.boredom = 80
	p.shop_cooldown = 0
	NeedsPolicy.arbitrate(_sim, p)
	var visit := _sim.shops.visit_of(id)
	print("VISITOR %d visit=%s" % [id, "none" if visit == null else visit.slot_key()])
	if visit == null:
		_invalid("passenger %d did not commit to the room" % id)
	return p


func _lounge() -> void:
	var a := _visitor()
	var b := _visitor()
	if not await _until(func() -> bool: return a.stage == Passenger.Stage.SHOP_BROWSE):
		_invalid("lounge: the first visitor never reached the sofa")
		return
	await _strip("lounge_strip_sit", a, STRIP_FRAMES)
	var seated := func() -> bool:
		for p in [a, b]:
			var sat := ActivityPoses.pose(_sim, p) == StageKinds.Pose.SEATED
			if not sat or _clock.tick - p.stage_tick < 40:
				return false
		return true
	if not await _until(seated):
		_invalid("lounge: both visitors never sat")
		return
	var spot := _spot()
	await _ortho_set("lounge", spot, [a.id, b.id], ["front", "side", "top"])
	await _plate("lounge_game", _game_cam(spot), [a.id, b.id])
	var getting_up := func() -> bool:
		return ActivityPoses.pose(_sim, a) == StageKinds.Pose.STANDING_UP
	if not await _until(getting_up):
		_invalid("lounge: the visitor never stood up")
		return
	await _strip("lounge_strip_up", a, STRIP_FRAMES)


func _pod() -> void:
	var p := _visitor()
	var reclined := func() -> bool: return ActivityPoses.recline(_sim, p) >= 1.0
	if not await _until(reclined):
		_invalid("pod: the visitor never reclined")
		return
	var spot := _spot()
	await _plate("pod_front", _ortho(spot, Vector3(0, 0, 1)), [p.id])
	# The side view through the pod's near shell (the pod is one mesh): the
	# camera's near plane cuts the piece SECTION_M from its middle, inside the
	# shell and clear of the body (elbows at 0.31 m).
	var cut := _ortho(spot, Vector3(1, 0, 0))
	cut.near = cut.global_position.x - spot.x - SECTION_M
	await _plate("pod_section", cut, [p.id])
	var cam := _game_cam(spot)
	await _plate("pod_game", cam, [p.id], true)
	# Control: the same view with the recline switched off differs.
	var recline := _views.node_for(p.id).get_meta(&"recline") as PodRecline
	await _part_twin(
		"pod_recline", cam, func(on: bool) -> void: recline.amount = 1.0 if on else 0.0
	)
	cam.queue_free()


func _shower() -> void:
	var p := _visitor()
	var in_foam := func() -> bool:
		return ActivityPoses.foam(_sim, p) >= 1.0 and _clock.tick - p.stage_tick >= 40
	if not await _until(in_foam):
		_invalid("shower: the visitor never got under the foam")
		return
	# A need to show over the foam (there is no cafe for it to go to).
	p.hunger = CafeSim.HUNGER_MAX
	await _until(func() -> bool: return int(_views.node_for(p.id).get_meta(&"needs", 0)) > 0, 40)
	var spot := _spot()
	await _ortho_set("shower", spot, [p.id], ["front", "side", "top"])
	var cam := _game_cam(spot)
	await _plate("shower_game", cam, [p.id], true)
	var node := _views.node_for(p.id)
	var foam := node.get_node("ShowerFoam") as ShowerFoam
	print(
		(
			"SHOWER foam=%.2f balls=%d needs=%d"
			% [foam.amount, foam.balls_shown(), node.get_meta(&"needs", 0)]
		)
	)
	await _part_twin("shower_foam", cam, func(on: bool) -> void: foam.visible = on)
	var steam := node.get_node("ShowerFoam/Steam") as Node3D
	await _part_twin("shower_steam", cam, func(on: bool) -> void: steam.visible = on)
	var icons: Array[Node3D] = []
	for sprite_name in NeedIcons.SPRITES:
		var sprite := node.get_node(sprite_name) as Node3D
		if sprite.visible:
			icons.append(sprite)
	if icons.is_empty():
		_invalid("shower: no need icon showed over the foam")
	else:
		await _part_twin(
			"shower_icons",
			cam,
			func(on: bool) -> void:
				for icon in icons:
					icon.visible = on
		)
	cam.queue_free()
	var far := Camera3D.new()
	far.fov = 40.0
	_main.add_child(far)
	far.look_at_from_position(spot + Vector3(5.0, 9.0, 7.5), spot)
	await _plate("distance", far, [p.id])


## Where the room's piece is drawn, on the floor.
func _spot() -> Vector3:
	var record := _mode.grid.get_object(_ids["use"])
	var def := BuildCatalog.get_def(record["def"])
	var frame := BuildView.object_transform(
		_mode.grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
	)
	return frame.origin


## Steps the clock by hand until `done` holds; false when LIMIT_TICKS pass.
func _until(done: Callable, limit := LIMIT_TICKS) -> bool:
	_clock.set_paused(false)
	var until := _clock.tick + limit
	while not done.call() and _clock.tick < until:
		_tick()
		if _clock.tick % 10 == 0:
			_beat("tick %d" % _clock.tick)
			await process_frame
	return done.call()


func _tick() -> void:
	_clock.set_paused(false)
	_clock.advance(SimClock.STEP)
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		var clip: String = node.get_meta(&"clip", "")
		var was: Array = _clips.get(id, ["", 0])
		_clips[id] = [clip, 0 if was[0] != clip else int(was[1]) + 1]


## A frozen frame strip of `p` from a 3/4 camera, the clips sought to the
## ticks they have played, every STRIP_STEP ticks.
func _strip(file: String, p: Passenger, count: int) -> void:
	var frames: Array[Image] = []
	var cam := _game_cam(_spot(), 3.0)
	var ok := true
	for i in count:
		_clock.set_paused(true)
		_seek_clips()
		cam.make_current()
		await _frames(3)
		var node := _views.node_for(p.id)
		ok = _in_frame(cam, node.global_position + Vector3.UP * 0.9, "%s[%d]" % [file, i]) and ok
		print(
			(
				"STRIP %s[%d] tick=%d clip=%s share=%.2f at=%s"
				% [
					file,
					i,
					_clock.tick,
					node.get_meta(&"clip", ""),
					ActivityPoses.share(_sim, p),
					node.global_position
				]
			)
		)
		var img := _grab()
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		frames.append(img)
		for k in STRIP_STEP:
			_tick()
	cam.queue_free()
	if not ok:
		_invalid("%s: subject out of frame" % file)
	var row := _row(frames)
	_save(row, file + ".png")


func _seek_clips() -> void:
	for id in _clips:
		var node := _views.node_for(id)
		if node == null:
			continue
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		var base: float = node.get_meta(&"base_speed", 1.0)
		if player.current_animation != "":
			player.seek(_clips[id][1] * SimClock.STEP * base, true)


func _ortho_set(prefix: String, spot: Vector3, ids: Array[int], views: Array) -> void:
	var dirs := {"front": Vector3(0, 0, 1), "side": Vector3(1, 0, 0), "top": Vector3.UP}
	for view: String in views:
		await _plate("%s_%s" % [prefix, view], _ortho(spot, dirs[view]), ids)


## A true-scale orthographic camera ORTHO_M tall looking at `spot` (1 m up)
## from `dir`, close enough to stay inside the room.
func _ortho(spot: Vector3, dir: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ORTHO_M
	cam.near = 0.05
	_main.add_child(cam)
	var target := spot + Vector3(0.6, 1.0, 0.4)
	if dir == Vector3.UP:
		cam.look_at_from_position(target + Vector3(0.0, 1.7, 0.001), target)
	else:
		cam.look_at_from_position(target + dir * 3.2, target)
	return cam


## A camera from the front right and above, at about the game's angle.
func _game_cam(spot: Vector3, back := 3.5) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 40.0
	_main.add_child(cam)
	cam.look_at_from_position(spot + Vector3(1.6, 3.0, back), spot + Vector3(0.0, 0.9, 0.4))
	return cam


## Saves a plate after proving each subject in frame and drawn: a twin with
## the subjects hidden must differ by MIN_DIFF_PX pixels.
func _plate(file: String, cam: Camera3D, ids: Array[int], keep := false) -> void:
	_beat(file)
	_clock.set_paused(true)
	cam.make_current()
	await _frames(4)
	var ok := true
	for id in ids:
		var node := _views.node_for(id)
		for up in [0.1, 1.1]:
			ok = (
				_in_frame(cam, node.global_position + Vector3.UP * up, "%s p%d" % [file, id]) and ok
			)
	var img := _grab()
	for id in ids:
		_views.node_for(id).visible = false
	await _frames(3)
	var bare := _grab()
	for id in ids:
		_views.node_for(id).visible = true
	var diff := _diff(img, bare)
	print("VISIBLE %s subjects=%s diff_px=%d need=%d" % [file, ids, diff, MIN_DIFF_PX])
	if not ok or diff < MIN_DIFF_PX:
		_invalid("%s: subject not shown (in_frame=%s diff=%d)" % [file, ok, diff])
	_save(img, file + ".png")
	_sheet.append(img)
	if not keep:
		cam.queue_free()


## Proves one part of a subject drawn: the frame with `toggle` on differs from
## it with `toggle` off by MIN_PART_PX pixels.
func _part_twin(label: String, cam: Camera3D, toggle: Callable) -> void:
	cam.make_current()
	toggle.call(true)
	await _frames(3)
	var on := _grab()
	toggle.call(false)
	await _frames(3)
	var off := _grab()
	toggle.call(true)
	var diff := _diff(on, off)
	print("PART %s diff_px=%d need=%d" % [label, diff, MIN_PART_PX])
	if diff < MIN_PART_PX:
		_invalid("%s: the part is not drawn (diff %d)" % [label, diff])


func _in_frame(cam: Camera3D, point: Vector3, label: String) -> bool:
	var rect := root.get_visible_rect().grow(-MARGIN_PX)
	var behind := cam.is_position_behind(point)
	var screen := cam.unproject_position(point)
	var ok := not behind and rect.has_point(screen)
	print("INFRAME %s screen=(%.0f,%.0f) frame=%s ok=%s" % [label, screen.x, screen.y, rect, ok])
	return ok


func _diff(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				count += 4
	return count


func _grab() -> Image:
	return root.get_texture().get_image()


## Frames in reading order, three to a row.
func _row(frames: Array[Image]) -> Image:
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var rows := ceili(frames.size() / 3.0)
	var sheet := Image.create(w * 3, h * rows, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var frame := frames[i]
		frame.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(w * (i % 3), h * (i / 3))
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), at)
	return sheet


func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 3
	var h := plates[0].get_height() / 3
	var rows := ceili(plates.size() / 3.0)
	var sheet := Image.create(w * 3, h * rows, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * (i % 3), h * (i / 3)))
	return sheet


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
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
			OS.crash("activity_poses_plates_probe: main thread stalled in %s" % stage)
