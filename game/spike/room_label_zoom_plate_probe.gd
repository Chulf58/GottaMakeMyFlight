extends SceneTree
## Windowed plates of the room label's zoom fade (RoomLabelLayout.zoom_alpha),
## board 9c2b0d32 parts 2 and 3. Boots main.tscn with the starter shell, builds a
## furnished cafe (counter and a table) by BuildMode.load_snapshot and looks at
## it from three camera distances measured against the rig's home_distance: the
## home zoom (label fully visible), 0.45x (label part faded) and 0.30x (label
## gone, the floor and the furniture bare). Each plate prints the zoom ratio,
## the fade RoomLabelLayout expects and the alpha and visibility the label
## really has, and proves the room's floor corners are inside the viewport by
## MARGIN_PX and that the camera ray to the room's centre reaches the floor. An
## alpha that differs from the expected one, or a ratio off its target, prints
## PROBE_INVALID, exit 1. A guard thread calls OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/room_label_zoom_plate_probe.gd [-- --out=<dir>]
##
## Plates go to tools/blender/out/hud-overlaps/ unless --out names a directory.

const OUT_REL := "res://../tools/blender/out/hud-overlaps"
const MARGIN_PX := 8.0
const HANG_MS := 60000
const FLOOR := Rect2i(18, 10, 24, 13)
const CAFE := Rect2i(26, 13, 5, 4)
## [file, camera distance as a fraction of the rig's home distance].
const SHOTS := [
	["label_zoom_home", 1.0],
	["label_zoom_045", 0.45],
	["label_zoom_030", 0.30],
]
const ALPHA_EPS := 0.03

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
	var room_id := mode.grid.room_at(CAFE.position)
	var views := mode.get_node("RoomView") as RoomView
	var rig := main.get_node("TycoonCamera") as TycoonCamera
	var cam := rig.get_node("Camera3D") as Camera3D
	cam.make_current()
	print(
		(
			"PROBE room=%d home_distance=%.2f viewport=%s"
			% [room_id, rig.home_distance, root.get_visible_rect().size]
		)
	)
	for shot: Array in SHOTS:
		_beat(shot[0])
		await _shoot(mode, views, rig, cam, room_id, shot[0], shot[1])
	_finish()


## The cafe, floored and walled on its north side, counter and table in it.
func _build(mode: BuildMode) -> bool:
	var scratch := BuildGrid.new(mode.grid.size, mode.grid.origin)
	var edits: Array[BuildEdit] = []
	for y in range(FLOOR.position.y, FLOOR.end.y):
		for x in range(FLOOR.position.x, FLOOR.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(CAFE.position.x, CAFE.end.x):
		edits.append(BuildEdit.place_wall(Vector2i(x, CAFE.position.y), BuildGrid.Side.NORTH))
	edits.append(BuildEdit.place_room(CAFE, &"cafe"))
	edits.append(BuildEdit.place_object(&"cafe_counter", CAFE.position + Vector2i(1, 0), 0))
	edits.append(BuildEdit.place_object(&"cafe_table", CAFE.position + Vector2i(1, 2), 0))
	var refused := 0
	for result in scratch.apply_batch(edits):
		refused += 0 if result.ok else 1
	print("PROBE scratch edits=%d refused=%d" % [edits.size(), refused])
	if refused > 0:
		_invalid("%d scratch edits refused" % refused)
		return false
	if not mode.load_snapshot(scratch.to_snapshot()) or mode.grid.room_at(CAFE.position) == 0:
		_invalid("BuildMode refused the snapshot or the cafe is not a room")
		return false
	return true


func _shoot(
	mode: BuildMode,
	views: RoomView,
	rig: TycoonCamera,
	cam: Camera3D,
	room_id: int,
	file: String,
	ratio: float
) -> void:
	var middle := mode.grid.cell_to_world(CAFE.get_center())
	rig.position = middle * Vector3(1, 0, 1) + Vector3(0, 0, 0.5)
	rig.yaw = 0.35
	rig.distance = rig.home_distance * ratio
	await _frames(10)
	var label := views.label_of(room_id)
	var expected := RoomLabelLayout.zoom_alpha(cam)
	var got_ratio := rig.distance / rig.home_distance
	var alpha := label.modulate.a if label != null else -1.0
	print(
		(
			"PLATE %s zoom_ratio=%.3f target=%.2f expected_fade=%.2f label_alpha=%.2f visible=%s"
			% [file, got_ratio, ratio, expected, alpha, label.visible if label != null else false]
		)
	)
	if label == null or absf(got_ratio - ratio) > 0.02:
		_invalid("%s: no label or the camera is not at %.2fx" % [file, ratio])
		return
	if ratio >= RoomLabelLayout.FADE_FAR and alpha < 0.95:
		_invalid("%s: the label should be fully visible, alpha %.2f" % [file, alpha])
	elif ratio <= RoomLabelLayout.FADE_NEAR and alpha > RoomLabelLayout.HIDDEN_ALPHA + ALPHA_EPS:
		_invalid("%s: the label should be gone, alpha %.2f" % [file, alpha])
	elif absf(alpha - expected) > ALPHA_EPS:
		_invalid("%s: label alpha %.2f, expected %.2f" % [file, alpha, expected])
	var frame := root.get_visible_rect().grow(-MARGIN_PX)
	var all_in := true
	for corner: Vector2i in [
		CAFE.position,
		Vector2i(CAFE.end.x, CAFE.position.y),
		CAFE.end,
		Vector2i(CAFE.position.x, CAFE.end.y)
	]:
		var world := mode.grid.cell_to_world(corner)
		var at := cam.unproject_position(world)
		var inside := frame.has_point(at) and not cam.is_position_behind(world)
		all_in = all_in and inside
		print("INFRAME %s corner=%s screen=%s in=%s" % [file, corner, at, inside])
	if not all_in:
		_invalid("%s: the cafe leaves the frame" % file)
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
			OS.crash("room_label_zoom_plate_probe: main thread stalled in %s" % stage)
