extends SceneTree
## Windowed plates of two cafe rooms inside the Toon terminal shell, in the real
## main scene: cafe A has a counter and a table and shows "Ready"; cafe B has
## only a counter and shows its note, "Needs a table". Each shot centres one
## room, points the room info panel at it and saves a plate.
##
## The rooms are built in a scratch BuildGrid in the shell's frame and loaded
## through BuildMode.load_snapshot(), so the plate also proves a snapshot with
## rooms passes the shell's own check. BuildMode's processing is turned off so
## the real mouse cannot move the panel's focus; update_room_focus() points it.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   timeout 600 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path game -s res://spike/room_plates_probe.gd
##
## Each shot must project the room (floor corners and label) inside the frame,
## clear of the HUD strips, and at least 80% of the camera rays to the room's
## empty floor cells must reach them past every visible shell mesh; the room
## statuses and the panel text must match. Otherwise the probe prints
## PROBE_INVALID and exits 1. A guard thread calls OS.crash() on a stall.
## Plates go to tools/blender/out/rooms/.

const OUT_REL := "res://../tools/blender/out/rooms"
const MARGIN_PX := 8.0
const TOP_HUD_PX := 56.0
const BOTTOM_HUD_PX := (
	BuildMenu.MARGIN
	+ BuildMenu.BAR_H
	+ BuildMenu.GAP
	+ BuildMenu.TRAY_H
	+ BuildMenu.GAP
	+ BuildMenu.STATUS_H
)
const FLOOR := Rect2i(18, 10, 24, 13)
const CAFE_A := Rect2i(21, 13, 5, 4)
const CAFE_B := Rect2i(29, 13, 5, 4)
const DISTANCES := [14.0, 16.0, 18.0, 21.0, 25.0]
const HANG_MS := 90000

var _out_dir := ""
var _failed := false
var _guard := Thread.new()
var _lock := Mutex.new()
var _beat_ms := 0
var _stage := "boot"
var _stop := false


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	var seed := randi()
	clock.seed_rng(seed)
	print("PROBE sim_seed=", seed)
	root.add_child(main)
	clock.set_paused(true)
	await _frames(3)
	var mode := main.get_node("BuildMode") as BuildMode
	var menu := main.get_node("BuildMenu") as BuildMenu
	mode.set_process(false)
	mode.set_tool(BuildMode.Tool.NONE)
	(mode.get_node("Ghost") as Node3D).visible = false
	_beat("build")
	var ids := _build(mode)
	await _frames(4)
	var grid := mode.grid
	print("PROBE rooms=%s objects=%d" % [grid.room_ids(), grid.object_ids().size()])
	if ids.size() != 2 or grid.room_ids().size() != 2:
		_invalid("expected two rooms, got %s" % [grid.room_ids()])
	var rig := main.get_node("TycoonCamera") as TycoonCamera
	var cam := rig.get_node("Camera3D") as Camera3D
	cam.make_current()
	print("PROBE viewport=%s" % root.get_visible_rect().size)
	var shots := [
		["ready", ids[0] if ids.size() > 0 else 0, CAFE_A, ["Ready"]],
		["needs_table", ids[1] if ids.size() > 1 else 0, CAFE_B, ["Needs a table"]],
	]
	var plates: Array[Image] = []
	for shot in shots:
		_beat(shot[0])
		var ok := _check_status(grid, shot[0], shot[1], shot[3])
		var area: Rect2i = shot[2]
		var box := _room_box(grid, area)
		var framed := false
		for d in DISTANCES:
			rig.position = box.get_center() * Vector3(1, 0, 1) + Vector3(0, 0, 0.5)
			rig.yaw = 0.35
			rig.distance = d
			rig.zoom(1.0)
			await _frames(8)
			if _in_frame(cam, shot[0], box, false):
				framed = true
				break
		print(
			(
				"CAMERA %s pos=%s distance=%.1f pitch_deg=%.1f yaw=%.2f"
				% [shot[0], cam.global_position, rig.distance, -cam.rotation_degrees.x, rig.yaw]
			)
		)
		if not framed:
			_invalid("%s: no distance frames the room" % shot[0])
		ok = _in_frame(cam, shot[0], box, true) and ok
		mode.update_room_focus(grid.cell_to_world(area.get_center()))
		await _frames(4)
		ok = _check_panel(menu, shot[0], shot[1], shot[3]) and ok
		var occluders := _colliders(main.get_node("Airside/Terminal") as Node3D)
		await physics_frame
		await physics_frame
		ok = _prove_visible(cam, grid, shot[0], area) and ok
		occluders.free()
		var img := await _grab()
		if ok:
			_save(img, "cafe_%s.png" % shot[0])
			plates.append(img)
	if plates.size() == shots.size():
		_save(_contact_sheet(plates), "contact_sheet.png")
	print("PROBE done failed=%s" % _failed)
	_finish()
	quit(1 if _failed else 0)


## Floor, a north wall behind each cafe, cafe A furnished and cafe B with only a
## counter, built in a scratch grid in the shell's frame and loaded through
## BuildMode. Returns the two room ids, A first.
func _build(mode: BuildMode) -> Array[int]:
	var scratch := BuildGrid.new(mode.grid.size, mode.grid.origin)
	var edits: Array[BuildEdit] = []
	for y in range(FLOOR.position.y, FLOOR.end.y):
		for x in range(FLOOR.position.x, FLOOR.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for area in [CAFE_A, CAFE_B]:
		for x in range(area.position.x, area.end.x):
			edits.append(BuildEdit.place_wall(Vector2i(x, area.position.y), BuildGrid.Side.NORTH))
		edits.append(BuildEdit.place_room(area, &"cafe"))
		edits.append(BuildEdit.place_object(&"cafe_counter", area.position + Vector2i(1, 0), 0))
	edits.append(BuildEdit.place_object(&"cafe_table", CAFE_A.position + Vector2i(1, 2), 0))
	var refused := 0
	for result in scratch.apply_batch(edits):
		refused += 0 if result.ok else 1
	print("PROBE scratch edits=%d refused=%d" % [edits.size(), refused])
	if refused > 0:
		_invalid("%d scratch edits refused" % refused)
	if not mode.load_snapshot(scratch.to_snapshot()):
		_invalid("BuildMode refused the snapshot with rooms")
	var ids: Array[int] = []
	for area in [CAFE_A, CAFE_B]:
		var room_id := mode.grid.room_at(area.position)
		if room_id != 0:
			ids.append(room_id)
	return ids


func _check_status(grid: BuildGrid, label: String, room_id: int, want: Array) -> bool:
	var status := RoomRules.status(grid, room_id)
	if status == null:
		_invalid("%s: room %d has no status" % [label, room_id])
		return false
	var got := [status.headline()] if status.ok else Array(status.notes)
	var ok := got == want
	print(
		(
			"STATUS %s room=%d ok=%s notes=%s seats=%d pieces=%s want=%s match=%s"
			% [label, room_id, status.ok, status.notes, status.seats, status.pieces, want, ok]
		)
	)
	if not ok:
		_invalid("%s: room status %s, wanted %s" % [label, got, want])
	return ok


func _check_panel(menu: BuildMenu, label: String, room_id: int, want: Array) -> bool:
	var panel := menu.room_panel()
	var texts := []
	for node in panel.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	var rect := panel.get_global_rect()
	var inside := root.get_visible_rect().encloses(rect)
	var ok := panel.visible and panel.room_id() == room_id and inside and texts.has(want[0])
	print(
		(
			"PANEL %s visible=%s room=%d rect=%s inside=%s texts=%s ok=%s"
			% [label, panel.visible, panel.room_id(), rect, inside, texts, ok]
		)
	)
	if not ok:
		_invalid("%s: the room panel does not show room %d" % [label, room_id])
	return ok


## The room's floor rectangle at floor height up to its label.
func _room_box(grid: BuildGrid, area: Rect2i) -> AABB:
	var corner := grid.origin + Vector3(area.position.x, 0.0, area.position.y)
	return AABB(corner, Vector3(area.size.x, RoomView.LABEL_Y + 1.0, area.size.y))


func _in_frame(cam: Camera3D, label: String, box: AABB, report: bool) -> bool:
	var size := root.get_visible_rect().size
	var rect := Rect2(
		Vector2(MARGIN_PX, TOP_HUD_PX), size - Vector2(MARGIN_PX * 2, TOP_HUD_PX + BOTTOM_HUD_PX)
	)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var behind := false
	for i in 8:
		var p := box.get_endpoint(i)
		behind = behind or cam.is_position_behind(p)
		var s := cam.unproject_position(p)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := not behind and rect.has_point(lo) and rect.has_point(hi)
	if report:
		print(
			(
				"INFRAME %s room screen=(%.0f,%.0f)-(%.0f,%.0f) size_px=(%.0f,%.0f) ok=%s"
				% [label, lo.x, lo.y, hi.x, hi.y, hi.x - lo.x, hi.y - lo.y, ok]
			)
		)
		if not ok:
			_invalid("%s: the room leaves the frame" % label)
	return ok


## Rays from the camera to the middle of each empty floor cell of the room, a
## little above the floor. A ray that hits a shell mesh before it gets within
## 5 cm of its target is occluded. At least 80% must arrive.
func _prove_visible(cam: Camera3D, grid: BuildGrid, label: String, area: Rect2i) -> bool:
	var space := cam.get_world_3d().direct_space_state
	var clear := 0
	var total := 0
	var blockers := {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if grid.object_at(cell) != 0:
				continue
			total += 1
			var target := grid.cell_to_world(cell) + Vector3(0.0, 0.1, 0.0)
			var from := cam.global_position
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, target))
			if hit and from.distance_to(hit.position) < from.distance_to(target) - 0.05:
				var owner := str((hit.collider as Node).get_meta("mesh", ""))
				blockers[owner] = blockers.get(owner, 0) + 1
			else:
				clear += 1
	var ok := clear > 0 and clear * 5 >= total * 4
	print(
		"VISIBLE %s floor_rays_clear=%d/%d ok=%s blockers=%s" % [label, clear, total, ok, blockers]
	)
	if not ok:
		_invalid("%s: room floor occluded (%d of %d rays clear)" % [label, clear, total])
	return ok


## The plates side by side at half size.
func _contact_sheet(plates: Array[Image]) -> Image:
	var w := plates[0].get_width() / 2
	var h := plates[0].get_height() / 2
	var sheet := Image.create(w * plates.size(), h, false, Image.FORMAT_RGBA8)
	for i in plates.size():
		var small := plates[i].duplicate() as Image
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	return sheet


## One static body per visible shell mesh, in world space.
func _colliders(shell: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ProbeColliders"
	root.add_child(holder)
	for mi in shell.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if not inst.is_visible_in_tree() or inst.mesh == null:
			continue
		var local_faces := inst.mesh.get_faces()
		if local_faces.is_empty():
			continue
		var faces := PackedVector3Array()
		var at := inst.global_transform
		for p in local_faces:
			faces.append(at * p)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var shape_node := CollisionShape3D.new()
		shape_node.shape = shape
		var body := StaticBody3D.new()
		body.set_meta("mesh", inst.name)
		body.add_child(shape_node)
		holder.add_child(body)
	print("PROBE occluder bodies=%d" % holder.get_child_count())
	return holder


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_beat(_stage)
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


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
			OS.crash("room_plates_probe: main thread stalled in %s" % stage)
