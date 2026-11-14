extends SceneTree
## Windowed plates for the calm view's passenger bubbles (decision calm-cozy-
## default-view-quiet-world-detail-on-ask-soft-statio, part 3; calm-view-
## technical-design-shared-hover-target-reusing-click, part 5; board 63e47a88).
## Boots the real main scene with a new random sim seed (printed; PROBE_SEED
## replays one), builds the reference terminal with toilets, a cafe and a screen
## stand (NeedFacilityKit), opens the airport, sends in CROWD passengers, makes
## them all bored (so the shopless terminal gives them wishes) and marks every
## LATE_EVERY-th passenger near the busy gate late (the sim is stopped for the
## plates, so the mark holds). Frames the same busy gate at the 38 degree angle
## step and about 11 m in four states: the default view, one hovered passenger
## (through main's HoverTarget, resolved inside PassengerViews.draw()), the Mood
## overlay's Boredom mode and its Late mode. Each plate prints the speech and
## wish bubbles drawn and in frame, and the subject's projected head (in frame
## with a margin, and a sight line from the camera that lands on its own body
## with nothing in front, after a control line through that body came back
## blocked); a plate whose bubbles break the ruling, or whose subject is out of
## frame or hidden, prints PROBE_INVALID and the run exits 1. The HUD layers are
## hidden for the plates.
##
## Windowed, hold tools/blender/out/.windowed.lock for the whole run:
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     -s res://spike/calm_bubbles_plates_probe.gd

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/calm_bubbles_20261114"
const CROWD := 300
const SPAWN_BATCH := 10
const BATCH_TICKS := 100
const SPREAD_TICKS := 300
const MARGIN_PX := 16.0
const DISTANCE_M := 11.0
const FADE_LIMIT_FRAMES := 120
const OCCLUDER_OWNERS: Array[String] = ["Airside/Terminal", "BuildMode", "PassengerViews"]
const SUBJECT_TAG := "subject"
const NO_TAG := "no_subject"
const CONTROL_RUN_M := 1.0
const BUSY_RADIUS_M := 4.0
## Every this many passengers within LATE_RADIUS_M of the busy spot is marked late.
const LATE_EVERY := 3
const LATE_RADIUS_M := 8.0
## Plate name, overlay open, its mode, and whether the subject is hovered.
const STATES := [
	["a_default_view", false, MoodTint.Mode.MOOD, false],
	["b_hovered", false, MoodTint.Mode.MOOD, true],
	["c_boredom_mode", true, MoodTint.Mode.BOREDOM, false],
	["d_late_mode", true, MoodTint.Mode.LATE, false],
]

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _hover: HoverTarget
var _subject := 0
var _colliders: Node3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _run() -> void:
	if await _boot():
		await _plates()
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)


func _boot() -> bool:
	_main = load(MAIN_SCENE).instantiate()
	_clock = _main.get_node("SimClock")
	var seed := randi()
	if OS.has_environment("PROBE_SEED"):
		seed = OS.get_environment("PROBE_SEED").to_int()
	_clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(3)
	var mode := _main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	(mode.get_node("Ghost") as Node3D).visible = false
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	_hover = _main.get_node("HoverTarget")
	_hover.pointer_override = Vector2(-1.0, -1.0)
	NeedFacilityKit.build(mode.grid)
	if not StarterFlight.add_gate_desk(mode.grid):
		_invalid("the gate desk was refused")
		return false
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	print("PROBE hired=%d opened tick=%d doors=%d" % [hired, _clock.tick, doors])
	if hired == 0 or doors < 0:
		_invalid("no staff or no opening")
		return false
	var flight := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	for i in CROWD:
		if i % SPAWN_BATCH == 0:
			_advance(BATCH_TICKS)
		_sim.spawn_now(flight)
	_advance(SPREAD_TICKS)
	for id in _sim.passenger_ids():
		_sim.get_passenger(id).boredom = BoredomSim.MAX
	_advance(1)
	if _main.get_node("PlaneFleet").has_method("update_views"):
		_main.get_node("PlaneFleet").call("update_views")
	print(
		(
			"PROBE crowd tick=%d doors=%d passengers=%d drawn=%d"
			% [_clock.tick, doors, _sim.passenger_ids().size(), _views.active_count()]
		)
	)
	if _clock.tick >= doors:
		_invalid("the doors closed before the plates")
		return false
	return true


func _advance(ticks: int) -> void:
	for i in ticks:
		_clock.advance(SimClock.STEP)


func _aim(at: Vector3, distance: float) -> void:
	_rig.stop_follow()
	_rig.position = Vector3(at.x, 0.0, at.z)
	_rig.yaw = 0.0
	_rig.distance = distance
	await _frames(20)
	var roof := _main.get_node("RoofView") as RoofView
	var fade := 0
	while roof.cutaway.roof_level != roof.cutaway.roof_target and fade < FADE_LIMIT_FRAMES:
		await process_frame
		fade += 1
	if roof.cutaway.roof_level != roof.cutaway.roof_target:
		_invalid("the roof fade did not end in %d frames" % FADE_LIMIT_FRAMES)
	print(
		(
			"PROBE aim at=%s distance=%.2f home=%.2f pitch=%.1f fade_frames=%d"
			% [at, _rig.distance, _rig.home_distance, _rig.pitch_degrees(), fade]
		)
	)
	if absf(_rig.distance - distance) > 0.01 or _rig.distance >= _rig.home_distance:
		_invalid("the camera is not at %.2f m, inside the home zoom" % distance)


func _plates() -> void:
	var layers := 0
	for node in _main.find_children("*", "CanvasLayer", true, false):
		if (node as CanvasLayer).visible:
			(node as CanvasLayer).visible = false
			layers += 1
	print("PROBE hud layers hidden=%d" % layers)
	await _frames(30)
	_rig.follow(_views)
	_rig.stop_follow()
	_rig.set_angle_step(TycoonCamera.AngleStep.LOW)
	_views.draw()
	var busy := _busiest()
	await _aim(busy, DISTANCE_M)
	_mark_late(busy)
	_subject = _hoverable_wisher(busy)
	if _subject == 0:
		_invalid("no wishing passenger near the busy spot takes the hover")
		return
	await _build_colliders()
	var overlay := _main.get_node("MoodOverlay") as MoodOverlay
	for state: Array in STATES:
		overlay.set_mode(state[2])
		overlay.set_shown(state[1])
		_hover.pointer_override = _head_point(_subject) if state[3] else Vector2(-1.0, -1.0)
		await _plate(state[0], state[2] if state[1] else -1, state[3])
	_hover.pointer_override = Vector2(-1.0, -1.0)
	_colliders.free()


## Marks every LATE_EVERY-th drawn passenger within LATE_RADIUS_M of `busy`
## late, then syncs the views so they read it. Prints the count.
func _mark_late(busy: Vector3) -> void:
	var near: Array[int] = []
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null and node.global_position.distance_to(busy) <= LATE_RADIUS_M:
			near.append(id)
	near.sort()
	var marked := 0
	for i in near.size():
		if i % LATE_EVERY == 0:
			_sim.get_passenger(near[i]).late = true
			marked += 1
	_views.sync()
	print("PROBE late marked=%d of %d near the busy spot" % [marked, near.size()])


## The screen point over `id`'s head that a hover takes, in viewport px.
func _head_point(id: int) -> Vector2:
	var node := _views.node_for(id)
	return _cam.unproject_position(node.global_position + Vector3(0.0, 1.0, 0.0))


## The wishing, not late passenger nearest `busy` that a hover at its head
## resolves to, or 0.
func _hoverable_wisher(busy: Vector3) -> int:
	var candidates: Array[int] = []
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null and node.get_meta(&"wish", "") != "" and not _sim.get_passenger(id).late:
			candidates.append(id)
	candidates.sort_custom(
		func(a: int, b: int) -> bool:
			return (
				_views.node_for(a).global_position.distance_to(busy)
				< _views.node_for(b).global_position.distance_to(busy)
			)
	)
	for id in candidates:
		_hover.pointer_override = _head_point(id)
		_hover.refresh()
		if _hover.hovered_passenger() == id:
			_hover.pointer_override = Vector2(-1.0, -1.0)
			_hover.refresh()
			print("PROBE subject=%d of %d wishers" % [id, candidates.size()])
			return id
	return 0


func _plate(name: String, mode: int, hovered: bool) -> void:
	await _frames(3)
	var to_output := root.get_stretch_transform().get_scale().y
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX,
		root.get_visible_rect().size * to_output - Vector2.ONE * MARGIN_PX * 2
	)
	var speech_ids: Array[int] = []
	var speech_in_frame := 0
	var texts := {}
	var wish_ids: Array[int] = []
	var wish_in_frame := 0
	var could_speak := 0
	var could_wish := 0
	var late_ids: Array[int] = []
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		could_speak += int(node.get_meta(&"speech", "") != "")
		could_wish += int(node.get_meta(&"wish", "") != "")
		if MoodTint.is_late(_sim.get_passenger(id)):
			late_ids.append(id)
		var bubble := node.get_node("Bubble") as Label3D
		if bubble.visible and bubble.text != "":
			speech_ids.append(id)
			texts[bubble.text] = texts.get(bubble.text, 0) + 1
			var at := _cam.unproject_position(bubble.global_position) * to_output
			speech_in_frame += int(frame.has_point(at))
		var wish := node.get_node(WishIconView.SPRITE) as Sprite3D
		if wish.visible:
			wish_ids.append(id)
			wish_in_frame += int(
				frame.has_point(_cam.unproject_position(wish.global_position) * to_output)
			)
	var overlay := _main.get_node("MoodOverlay") as MoodOverlay
	var head: Vector3 = (
		_views.node_for(_subject).global_transform
		* NeedIcons.head_centre(_views.node_for(_subject))
	)
	var head_px := _cam.unproject_position(head) * to_output
	print(
		(
			(
				"PROBE plate=%s overlay_shown=%s mode=%d hovered=%d speech=%d in_frame=%d texts=%s"
				+ " wishes=%d in_frame=%d could_speak=%d could_wish=%d late=%d tinted=%d"
				+ " subject=%d subject_head_px=%s distance=%.2f pitch=%.1f"
			)
			% [
				name,
				overlay.is_shown(),
				overlay.mode(),
				_hover.hovered_passenger(),
				speech_ids.size(),
				speech_in_frame,
				texts,
				wish_ids.size(),
				wish_in_frame,
				could_speak,
				could_wish,
				late_ids.size(),
				overlay.tinted_cells().size(),
				_subject,
				head_px.round(),
				_rig.distance,
				_rig.pitch_degrees()
			]
		)
	)
	if not frame.has_point(head_px):
		_invalid("%s: the subject's head is out of frame" % name)
	_check_head_seen(name, head)
	_check_bubbles(name, mode, hovered, speech_ids, wish_ids, late_ids, wish_in_frame)
	if mode == MoodTint.Mode.LATE and speech_in_frame == 0:
		_invalid("%s: no late bubble is in frame" % name)
	# One soft disc per drawn late passenger in Late mode, none otherwise.
	var marks := (_views.get_node("LateMarks") as MultiMeshInstance3D).multimesh
	var want := late_ids.size() if mode == MoodTint.Mode.LATE else 0
	print("PROBE late_marks plate=%s drawn=%d want=%d" % [name, marks.visible_instance_count, want])
	if marks.visible_instance_count != want:
		_invalid("%s: %d late discs drawn, %d wanted" % [name, marks.visible_instance_count, want])
	var plate := await PlateSight.grab(self)
	var path := _out_dir.path_join(name + ".png")
	if plate.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, plate.get_size()])


## Fails the plate when its bubbles break the ruling: none by default, only the
## hovered subject's on hover, wishes and no speech in Boredom mode, and only
## late passengers' late bubbles in Late mode.
func _check_bubbles(
	name: String,
	mode: int,
	hovered: bool,
	speech_ids: Array[int],
	wish_ids: Array[int],
	late_ids: Array[int],
	wish_in_frame: int
) -> void:
	if hovered:
		if _hover.hovered_passenger() != _subject:
			_invalid(
				"%s: the hover is on %d, not %d" % [name, _hover.hovered_passenger(), _subject]
			)
		var own: Array[int] = []
		own.append(_subject)
		if not wish_ids == own or speech_ids.any(func(id: int) -> bool: return id != _subject):
			_invalid("%s: bubbles other than the hovered subject's show" % name)
		return
	if mode == MoodTint.Mode.BOREDOM:
		if not speech_ids.is_empty() or wish_in_frame == 0:
			_invalid("%s: speech shows, or no wish is in frame" % name)
		return
	if mode == MoodTint.Mode.LATE:
		if (
			not wish_ids.is_empty()
			or speech_ids.any(func(id: int) -> bool: return id not in late_ids)
		):
			_invalid("%s: a wish or a bubble of a passenger who is not late shows" % name)
		for id in speech_ids:
			if (
				(_views.node_for(id).get_node("Bubble") as Label3D).text
				!= BubbleDeclutter.LATE_TEXT
			):
				_invalid("%s: a late passenger's bubble is not the late text" % name)
		return
	if not speech_ids.is_empty() or not wish_ids.is_empty():
		_invalid(
			"%s: %d speech and %d wish bubbles show" % [name, speech_ids.size(), wish_ids.size()]
		)


func _build_colliders() -> void:
	var owners: Array[Node] = []
	for path in OCCLUDER_OWNERS:
		owners.append(_main.get_node(path))
	_colliders = PlateSight.colliders(root, owners, {_views.node_for(_subject): SUBJECT_TAG})
	await physics_frame
	await physics_frame
	var bounds: Dictionary = _colliders.get_meta("bounds")
	print("PROBE colliders subject_bounds=%s" % [bounds.get(SUBJECT_TAG)])
	if not bounds.has(SUBJECT_TAG):
		_invalid("the subject has no collider, so no sight line can find it")


func _check_head_seen(name: String, head: Vector3) -> void:
	var space := _cam.get_world_3d().direct_space_state
	var from := _cam.global_position
	var targets: Array[Vector3] = [head]
	var lines := PlateSight.sight_lines(space, from, targets, SUBJECT_TAG)
	var through: Array[Vector3] = [head + (head - from).normalized() * CONTROL_RUN_M]
	var control := PlateSight.sight_lines(space, from, through, NO_TAG)
	var control_blockers: Array[String] = control["blockers"]
	print(
		(
			"PROBE sight plate=%s on_subject=%d blockers=%s control_blocked_by=%s"
			% [name, (lines["on_subject"] as Array).size(), lines["blockers"], control_blockers]
		)
	)
	if control_blockers.is_empty():
		_invalid("%s: the control line through the subject's body was not blocked" % name)
	if (lines["on_subject"] as Array).is_empty() or not (lines["blockers"] as Array).is_empty():
		_invalid("%s: the subject's head is hidden behind %s" % [name, lines["blockers"]])


func _busiest() -> Vector3:
	var spots: Array[Vector3] = []
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null:
			spots.append(node.global_position)
	var best := Vector3.ZERO
	var best_n := -1
	for a in spots:
		var n := 0
		for b in spots:
			n += int(a.distance_to(b) <= BUSY_RADIUS_M)
		if n > best_n:
			best = a
			best_n = n
	print("PROBE busiest=%s neighbours=%d" % [best, best_n])
	return best


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
