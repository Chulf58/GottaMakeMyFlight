extends SceneTree
## Windowed plates of a 'Wall gap' marker standing near the top HUD (GapMarkers,
## board item b42f26a7). Boots main.tscn, builds a floored box with one open wall
## by BuildMode.load_snapshot, then moves the camera rig so the gap sign's foot
## lands just inside the lower edge of a HUD control near the top of the screen.
## Plate 1 (wall_gap_hud_before) puts the caption back under its sign, as it was
## before the HUD rule; plate 2 (wall_gap_hud_after) lets GapMarkers lay it out.
## The probe prints the sign's screen point, the HUD rectangles, and the caption
## rectangle in both plates, and proves the subject was engaged: the home caption
## overlaps the HUD rectangle and the laid-out one clears it by RoomLabelLayout.GAP_PX
## (or is hidden with no clear spot). A sign point outside the viewport, a home
## caption that does not overlap, or a laid-out caption that still touches the HUD
## prints PROBE_INVALID, exit 1. A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/wall_gap_hud_plate_probe.gd [-- --out=<dir>]
##
## Plates go to tools/blender/out/wall-gap-hud/ unless --out names a directory.

const OUT_REL := "res://../tools/blender/out/wall-gap-hud"
const MARGIN_PX := 8.0
const HANG_MS := 60000
const FLOOR := Rect2i(18, 10, 24, 13)
const GAP_CELL := Vector2i(30, 10)

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var world_seed := randi()
	clock.seed_rng(world_seed)
	print("PROBE sim_seed=", world_seed)
	root.add_child(main)
	clock.set_paused(true)
	await _frames(3)
	var mode := main.get_node("BuildMode") as BuildMode
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	(mode.get_node("Ghost") as Node3D).visible = false
	if not _build(mode):
		_finish()
		return
	await _frames(4)
	var markers := main.get_node("GapMarkers") as GapMarkers
	print("PROBE sign_count=%d strips=%d" % [markers.sign_count(), markers.strip_count()])
	if markers.sign_count() == 0:
		_invalid("no gap sign")
		_finish()
		return
	var rig := main.get_node("TycoonCamera") as TycoonCamera
	var cam := rig.get_node("Camera3D") as Camera3D
	cam.make_current()
	rig.yaw = 0.35
	rig.distance = rig.home_distance
	await _frames(4)
	var sign := markers.signs()[0]
	var hud := HudRects.collect(markers, _to_output())
	for rect in hud:
		print("HUD rect=%s" % rect)
	var target := _target(hud)
	print("PROBE target_hud=%s" % target)
	_aim_sign_at(rig, cam, sign, Vector2(target.get_center().x, target.end.y - 30.0))
	await _frames(6)
	markers.set_process(false)
	await _shoot(markers, cam, sign, target, hud, false)
	await _shoot(markers, cam, sign, target, hud, true)
	_finish()


## A floored box with one open wall on its north side.
func _build(mode: BuildMode) -> bool:
	var scratch := BuildGrid.new(mode.grid.size, mode.grid.origin)
	var edits: Array[BuildEdit] = []
	for y in range(FLOOR.position.y, FLOOR.end.y):
		for x in range(FLOOR.position.x, FLOOR.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var refused := 0
	for result in scratch.apply_batch(edits):
		refused += 0 if result.ok else 1
	EnclosureKit.close_floor(scratch)
	if not scratch.apply(BuildEdit.remove_wall(GAP_CELL, BuildGrid.Side.NORTH)).ok:
		refused += 1
	print("PROBE scratch edits=%d refused=%d" % [edits.size(), refused])
	if refused > 0:
		_invalid("%d scratch edits refused" % refused)
		return false
	if not mode.load_snapshot(scratch.to_snapshot()):
		_invalid("BuildMode refused the snapshot")
		return false
	return true


func _to_output() -> float:
	return root.get_stretch_transform().get_scale().y


## The HUD control near the top of the screen that the sign is put under: the
## rightmost one in the top 200 px that is under 500 px wide (a button).
func _target(hud: Array[Rect2]) -> Rect2:
	var best := Rect2()
	for rect in hud:
		if rect.position.y < 200.0 and rect.size.x < 500.0 and rect.size.y > 10.0:
			if best.size == Vector2.ZERO or rect.get_center().x > best.get_center().x:
				best = rect
	if best.size == Vector2.ZERO:
		_invalid("no HUD control in the top 200 px")
	return best


## Moves the rig on the ground so the sign's foot projects to `screen`.
func _aim_sign_at(rig: TycoonCamera, cam: Camera3D, sign: Sprite3D, screen: Vector2) -> void:
	var at := sign.global_position
	var layout := screen / _to_output()
	var hit: Variant = Plane(Vector3.UP, at.y).intersects_ray(
		cam.project_ray_origin(layout), cam.project_ray_normal(layout)
	)
	if hit == null:
		_invalid("the target ray misses the sign's plane")
		return
	var delta: Vector3 = at - (hit as Vector3)
	rig.position += Vector3(delta.x, 0.0, delta.z)


## The caption's screen rectangle from its pixel offset, as the test computes it.
func _caption_rect(caption: Label3D, point: Vector2) -> Rect2:
	var size := MissMarkers.caption_size(GapMarkers.CAPTION)
	var moved := caption.offset - Vector2(0.0, -MissMarkers.CAPTION_GAP_PX)
	return Rect2(
		Vector2(point.x - size.x / 2.0 + moved.x, point.y + MissMarkers.CAPTION_GAP_PX - moved.y),
		size
	)


func _shoot(
	markers: GapMarkers,
	cam: Camera3D,
	sign: Sprite3D,
	target: Rect2,
	hud: Array[Rect2],
	laid_out: bool
) -> void:
	var file := "wall_gap_hud_after" if laid_out else "wall_gap_hud_before"
	_beat(file)
	var caption := markers.caption_of(sign)
	var view := root.get_visible_rect().size * root.get_stretch_transform().get_scale()
	if laid_out:
		markers.layout_captions(cam, _to_output(), view, hud)
	else:
		markers.layout_captions(cam, _to_output(), view, [] as Array[Rect2])
	await _frames(4)
	var point := cam.unproject_position(sign.global_position) * _to_output()
	var rect := _caption_rect(caption, point)
	var inside := Rect2(Vector2.ZERO, view).grow(-MARGIN_PX).has_point(point)
	print(
		(
			"PLATE %s sign_point=%s in_view=%s caption_rect=%s visible=%s offset=%s overlaps_target=%s"
			% [file, point, inside, rect, caption.visible, caption.offset, rect.intersects(target)]
		)
	)
	if not inside:
		_invalid("%s: the sign point is outside the viewport" % file)
	if not laid_out and not rect.intersects(target):
		_invalid("%s: the home caption does not overlap the HUD control" % file)
	if laid_out and caption.visible:
		for control in hud:
			if rect.grow(RoomLabelLayout.GAP_PX).intersects(control):
				_invalid("%s: the caption still touches the HUD %s" % [file, control])
	if _failed:
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(file + ".png")
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _finish() -> void:
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var stage := _stage
		var silent := Time.get_ticks_msec() - _beat_ms
		_lock.unlock()
		if stop:
			return
		if silent > HANG_MS:
			print("PROBE_INVALID hang: stage=%s silent_ms=%d" % [stage, silent])
			OS.crash("wall_gap_hud_plate_probe: main thread stalled in %s" % stage)
