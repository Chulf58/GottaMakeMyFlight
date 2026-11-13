extends SceneTree
## Windowed plates for the Mood overlay's need icons (decision need-icons-show-
## only-in-the-mood-overlay-need-modes-n-key-removed; board 7257fa2a). Boots the
## real main scene with a new random sim seed (printed; PROBE_SEED replays one),
## builds the reference terminal with toilets, a cafe and a screen stand
## (NeedFacilityKit), opens the airport, sends in CROWD passengers, gives each
## of them all three needs and frames the same busy gate at the 38 degree angle
## step and about 11 m in four states: the overlay off, Mood mode, Toilet mode
## and Boredom mode. Each plate prints the need icons and badges drawn, per
## kind, and the subject's projected position (in frame with a margin); a plate
## whose counts break the ruling, or whose subject is out of frame, prints
## PROBE_INVALID and the run exits 1. The HUD layers are hidden for the plates,
## so the legend does not cover the crowd.
##
## Windowed, hold tools/blender/out/.windowed.lock for the whole run:
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     -s res://spike/overlay_icons_plates_probe.gd

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/overlay_icons_20261114"
const CROWD := 300
const SPAWN_BATCH := 10
const BATCH_TICKS := 100
## Ticks run after the last batch, so the crowd spreads over the queues.
const SPREAD_TICKS := 300
const MARGIN_PX := 16.0
const DISTANCE_M := 11.0
const FADE_LIMIT_FRAMES := 120
## Metres around a passenger counted as its neighbours, to find the busiest spot.
const BUSY_RADIUS_M := 4.0
## The states framed: plate name, whether the overlay is open, its mode, and the
## need whose icons may show (-1 for none).
const STATES := [
	["a_overlay_off", false, MoodTint.Mode.MOOD, -1],
	["b_mood_mode", true, MoodTint.Mode.MOOD, -1],
	["c_toilet_mode", true, MoodTint.Mode.TOILET, NeedIcons.Need.TOILET],
	["d_boredom_mode", true, MoodTint.Mode.BOREDOM, NeedIcons.Need.BOREDOM],
]

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews
var _subject := 0


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
	# The probe builds its own furnished terminal: the starter shell would
	# refuse the reference terminal's first wall.
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
	NeedFacilityKit.build(mode.grid)
	if not StarterFlight.add_gate_desk(mode.grid):
		_invalid("the gate desk was refused")
		return false
	(mode.get_node("BuildView") as BuildView).refresh(mode.grid)
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, _main.get_node("FlightSim"), staff)
	var built := NeedIcons.provided(_sim)
	print("PROBE hired=%d opened tick=%d doors=%d built=%s" % [hired, _clock.tick, doors, built])
	if hired == 0 or doors < 0 or built.values().has(false):
		_invalid("no staff, no opening or a need nothing built meets")
		return false
	var flight := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	for i in CROWD:
		if i % SPAWN_BATCH == 0:
			_advance(BATCH_TICKS)
		_sim.spawn_now(flight)
	_advance(SPREAD_TICKS)
	_give_needs()
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


## Puts the rig over `at` at `distance` and waits for the roof fade to end.
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
			"PROBE aim at=%s distance=%.2f asked=%.2f home=%.2f fade_frames=%d"
			% [at, _rig.distance, distance, _rig.home_distance, fade]
		)
	)
	if absf(_rig.distance - distance) > 0.01 or _rig.distance >= _rig.home_distance:
		_invalid("the camera is not at %.2f m, inside the home zoom" % distance)


## Every passenger gets all three needs at their maximum, so each need mode has
## a crowd to show. Prints the count.
func _give_needs() -> void:
	var given := 0
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		p.toilet_need = ToiletSim.NEED_MAX
		p.hunger = CafeSim.HUNGER_MAX
		p.boredom = BoredomSim.MAX
		given += 1
	print("PROBE needs set on %d passengers" % given)


func _plates() -> void:
	var layers := 0
	for node in _main.find_children("*", "CanvasLayer", true, false):
		if (node as CanvasLayer).visible:
			(node as CanvasLayer).visible = false
			layers += 1
	print("PROBE hud layers hidden=%d home_distance=%.1f" % [layers, _rig.home_distance])
	# Hiding the panels refits the start view (TycoonCamera.set_room()); wait it
	# out, then leave the start view so it no longer pulls the zoom back home.
	await _frames(30)
	_rig.follow(_views)
	_rig.stop_follow()
	_rig.set_angle_step(TycoonCamera.AngleStep.LOW)
	_views.draw()
	var busy := _busiest()
	_subject = _nearest_to(busy)
	await _aim(busy, DISTANCE_M)
	var overlay := _main.get_node("MoodOverlay") as MoodOverlay
	for state: Array in STATES:
		overlay.set_mode(state[2])
		overlay.set_shown(state[1])
		await _plate(state[0], state[3])


## Id of the drawn passenger nearest `at`.
func _nearest_to(at: Vector3) -> int:
	var best := 0
	var best_d := INF
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node != null and node.global_position.distance_to(at) < best_d:
			best_d = node.global_position.distance_to(at)
			best = id
	return best


## Saves the plate `name` after checking the counts against `need` (the one need
## whose icons may show, -1 for none) and that the subject is in frame.
func _plate(name: String, need: int) -> void:
	await _frames(3)
	var to_output := root.get_stretch_transform().get_scale().y
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX,
		root.get_visible_rect().size * to_output - Vector2.ONE * MARGIN_PX * 2
	)
	var drawn := {}
	var in_frame := {}
	for kind in NeedIcons.Need.values():
		drawn[kind] = 0
		in_frame[kind] = 0
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		var kinds: Array = node.get_meta(&"need_kinds", [])
		for i in kinds.size():
			var sprite := node.get_node(NeedIcons.SPRITES[i]) as Sprite3D
			if sprite.visible:
				drawn[kinds[i]] += 1
				var at := _cam.unproject_position(sprite.global_position) * to_output
				in_frame[kinds[i]] += int(frame.has_point(at))
	var badges := _views.need_badges()
	var badge_kinds := {}
	var badges_in_frame := 0
	for badge in badges:
		badge_kinds[badge["kind"]] = badge_kinds.get(badge["kind"], 0) + int(badge["count"])
		badges_in_frame += int(frame.encloses(badge["rect"]))
	var head: Vector3 = (
		_views.node_for(_subject).global_transform
		* NeedIcons.head_centre(_views.node_for(_subject))
	)
	var head_px := _cam.unproject_position(head) * to_output
	print(
		(
			(
				"PROBE plate=%s overlay_shown=%s mode=%d icons=%s in_frame=%s badges=%d badge_members=%s"
				+ " badges_in_frame=%d subject_head_px=%s frame=%s distance=%.2f pitch=%.1f"
			)
			% [
				name,
				(_main.get_node("MoodOverlay") as MoodOverlay).is_shown(),
				(_main.get_node("MoodOverlay") as MoodOverlay).mode(),
				drawn,
				in_frame,
				badges.size(),
				badge_kinds,
				badges_in_frame,
				head_px.round(),
				frame,
				_rig.distance,
				_rig.pitch_degrees()
			]
		)
	)
	if not frame.has_point(head_px):
		_invalid("%s: the subject's head is out of frame" % name)
	var shown_total := 0
	for kind in NeedIcons.Need.values():
		shown_total += drawn[kind] + int(badge_kinds.get(kind, 0))
		if need != kind and (drawn[kind] > 0 or badge_kinds.has(kind)):
			_invalid("%s: need %d shows but only %d may" % [name, kind, need])
	if need < 0 and shown_total > 0:
		_invalid("%s: %d icons or badge members show with no need mode" % [name, shown_total])
	if need >= 0 and (in_frame[need] + badges_in_frame) == 0:
		_invalid("%s: no icon or badge of need %d is in frame" % [name, need])
	var plate := await PlateSight.grab(self)
	var path := _out_dir.path_join(name + ".png")
	if plate.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, plate.get_size()])


## The drawn passenger with the most others within BUSY_RADIUS_M.
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
