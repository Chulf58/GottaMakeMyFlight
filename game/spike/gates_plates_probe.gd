extends SceneTree
## Plates of two planes parked at two gate stands (gates slice 1b, decision
## gates-technical-design-gate-desks-link-to-north-exits-one-st). One windowed
## run:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/gates_plates_probe.gd
## Boots main.tscn with a new random world seed (printed), fills the starter
## shell with the debug button (which adds gate desk A by its exit), buys the
## land for a second shell 44 cells east, builds it with a gate desk by its
## exit (gate B), hires a check-in agent and an officer, and lets the airport
## open with the starter contract at gate A. A second contract, departing just
## late enough to clear the runway and taxi lane, gets gate B. While both
## planes stand at their stands it saves three plates under
## tools/blender/out/gates-1b/: both stands from above, both from the apron
## side, and gate B close up with its exit and desk. Each plane must stand on
## its own gate's stand (within 5 cm). Before each save every subject point
## must project inside the window and the points it is about must have no mesh
## between them and the camera (a control under the ground must report one);
## otherwise PROBE_INVALID, exit 1. A guard thread ends a hang (anti-pattern
## a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/gates-1b"
const TICKS_PER_FRAME := 40
const OPEN_LIMIT := 6000
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 600000
const MARGIN_PX := 8.0
const OCCLUSION_STOP_M := 0.3
const SETTLE_FRAMES := 40
const EAST := Vector2i(44, 0)
const DESK_EAST := Vector2i(63, 115)
const SECOND := "GMF202"

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _out_dir := ""
var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _staff: StaffSim
var _grid: BuildGrid
var _mode: BuildMode
var _hud: PassengerHud
var _rig: TycoonCamera
var _cam: Camera3D
var _apron: ApronStand
var _gates: GateDesks
var _fleet: PlaneFleet


func _initialize() -> void:
	_beat("boot")
	_guard.start(_watch)
	var world_seed := randi()
	print("PROBE world_seed=%d" % world_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=%s" % _out_dir)
	_main = load(MAIN).instantiate()
	_clock = _main.get_node("SimClock")
	_clock.seed_rng(world_seed)
	_flights = _main.get_node("FlightSim")
	_staff = _main.get_node("Staff")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _run() -> void:
	await _frames(3)
	_mode = _main.get_node("BuildMode")
	_grid = _mode.grid
	_hud = _main.get_node("PassengerHud")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_apron = _main.get_node("ApronStand")
	_gates = _main.get_node("GateDesks")
	_fleet = _main.get_node("PlaneFleet")
	_hud.dismiss_intro()
	_clock.set_paused(true)
	_hud.press_starter_terminal()
	if not _build_east():
		return
	print("PROBE gates %s, stands %s" % [_gates.bindings, _apron.gate_stands])
	var two_gates: Array[String] = ["A", "B"]
	if _flights.gate_ids() != two_gates:
		_fail("the two gate desks did not make gates A and B")
		return
	_staff.hire(StaffMember.Role.CHECKIN)
	_staff.hire(StaffMember.Role.SECURITY)
	var hired_at := _clock.tick
	while _flights.opened_tick < 0:
		await _ticks(TICKS_PER_FRAME)
		if _clock.tick - hired_at > OPEN_LIMIT:
			_fail("the airport did not open %d ticks after hiring" % OPEN_LIMIT)
			return
	var starter := FlightSim.DEFAULT_ID
	if not _accept_second(starter):
		return
	# The two flights of the second contract's first day, once both are issued.
	var day: int = _flights.start_days[SECOND]
	var first := FlightTimetable.occurrence_id(starter, day)
	var second := FlightTimetable.occurrence_id(SECOND, day)
	while not (_flights.flight_ids().has(first) and _flights.flight_ids().has(second)):
		await _ticks(TICKS_PER_FRAME)
	# Both at their stands: the second has arrived, the first not yet pushed back.
	var both := maxi(
		_flights.state_start(second, FlightSim.State.AT_STAND),
		_flights.state_start(first, FlightSim.State.AT_STAND)
	)
	var until := mini(
		_flights.state_start(first, FlightSim.State.PUSHBACK),
		_flights.state_start(second, FlightSim.State.PUSHBACK)
	)
	print("PROBE %s and %s both parked from %d to %d" % [first, second, both, until])
	if until - both < 40:
		_fail("the two flights are never parked at once")
		return
	await _run_to(both + (until - both) / 2)
	await _plates(first, second)
	if not _done:
		print("PROBE_PASS plates")
		_finish(0)


## Buys the land for, and builds, a second shell 44 cells east with a gate
## desk by its exit. False (after _fail) when any of it is refused.
func _build_east() -> bool:
	var land := _mode.land_tool.land
	var shell := ReferenceTerminal.shell_edits(_mode.site.starter_offset + EAST)
	var wanted := {}
	for edit in shell:
		wanted[land.plot_of(edit.cell)] = true
	wanted[land.plot_of(DESK_EAST)] = true
	for plot: Vector2i in wanted:
		while not land.is_owned(plot):
			var best := Vector2i(-1, -1)
			var best_d := 1 << 30
			for candidate in land.buyable_plots():
				var d := absi(candidate.x - plot.x) + absi(candidate.y - plot.y)
				if d < best_d:
					best_d = d
					best = candidate
			if best == Vector2i(-1, -1) or not land.buy(best, null).ok:
				_fail("the land toward plot %s could not be bought" % plot)
				return false
	for result in _grid.apply_batch(shell):
		if not result.ok:
			_fail("the east shell was refused: %s" % result.reason_text())
			return false
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK_EAST, 0))
	if not desk.ok:
		_fail("the east gate desk was refused: %s" % desk.reason_text())
		return false
	return true


## Accepts a contract departing the fewest minutes after the starter that
## clears the shared runway and lane; it gets gate B, A being busy then.
func _accept_second(starter: String) -> bool:
	var minute: int = _flights.contract_of(starter)["departure_minute"]
	for later in range(40, 90):
		var terms := FlightSim.starter_terms(0)
		terms["id"] = SECOND
		terms["departure_minute"] = (minute + later) % GameCalendar.MINUTES_PER_DAY
		if _flights.accept_gate(terms) == "B":
			_flights.accept_contract(terms)
			print("PROBE second contract %d minutes after the starter, at gate B" % later)
			return true
	_fail("no departure after the starter's got gate B")
	return false


func _plates(first: String, second: String) -> void:
	var view_a := _view_of("A")
	var view_b := _view_of("B")
	var stand_a := StandPlacement.stand_point(_apron.gate_stands["A"]["live"])
	var stand_b := StandPlacement.stand_point(_apron.gate_stands["B"]["live"])
	if view_a == null or view_b == null:
		_fail("a gate has no plane drawn (A %s, B %s)" % [view_a, view_b])
		return
	for pair in [[view_a, stand_a, first], [view_b, stand_b, second]]:
		var view: PlaneView = pair[0]
		var off := view.global_position.distance_to(_parked(pair[1]))
		print(
			(
				"PROBE gate %s draws %s at %s, its stand %s, off by %.3f m"
				% [view.gate, view.flight_id, view.global_position, pair[1], off]
			)
		)
		if view.flight_id != pair[2] or off > 0.05:
			_fail("gate %s's plane is not %s at its own stand" % [view.gate, pair[2]])
			return
	var top_a := view_a.global_position + Vector3.UP * 3.0
	var top_b := view_b.global_position + Vector3.UP * 3.0
	var middle := (stand_a + stand_b) / 2.0
	_view(middle + Vector3(0.0, 0.0, 10.0), 95.0, 0.0)
	await _plate(
		"a_two_planes_from_above", [stand_a, stand_b], [], [[top_a, view_a], [top_b, view_b]]
	)
	if _done:
		return
	_view(middle + Vector3(0.0, 0.0, -5.0), 75.0, PI)
	await _plate(
		"b_two_planes_apron_side", [stand_a, stand_b], [], [[top_a, view_a], [top_b, view_b]]
	)
	if _done:
		return
	var exit_b := _grid.cell_to_world(_exit_cell("B")) + Vector3(0.0, 1.5, 0.0)
	var desk_b := _grid.cell_to_world(DESK_EAST) + Vector3(0.5, 2.3, 0.0)
	_view(stand_b + Vector3(0.0, 0.0, 12.0), 45.0, deg_to_rad(200.0))
	await _plate("c_gate_b_close", [stand_b, exit_b], [desk_b], [[top_b, view_b]])


## The PlaneView drawing gate `gate`'s parked plane, or null.
func _view_of(gate: String) -> PlaneView:
	for view in _fleet.views:
		if view.gate == gate and view.visible and view.flight_id != "":
			return view
	return null


func _exit_cell(gate: String) -> Vector2i:
	return _grid.get_object(_gates.binding_of(gate)["exit"])["anchor"]


func _view(focus: Vector3, distance: float, yaw: float) -> void:
	_rig.position = focus
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)


## Saves a plate once every `framed`, `visible` and `on_plane` point projects
## inside the window, no mesh hides a `visible` point, and no mesh other than
## its own plane's hides an `on_plane` point ([point, its PlaneView] pairs).
func _plate(label: String, framed: Array, visible: Array, on_plane: Array) -> void:
	_stage = "plate %s" % label
	await _frames(SETTLE_FRAMES)
	var view := root.get_visible_rect()
	var ok := true
	print(
		(
			"PLATE %s rig %s distance %.1f camera %s"
			% [label, _rig.position, _rig.distance, _cam.global_position]
		)
	)
	var control := _occluder(Vector3(-27.0, -2.0, -90.0))
	print("  CONTROL under the ground: %s" % (control if control != "" else "clear"))
	if control == "":
		_fail("%s: the occlusion control found nothing" % label)
		return
	var points: Array = framed + visible
	for pair: Array in on_plane:
		points.append(pair[0])
	for point: Vector3 in points:
		var p := _cam.unproject_position(point)
		var in_frame := view.grow(-MARGIN_PX).has_point(p) and not _cam.is_position_behind(point)
		print("  FRAMED %s -> %s in_frame=%s" % [point, p, in_frame])
		ok = ok and in_frame
	for point: Vector3 in visible:
		var occluder := _occluder(point)
		print("  OCCLUSION %s: %s" % [point, occluder if occluder != "" else "clear"])
		ok = ok and occluder == ""
	for pair: Array in on_plane:
		var occluder := _occluder(pair[0], pair[1])
		print("  OCCLUSION plane %s: %s" % [pair[0], occluder if occluder != "" else "clear"])
		ok = ok and occluder == ""
	if not ok:
		_fail("%s: a subject check failed" % label)
		return
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(label + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_fail("%s: not saved" % label)


## The first opaque mesh the camera-to-subject segment crosses, or "";
## meshes under `own` (the subject itself) do not count.
func _occluder(subject: Vector3, own: Node = null) -> String:
	var from := _cam.global_position
	var to := subject + (from - subject).normalized() * OCCLUSION_STOP_M
	var ghost := _main.get_node("BuildMode/Ghost")
	var best := ""
	var best_distance := INF
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree() or ghost.is_ancestor_of(node):
			continue
		if own != null and own.is_ancestor_of(node):
			continue
		var material := instance.material_override
		if material == null and instance.mesh.get_surface_count() > 0:
			material = instance.get_active_material(0)
		var base := material as BaseMaterial3D
		if base != null and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
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
			best = "%s at %s" % [instance.get_path(), world_hit]
	return best


func _run_to(tick: int) -> void:
	while _clock.tick < tick:
		await _ticks(mini(TICKS_PER_FRAME, tick - _clock.tick))


func _ticks(count: int) -> void:
	for i in count:
		_clock.set_paused(false)
		_clock.advance(SimClock.STEP)
		_clock.set_paused(true)
	_beat("tick %d" % _clock.tick)
	await process_frame


func _frames(count: int) -> void:
	for i in count:
		_beat(_stage)
		await process_frame


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
			OS.crash("gates plates probe hung")


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


## Where the plane rests over a stand point: on the ground there.
func _parked(stand_point: Vector3) -> Vector3:
	return stand_point + Vector3.UP * PlaneView.ground_height_at(stand_point)
