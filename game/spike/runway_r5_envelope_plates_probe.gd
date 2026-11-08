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
## BuildSession's changed signal calls), hides the open-airport checklist (the
## StaffPanel layer) and saves two plates under tools/blender/out/runway-r5/,
## each looking straight down: both envelopes out to the taxi lane, and the two
## stands close up with the gate captions over the desks ("Gate A" / "up to
## large planes"). Before each save every subject point (the envelope corners
## and the captions) must project inside the window, and the stand points and
## the floor patch must have no mesh between them and the camera (a control
## under the ground must report one); otherwise PROBE_INVALID, exit 1. No two
## shown gate captions may overlap on screen, nor any of them a MissMarkers sign
## or caption (the desks' Closed and "!" signs); caption rectangles come from the
## font's measured text, anchored and lifted as GateLinksView draws them; the
## control is the
## old one-line class captions at the stand points, which must overlap. An
## overlap prints PROBE_FAIL, the plate is still saved for review, and the run
## exits 1. No click is pushed, so
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
## The old class captions (before the class moved under the gate caption),
## each 6 m over its stand point: the overlap check's control.
const OLD_CAPTIONS := ["Gate A: up to large planes", "Gate B: up to medium planes"]
const OLD_CAPTION_LIFT_M := 6.0

var _guard := Thread.new()
var _mutex := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _done := false
var _overlap := false

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
	(_main.get_node("StaffPanel") as CanvasLayer).visible = false
	_rig.set_process(false)
	_rig.set_physics_process(false)
	await _plates()
	if _done:
		return
	if _overlap:
		print("PROBE_FAIL gate captions overlap on screen")
		_finish(1)
		return
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
	var captions := links.gate_captions()
	var texts := []
	for caption in captions:
		texts.append(caption.text)
	print("PROBE envelope outlines %d, captions %s" % [paths.size(), texts])
	var wanted := ["Gate A\nup to large planes", "Gate B\nup to medium planes"]
	if paths.size() != 2 or texts != wanted:
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
	var spots: Array = []
	for caption in captions:
		spots.append(caption.global_position)
	var old: Array = [
		[OLD_CAPTIONS[0], stand_a + Vector3.UP * OLD_CAPTION_LIFT_M],
		[OLD_CAPTIONS[1], stand_b + Vector3.UP * OLD_CAPTION_LIFT_M],
	]
	# Straight down, out to the taxi lane at z -284.
	_view(Vector3(middle.x, 0.0, -190.0), 215.0)
	await _plate("a_envelopes_from_above", corners + spots, [stand_a, stand_b, patch], old)
	if _done:
		return
	_view(Vector3(middle.x, 0.0, -118.0), 90.0)
	await _plate("b_stands_close_with_captions", spots, [stand_a, stand_b, patch], old)


## Puts the camera `height` metres straight over `focus`, north up. The rig
## is stopped, so it does not tilt the camera back.
func _view(focus: Vector3, height: float) -> void:
	var down := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	_cam.global_transform = Transform3D(down, focus + Vector3.UP * height)


## Saves a plate once every `framed` and `visible` point projects inside the
## window and no mesh hides a `visible` point. The shown gate captions must not
## overlap on screen, and the `old` ([text, anchor]) captions, the control,
## must.
func _plate(label: String, framed: Array, visible: Array, old: Array) -> void:
	_stage = "plate %s" % label
	await _frames(SETTLE_FRAMES)
	var view := root.get_visible_rect()
	var ok := true
	print(
		(
			"PLATE %s camera %s looking %s fov %.1f"
			% [label, _cam.global_position, -_cam.global_basis.z, _cam.fov]
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
	var shown: Array[Label3D] = _apron.links_view().gate_captions()
	var font := _font_of(shown[0])
	var old_rects: Array[Rect2] = []
	for entry: Array in old:
		old_rects.append(_caption_rect(font, entry[0], entry[1]))
	var old_overlap := _first_overlap(old_rects)
	print("  CAPTION CONTROL old captions %s: %s" % [old_rects, old_overlap])
	if old_overlap == "":
		_fail("%s: the caption overlap control found no overlap" % label)
		return
	var rects: Array[Rect2] = []
	for caption in shown:
		var lifted := _caption_rect(font, caption.text, caption.global_position)
		lifted.position.y -= caption.offset.y / root.get_stretch_transform().get_scale().y
		rects.append(lifted)
	var signs := _sign_rects()
	print("  SIGNS %s" % [signs])
	var overlap := _first_overlap(rects)
	for i in rects.size():
		for sign: Rect2 in signs:
			if overlap == "" and rects[i].intersects(sign):
				overlap = "caption %d and sign %s" % [i, sign]
	print("  CAPTIONS %s: %s" % [rects, overlap if overlap != "" else "no overlap"])
	if overlap != "":
		print("PROBE_FAIL %s: gate captions overlap: %s" % [label, overlap])
		_overlap = true
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(label + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_fail("%s: not saved" % label)


## The font a caption draws with: its own, or the default one.
func _font_of(caption: Label3D) -> Font:
	if caption.font != null:
		return caption.font
	var theme := ThemeDB.get_project_theme()
	if theme != null and theme.default_font != null:
		return theme.default_font
	return ThemeDB.fallback_font


## The screen rectangle (in unproject_position's units) of a GateLinksView
## caption saying `text` anchored at `at`: centred across, its bottom on the
## anchor, MissMarkers.CAPTION_FONT pixels per line plus the outline. A
## fixed-size caption keeps its font size in window pixels (update_sizes), so
## the stretch scale turns it into viewport units.
func _caption_rect(font: Font, text: String, at: Vector3) -> Rect2:
	var size := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, -1, MissMarkers.CAPTION_FONT
	)
	size += Vector2.ONE * MissMarkers.CAPTION_OUTLINE
	size /= root.get_stretch_transform().get_scale().y
	var p := _cam.unproject_position(at)
	return Rect2(p.x - size.x / 2.0, p.y - size.y, size.x, size.y)


## The screen rectangles (unproject_position's units) of MissMarkers' shown
## signs and captions, measured as MissMarkers lays them out: a SIGN_PX icon
## standing on its point, a caption (MissMarkers.caption_size) bottom-aligned
## at its offset.
func _sign_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var markers := _main.get_node("PassengerViews/MissMarkers")
	var scale := root.get_stretch_transform().get_scale().y
	for node in markers.find_children("*", "GeometryInstance3D", true, false):
		var shown := node as Node3D
		if not shown.is_visible_in_tree() or _cam.is_position_behind(shown.global_position):
			continue
		var p := _cam.unproject_position(shown.global_position)
		if shown is Sprite3D:
			var side := MissMarkers.SIGN_PX / scale
			out.append(Rect2(p.x - side / 2.0, p.y - side, side, side))
		elif shown is Label3D:
			var label := shown as Label3D
			var size := MissMarkers.caption_size(label.text) / scale
			var bottom := p.y - label.offset.y / scale
			out.append(
				Rect2(p.x + label.offset.x / scale - size.x / 2.0, bottom - size.y, size.x, size.y)
			)
	return out


## "i and j" for the first two of `rects` that overlap, or "".
func _first_overlap(rects: Array[Rect2]) -> String:
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				return "%d and %d" % [i, j]
	return ""


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
