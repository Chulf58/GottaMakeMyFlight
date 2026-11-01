extends SceneTree
## Plates of the plane stand after the airside moved north (decision plane-
## stand-design-airside-moves-110-m-north-stand-snaps-to). One windowed run:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/plane_stand_plates_probe.gd
## Boots main.tscn with a new random world seed (printed), fills the starter
## shell with the debug button, hires a check-in agent and an officer, and
## follows the first flight: its landing on the runway at z -310 seen from the
## camera's focus clamp, a taxi-in strip, the plane nose-in at the north exit
## (from above and from the apron), the guarded area, a passenger between the
## exit and the plane door and a pushback strip. After its TAKEOFF it opens a
## second north exit and blocks the starter exit's straight walk, so the stand
## moves; the next day's flight flies the lead-in pass whose shadow crosses the
## terminal and parks at the new stand. Plates go under
## tools/blender/out/plane-stand/. Before each save every subject point must
## project inside the window, and the points it is about must have no mesh
## between them and the camera (a control under the ground must report one);
## otherwise PROBE_INVALID, exit 1. A guard thread ends a hang (anti-pattern
## a-frame-counting-watchdog-cannot-catch-a-stuck-main-thread).

const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/plane-stand"
const TICKS_PER_FRAME := 40
const FAST_TICKS_PER_FRAME := 400
const OPEN_LIMIT := 4000
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 900000
const MARGIN_PX := 8.0
const OCCLUSION_STOP_M := 0.3
const SETTLE_FRAMES := 40
const STRIP_SCALE := 0.5
## The second exit, in the shell's north wall, and the floor that makes the
## starter exit's walk go round.
const NEW_EXIT := Vector2i(10, 112)
const BLOCK := Vector2i(20, 110)

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _out_dir := ""
var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _sim: PassengerSim
var _staff: StaffSim
var _grid: BuildGrid
var _hud: PassengerHud
var _rig: TycoonCamera
var _cam: Camera3D
var _apron: ApronStand
var _plane: PlaneView
var _site: SiteDefinition


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
	_sim = _main.get_node("PassengerSim")
	_staff = _main.get_node("Staff")
	root.add_child(_main)
	current_scene = _main
	_clock.set_paused(true)
	_run.call_deferred()


func _run() -> void:
	await _frames(3)
	var build_mode: BuildMode = _main.get_node("BuildMode")
	_grid = build_mode.grid
	_site = build_mode.site
	_hud = _main.get_node("PassengerHud")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_apron = _main.get_node("ApronStand")
	_plane = _main.get_node("PlaneView")
	_hud.dismiss_intro()
	_clock.set_paused(true)
	_hud.press_starter_terminal()
	var desks: Array = ReferenceTerminal.object_ids(_grid)["desks"]
	print("PROBE desks after the debug fill: %d, live stand %s" % [desks.size(), _apron.live])
	if desks.size() != 2:
		_fail("the debug fill did not put the reference interior in the shell")
		return
	_staff.hire(StaffMember.Role.CHECKIN)
	_staff.hire(StaffMember.Role.SECURITY)
	var hired_at := _clock.tick
	while _flights.opened_tick < 0:
		await _ticks(TICKS_PER_FRAME)
		if _clock.tick - hired_at > OPEN_LIMIT:
			_fail("the airport did not open %d ticks after hiring" % OPEN_LIMIT)
			return
	while _flights.flight_ids().is_empty():
		await _ticks(TICKS_PER_FRAME)
	var first: String = _flights.flight_ids()[0]
	print("PROBE opened at %d, first flight %s" % [_flights.opened_tick, first])
	await _first_flight(first)
	if _done:
		return
	await _next_flight(first)
	if not _done:
		print("PROBE_PASS plates")
		_finish(0)


func _first_flight(id: String) -> void:
	var starter := StandPlacement.stand_point(_apron.live)
	await _run_to(_at(id, FlightSim.State.LANDING, 0.45))
	# Focus asked for beyond the runway: the rig's bounds clamp it at z -260.
	_rig.glide_to(Vector3(-80.0, 0.0, -330.0), 170.0)
	await _frames(SETTLE_FRAMES)
	while _rig.is_gliding():
		await _frames(1)
	print("PROBE focus clamp: rig at %s (bounds %.0f)" % [_rig.position, _rig.bounds_half_extent])
	if _rig.position.z < -_rig.bounds_half_extent - 0.01:
		_fail("the camera focus was not clamped")
		return
	var touchdown: Vector3 = (_main.get_node("Airside") as Airside).graph.position_of(&"Touchdown")
	await _plate(
		"a_landing_from_focus_clamp", [touchdown], [], [_plane.global_position + Vector3.UP * 2.0]
	)
	if _done:
		return
	_view(Vector3(0.0, 0.0, -190.0), 230.0, 0.0)
	await _strip("b_taxi_in_strip", id, FlightSim.State.TAXI_IN, [0.1, 0.35, 0.6, 0.85, 1.0])
	if not _done:
		await _at_the_stand(id, starter)


func _at_the_stand(id: String, starter: Vector3) -> void:
	await _run_to(_at(id, FlightSim.State.BOARDING, 0.15))
	print(
		(
			"PROBE parked at %s, starter stand %s, distance %.3f"
			% [_plane.global_position, starter, _plane.global_position.distance_to(starter)]
		)
	)
	if _plane.global_position.distance_to(starter) > 0.05:
		_fail("the plane is not at the starter stand while boarding")
		return
	var exit_point := _grid.cell_to_world(ReferenceTerminal.EXIT_CELL + _site.starter_offset)
	var gap := Vector3(exit_point.x, 0.3, exit_point.z - 1.6)
	var door := StandPlacement.door_point(_apron.live) + Vector3(0.0, 2.0, 0.0)
	_view(starter + Vector3(0.0, 0.0, 6.0), 55.0, PI / 2.0)
	await _plate(
		"c_nose_in_top",
		[starter, exit_point],
		[gap, Vector3(exit_point.x, 1.5, exit_point.z - 0.8)]
	)
	if _done:
		return
	_view(starter + Vector3(4.0, 0.0, 8.0), 34.0, deg_to_rad(160.0))
	await _plate("d_nose_in_apron_side", [starter, exit_point], [gap], [door])
	if _done:
		return
	var rects := _apron.guard_rects()
	print("PROBE guarded rects %s" % [rects])
	if rects.size() != 2:
		_fail("the guarded area is not shown while the plane is at the stand")
		return
	var corner_low := Vector3(rects[0].position.x, 0.3, rects[0].end.y)
	var corner_north := Vector3(rects[1].get_center().x, 0.3, rects[1].position.y + 5.0)
	_view(Vector3(starter.x, 0.0, -170.0), 240.0, 0.0)
	await _plate(
		"e_guarded_area", [corner_low, corner_north], [Vector3(starter.x + 15.0, 0.35, -180.0)]
	)
	if not _done:
		await _departure(id, starter, exit_point, door)


func _departure(id: String, starter: Vector3, exit_point: Vector3, door: Vector3) -> void:
	await _walker(id, exit_point, door)
	if _done:
		return
	_view(starter + Vector3(0.0, 0.0, -20.0), 110.0, 0.0)
	await _strip("g_pushback_strip", id, FlightSim.State.PUSHBACK, [0.0, 0.35, 0.65, 1.0])
	if _done:
		return
	_view(Vector3(starter.x - 30.0, 0.0, -215.0), 200.0, 0.0)
	await _strip("h_taxi_out_start_strip", id, FlightSim.State.TAXI_OUT, [0.05, 0.2, 0.4, 0.7])


func _walker(id: String, exit_point: Vector3, door: Vector3) -> void:
	var end := _flights.state_start(id, FlightSim.State.DOORS_CLOSED)
	while _clock.tick < end:
		for pid in _sim.passenger_ids():
			var p := _sim.get_passenger(pid)
			if p.stage != Passenger.Stage.APRON:
				continue
			var at := _sim.world_position(p)
			if at.z < exit_point.z - 1.5 and at.z > door.z + 1.0:
				print(
					(
						"PROBE walker %d at %s between exit %s and door %s"
						% [pid, at, exit_point, door]
					)
				)
				_view(Vector3(exit_point.x, 0.0, exit_point.z - 4.0), 22.0, deg_to_rad(110.0))
				await _plate("f_walker_exit_to_door", [exit_point, door], [at + Vector3.UP * 1.0])
				return
		await _ticks(2)
	_fail("no passenger was seen between the exit and the plane door")


func _next_flight(first: String) -> void:
	await _run_to(_flights.state_start(first, FlightSim.State.TAKEOFF) + 5)
	var before := _apron.live.duplicate()
	var opened := _grid.apply(BuildEdit.remove_wall(NEW_EXIT, BuildGrid.Side.NORTH))
	if not opened.ok:
		_fail("the wall at the new exit could not be removed: %s" % opened.reason_text())
		return
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", NEW_EXIT, 0))
	var blocked := _grid.apply(BuildEdit.paint_floor(BLOCK, BuildGrid.FLOOR_TILE, 1))
	print(
		(
			"PROBE exit change: new exit %s (%s), block %s; stand %s -> %s"
			% [placed.ok, placed.reason_text(), blocked.ok, before, _apron.live]
		)
	)
	if not placed.ok or int(_apron.live["exit"]) != placed.object_id:
		_fail("the stand did not move to the new exit after the takeoff")
		return
	var moved := StandPlacement.stand_point(_apron.live)
	var next := ""
	while next == "":
		await _ticks(FAST_TICKS_PER_FRAME)
		for fid in _flights.flight_ids():
			if fid != first and _flights.state_of(fid) < FlightSim.State.DEPARTED:
				next = fid
	var starts := _plane.starts_of(next)
	print("PROBE next flight %s full lead-in %s" % [next, _plane.has_full_lead_in(next)])
	var pass_tick := _shadow_tick(starts)
	if pass_tick < 0:
		_fail("the lead-in pass never puts the shadow on the terminal")
		return
	await _run_to(pass_tick)
	_rig.frame_start_view(StartView.area_for(_grid))
	await _frames(SETTLE_FRAMES * 2)
	var shadow := _plane.shadow_ground_point()
	print("PROBE plane at %s, shadow on %s" % [_plane.global_position, shadow])
	await _plate("i_shadow_pass_over_terminal", [shadow], [shadow + Vector3.UP * 0.4])
	if _done:
		return
	await _run_to(_at(next, FlightSim.State.BOARDING, 0.1))
	print(
		(
			"PROBE next flight parked at %s, moved stand %s, distance %.3f"
			% [_plane.global_position, moved, _plane.global_position.distance_to(moved)]
		)
	)
	if _plane.global_position.distance_to(moved) > 0.05:
		_fail("the next flight did not park at the moved stand")
		return
	var old_gap := _grid.cell_to_world(ReferenceTerminal.EXIT_CELL + _site.starter_offset)
	_view(moved + Vector3(4.0, 0.0, 4.0), 70.0, PI / 2.0)
	await _plate(
		"j_stand_moved_next_flight",
		[moved, old_gap],
		[_grid.cell_to_world(NEW_EXIT) + Vector3(0.0, 1.5, -0.8)]
	)


## The tick in the lead-in whose shadow lands nearest the starter's middle.
func _shadow_tick(starts: Array[int]) -> int:
	var middle := Vector3(-27.0, 0.0, -90.0)
	var best := -1
	var best_d := 1e9
	for t in range(starts[0] - 1200, starts[FlightSim.State.APPROACH]):
		var pose := _plane.pose_at(starts, float(t))
		if pose.is_empty():
			continue
		var ground := _plane.ground_point_of((pose["transform"] as Transform3D).origin)
		var d := Vector2(ground.x - middle.x, ground.z - middle.z).length()
		if d < best_d:
			best_d = d
			best = t
	print("PROBE shadow pass tick %d, %.1f m from the terminal middle" % [best, best_d])
	return best if best_d < 12.0 else -1


func _at(id: String, state: int, fraction: float) -> int:
	var start := _flights.state_start(id, state)
	var end := _flights.state_start(id, state + 1)
	return start + int((end - start) * fraction)


func _view(focus: Vector3, distance: float, yaw: float) -> void:
	_rig.position = focus
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)


func _strip(label: String, id: String, state: int, fractions: Array) -> void:
	var frames: Array[Image] = []
	for fraction: float in fractions:
		await _run_to(_at(id, state, fraction))
		await _frames(SETTLE_FRAMES / 4)
		var where := _plane.global_position + Vector3.UP * 2.0
		var view := root.get_visible_rect()
		var p := _cam.unproject_position(where)
		var in_frame := view.grow(-MARGIN_PX).has_point(p) and not _cam.is_position_behind(where)
		print("STRIP %s %.2f: plane %s -> %s in_frame=%s" % [label, fraction, where, p, in_frame])
		if not in_frame:
			_fail("%s: the plane is out of frame at %.2f" % [label, fraction])
			return
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.resize(int(image.get_width() * STRIP_SCALE), int(image.get_height() * STRIP_SCALE))
		frames.append(image)
	var w := frames[0].get_width()
	var strip := Image.create(
		w * frames.size(), frames[0].get_height(), false, frames[0].get_format()
	)
	for i in frames.size():
		strip.blit_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), Vector2i(w * i, 0))
	var path := _out_dir.path_join(label + ".png")
	var err := strip.save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_fail("%s: not saved" % label)


## Saves a plate once every `framed`, `visible` and `on_plane` point projects
## inside the window and no mesh hides a `visible` point, nor a mesh other than
## the plane's own an `on_plane` point.
func _plate(label: String, framed: Array, visible: Array, on_plane := []) -> void:
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
	for point: Vector3 in framed + visible + on_plane:
		var p := _cam.unproject_position(point)
		var in_frame := view.grow(-MARGIN_PX).has_point(p) and not _cam.is_position_behind(point)
		print("  FRAMED %s -> %s in_frame=%s" % [point, p, in_frame])
		ok = ok and in_frame
	for point: Vector3 in visible + on_plane:
		var occluder := _occluder(point, _plane if on_plane.has(point) else null)
		print("  OCCLUSION %s: %s" % [point, occluder if occluder != "" else "clear"])
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
			OS.crash("plane stand plates probe hung")


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
