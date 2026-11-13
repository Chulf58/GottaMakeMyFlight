extends SceneTree
## Windowed plates for the need icon count clusters (decision need-icon-count-
## clusters-technical-design-screen-space-clust; board ee914f84). Boots the
## real main scene with a new random sim seed (printed; PROBE_SEED replays one),
## builds the reference terminal with toilets, a cafe and a screen stand
## (NeedFacilityKit) so every need icon can show, opens the airport and sends
## in CROWD passengers in batches. Then it gives them toilet need, hunger and
## boredom in a fixed pattern (printed counts) and frames:
##   a  mid zoom on the busiest spot, clusters on
##   b  the same with clusters off, for comparison
##   c  the longest station queue moving at 1x, three frames 0.5 s apart
##   d  zoomed in on one group
## Each plate prints the cluster count, every badge's id, kind, count and
## screen rect, and the icons still drawn. The HUD layers are hidden for the
## plates (their panels would cover badges a ray test cannot see). A plate whose
## badges are all off the frame, or a clustered plate with no badge, prints
## PROBE_INVALID and the run exits 1. It also times the cluster pass and the
## whole PassengerViews.draw() with clusters on and off, over TIMING_RUNS calls.
##
## Windowed, hold tools/blender/out/.windowed.lock for the whole run:
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     -s res://spike/need_cluster_plates_probe.gd

const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/need-clusters"
const CROWD := 300
const SPAWN_BATCH := 10
const BATCH_TICKS := 100
## Ticks run after the last batch, so the crowd spreads over the queues.
const SPREAD_TICKS := 300
const MARGIN_PX := 16.0
## Camera distances: mid zoom as a share of the home distance (the icons hide
## at home and farther out), and zoomed in on one group, past the icons' near
## fade (NeedIcons.NEAR_FULL_M).
const MID_OF_HOME := 0.7
const CLOSE_M := 11.0
const FADE_LIMIT_FRAMES := 120
const TIMING_RUNS := 60
const QUEUE_GAP_S := 0.5
## Metres around a passenger counted as its neighbours, to find the busiest spot.
const BUSY_RADIUS_M := 4.0

var _out_dir := ""
var _failed := false
var _main: Node3D
var _cam: Camera3D
var _rig: TycoonCamera
var _clock: SimClock
var _sim: PassengerSim
var _views: PassengerViews


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
	_spread_needs()
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


## Toilet need for every other passenger, hunger for two in five, boredom for
## one in three; the rest calm. Prints the counts set.
func _spread_needs() -> void:
	var i := 0
	var given := [0, 0, 0]
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		p.toilet_need = ToiletSim.NEED_MAX if i % 2 == 0 else 0
		p.hunger = CafeSim.HUNGER_MAX if i % 5 < 2 else 0
		p.boredom = BoredomSim.MAX if i % 3 == 0 else 0
		given[0] += int(i % 5 < 2)
		given[1] += int(i % 2 == 0)
		given[2] += int(i % 3 == 0)
		i += 1
	print("PROBE needs set: hunger=%d toilet=%d boredom=%d" % given)


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
	var mid := _rig.home_distance * MID_OF_HOME
	print("PROBE home_distance=%.2f mid=%.2f" % [_rig.home_distance, mid])
	_views.draw()
	var busy := _busiest()
	await _aim(busy, mid)
	await _plate("a_mid_zoom_clusters", true)
	await _measure_cost()
	_views.cluster_needs = false
	await _plate("b_mid_zoom_no_clusters", false)
	_views.cluster_needs = true
	await _aim(_longest_queue(), mid)
	_clock.set_process(true)
	for k in 3:
		await _plate("c_moving_queue_%d" % k, true)
		await create_timer(QUEUE_GAP_S).timeout
	_clock.set_process(false)
	await _aim(busy, CLOSE_M)
	await _plate("d_zoomed_in_group", false)


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


## Saves a plate after checking its badges are in frame; `need_badge` fails a
## plate with no badge on screen.
func _plate(name: String, need_badge: bool) -> void:
	await _frames(2)
	var to_output := root.get_stretch_transform().get_scale().y
	var frame := Rect2(
		Vector2.ONE * MARGIN_PX,
		root.get_visible_rect().size * to_output - Vector2.ONE * MARGIN_PX * 2
	)
	var badges := _views.need_badges()
	var clusters := _views.need_clusters.clusters()
	var needy := 0
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		needy += int(node != null and int(node.get_meta(&"needs", 0)) > 0)
	print(
		(
			"PROBE gate toggle=%s shown_at=%s distance=%.2f overlay_hides=%s needy_nodes=%d"
			% [
				_views.need_icons_toggle.is_shown(),
				NeedIcons.shown_at(_cam),
				_rig.distance,
				_views.mood_overlay.hides_need_icons() if _views.mood_overlay else false,
				needy
			]
		)
	)
	var inside := 0
	var overlaps := 0
	var counts: Array[int] = []
	for i in badges.size():
		var rect: Rect2 = badges[i]["rect"]
		counts.append(badges[i]["count"])
		inside += int(frame.encloses(rect))
		for j in range(i + 1, badges.size()):
			overlaps += int(rect.intersects(badges[j]["rect"]))
		print(
			(
				"BADGE %s id=%d kind=%s count=%d rect=%s in_frame=%s"
				% [
					name,
					badges[i]["id"],
					NeedIcons.Need.keys()[badges[i]["kind"]],
					badges[i]["count"],
					rect,
					frame.encloses(rect)
				]
			)
		)
	print(
		(
			(
				"PROBE plate=%s clusters=%d badges_in_frame=%d overlapping_pairs=%d counts=%s"
				+ " icons_drawn=%d frame=%s"
			)
			% [name, clusters.size(), inside, overlaps, counts, _icons_drawn(), frame]
		)
	)
	if need_badge and inside == 0:
		_invalid("%s: no badge inside the frame" % name)
	if overlaps > 0:
		_invalid("%s: %d badge pairs overlap" % [name, overlaps])
	var plate := await PlateSight.grab(self)
	var path := _out_dir.path_join(name + ".png")
	if plate.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, plate.get_size()])


## Times the cluster pass alone, then PassengerViews.draw() with clusters on
## and off, each over TIMING_RUNS calls, and prints the mean per call.
func _measure_cost() -> void:
	var unit := NeedIcons.unit_of(root, _cam)
	var started := Time.get_ticks_usec()
	for i in TIMING_RUNS:
		_views.call("_cluster_icons", _cam, unit, true)
	var pass_us := (Time.get_ticks_usec() - started) / float(TIMING_RUNS)
	var draw_us := {}
	for on in [true, false]:
		_views.cluster_needs = on
		started = Time.get_ticks_usec()
		for i in TIMING_RUNS:
			_views.draw()
		draw_us[on] = (Time.get_ticks_usec() - started) / float(TIMING_RUNS)
	_views.cluster_needs = true
	_views.draw()
	print(
		(
			"COST passengers=%d drawn=%d pass_ms=%.3f draw_on_ms=%.3f draw_off_ms=%.3f delta_ms=%.3f"
			% [
				_sim.passenger_ids().size(),
				_views.active_count(),
				pass_us / 1000.0,
				draw_us[true] / 1000.0,
				draw_us[false] / 1000.0,
				(draw_us[true] - draw_us[false]) / 1000.0
			]
		)
	)


func _icons_drawn() -> int:
	var count := 0
	for id in _sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		for sprite_name in NeedIcons.SPRITES:
			count += int((node.get_node(sprite_name) as Sprite3D).visible)
	return count


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


## The middle of the longest check-in or security queue.
func _longest_queue() -> Vector3:
	var groups := {}
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.stage == Passenger.Stage.CHECKIN_QUEUE or p.stage == Passenger.Stage.SECURITY_QUEUE:
			if not groups.has(p.stage):
				groups[p.stage] = []
			(groups[p.stage] as Array).append(_views.node_for(id).global_position)
	var longest: Array = []
	for stage: int in groups:
		if (groups[stage] as Array).size() > longest.size():
			longest = groups[stage]
	var centre := Vector3.ZERO
	for at: Vector3 in longest:
		centre += at
	centre /= maxf(longest.size(), 1.0)
	print("PROBE longest_queue=%d centre=%s" % [longest.size(), centre])
	return centre


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw
