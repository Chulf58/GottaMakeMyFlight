extends SceneTree
## Probe of the new-game starter shell on the real main scene (decision
## terminal-growth-and-starter-building-move-the-airside-north).
##
## Headless (the default):
##   Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/starter_building_probe.gd
## Boots main.tscn with a new random world seed (printed) and checks the shell
## a new game starts with: one entrance, one exit, no desks, the wallet still at
## the starting budget and no rescue grant after CLOSED_TICKS ticks. It presses
## the Debug panel's Starter terminal button, checks the reference interior
## arrived, hires a check-in agent and a security officer, and runs until the
## starter flight has departed. Pass values are positives, printed as compared:
## the passengers seen at a check-in desk, the passengers seen boarded (on the
## apron or made), and the check-in positions that fell inside the starter's
## footprint (all of them must). Otherwise it prints PROBE_INVALID and exits 1.
##
## Windowed plates (one windowed Godot run project-wide; hold the slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/starter_building_probe.gd -- --plates
## Runs the shell checks, then saves four plates under
## tools/blender/out/starter-building/: the start view and a far view (roof
## drawn) of the bare shell, the same two after the debug fill. Before each save
## it proves the footprint corners project inside the window clear of every HUD
## panel, that the points the plate is about are not hidden by a mesh (a
## positive control: a point under the ground must report one), and that the
## roof is gone at the start view and drawn at the far view; otherwise
## PROBE_INVALID, exit 1.
##
## A guard thread ends a hang (anti-pattern a-frame-counting-watchdog-cannot-
## catch-a-stuck-main-thread).

const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/starter-building"
const CLOSED_TICKS := 300
const TICKS_PER_FRAME := 40
const OPEN_LIMIT := 4000
const HANG_LIMIT_MS := 30000
const TOTAL_LIMIT_MS := 420000
const MARGIN_PX := 8.0
const OCCLUSION_STOP_M := 0.1
## The roof shows above RoofView.roof_show_above (120 m); this is past it.
const FAR_DISTANCE := 150.0
const FADE_FRAMES := 90
const ROOF_TOP_M := 5.2

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _plates := false
var _out_dir := ""
var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _sim: PassengerSim
var _staff: StaffSim
var _grid: BuildGrid
var _hud: PassengerHud
var _menu: BuildMenu
var _roof: RoofView
var _rig: TycoonCamera
var _cam: Camera3D
var _grants := 0
var _checked_in := {}
var _boarded := {}
var _desk_positions := 0
var _desk_positions_inside := 0
var _first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	_plates = OS.get_cmdline_user_args().has("--plates")
	var world_seed := randi()
	print("PROBE world_seed=%d plates=%s" % [world_seed, _plates])
	if _plates:
		_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
		DirAccess.make_dir_recursive_absolute(_out_dir)
		print("PROBE out_dir=%s" % _out_dir)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	(_main.get_node("RescueGrant") as RescueGrant).granted.connect(_on_granted)
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _run() -> void:
	# BuildMode builds its grid when it enters the tree, after _initialize().
	await _frames(3)
	_grid = (_main.get_node("BuildMode") as BuildMode).grid
	_hud = _main.get_node("PassengerHud")
	_menu = _main.get_node("BuildMenu")
	_roof = _main.find_child("RoofView", true, false) as RoofView
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	# The intro dialogue covers the view; closing it unpauses the clock.
	_hud.dismiss_intro()
	_clock.set_paused(true)
	if not await _shell_and_closed():
		return
	if _plates:
		await _plate_pair("a_shell", false)
	if _done or not _fill():
		return
	if _plates:
		await _plate_pair("b_filled", true)
		if not _done:
			print("PROBE_PASS plates")
			_finish(0)
		return
	_staff.hire(StaffMember.Role.CHECKIN)
	_staff.hire(StaffMember.Role.SECURITY)
	var hired_at := _clock.tick
	while _flights.opened_tick < 0:
		await _ticks(TICKS_PER_FRAME)
		if _clock.tick - hired_at > OPEN_LIMIT:
			_fail("the airport did not open %d ticks after hiring" % OPEN_LIMIT)
			return
	print("PROBE opened hired_at=%d opened_tick=%d" % [hired_at, _flights.opened_tick])
	var limit := 3 * FlightTimetable.ISSUE_LEAD_TICKS + 2600
	while _flights.state_of(_first) != FlightSim.State.DEPARTED:
		await _ticks(TICKS_PER_FRAME, true)
		if _clock.tick - _flights.opened_tick > limit:
			_fail("the starter's first flight never departed")
			return
	_report_passengers()


func _frames(count: int) -> void:
	for i in count:
		_beat(_stage)
		await process_frame


## `count` ticks, then a frame; sampling the passengers each tick when asked.
func _ticks(count: int, sample := false) -> void:
	for i in count:
		_clock.set_paused(false)
		_clock.advance(SimClock.STEP)
		_clock.set_paused(true)
		if sample:
			_sample()
	_beat("tick %d" % _clock.tick)
	await process_frame


func _counts() -> Dictionary:
	var kinds := ReferenceTerminal.object_ids(_grid)
	var floors := 0
	for y in _grid.size.y:
		for x in _grid.size.x:
			if _grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE:
				floors += 1
	var divider := 0
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		if _grid.has_wall(Vector2i(x, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH):
			divider += 1
	return {
		"floors": floors,
		"entrances": (kinds["entrances"] as Array).size(),
		"exits": (kinds["exits"] as Array).size(),
		"desks": (kinds["desks"] as Array).size(),
		"scanners": (kinds["scanners"] as Array).size(),
		"seats": (kinds["seats"] as Array).size(),
		"divider": divider,
	}


func _shell_and_closed() -> bool:
	var shell := _counts()
	print("PROBE shell %s" % [shell])
	if (
		shell["floors"] != 12 * 16
		or shell["entrances"] != 1
		or shell["exits"] != 1
		or shell["desks"] != 0
		or shell["scanners"] != 0
		or shell["seats"] != 0
		or shell["divider"] != 0
	):
		_fail("the new game did not start with the bare shell")
		return false
	for i in CLOSED_TICKS / TICKS_PER_FRAME + 1:
		await _ticks(TICKS_PER_FRAME)
	var wallet: Wallet = (_main.get_node("Finances") as Finances).wallet
	print(
		(
			"PROBE closed ticks=%d balance=%d (expected %d) grants=%d opened_tick=%d"
			% [
				_clock.tick,
				wallet.balance,
				PriceTable.STARTING_BUDGET,
				_grants,
				_flights.opened_tick
			]
		)
	)
	if wallet.balance != PriceTable.STARTING_BUDGET or _grants != 0 or _flights.opened_tick != -1:
		_fail("the shell start paid a grant, spent money or opened by itself")
		return false
	return true


func _fill() -> bool:
	_hud.press_starter_terminal()
	var filled := _counts()
	print("PROBE filled status='%s' %s" % [_hud.status_text(), filled])
	if (
		filled["desks"] < 1
		or filled["scanners"] < 1
		or filled["seats"] < 1
		or filled["divider"] < 1
		or filled["entrances"] != 1
		or filled["exits"] != 1
	):
		_fail("the debug button did not fill the shell with the reference interior")
		return false
	return true


func _report_passengers() -> void:
	print(
		(
			"PROBE passengers through_check_in=%d boarded=%d desk_positions=%d inside_footprint=%d"
			% [_checked_in.size(), _boarded.size(), _desk_positions, _desk_positions_inside]
		)
	)
	if _checked_in.size() < 1 or _boarded.size() < 1:
		_fail("no passenger went through the starter's check-in and boarded")
		return
	if _desk_positions < 1 or _desk_positions_inside != _desk_positions:
		_fail("a passenger checked in outside the starter's footprint")
		return
	print("PROBE_PASS")
	_finish(0)


## Notes each passenger standing at a check-in desk (and where) and each one on
## the apron or made, once a tick.
func _sample() -> void:
	var low := ReferenceTerminal.FLOOR_MIN
	var high := ReferenceTerminal.FLOOR_MAX
	for id in _sim.passenger_ids():
		var p := _sim.get_passenger(id)
		if p.stage == Passenger.Stage.CHECKIN:
			_checked_in[id] = true
			_desk_positions += 1
			if p.at.x >= low.x and p.at.x <= high.x and p.at.y >= low.y and p.at.y <= high.y:
				_desk_positions_inside += 1
		elif p.stage == Passenger.Stage.APRON or p.stage == Passenger.Stage.MADE:
			_boarded[id] = true


## The start view (roof gone, the interior open) and a far view (roof drawn) of
## the building as it stands.
func _plate_pair(prefix: String, filled: bool) -> void:
	await _frames(FADE_FRAMES)
	print("PROBE %s roof level at the start view: %.2f" % [prefix, _roof.cutaway.roof_level])
	if _roof.cutaway.roof_level < 1.0:
		_fail("%s: the roof is still drawn at the start view" % prefix)
		return
	await _plate("%s_start_view" % prefix, _corner_points(), _interior_points(filled))
	if _done:
		return
	var home := _rig.position
	_rig.distance = FAR_DISTANCE
	# zoom() applies the distance to the camera node at once.
	_rig.zoom(1.0)
	await _frames(FADE_FRAMES)
	print("PROBE %s roof level at the far view: %.2f" % [prefix, _roof.cutaway.roof_level])
	if _roof.cutaway.roof_level > 0.0:
		_fail("%s: the roof is not drawn at the far view" % prefix)
		return
	await _plate("%s_far_view" % prefix, _corner_points(), [_roof_point()])
	_rig.position = home
	_rig.frame_start_view(StartView.area_for(_grid))
	await _frames(FADE_FRAMES)


func _corner_points() -> Array:
	var low := ReferenceTerminal.FLOOR_MIN
	var high := ReferenceTerminal.FLOOR_MAX + Vector2i.ONE
	return [
		_grid.cell_to_world(low),
		_grid.cell_to_world(Vector2i(high.x, low.y)),
		_grid.cell_to_world(Vector2i(low.x, high.y)),
		_grid.cell_to_world(high),
	]


## The footprint's middle at roof height, a point on the roof's top.
func _roof_point() -> Vector3:
	var low := ReferenceTerminal.FLOOR_MIN
	var high := ReferenceTerminal.FLOOR_MAX + Vector2i.ONE
	var middle := (_grid.cell_to_world(low) + _grid.cell_to_world(high)) / 2.0
	return middle + Vector3(0.0, ROOF_TOP_M, 0.0)


## Floor points in the open interior: the cell in front of each desk and
## scanner (and an aisle cell) when the interior is filled, the hall's quarter
## points when it is the bare shell.
func _interior_points(filled: bool) -> Array:
	var out: Array = []
	if not filled:
		for cell in [Vector2i(13, 5), Vector2i(18, 5), Vector2i(13, 13), Vector2i(18, 13)]:
			out.append(_grid.cell_to_world(cell))
		return out
	var kinds := ReferenceTerminal.object_ids(_grid)
	for kind in ["desks", "scanners"]:
		for id in kinds[kind]:
			out.append(_grid.cell_to_world(_grid.interaction_cell(id)))
	# Seat rows have no front cell; the aisle beside them stands in.
	out.append(_grid.cell_to_world(Vector2i(18, 4)))
	return out


## Saves a plate after the checks: `framed` points inside the window by
## MARGIN_PX (a corner under a HUD card is printed, not failed), `visible`
## points inside, clear of every HUD panel and with nothing opaque between them
## and the camera.
func _plate(label: String, framed: Array, visible: Array) -> void:
	_stage = "plate %s" % label
	var view := root.get_visible_rect()
	var panels := _panels()
	var ok := true
	print("PLATE %s window=%s" % [label, view.size])
	print(
		(
			"  CAMERA rig_distance=%.1f camera_at=%s focus=%s"
			% [_rig.distance, _cam.global_position, _rig.position]
		)
	)
	var under := _grid.cell_to_world(ReferenceTerminal.FLOOR_MIN) + Vector3(0.0, -1.0, 0.0)
	var control := _occluder(under)
	print("  CONTROL point under the ground: %s" % (control if control != "" else "clear"))
	if control == "":
		_fail("%s: the occlusion check found nothing above a point under the ground" % label)
		return
	for point in framed:
		ok = _framed(point, view, panels, "FRAMED", false) and ok
	for point in visible:
		var framed_ok := _framed(point, view, panels, "VISIBLE")
		var occluder := _occluder(point)
		print("    OCCLUSION %s: %s" % [point, occluder if occluder != "" else "clear"])
		ok = framed_ok and occluder == "" and ok
	if not ok:
		_fail("%s: a subject check failed" % label)
		return
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(label + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_fail("%s: the plate was not saved (error %d)" % [label, err])


## Whether `point` projects inside the window by MARGIN_PX, in front of the
## camera and under no HUD panel; prints where it landed.
func _framed(
	point: Vector3, view: Rect2, panels: Dictionary, tag: String, panel_clear := true
) -> bool:
	var p := _cam.unproject_position(point)
	var in_frame := view.grow(-MARGIN_PX).has_point(p) and not _cam.is_position_behind(point)
	var covered := ""
	for key in panels:
		if (panels[key] as Rect2).has_point(p):
			covered = key
	print("  %s %s -> %s in_frame=%s covered_by='%s'" % [tag, point, p, in_frame, covered])
	return in_frame and (covered == "" or not panel_clear)


## The first opaque mesh triangle the camera-to-subject segment crosses, as a
## description, or "" for a clear line. The game has no colliders, so the test
## runs on mesh triangles (AABB first); the segment stops OCCLUSION_STOP_M short
## of the subject so the ground it stands on does not count, and the build
## ghost and transparent materials are skipped.
func _occluder(subject: Vector3) -> String:
	var from := _cam.global_position
	var to := subject + (from - subject).normalized() * OCCLUSION_STOP_M
	var ghost := _main.get_node("BuildMode/Ghost")
	var best := ""
	var best_distance := INF
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree() or ghost.is_ancestor_of(node):
			continue
		if _is_transparent(instance):
			continue
		var xform := instance.global_transform
		if (xform * instance.get_aabb()).intersects_segment(from, to) == null:
			continue
		var inverse := xform.affine_inverse()
		var hit: Dictionary = instance.mesh.generate_triangle_mesh().intersect_segment(
			inverse * from, inverse * to
		)
		if hit.is_empty():
			continue
		var world_hit: Vector3 = xform * (hit["position"] as Vector3)
		var distance := from.distance_to(world_hit)
		if distance < best_distance:
			best_distance = distance
			best = (
				"%s hit at %s, %.2f m from the camera" % [instance.get_path(), world_hit, distance]
			)
	return best


func _is_transparent(instance: MeshInstance3D) -> bool:
	var material := instance.material_override
	if material == null and instance.mesh.get_surface_count() > 0:
		material = instance.get_active_material(0)
	var base := material as BaseMaterial3D
	return base != null and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


## The on-screen rect of every visible HUD panel.
func _panels() -> Dictionary:
	var out := {}
	out["bar"] = _menu.bar().get_global_rect()
	if _menu.is_tray_open():
		out["tray"] = _menu.tray().get_global_rect()
	if _menu.status_label().text != "":
		out["status"] = _menu.status_label().get_global_rect()
	out["money"] = (_menu.find_child("MoneySlot", true, false) as Control).get_global_rect()
	out["flight"] = (_hud.find_child("FlightPanel", true, false) as Control).get_global_rect()
	out["debug"] = (_hud.find_child("DebugCorner", true, false) as Control).get_global_rect()
	var hint := _main.find_child("StaffHintCard", true, false) as Control
	if hint != null and hint.is_visible_in_tree():
		out["staff_hint"] = hint.get_global_rect()
	return out


func _on_granted(_amount: int, _message: String) -> void:
	_grants += 1


func _beat(stage: String) -> void:
	_mutex.lock()
	_beat_ms = Time.get_ticks_msec()
	_stage = stage
	_mutex.unlock()


func _watch() -> void:
	var started := Time.get_ticks_msec()
	while true:
		OS.delay_msec(500)
		_mutex.lock()
		var done := _done
		var beat := _beat_ms
		var stage := _stage
		_mutex.unlock()
		if done:
			return
		var now := Time.get_ticks_msec()
		if now - beat > HANG_LIMIT_MS or now - started > TOTAL_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang in stage '%s': %d ms since the last beat, %d ms in all"
					% [stage, now - beat, now - started]
				)
			)
			OS.crash("starter building probe hung")


func _fail(reason: String) -> void:
	print("PROBE_INVALID %s" % reason)
	_finish(1)


func _finish(code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	if _guard.is_started():
		_guard.wait_to_finish()
	if _main != null:
		_main.queue_free()
	quit(code)
