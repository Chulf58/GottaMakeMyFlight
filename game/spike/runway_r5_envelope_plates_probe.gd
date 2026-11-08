extends SceneTree
## Plates of the gate stand envelopes in build mode (Runway R5, board 8b6ea4ef;
## decision runway-and-taxi-technical-design-movement-plan-analytic-bookings-
## planned-pauses, section 3). One windowed run:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/runway_r5_envelope_plates_probe.gd
## Boots main.tscn with a new random world seed (printed), fills the starter
## shell with the debug button (which adds gate desk A by its exit), buys the
## land for a second shell 19 cells east, the least spacing two gates need,
## builds it with a gate desk by its exit (gate B), and paints a floor patch in
## gate B's large-only space, so gate A takes large planes and gate B medium.
## Then it turns build mode's ground views on (ApronStand.set_building, which
## BuildSession's changed signal calls) and saves two plates under
## tools/blender/out/runway-r5/: both envelopes from above out to the taxi lane,
## and the two stands close up with their "Gate A: up to large planes" captions.
## Before each save every subject point (the envelope corners and the captions)
## must project inside the window, and the stand points and the floor patch
## must have no mesh between them and the camera (a control under the ground
## must report one); otherwise PROBE_INVALID, exit 1. No click is pushed, so
## the click owners of anti-pattern a-main-tscn-click-test-that-calls-
## unhandled-input-directly-m are not in play. A guard thread ends a hang.

const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/runway-r5"
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 300000
const MARGIN_PX := 8.0
const OCCLUSION_STOP_M := 0.3
const SETTLE_FRAMES := 40
const EAST := Vector2i(19, 0)
const DESK_EAST := Vector2i(38, 115)
## Gate B's stand point is at x -7: x 13.6 to 25.9 is its large-only space.
const PATCH := Rect2i(58, 98, 3, 3)

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false

var _out_dir := ""
var _main: Node
var _clock: SimClock
var _grid: BuildGrid
var _mode: BuildMode
var _hud: PassengerHud
var _rig: TycoonCamera
var _cam: Camera3D
var _apron: ApronStand
var _gates: GateDesks


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
	_hud.dismiss_intro()
	_clock.set_paused(true)
	_hud.press_starter_terminal()
	if not _build_east():
		return
	var classes := [_gates.max_class("A"), _gates.max_class("B")]
	print("PROBE gates %s, max classes %s" % [_gates.bindings, classes])
	if _gates.gate_ids() != (["A", "B"] as Array[String]) or classes != ["large", "medium"]:
		_fail("expected gates A (large) and B (medium), got %s %s" % [_gates.gate_ids(), classes])
		return
	_apron.set_building(true)
	await _plates()
	if not _done:
		print("PROBE_PASS plates")
		_finish(0)


## Buys the land for, and builds, a second shell 19 cells east with a gate desk
## by its exit, and a floor patch in gate B's large-only space. False (after
## _fail) when any of it is refused.
func _build_east() -> bool:
	var shell := ReferenceTerminal.shell_edits(_mode.site.starter_offset + EAST)
	var cells: Array[Vector2i] = [DESK_EAST, PATCH.position, PATCH.end - Vector2i.ONE]
	for edit in shell:
		cells.append(edit.cell)
	if not _own(cells):
		return false
	for result in _grid.apply_batch(shell):
		if not result.ok:
			_fail("the east shell was refused: %s" % result.reason_text())
			return false
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK_EAST, 0))
	if not desk.ok:
		_fail("the east gate desk was refused: %s" % desk.reason_text())
		return false
	var patch: Array[BuildEdit] = []
	for y in range(PATCH.position.y, PATCH.end.y):
		for x in range(PATCH.position.x, PATCH.end.x):
			patch.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in _grid.apply_batch(patch):
		if not result.ok:
			_fail("the floor patch was refused: %s" % result.reason_text())
			return false
	return true


## Buys, nearest first, the plots that join every cell of `cells` to the land.
func _own(cells: Array[Vector2i]) -> bool:
	var land := _mode.land_tool.land
	var wanted := {}
	for cell in cells:
		wanted[land.plot_of(cell)] = true
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
	return true


func _plates() -> void:
	var links := _apron.links_view()
	var paths := links.envelope_paths()
	var captions := links.class_captions()
	var texts := []
	for caption in captions:
		texts.append(caption.text)
	print("PROBE envelope outlines %d, captions %s" % [paths.size(), texts])
	if paths.size() != 2 or texts != ["Gate A: up to large planes", "Gate B: up to medium planes"]:
		_fail("the build-mode views do not show both envelopes with their classes")
		return
	var stand_a := StandPlacement.stand_point(_apron.gate_stands["A"]["live"])
	var stand_b := StandPlacement.stand_point(_apron.gate_stands["B"]["live"])
	var patch := _grid.cell_to_world(PATCH.position + Vector2i.ONE)
	var corners: Array = []
	for path in paths:
		for point in path:
			corners.append(point)
	var middle := (stand_a + stand_b) / 2.0
	# From above, out to the taxi lane at z -284.
	_view(Vector3(middle.x, 0.0, -195.0), 260.0, 0.0)
	await _plate("a_envelopes_from_above", corners, [stand_a, stand_b, patch])
	if _done:
		return
	var spots: Array = []
	for caption in captions:
		spots.append(caption.global_position)
	_view(middle + Vector3(0.0, 0.0, -12.0), 110.0, 0.0)
	await _plate("b_stands_close_with_captions", spots, [stand_a, stand_b, patch])


func _view(focus: Vector3, distance: float, yaw: float) -> void:
	_rig.position = focus
	_rig.yaw = yaw
	_rig.distance = distance
	_rig.zoom(1.0)


## Saves a plate once every `framed` and `visible` point projects inside the
## window and no mesh hides a `visible` point.
func _plate(label: String, framed: Array, visible: Array) -> void:
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
	for point: Vector3 in framed + visible:
		var p := _cam.unproject_position(point)
		var in_frame := view.grow(-MARGIN_PX).has_point(p) and not _cam.is_position_behind(point)
		print("  FRAMED %s -> %s in_frame=%s" % [point, p, in_frame])
		ok = ok and in_frame
	for point: Vector3 in visible:
		var occluder := _occluder(point + Vector3.UP * 0.2)
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


## The first opaque mesh the camera-to-subject segment crosses, or "".
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
			OS.crash("runway r5 envelope plates probe hung")


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
