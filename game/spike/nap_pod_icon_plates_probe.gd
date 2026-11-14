extends SceneTree
## Windowed plates of the need icons over a passenger reclined in a nap pod
## (board 4773e61e), seen through the real game camera (TycoonCamera at its
## 70 degree default step). Boots main.tscn, builds ActivityTestLayout's nap
## pod room with NeedFacilityKit's landside cafe (so a hunger icon may show:
## decision crowd-need-display-mood-overlay-gains-hunger-toilet-and-bore, point
## 3), opens the airport, sends one bored passenger with no bags into the pod,
## steps the clock by hand until it is fully reclined, then makes it hungry.
##
## Measures and prints, in the passenger node's own space (+z out of the pod,
## -z toward its back): the Head bone in the recline pose (HEAD), the head top
## (0.12 m over the bone, HEAD_TOP), the icon anchor in use (ANCHOR) and the
## top of the pod's meshes (POD_TOP). Per plate, in viewport pixels: GAP, from
## the head top up to the bottom of the icon row (under 0 means the row sits on
## the head), and the room label's projected position.
##
## Proofs before a plate is saved: the feet, the head and the icon anchor
## project inside the frame by MARGIN_PX and in front of the camera; a twin
## with the passenger hidden differs by MIN_DIFF_PX (the pod shell makes a ray
## test meaningless); a twin with the icons hidden differs by MIN_PART_PX (the
## icons are drawn). The HUD CanvasLayers are hidden, so no panel covers the
## subject (anti-pattern a-plate-probe-s-occlusion-rays-see-only-meshes-so-a-
## hud-pane). Otherwise PROBE_INVALID, exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/nap_pod_icon_plates_probe.gd -- [--seed=N] [--tag=T]
##
## Plates go to tools/blender/out/nap_pod_icon/, named <tag>_<shot>.png.

const StarterFlight := preload("res://spike/starter_flight.gd")
const OUT_REL := "res://../tools/blender/out/nap_pod_icon"
const MARGIN_PX := 8.0
const MIN_DIFF_PX := 300
const MIN_PART_PX := 40
const HANG_MS := 120000
const LIMIT_TICKS := 3000
const HEAD_TOP_M := 0.12
const STILL_TRIES := 40
## The shots: [name, rig yaw, rig distance in metres, or under 1 a fraction
## of the rig's home distance]. The close ones stand past NeedIcons.NEAR_FULL_M,
## so the icons are not faded; the distance one stays inside the home distance,
## where the icons still show (NeedIcons.shown_at).
const SHOTS := [
	["close_front", 0.35, 10.0],
	["close_side", 1.25, 10.0],
	["distance", 0.35, 0.8],
]

var _out_dir := ""
var _out_rel := OUT_REL
## The camera's angle steps plated: the 70 degree default, or with
## --steps=both also 38 degrees (board b679fd1d).
var _steps: Array[int] = [TycoonCamera.AngleStep.TOP_DOWN]
var _tag := "run"
var _failed := false
var _seed := 0
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
var _rig: TycoonCamera
var _cam: Camera3D
var _ids := {}
var _sheet: Array[Image] = []


func _initialize() -> void:
	_seed = randi()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--tag="):
			_tag = arg.get_slice("=", 1)
		elif arg == "--steps=both":
			_steps = [TycoonCamera.AngleStep.TOP_DOWN, TycoonCamera.AngleStep.LOW]
		elif arg.begins_with("--out="):
			_out_rel = "res://../tools/blender/out/" + arg.get_slice("=", 1)
	_out_dir = ProjectSettings.globalize_path(_out_rel).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE sim_seed=%d tag=%s out_dir=%s" % [_seed, _tag, _out_dir])
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	if await _boot():
		await _pod()
	if not _sheet.is_empty():
		_save(_contact_sheet(_sheet), "%s_contact_sheet.png" % _tag)
	print("PROBE done plates=%d failed=%s" % [_sheet.size(), _failed])
	_finish()
	quit(1 if _failed else 0)


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
	_ids = ActivityTestLayout.build(_mode.grid, &"nap_pod")
	NeedFacilityKit.add_landside_cafe(_mode.grid)
	if not StarterFlight.add_gate_desk(_mode.grid):
		_invalid("the gate desk was refused")
		return false
	(_mode.get_node("BuildView") as BuildView).refresh(_mode.grid)
	await _frames(4)
	_sim.shops.refresh()
	_sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(
		_clock, _main.get_node("FlightSim") as FlightSim, staff
	)
	print("PROBE ids=%s hired=%d opened tick=%d" % [_ids, hired, _clock.tick])
	if hired == 0 or doors < 0:
		_invalid("the airport did not open")
		return false
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_rig = _main.get_node("TycoonCamera") as TycoonCamera
	_cam = _rig.get_node("Camera3D") as Camera3D
	_cam.make_current()
	return true


func _pod() -> void:
	var id := _sim.spawn_now(FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0))
	var p := _sim.get_passenger(id)
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _clock.tick
	p.at = ShopTestLayout.AIRSIDE_CELL + ReferenceTerminal.offset_on(_mode.grid)
	p.clear_path()
	p.boredom = 80
	p.shop_cooldown = 0
	NeedsPolicy.arbitrate(_sim, p)
	if _sim.shops.visit_of(id) == null:
		_invalid("the passenger did not commit to the nap pod")
		return
	var reclined := func() -> bool:
		return ActivityPoses.recline(_sim, p) >= 1.0 and _clock.tick - p.stage_tick >= 40
	if not await _until(reclined):
		_invalid("the visitor never reclined")
		return
	p.hunger = CafeSim.HUNGER_MAX
	var overlay := _main.get_node("MoodOverlay") as MoodOverlay
	overlay.set_mode(MoodTint.Mode.HUNGER)
	overlay.set_shown(true)
	if not await _until(
		func() -> bool: return int(_views.node_for(id).get_meta(&"needs", 0)) > 0, 40
	):
		_invalid("no need icon came up over the reclined visitor")
		return
	_clock.set_paused(true)
	await _frames(4)
	var node := _views.node_for(id)
	var pose := ActivityPoses.pose(_sim, p)
	var lean := ActivityPoses.recline(_sim, p)
	print(
		(
			"POSE id=%d kind=%s pose=%s recline=%.2f clip=%s icon_seated=%s icon_reclined=%s"
			% [
				id,
				ActivityPoses.Kind.keys()[ActivityPoses.kind(_sim, p)],
				StageKinds.Pose.keys()[pose],
				lean,
				node.get_meta(&"clip", ""),
				node.get_meta(&"icon_seated", false),
				node.get_meta(&"icon_reclined", false),
			]
		)
	)
	if pose != StageKinds.Pose.SEATED or lean < 1.0:
		_invalid("the visitor is not in the full recline pose")
		return
	var to_local := node.global_transform.affine_inverse()
	var head := _head_point(node)
	print("HEAD local=%s world=%s" % [to_local * head, head])
	print("HEAD_TOP local=%s" % [to_local * (head + Vector3.UP * HEAD_TOP_M)])
	print("ANCHOR head_anchor=%s" % [NeedIcons.head_anchor(node)])
	print("POD_TOP m=%.2f" % _pod_top())
	var tag := _tag
	for step in _steps:
		# Set directly: set_angle_step() would save the angle to the user's settings.
		_rig.angle_step = step as TycoonCamera.AngleStep
		if _steps.size() > 1:
			_tag = "%s_%ddeg" % [tag, int(TycoonCamera.STEP_PITCH_DEGREES[step])]
		for shot: Array in SHOTS:
			await _plate(shot[0], shot[1], shot[2], node)
	_tag = tag


## One plate through the game camera, its focus on the passenger.
func _plate(shot: String, yaw: float, distance: float, node: Node3D) -> void:
	_beat(shot)
	if distance < 1.0:
		distance *= _rig.home_distance
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)
	_rig.position = node.global_position * Vector3(1, 0, 1)
	await _frames(8)
	var tag := "%s_%s" % [_tag, shot]
	# Control: the frame holds still (two grabs a few frames apart differ by
	# under MIN_PART_PX), so the numbers and the twins below measure the toggled part alone.
	var img := _grab()
	var still := -1
	for i in STILL_TRIES:
		await _frames(3)
		var next := _grab()
		still = _diff(img, next)
		img = next
		if still < MIN_PART_PX:
			break
	print("STILL %s control_diff_px=%d" % [tag, still])
	if still >= MIN_PART_PX:
		_invalid("%s: the frame never held still (%d)" % [tag, still])
	var head := _head_point(node)
	var top := head + Vector3.UP * HEAD_TOP_M
	var first := node.get_node(NeedIcons.SPRITES[0]) as Sprite3D
	var anchor := node.global_transform * first.position
	var ok := _in_frame(node.global_position, tag + " feet")
	ok = _in_frame(top, tag + " head_top") and ok
	ok = _in_frame(anchor, tag + " anchor") and ok
	var rects := _icon_rects(node)
	var gap := INF
	var top_px := _cam.unproject_position(top)
	for rect in rects:
		gap = minf(gap, top_px.y - rect.end.y)
	print(
		(
			(
				"PLATE %s cam_dist_m=%.2f home_m=%.1f pitch=%.0f icons=%d GAP_px=%.1f "
				+ "head_top_px=%s rects=%s"
			)
			% [
				tag,
				_cam.global_position.distance_to(node.global_position),
				_rig.home_distance,
				_rig.pitch_degrees(),
				rects.size(),
				gap,
				top_px.round(),
				rects
			]
		)
	)
	_print_labels(tag, rects)
	if rects.is_empty():
		_invalid("%s: no icon of the subject is drawn" % tag)
	node.visible = false
	await _frames(3)
	var hidden := _diff(img, _grab())
	node.visible = true
	# The icons off by closing the overlay (PassengerViews lays the sprites out
	# every frame, so hiding a sprite would not hold).
	_views.mood_overlay.set_shown(false)
	await _frames(3)
	var no_icons := _diff(img, _grab())
	_views.mood_overlay.set_shown(true)
	await _frames(3)
	print(
		(
			"VISIBLE %s subject_diff_px=%d need=%d icons_diff_px=%d need=%d"
			% [tag, hidden, MIN_DIFF_PX, no_icons, MIN_PART_PX]
		)
	)
	if not ok or hidden < MIN_DIFF_PX or no_icons < MIN_PART_PX:
		_invalid("%s: subject or icons not shown (in_frame=%s)" % [tag, ok])
	_save(img, tag + ".png")
	_sheet.append(img)
	if distance <= 20.0:
		var to_image := Vector2(img.get_size()) / root.get_visible_rect().size
		var centre := Vector2i(top_px * to_image) - Vector2i(110, 140)
		var crop := Rect2i(centre, Vector2i(220, 220)).intersection(
			Rect2i(Vector2i.ZERO, img.get_size())
		)
		var small := img.get_region(crop)
		small.resize(small.get_width() * 3, small.get_height() * 3, Image.INTERPOLATE_NEAREST)
		_save(small, tag + "_crop.png")


## Prints each room label's projected position and whether an icon rect of the
## subject covers it.
func _print_labels(tag: String, rects: Array[Rect2]) -> void:
	for label in _main.find_children("*", "Label3D", true, false):
		var l := label as Label3D
		if not l.visible or l.text == "" or l.name == "Bubble":
			continue
		if not (l.get_parent() is RoomView or l.get_parent().get_parent() is RoomView):
			continue
		var at := l.global_position
		if _cam.is_position_behind(at):
			continue
		var px := _cam.unproject_position(at) + l.offset * Vector2(1, -1)
		var covered := false
		for rect in rects:
			covered = covered or rect.grow(20.0).has_point(px)
		print(
			(
				"LABEL %s text=%s px=%s near_icon=%s"
				% [tag, l.text.replace("\n", "|"), px.round(), covered]
			)
		)


## The world position of a passenger's Head bone.
func _head_point(node: Node3D) -> Vector3:
	var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := skeleton.find_bone("Head")
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


## The top of the meshes BuildView draws within 1.5 m of the pod, over the floor.
func _pod_top() -> float:
	var spot := ActivityPoses.spot_of(_mode.grid, _mode.grid.get_object(_ids["use"]), 0)
	var top := 0.0
	for mesh in _mode.get_node("BuildView").find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var box := mi.global_transform * mi.get_aabb()
		var centre := box.get_center()
		if Vector2(centre.x - spot.x, centre.z - spot.z).length() < 1.5 and box.size.y < 2.6:
			top = maxf(top, box.end.y - spot.y)
	return top


## Screen rectangles of the icons a passenger node shows (ICON_PX squares).
func _icon_rects(node: Node3D) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var k := NeedIcons.ICON_PX / NeedIcons.SIZE
	for sprite_name in NeedIcons.SPRITES:
		var sprite := node.get_node(sprite_name) as Sprite3D
		if not sprite.visible:
			continue
		var anchor := node.global_transform * sprite.position
		if _cam.is_position_behind(anchor):
			continue
		var centre := (
			_cam.unproject_position(anchor) + Vector2(sprite.offset.x * k, -sprite.offset.y * k)
		)
		out.append(
			Rect2(centre - Vector2.ONE * NeedIcons.ICON_PX / 2.0, Vector2.ONE * NeedIcons.ICON_PX)
		)
	return out


func _until(done: Callable, limit := LIMIT_TICKS) -> bool:
	_clock.set_paused(false)
	var until := _clock.tick + limit
	while not done.call() and _clock.tick < until:
		_clock.advance(SimClock.STEP)
		if _clock.tick % 10 == 0:
			_beat("tick %d" % _clock.tick)
			await process_frame
	return done.call()


func _in_frame(point: Vector3, label: String) -> bool:
	var rect := root.get_visible_rect().grow(-MARGIN_PX)
	var behind := _cam.is_position_behind(point)
	var screen := _cam.unproject_position(point)
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
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var sheet := Image.create(w * plates.size(), h, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
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
			OS.crash("nap_pod_icon_plates_probe: main thread stalled in %s" % stage)
