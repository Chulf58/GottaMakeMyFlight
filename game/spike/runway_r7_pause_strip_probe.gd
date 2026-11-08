extends SceneTree
## Runway R7 frame strip: a planned taxi pause played by the real game (board
## 4aa85bed; decision runway-and-taxi-technical-design-movement-plan-analytic-
## bookings-planned-pauses, section 4; user ruling a-gate-has-no-size-planes-
## use-any-stand-they-fit-neighbours-share-apron-space). One windowed run:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/runway_r7_pause_strip_probe.gd
## Boots main.tscn with a new random world seed (printed) and builds the two
## gates of gates_plates_probe.gd (the starter shell with desk A, a second
## shell 44 cells east with desk B), then opens the airport with the starter at
## gate A. It looks for a second contract at gate B that FlightSim plans with a
## pause (a scratch FlightSim loaded from the live save is run ahead to find
## out), accepts it, and runs the clock to the pause. Through every tick of the
## pause the paused plane's drawn position must stay within STOPPED_M of the
## hold line (the largest drift is printed). It saves five plates under
## tools/blender/out/runway-r7-pause/ (before, the pause's start, middle and
## end, after), the paused plane at least MOVED_M off the hold on the first and
## last; the rig is fitted to the hold and both planes' boxes, and before each
## save every corner of every drawn plane's box must project inside
## the window and have no mesh between it and the camera (a control under the
## ground must report one), else PROBE_INVALID, exit 1. A guard thread ends a
## hang.

const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/runway-r7-pause"
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
## The paused plane stands still to within this on the hold line.
const STOPPED_M := 0.05
## Ticks before and after the pause of the first and last plates.
const AROUND_TICKS := 60
## The paused plane is this far from the hold at least on the first and last plates.
const MOVED_M := 1.0
## The rig distances tried, nearest first, to frame both planes and the hold.
const FIT_DISTANCES: Array[float] = [140.0, 170.0, 200.0, 240.0, 280.0, 300.0]
const FIT_FRAMES := 4
## The fit keeps every point this far inside the window, so no plane hugs an edge.
const FIT_MARGIN_PX := 100.0
const VIEW_YAW_DEGREES := 200.0

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
	var day: int = _flights.start_days[SECOND]
	var first := FlightTimetable.occurrence_id(starter, day)
	var second := FlightTimetable.occurrence_id(SECOND, day)
	while not (_flights.flight_ids().has(first) and _flights.flight_ids().has(second)):
		await _ticks(TICKS_PER_FRAME)
	var paused := _paused_one([first, second])
	if paused.is_empty():
		_fail("neither %s nor %s has a planned pause" % [first, second])
		return
	await _strip(paused, first if paused["id"] == second else second)
	if not _done:
		print("PROBE_PASS strip")
		_finish(0)


## {"id", "state", "pause"} of the first of `ids` with a planned pause, or {}.
func _paused_one(ids: Array) -> Dictionary:
	for id: String in ids:
		var plan := _flights.taxi_plan(id)
		for state: int in plan:
			if not (plan[state] as Dictionary).is_empty():
				print("PROBE %s pauses in state %d: %s" % [id, state, plan[state]])
				return {"id": id, "state": state, "pause": plan[state]}
	return {}


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
	var save := _flights.to_snapshot()
	for later in range(20, 240, 2):
		var terms := FlightSim.starter_terms(0)
		terms["id"] = SECOND
		terms["departure_minute"] = minute + later
		if _flights.accept_gate(terms) != "B" or not _pauses_with(save, terms, starter):
			continue
		_flights.accept_contract(terms)
		print("PROBE second contract %d minutes after the starter, at gate B, pauses" % later)
		return true
	_fail("no departure after the starter's got gate B with a planned pause")
	return false


## Whether a scratch copy of the sim, given `terms`, plans a pause for the
## starter's or the new contract's occurrence of the new contract's first day.
func _pauses_with(save: Dictionary, terms: Dictionary, starter: String) -> bool:
	var scratch := FlightSim.new()
	scratch.gate_source = _flights.gate_source
	scratch.stand_source = _flights.stand_source
	var found := false
	if scratch.from_snapshot(save.duplicate(true)) and scratch.accept_contract(terms):
		var day: int = scratch.start_days[SECOND]
		var ids := [
			FlightTimetable.occurrence_id(starter, day), FlightTimetable.occurrence_id(SECOND, day)
		]
		var issue := FlightTimetable.issue_tick(scratch.contract_of(SECOND), day)
		for t in range(scratch.tick + 1, issue + 1):
			scratch.on_tick(t)
		for id: String in ids:
			for pause: Dictionary in scratch.taxi_plan(id).values():
				found = found or not pause.is_empty()
	scratch.free()
	return found


## Runs the clock through the pause of `paused` ({"id", "state", "pause"}),
## checking every tick that its drawn plane stands on the hold line, and saves
## the strip's plates with both planes framed. The plan holds the plane for
## elapsed ticks t1 to t1 + pause_ticks, so the held ticks are the pause_ticks
## whole ticks from ceil(start + t1) on.
func _strip(paused: Dictionary, other: String) -> void:
	var id: String = paused["id"]
	var state: int = paused["state"]
	var gate := _flights.flight_gate(id)
	var plane_class: String = _flights.contract_of(_flights.flight_contract_id(id))["plane_size"]
	var airside: Airside = _main.get_node("Airside")
	var route := airside.phase_path(state, gate, plane_class)
	var start := _flights.state_start(id, state)
	var budget := float(_flights.state_start(id, state + 1) - start)
	var plan := MovementPlan.taxi(route, budget, paused["pause"])
	var hold := MovementPlan.point_at(route, paused["pause"]["hold_s"])
	var pause_ticks: int = plan["pause_ticks"]
	var from := ceili(start + float(plan["t1"]))
	var to := from + pause_ticks - 1
	print(
		(
			"PROBE %s holds at %s from tick %d to %d (%d ticks, planned %d)"
			% [id, hold, from, to, to - from + 1, pause_ticks]
		)
	)
	var ticks := [from - AROUND_TICKS, from, (from + to) / 2, to, to + AROUND_TICKS]
	var labels := ["a_before", "b_pause_start", "c_pause_middle", "d_pause_end", "e_after"]
	# The HUD panels are not meshes, so the occlusion rays cannot see them: with
	# them shown, a plane in frame can sit under the Departures panel.
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var drift := 0.0
	var held := 0
	for i in ticks.size():
		var at: int = ticks[i]
		while _clock.tick < at:
			await _ticks(1)
			if _clock.tick >= from and _clock.tick <= to:
				_fleet.update_views()
				var view := _view_of_flight(id)
				if view == null:
					_fail("%s is not drawn at tick %d" % [id, _clock.tick])
					return
				drift = maxf(drift, _flat_offset(view, hold))
				held += 1
		if i == 3:
			print(
				(
					"PROBE %s held %d ticks of %d planned, largest drift from the hold %.4f m"
					% [id, held, pause_ticks, drift]
				)
			)
			if drift > STOPPED_M or held != pause_ticks:
				_fail("%s did not stand at the hold line through its pause" % id)
				return
		_fleet.update_views()
		var subject := _view_of_flight(id)
		if subject == null:
			_fail("%s is not drawn at tick %d" % [id, _clock.tick])
			return
		var off := _flat_offset(subject, hold)
		print("PROBE tick %d: %s is %.3f m from the hold" % [_clock.tick, id, off])
		var moving := i == 0 or i == 4
		if (moving and off <= MOVED_M) or (not moving and off > STOPPED_M):
			_fail("%s: %s is %.3f m from the hold at tick %d" % [labels[i], id, off, _clock.tick])
			return
		var framed: Array = [hold]
		var on_plane: Array = []
		for flight in [id, other]:
			var view := _view_of_flight(flight)
			if view != null:
				var box := _aabb_of(view)
				if not box.has_volume():
					_fail("%s: %s is drawn with no mesh" % [labels[i], flight])
					return
				framed.append_array(_corners(box))
				on_plane.append([view.global_position + Vector3.UP * 3.0, view])
		print("PROBE tick %d: %d of 2 planes drawn" % [_clock.tick, on_plane.size()])
		await _fit(framed)
		await _plate(labels[i], framed, [], on_plane)
		if _done:
			return


## How far `view` stands from `point` across the ground, in metres.
func _flat_offset(view: Node3D, point: Vector3) -> float:
	return Vector2(view.global_position.x - point.x, view.global_position.z - point.z).length()


## Points the rig at the middle of `points` across the ground and steps out
## through FIT_DISTANCES to the first distance that projects all of them
## FIT_MARGIN_PX inside the window (the last when none does; _plate() then
## checks against MARGIN_PX and fails loudly).
func _fit(points: Array) -> void:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector3 in points:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.z))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.z))
	var middle := (low + high) * 0.5
	var frame := root.get_visible_rect().grow(-FIT_MARGIN_PX)
	for distance in FIT_DISTANCES:
		_view(Vector3(middle.x, 0.0, middle.y), distance, deg_to_rad(VIEW_YAW_DEGREES))
		await _frames(FIT_FRAMES)
		var fits := true
		for point: Vector3 in points:
			if (
				_cam.is_position_behind(point)
				or not frame.has_point(_cam.unproject_position(point))
			):
				fits = false
				break
		print("  FIT distance %.0f fits=%s" % [distance, fits])
		if fits:
			return


## The world box around every mesh drawn under `node`.
func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var instance := found as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		var bounds: AABB = instance.global_transform * instance.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return box


func _corners(box: AABB) -> Array:
	var out: Array = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


## The PlaneView drawing flight `id`, or null.
func _view_of_flight(id: String) -> PlaneView:
	for view in _fleet.views:
		if view.flight_id == id and view.visible:
			return view
	return null


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
