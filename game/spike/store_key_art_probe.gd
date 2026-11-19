extends SceneTree
## Windowed staged key-art probe for Steam capsules and library hero (D6b,
## 3c5a08a9; decisions a7f1b1e4, 56cccfaf; finding bb598d8c). Furnishes an
## active terminal with staff, passengers + bags, and Gotta Air's plane at Gate
## A, hides all UI, verifies framing/sightlines, and writes raw hero PNGs.

const IntroClose := preload("res://spike/intro_close.gd")
const PlateSight := preload("res://spike/plate_sight.gd")
const StarterFlight := preload("res://spike/starter_flight.gd")
const MAIN_SCENE := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/store/raw"
const HANG_LIMIT_MS := 120000
const TICKS_PER_FRAME := 8
const MARGIN_PX := 20.0
const MIN_PAX_IN_FRAME := 10
const OCCLUDERS := (
	"Ground,BuildMode,Airside,PlaneView,PlaneFleet,"
	+ "ApronStand,PassengerViews,StaffCharacters,RoofView"
)
const FREEZE := (
	"PlaneFleet,PassengerViews,BaggageViews,StaffCharacters,"
	+ "LandsideViews,ApronStand,BirdFlock,HoverTarget"
)

var _out_dir := ""
var _failed := false
var _done := false
var _beat_ms := 0
var _guard := Thread.new()
var _mutex := Mutex.new()
var _main: Node3D
var _clock: SimClock
var _mode: BuildMode
var _grid: BuildGrid
var _sim: PassengerSim
var _vp: SubViewport
var _cam: Camera3D


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var world_seed := IntroClose.seed_or_random()
	print("PROBE world_seed=%d out_dir=%s" % [world_seed, _out_dir])
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(world_seed)
	(_main.get_node("BuildMode") as BuildMode).starter_shell = false
	root.add_child(_main)
	current_scene = _main
	_clock.set_process(false)
	_clock.set_paused(false)
	await _frames(4)
	if _setup_terminal() and await _stage_activity():
		_freeze_and_hide_ui()
		await _frames(6)
		await _render_all_shots()
	_finish()


func _setup_terminal() -> bool:
	_beat("setup_terminal")
	var intro_err := IntroClose.close(_main)
	if intro_err != "":
		_invalid(intro_err)
		return false
	_mode = _main.get_node("BuildMode") as BuildMode
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.NONE)
	(_mode.get_node("Ghost") as Node3D).visible = false
	_grid = _mode.grid
	_sim = _main.get_node("PassengerSim") as PassengerSim
	CafeTestLayout.build(_grid, true)
	if not StarterFlight.add_gate_desk(_grid):
		_invalid("gate desk placement refused")
		return false
	_decorate_terminal()
	(_mode.get_node("BuildView") as BuildView).refresh(_grid)
	_sim.cafes.refresh()
	return true


func _decorate_terminal() -> void:
	var at := ReferenceTerminal.offset_on(_grid)
	for x in range(10, 28):
		if x == ReferenceTerminal.EXIT_CELL.x:
			continue
		var row := 2 if x < 22 else 3
		_grid.apply(
			BuildEdit.place_wall(
				Vector2i(x, row) + at, BuildGrid.Side.NORTH, BuildGrid.WallKind.GLASS
			)
		)
	var placed := 0
	for item in [
		[&"tree_indoor", Vector2i(10, 15)],
		[&"plant_pot_2a", Vector2i(13, 15)],
		[&"screen_stand", Vector2i(16, 15)],
		[&"plant_pot_1a", Vector2i(10, 4)],
		[&"plant_pot_1a", Vector2i(26, 14)],
		[&"plant_pot_1a", Vector2i(26, 7)],
	]:
		if _grid.apply(BuildEdit.place_object(item[0], item[1] + at, 0)).ok:
			placed += 1
	print("PROBE decor_placed=%d" % placed)


func _stage_activity() -> bool:
	_beat()
	var flights := _main.get_node("FlightSim") as FlightSim
	var staff := _main.get_node("Staff") as StaffSim
	var hired := StarterFlight.hire_per_station(_sim, staff)
	var doors := StarterFlight.advance_until_open(_clock, flights, staff)
	var flight := StarterFlight.first_flight()
	print("PROBE hired=%d opened_tick=%d doors_close=%d" % [hired, _clock.tick, doors])
	if hired < 4 or doors < 0 or not flights.flight_ids().has(flight):
		_invalid("airport failed to open with staffed stations")
		return false
	var stand_tick := flights.state_start(flight, FlightSim.State.AT_STAND)
	var push_tick := flights.state_start(flight, FlightSim.State.PUSHBACK)
	var target_tick := stand_tick + mini(70, maxi(20, (push_tick - stand_tick) / 6))
	var spawn_start := maxi(_clock.tick + 10, target_tick - 660)
	var spawned := 0
	while _clock.tick < target_tick:
		_beat()
		for _i in TICKS_PER_FRAME:
			if _clock.tick >= target_tick:
				break
			var due := _clock.tick >= spawn_start and (_clock.tick - spawn_start) % 24 == 0
			if due and spawned < 22 and _spawn_staged_passenger(flight, spawned):
				spawned += 1
			_clock.advance(SimClock.STEP)
		await process_frame
	for _i in 6:
		_clock.advance(SimClock.STEP)
		await process_frame
	print("PROBE stand_tick=%d target_tick=%d spawned=%d" % [stand_tick, target_tick, spawned])
	return _plane_at_gate("A") != null


func _spawn_staged_passenger(flight: String, idx: int) -> bool:
	var pid := _sim.spawn_now(flight)
	var pax := _sim.get_passenger(pid) if pid > 0 else null
	if pax == null:
		return false
	pax.carry_on = 1 + (idx % 2)
	pax.liquids = false
	pax.alarm = false
	if idx % 3 == 0:
		pax.hunger = 62
	return true


func _freeze_and_hide_ui() -> void:
	_beat()
	var fleet := _main.get_node("PlaneFleet") as PlaneFleet
	if fleet.has_method("update_views"):
		fleet.call("update_views")
	for view in fleet.views:
		view.update_pose()
		view.set_process(false)
	for node_name in FREEZE.split(","):
		var n := _main.get_node_or_null(node_name)
		if n != null:
			n.set_process(false)
	var roof := _main.get_node("RoofView") as RoofView
	roof.set_process(false)
	roof.draw_level(1.0)
	for extra in ["GapMarkers", "BuildableOutline", "MoodOverlay"]:
		var node3d := _main.get_node_or_null(extra) as Node3D
		if node3d != null:
			node3d.visible = false
	for layer in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for lbl in _main.find_children("*", "Label3D", true, false):
		(lbl as Label3D).visible = false
	for spr in _main.find_children("*", "Sprite3D", true, false):
		(spr as Sprite3D).visible = false


func _render_all_shots() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = false
	_vp.world_3d = root.world_3d
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_cam = Camera3D.new()
	_cam.far = 2500.0
	_vp.add_child(_cam)
	_cam.current = true
	var plane := _plane_at_gate("A")
	if plane == null:
		_invalid("no plane parked at Gate A")
		return
	var mid := _terminal_center().lerp(plane.global_position + Vector3(0.0, 1.1, 0.0), 0.36)
	await _capture(
		"raw_hero_3840x1240",
		Vector2i(3840, 1240),
		mid + Vector3(-0.5, 0.4, 5.5),
		Vector3(-20, 35, 55),
		26.0,
		plane,
		true
	)
	await _capture(
		"raw_landscape_2464x1412",
		Vector2i(2464, 1412),
		mid + Vector3(-4.2, 0.4, 2.6),
		Vector3(-22, 38, 56),
		32.0,
		plane,
		false
	)
	await _capture(
		"raw_portrait_1496x1792",
		Vector2i(1496, 1792),
		mid + Vector3(3.3, 0.4, -2.5),
		Vector3(-16, 38, 62),
		40.0,
		plane,
		false
	)


func _capture(
	shot: String,
	res: Vector2i,
	focus: Vector3,
	orbit: Vector3,
	fov: float,
	plane: PlaneView,
	hero: bool
) -> void:
	_beat(shot)
	_vp.size = res
	var basis := Basis.from_euler(Vector3(-deg_to_rad(orbit.y), deg_to_rad(orbit.x), 0.0))
	_cam.global_transform = Transform3D(basis, focus + basis.z * orbit.z)
	_cam.fov = fov
	var bv := _mode.get_node("BuildView") as BuildView
	bv.set_process(false)
	bv.cutaway_enabled = true
	bv.update_cutaway(_cam.global_basis.z)
	await _frames(8)
	await _verify_shot(shot, res, plane, hero)
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var out_path := _out_dir.path_join(shot + ".png")
	var err := img.save_png(out_path)
	print("PROBE saved %s size=%s err=%d" % [out_path, img.get_size(), err])
	if err != OK or img.get_size() != res:
		_invalid("%s failed to save at %s" % [shot, res])


func _verify_shot(shot: String, res: Vector2i, plane: PlaneView, is_hero: bool) -> void:
	var frame := Rect2(Vector2.ZERO, Vector2(res)).grow(-MARGIN_PX)
	var term_pt := _terminal_center() + Vector3(0.0, 1.0, 0.0)
	var plane_pt := plane.global_position + Vector3(0.0, 1.1, 0.0)
	var term_px := _cam.unproject_position(term_pt)
	var plane_px := _cam.unproject_position(plane_pt)
	for corner in _terminal_corners():
		if _cam.is_position_behind(corner) or not frame.has_point(_cam.unproject_position(corner)):
			_invalid("%s: terminal corner outside frame %s" % [shot, frame])
	var pax_pts := _active_passenger_points()
	var pax_in := 0
	for pt in pax_pts:
		if not _cam.is_position_behind(pt) and frame.has_point(_cam.unproject_position(pt)):
			pax_in += 1
	var owners: Array[Node] = []
	for name_str in OCCLUDERS.split(","):
		var node := _main.get_node_or_null(name_str)
		if node != null:
			owners.append(node)
	var holder := PlateSight.colliders(_main, owners, {plane: "plane"})
	await physics_frame
	var space := _cam.get_world_3d().direct_space_state
	var p_sight := PlateSight.sight_lines(space, _cam.global_position, [plane_pt], "plane")
	var c_sight := PlateSight.sight_lines(
		space, _cam.global_position, [term_pt - Vector3(0, 6, 0)], "none"
	)
	holder.free()
	print(
		(
			"PROBE in_frame %s res=%s term=%s plane=%s pax=%d/%d blockers=%s ctrl=%d"
			% [
				shot,
				res,
				term_px.round(),
				plane_px.round(),
				pax_in,
				pax_pts.size(),
				p_sight["blockers"],
				(c_sight["blockers"] as Array).size()
			]
		)
	)
	if _cam.is_position_behind(term_pt) or not frame.has_point(term_px):
		_invalid("%s: terminal center outside frame" % shot)
	if _cam.is_position_behind(plane_pt) or not frame.has_point(plane_px):
		_invalid("%s: plane outside frame" % shot)
	if pax_in < MIN_PAX_IN_FRAME:
		_invalid("%s: too few passengers in frame (%d)" % [shot, pax_in])
	if not (p_sight["blockers"] as Array).is_empty() or (c_sight["blockers"] as Array).is_empty():
		_invalid("%s: raycast check failed" % shot)
	if (
		is_hero
		and not Rect2((Vector2(res) - Vector2(1400, 680)) * 0.5, Vector2(1400, 680)).has_point(
			term_px
		)
	):
		_invalid("%s: terminal focal point %s outside center safe zone" % [shot, term_px])


func _terminal_center() -> Vector3:
	var at := ReferenceTerminal.offset_on(_grid)
	return (
		(_grid.cell_to_world(Vector2i(10, 2) + at) + _grid.cell_to_world(Vector2i(27, 17) + at))
		* 0.5
	)


func _terminal_corners() -> Array[Vector3]:
	var at := ReferenceTerminal.offset_on(_grid)
	return [
		_grid.cell_to_world(Vector2i(10, 2) + at),
		_grid.cell_to_world(Vector2i(27, 3) + at),
		_grid.cell_to_world(Vector2i(10, 17) + at),
		_grid.cell_to_world(Vector2i(27, 16) + at),
	]


func _plane_at_gate(gate: String) -> PlaneView:
	for view in (_main.get_node("PlaneFleet") as PlaneFleet).views:
		if view.gate == gate and view.visible and view.flight_id != "":
			return view
	return null


func _active_passenger_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for child in _main.get_node("PassengerViews").get_children():
		var n := child as Node3D
		if n != null and n.visible and n.find_child("Skeleton3D", true, false) != null:
			pts.append(n.global_position + Vector3(0.0, 1.0, 0.0))
	return pts


func _frames(count: int) -> void:
	for _i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _invalid(msg: String) -> void:
	print("PROBE_INVALID %s" % msg)
	_failed = true


func _beat(_tag := "") -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_mutex.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var age := Time.get_ticks_msec() - _beat_ms
		_mutex.unlock()
		if done:
			return
		if age > HANG_LIMIT_MS:
			printerr("PROBE_INVALID stalled %d ms" % age)
			OS.crash("store_key_art_probe hang")


func _finish() -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _vp != null:
		_vp.queue_free()
	if _main != null:
		_main.queue_free()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)
