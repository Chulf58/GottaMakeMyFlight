extends SceneTree
## Windowed measurement and plates of the need-icon anchor while a passenger
## stands up from a gate chair (board 3a5e1d0d: during STANDING_UP the icons
## took the standing anchor at once and sat on the head or chest for the
## clip's 1.2 s). Boots main.tscn with NeedFacilityKit's terminal and a gate
## desk, sends in a crowd and steps the clock until SEATED_WANT passengers sit
## at the gate, then freezes one of them (the subject) in STANDING_UP at chosen
## ticks of the clip: the stage is set by hand with the clock paused and
## PassengerViews.snap() starts the clip where the sim is in it, as a load
## does.
##
## The head path: at every SAMPLE_TICKS tick of the clip it prints the Head
## bone in the subject node's space (the space NeedIcons.head_anchor() answers
## in), the anchor and head_top() the game gives it, and through the game
## camera (70 degrees, CLOSE_M, at each of SCREEN_YAWS) the screen pixels the
## anchor stands over the bone-measured head top (positive is over).
## Plates: the subject at the start and the middle of the clip at close zoom,
## and a distance shot; a _marked copy crosses the bone-measured head top
## (blue) and the anchor (red), and a _crop is the THUMB around the head. The
## subject has two needs, the rest of the crowd none, so its icon row is the
## only one.
## Proofs before a plate is saved: the subject's head and anchor inside the
## frame by MARGIN_PX, and a physics ray from the camera to its head not
## blocked. The HUD CanvasLayers are hidden. Otherwise PROBE_INVALID, exit 1.
## PROBE_SEED replays a seed; PROBE_TAG names the plates (before, after).
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/standup_icon_anchor_probe.gd
## Plates go to tools/blender/out/standup_icon_anchor/.

const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/standup_icon_anchor"
const CROWD := 24
const SPAWN_GAP_TICKS := 20
const SEATED_WANT := 4
const ARRIVE_LIMIT_TICKS := 6000
const MARGIN_PX := 12.0
const CLOSE_M := 10.0
const SIDE_M := 12.0
const FAR_M := 16.0
const HEAD_UP_M := 0.12
const SAMPLE_TICKS := [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24]
const SCREEN_YAWS := [0.0, PI / 2.0, PI, -PI / 2.0]
const FADE_LIMIT_FRAMES := 120
const THUMB := Vector2i(640, 360)
const LIVE_MS := 1800
const LIVE_STEP_MS := 150

var _out_dir := ""
var _tag := "run"
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _subject: Passenger
var _saved: Array[String] = []


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if OS.has_environment("PROBE_TAG"):
		_tag = OS.get_environment("PROBE_TAG")
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	if await _boot():
		await _measure(Passenger.Stage.STANDING_UP)
		await _measure(Passenger.Stage.SITTING_DOWN)
		await _live(Passenger.Stage.STANDING_UP)
		await _live(Passenger.Stage.SITTING_DOWN)
		await _plates()
		_contact_sheet()
	print("PROBE done failed=%s plates=%d" % [_failed, _saved.size()])
	quit(1 if _failed else 0)


func _boot() -> bool:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	if OS.has_environment("PROBE_SEED"):
		seed = OS.get_environment("PROBE_SEED").to_int()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.starter_shell = false
	root.add_child(_main)
	_clock.set_paused(true)
	await _frames(5)
	NeedFacilityKit.build(mode.grid)
	if not StarterFlight.add_gate_desk(mode.grid):
		_invalid("the gate desk was refused")
		return false
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	mode.set_tool(BuildMode.Tool.NONE)
	mode.set_process(false)
	(mode.get_node("Ghost") as Node3D).visible = false
	await _frames(20)
	_clock.set_process(false)
	_rig = _main.get_node("TycoonCamera")
	_rig.set_angle_step(TycoonCamera.AngleStep.TOP_DOWN)
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	var staff := _main.get_node("Staff") as StaffSim
	StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	if doors < 0:
		_invalid("the airport did not open")
		return false
	_clock.set_paused(false)
	var spawned := 0
	var ticks := 0
	while ticks < ARRIVE_LIMIT_TICKS and _seated().size() < SEATED_WANT:
		if spawned < CROWD and ticks % SPAWN_GAP_TICKS == 0:
			_sim.spawn_now(StarterFlight.first_flight())
			spawned += 1
		_clock.advance(SimClock.STEP)
		ticks += 1
		# Calm on the way in, so nobody turns off to a toilet, cafe or shop.
		for id in _sim.passenger_ids():
			var p := _sim.get_passenger(id)
			p.hunger = 0
			p.toilet_need = 0
			p.boredom = 0
	_clock.set_paused(true)
	var seated := _seated()
	print("PROBE arrive ticks=%d tick=%d seated=%d" % [ticks, _clock.tick, seated.size()])
	if seated.size() < SEATED_WANT:
		_invalid("only %d seated at the gate" % seated.size())
		return false
	_subject = _sim.get_passenger(seated[0])
	_subject.hunger = CafeSim.HUNGER_MAX
	_subject.toilet_need = ToiletSim.NEED_MAX
	_open_overlay(MoodTint.Mode.TOILET)
	print("PROBE subject id=%d stage=%s" % [_subject.id, Passenger.Stage.keys()[_subject.stage]])
	return true


## Opens the Mood overlay in `mode`: need icons show only in a need mode.
func _open_overlay(mode: MoodTint.Mode) -> void:
	var overlay := _main.get_node("MoodOverlay") as MoodOverlay
	overlay.set_mode(mode)
	overlay.set_shown(true)


## Ids of the passengers drawn sitting on a gate chair.
func _seated() -> Array[int]:
	var out: Array[int] = []
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		var node := _views.node_for(id)
		var on_chair := p.stage == Passenger.Stage.SEATED
		if node != null and on_chair and node.get_meta(&"icon_seated", false):
			out.append(id)
	return out


## Freezes the subject `ticks` into `stage` (its stand-up or sit-down clip).
func _freeze(ticks: int, stage := Passenger.Stage.STANDING_UP) -> Node3D:
	_subject.stage = stage
	_subject.stage_tick = _clock.tick - ticks
	_views.snap()
	await _frames(3)
	return _views.node_for(_subject.id)


func _head_bone(node: Node3D) -> Vector3:
	for skeleton in node.find_children("*", "Skeleton3D", true, false):
		var bones := skeleton as Skeleton3D
		for i in bones.get_bone_count():
			if bones.get_bone_name(i).to_lower().contains("head"):
				return bones.global_transform * bones.get_bone_global_pose(i).origin
	_invalid("no head bone on the subject")
	return node.global_position


func _measure(stage: Passenger.Stage) -> void:
	var node := await _freeze(0, stage)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	print(
		(
			"PROBE %s stand_up length=%.3f sit_down length=%.3f held=%d"
			% [
				Passenger.Stage.keys()[stage],
				player.get_animation("stand_up").length,
				player.get_animation("sit_down").length,
				SitHold.held_ticks(_views.carry_on_props(), _sim, _subject)
			]
		)
	)
	for ticks: int in SAMPLE_TICKS:
		node = await _freeze(ticks, stage)
		player = node.get_node("AnimationPlayer") as AnimationPlayer
		var head := _head_bone(node)
		var local := node.global_transform.affine_inverse() * head
		var anchor := NeedIcons.head_anchor(node)
		var top := NeedIcons.head_top(node)
		var over := []
		for yaw: float in SCREEN_YAWS:
			await _aim(head, CLOSE_M, yaw)
			var head_px := _cam.unproject_position(head + Vector3.UP * HEAD_UP_M)
			var anchor_px := _cam.unproject_position(node.global_transform * anchor)
			over.append(snappedf(head_px.y - anchor_px.y, 0.1))
		print(
			(
				(
					"SAMPLE stage=%s ticks=%d clip_pos=%.3f clip=%s head_local=%s anchor=%s head_top=%s"
					+ " anchor_over_head_px=%s"
				)
				% [
					Passenger.Stage.keys()[stage],
					ticks,
					player.current_animation_position if player.current_animation != "" else -1.0,
					player.current_animation,
					local,
					anchor,
					top,
					over
				]
			)
		)


## A live run: the subject's clip played to its natural end by the frames
## (the clock unpaused, its ticks still stopped so the stage holds), printing
## the clip and the anchor every LIVE_STEP_MS for LIVE_MS, past the clip's
## 1.2 s end.
func _live(stage: Passenger.Stage) -> void:
	var node := await _freeze(0, stage)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	_clock.set_paused(false)
	var start := Time.get_ticks_msec()
	var next := 0
	var i := 0
	while Time.get_ticks_msec() - start < LIVE_MS:
		await process_frame
		i += 1
		if Time.get_ticks_msec() - start < next:
			continue
		next += LIVE_STEP_MS
		print(
			(
				"LIVE stage=%s frame=%d clip=%s assigned=%s pos=%.3f playing=%s anchor=%s"
				% [
					Passenger.Stage.keys()[stage],
					i,
					player.current_animation,
					player.assigned_animation,
					player.current_animation_position,
					player.is_playing(),
					NeedIcons.head_anchor(node)
				]
			)
		)
	_clock.set_paused(true)


func _plates() -> void:
	var layers := 0
	for node in _main.find_children("*", "CanvasLayer", true, false):
		if (node as CanvasLayer).visible:
			(node as CanvasLayer).visible = false
			layers += 1
	print("PROBE hud layers hidden=%d pitch=%.1f" % [layers, _rig.pitch_degrees()])
	for ticks: int in [0, 12]:
		var node := await _freeze(ticks)
		var label := "start" if ticks == 0 else "mid"
		await _aim(node.global_position, CLOSE_M, 0.0)
		await _plate("close_%s_%dm" % [label, int(CLOSE_M)], node)
		await _aim(node.global_position, SIDE_M, 1.2)
		await _plate("close_%s_%dm_side" % [label, int(SIDE_M)], node)
	var sinking := await _freeze(12, Passenger.Stage.SITTING_DOWN)
	await _aim(sinking.global_position, CLOSE_M, 0.0)
	await _plate("close_sit_mid_%dm" % int(CLOSE_M), sinking)
	# The distance shot at FAR_M: icons hide beyond NeedIcons.shown_at()'s zoom,
	# so the home zoom shows none (finding e9d49c8a: plate at 10 to 16 m).
	var mid := await _freeze(12)
	await _aim(mid.global_position, FAR_M, 0.6)
	await _plate("distance_mid_%dm" % int(FAR_M), mid)


func _aim(at: Vector3, distance: float, yaw: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = yaw
	_rig.distance = distance
	await _frames(12)
	var roof := _main.get_node("RoofView") as RoofView
	var fade := 0
	while roof.cutaway.roof_level != roof.cutaway.roof_target and fade < FADE_LIMIT_FRAMES:
		await process_frame
		fade += 1
	if absf(_rig.distance - distance) > 0.01:
		_invalid("the camera is at %.2f m, not %.2f" % [_rig.distance, distance])


func _plate(name: String, node: Node3D) -> void:
	await _frames(2)
	var to_output := root.get_stretch_transform().get_scale().y
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX,
		root.get_visible_rect().size * to_output - Vector2.ONE * MARGIN_PX * 2.0
	)
	var head := _head_bone(node)
	var head_px := _cam.unproject_position(head + Vector3.UP * HEAD_UP_M) * to_output
	var anchor_px := _cam.unproject_position(node.global_transform * NeedIcons.head_anchor(node))
	anchor_px *= to_output
	var sprite := node.get_node("NeedIcon0") as Sprite3D
	print(
		(
			"PROBE %s head_top_px=%s anchor_px=%s frame=%s icon0_visible=%s stage=%s clip=%s"
			% [
				name,
				head_px,
				anchor_px,
				frame,
				sprite.visible,
				Passenger.Stage.keys()[_subject.stage],
				node.get_meta(&"clip", "")
			]
		)
	)
	if not frame.has_point(head_px) or not frame.has_point(anchor_px):
		_invalid("%s: the subject's head or anchor is out of frame" % name)
		return
	if not sprite.visible:
		_invalid("%s: the subject's icon row is not drawn" % name)
	var space := _cam.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(_cam.global_position, head))
	print("PROBE %s ray_to_head blocked=%s" % [name, not hit.is_empty()])
	if not hit.is_empty() and (hit["position"] as Vector3).distance_to(head) > 0.5:
		_invalid("%s: the subject's head is behind %s" % [name, hit["collider"]])
		return
	var img := root.get_texture().get_image()
	var k := img.get_size().x / (root.get_visible_rect().size.x * to_output)
	var file := "%s_%s.png" % [_tag, name]
	_save(img, file)
	var marked := img.duplicate() as Image
	_mark(marked, head_px * k, Color(0.1, 0.4, 1.0))
	_mark(marked, anchor_px * k, Color(1.0, 0.1, 0.1))
	_save(marked, "%s_%s_marked.png" % [_tag, name])
	# The subject close up: THUMB around its head, from the unmarked plate.
	var corner := Vector2i(head_px * k) - THUMB / 2
	corner = corner.clamp(Vector2i.ZERO, img.get_size() - THUMB)
	_save(img.get_region(Rect2i(corner, THUMB)), "%s_%s_crop.png" % [_tag, name])


## A small cross at `at` (image pixels).
func _mark(img: Image, at: Vector2, colour: Color) -> void:
	var c := Vector2i(at)
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	for r in [Rect2i(c.x - 10, c.y - 1, 21, 3), Rect2i(c.x - 1, c.y - 10, 3, 21)]:
		var clipped := (r as Rect2i).intersection(bounds)
		if clipped.has_area():
			img.fill_rect(clipped, colour)


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	_saved.append(path)
	print("PLATE saved %s size=%s" % [path, img.get_size()])


## One sheet of every _crop plate of this run, two across.
func _contact_sheet() -> void:
	var marked := _saved.filter(func(p: String) -> bool: return p.ends_with("_crop.png"))
	if marked.is_empty():
		return
	var rows := ceili(marked.size() / 2.0)
	var sheet := Image.create(THUMB.x * 2, THUMB.y * rows, false, Image.FORMAT_RGB8)
	for i in marked.size():
		var img := Image.load_from_file(marked[i])
		img.convert(Image.FORMAT_RGB8)
		img.resize(THUMB.x, THUMB.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, THUMB), Vector2i(i % 2, i / 2) * THUMB)
	_save(sheet, "%s_contact_sheet.png" % _tag)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
