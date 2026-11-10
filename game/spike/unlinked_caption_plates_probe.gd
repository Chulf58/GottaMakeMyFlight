extends SceneTree
## Plates of an unlinked gate desk's sign caption, before and after it moved
## off the desk (smoke playtest 11, board f0fbae3c (g)). One windowed run:
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/unlinked_caption_plates_probe.gd
## Boots main.tscn with a new random world seed (printed), fills the starter
## shell with the debug button (gate desk A by its exit), then places a second
## gate desk too far from any north exit (NO_EXIT) with a seat row west of it,
## as in the playtest. It hides every CanvasLayer (the HUD; anti-pattern
## a-plate-probe-s-occlusion-rays-see-only-meshes-so-a-hud-pane) and stops the
## camera rig. It saves plates under tools/blender/out/gate-caption/ at play
## distance (80 m, the home distance) and close up (25 m), both at the middle
## angle step (54 degrees), first "before": the old one-line caption hung under
## the sign (the view's layout stopped), then "after": the live view. Before
## each save the desk, the seat row, the sign and the caption's corners must
## project inside the window, and the desk's top and the seats must have no mesh
## between them and the camera (a control under the ground must report one);
## otherwise PROBE_INVALID, exit 1. A before plate's caption must meet the
## desk's or the seats' screen box (the control); an after plate's caption that
## meets either prints PROBE_FAIL and the run exits 1. A contact sheet of the
## four is saved last. No click is pushed. A guard thread ends a hang.

const MAIN := "res://main/main.tscn"
const OUT_REL := "res://../tools/blender/out/gate-caption"
const HANG_LIMIT_MS := 60000
const TOTAL_LIMIT_MS := 300000
const MARGIN_PX := 8.0
const OCCLUSION_STOP_M := 0.3
const SETTLE_FRAMES := 40
const PITCH := 54.0
const OLD_TEXT := "Unlinked: no north exit within 4 cells"

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
var _rig: TycoonCamera
var _cam: Camera3D
var _gates: GateDesks
var _links: GateLinksView
var _desk := 0
var _seats := 0
var _saved: Array[String] = []


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
	var mode: BuildMode = _main.get_node("BuildMode")
	_grid = mode.grid
	var hud: PassengerHud = _main.get_node("PassengerHud")
	_rig = _main.get_node("TycoonCamera")
	_cam = _rig.get_node("Camera3D")
	_gates = _main.get_node("GateDesks")
	_links = (_main.get_node("ApronStand") as ApronStand).links_view()
	hud.dismiss_intro()
	_clock.set_paused(true)
	hud.press_starter_terminal()
	if not _place_unlinked():
		return
	for layer in _main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_rig.set_process(false)
	_rig.set_physics_process(false)
	var marker: Sprite3D = _links.signs()[0]
	var caption := _links.caption_of(marker)
	var new_text := caption.text
	print("PROBE sign desk %d text '%s'" % [marker.get_meta("desk"), new_text.c_escape()])
	# Before: the old caption, one line hung a gap under the sign's foot.
	_links.set_process(false)
	caption.text = OLD_TEXT
	caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	caption.offset = Vector2(0.0, -MissMarkers.CAPTION_GAP_PX)
	for shot in [["before_a_play_distance", 80.0], ["before_b_close_up", 25.0]]:
		await _plate(shot[0], shot[1], true)
		if _done:
			return
	caption.text = new_text
	caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_links.set_process(true)
	for shot in [["after_a_play_distance", 80.0], ["after_b_close_up", 25.0]]:
		await _plate(shot[0], shot[1], false)
		if _done:
			return
	_contact_sheet()
	if _overlap:
		print("PROBE_FAIL the caption meets the desk or the seats")
		_finish(1)
		return
	print("PROBE_PASS plates")
	_finish(0)


## Makes gate A's desk unlinked (NO_EXIT) with a seat row west of it: places
## the row (or finds one already there), then takes the gate's exit away. A
## desk cannot be placed out of an exit's reach (the build tool refuses it), so
## an unlinked desk is one whose exit went. When the guard refuses the removal
## (booked contracts with nowhere to move), it says why and removes the exit
## with the guard off. False (after _fail) when any of it fails.
func _place_unlinked() -> bool:
	if _gates.bindings.is_empty():
		_fail("the starter terminal has no gate desk")
		return false
	var binding: Dictionary = _gates.bindings[0]
	_desk = binding["desk"]
	var home: Vector2i = _grid.get_object(_desk)["anchor"]
	var row_at := home - Vector2i(3, 0)
	_seats = _grid.object_at(row_at)
	if _seats == 0 or _grid.get_object(_seats)["def"] != &"seat_row":
		var seats := _grid.apply(BuildEdit.place_object(&"seat_row", row_at, 0))
		if not seats.ok:
			_fail("the seat row at %s was refused: %s" % [row_at, seats.reason_text()])
			return false
		_seats = seats.object_id
	var exit := BuildEdit.remove_object(binding["exit"])
	var removed := _grid.apply(exit)
	if not removed.ok:
		print("PROBE exit removal refused (%s); removing it unguarded" % removed.reason_text())
		var site := _grid as SiteGrid
		var guard := site.guard
		site.guard = Callable()
		removed = _grid.apply(exit)
		site.guard = guard
	var why: Dictionary = _gates.unlinked().get(_desk, {})
	print(
		(
			"PROBE desk %d at %s seats %d exit removed %s why %s"
			% [_desk, home, _seats, removed.ok, why]
		)
	)
	if not removed.ok or why.get("why", -1) != GateDesks.Unlinked.NO_EXIT:
		_fail("gate A's desk did not become unlinked with NO_EXIT")
		return false
	return true


## The camera `distance` metres from the unlinked desk, PITCH degrees down,
## looking north.
func _view(distance: float) -> void:
	var at := _top(_desk)
	at.y = 0.0
	var down := deg_to_rad(PITCH)
	var eye := at + Vector3(0.0, sin(down), cos(down)) * distance
	_cam.global_transform = Transform3D.IDENTITY.translated(eye).looking_at(at)


## The top centre of object `id`'s footprint at its catalog height.
func _top(id: int) -> Vector3:
	var record := _grid.get_object(id)
	var def := BuildCatalog.get_def(record["def"])
	var at := Vector3.ZERO
	var cells := def.footprint(record["anchor"], record["facing"])
	for cell in cells:
		at += _grid.cell_to_world(cell)
	at /= cells.size()
	at.y = _grid.origin.y + def.height
	return at


## The caption's screen rectangle (output pixels) as drawn: centred across its
## sign, its top (TOP) or bottom (BOTTOM) `offset` above the sign's point.
func _caption_rect(marker: Sprite3D, caption: Label3D, to_output: float) -> Rect2:
	var size := GateLinksView.caption_size(caption.text)
	var foot := _cam.unproject_position(marker.global_position) * to_output
	var y := foot.y - caption.offset.y
	if caption.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		y -= size.y
	return Rect2(foot.x - size.x / 2.0, y, size.x, size.y)


func _plate(label: String, distance: float, before: bool) -> void:
	_stage = "plate %s" % label
	_view(distance)
	await _frames(SETTLE_FRAMES)
	var view := root.get_visible_rect()
	var to_output := root.get_stretch_transform().get_scale().y
	var marker: Sprite3D = _links.signs()[0]
	var caption := _links.caption_of(marker)
	var rect := _caption_rect(marker, caption, to_output)
	print(
		(
			"PLATE %s camera %s looking %s fov %.1f text '%s' offset %.1f"
			% [
				label,
				_cam.global_position,
				-_cam.global_basis.z,
				_cam.fov,
				caption.text.c_escape(),
				caption.offset.y
			]
		)
	)
	var control := _occluder(_top(_desk) + Vector3(0.0, -4.0, 0.0))
	print("  CONTROL under the ground: %s" % (control if control != "" else "clear"))
	if control == "":
		_fail("%s: the occlusion control found nothing" % label)
		return
	var ok := true
	var desk_top := _top(_desk)
	var seat_top := _top(_seats)
	var points: Array[Vector3] = [desk_top, seat_top, marker.global_position]
	for point in points:
		var p := _cam.unproject_position(point)
		var in_frame := view.grow(-MARGIN_PX).has_point(p) and not _cam.is_position_behind(point)
		print("  FRAMED %s -> %s in_frame=%s" % [point, p, in_frame])
		ok = ok and in_frame
	var corners := [rect.position, rect.end, Vector2(rect.position.x, rect.end.y)]
	for corner: Vector2 in corners:
		var in_frame := view.grow(-MARGIN_PX).has_point(corner / to_output)
		print("  FRAMED caption corner %s in_frame=%s" % [corner, in_frame])
		ok = ok and in_frame
	for point in [desk_top, seat_top]:
		var occluder := _occluder(point + Vector3.UP * 0.05)
		print("  OCCLUSION %s: %s" % [point, occluder if occluder != "" else "clear"])
		ok = ok and occluder == ""
	if not ok:
		_fail("%s: a subject check failed" % label)
		return
	var boxes: Array[Rect2] = []
	for id in [_desk, _seats]:
		var record := _grid.get_object(id)
		var def := BuildCatalog.get_def(record["def"])
		var cells := def.footprint(record["anchor"], record["facing"])
		boxes.append(GateLinksView.screen_box(_cam, _corners(cells, def.height), to_output))
	var hits := boxes.map(func(box: Rect2) -> bool: return rect.intersects(box))
	print("  CAPTION %s desk box %s seat box %s meets %s" % [rect, boxes[0], boxes[1], hits])
	if before and not hits.has(true):
		_fail("%s: the control (old caption) meets neither the desk nor the seats" % label)
		return
	if not before and hits.has(true):
		print("PROBE_FAIL %s: the caption meets the desk or the seats" % label)
		_overlap = true
	# The wall-gap sign and caption the exit's removal left (GapMarkers).
	var gap_rects := GateLinksView.marker_rects(_main.get_node("GapMarkers"), _cam, to_output)
	var gap_hits := gap_rects.filter(func(other: Rect2) -> bool: return rect.intersects(other))
	print("  WALL GAP marks %s, met by the caption %s" % [gap_rects, gap_hits])
	if not before and not gap_hits.is_empty():
		print("PROBE_FAIL %s: the caption meets a wall-gap mark" % label)
		_overlap = true
	await RenderingServer.frame_post_draw
	var path := _out_dir.path_join(label + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_fail("%s: not saved" % label)
		return
	_saved.append(path)


## The 8 world corners of `cells` from the floor up to `height`.
func _corners(cells: Array[Vector2i], height: float) -> PackedVector3Array:
	var area := Rect2i(cells[0], Vector2i.ONE)
	for cell in cells:
		area = area.merge(Rect2i(cell, Vector2i.ONE))
	var out := PackedVector3Array()
	for y in [0.0, height]:
		for x in [area.position.x, area.end.x]:
			for z in [area.position.y, area.end.y]:
				out.append(_grid.origin + Vector3(x, y, z))
	return out


## The saved plates at half size, two across, before over after.
func _contact_sheet() -> void:
	var sheet: Image = null
	for i in _saved.size():
		var plate := Image.load_from_file(_saved[i])
		plate.resize(plate.get_width() / 2, plate.get_height() / 2)
		if sheet == null:
			var cols := 2
			var rows := ceili(_saved.size() / float(cols))
			sheet = Image.create(
				plate.get_width() * cols, plate.get_height() * rows, false, plate.get_format()
			)
		var at := Vector2i(i % 2 * plate.get_width(), i / 2 * plate.get_height())
		sheet.blit_rect(plate, Rect2i(Vector2i.ZERO, plate.get_size()), at)
	var path := _out_dir.path_join("contact_sheet.png")
	print("PLATE contact sheet %s err=%d" % [path, sheet.save_png(path)])


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
			OS.crash("unlinked caption plates probe hung")


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
