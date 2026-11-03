extends SceneTree
## Windowed plate probe for moving a room (RoomMoveTool, board bbfcfee7), in
## the real main scene with a new random seed (printed). On a strip of floor
## through the BuildMode API: a cafe with a bin, a 2 x 2 pot, a second bin and
## a belt across its west edge (one belt inside, a bend and a belt outside), a
## toilet room, and a bag room with a check-in desk. The pointer is moved with
## BuildMode.pointer_override, so RoomMoveTool reads it as it reads the mouse.
##   a. the cafe lifted over a free floored spot: green ghost with its pieces,
##      the original dimmed;
##   b. over bare ground: the cost line shows the new floor only;
##   c. turned once over the free spot;
##   d. over the toilet room: red ghost, the status line and the ghost card;
##   e. the bag room (check-in desk) is not lifted, the status line says why;
##   g. one cell east, the ghost over the original (no z-fighting of the slabs);
##   f. set down on the free spot, the belts reshaped; then one undo.
## Every plate proves its subject is in frame (the rectangle's corners and
## centre are projected and printed) and not hidden (sight lines against the
## boxes of every visible mesh outside BuildMode above the floor). A plate that
## fails prints PROBE_INVALID and the probe exits 1. A guard thread calls
## OS.crash() on a stall.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/room_move_tool_plates_probe.gd [-- --out=<dir>]
##
## Plates go to tools/blender/out/room_move_tool/ (gitignored) unless --out names a directory.

const OUT_REL := "res://../tools/blender/out/room_move_tool"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 8.0
const HANG_LIMIT_MS := 60000
const SETTLE_FRAMES := 8
## The floor strip, in the middle of the 66 x 30 grid under the default camera.
const FLOOR_MIN := Vector2i(23, 11)
const FLOOR_MAX := Vector2i(39, 17)
const CAFE := Rect2i(25, 12, 4, 3)
const TOILET := Rect2i(33, 12, 3, 3)
const BAG_ROOM := Rect2i(37, 14, 3, 3)
## The belt: one cell inside the cafe's west edge, a bend and a belt outside it.
const BELT_INSIDE := Vector2i(25, 13)
const BELT_BEND := Vector2i(24, 13)
const BELT_OUT := Vector2i(24, 12)
## Ghost centres: a free floored spot, bare ground, over the toilet.
const FREE_CENTRE := Vector2i(30, 16)
const BARE_CENTRE := Vector2i(30, 20)
const TOILET_CENTRE := Vector2i(34, 13)
## Where the camera looks from for every plate.
const SCREEN_AIM := Vector2(0.5, 0.36)
const VIEW_DISTANCE := 20.0
## A mesh whose top is below this height is ground, not a blocker.
const GROUND_TOP_M := 0.2

var _out_dir := ""
var _failed := false
var _stage := "init"
var _heartbeat_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard: Thread
var _build: BuildMode
var _menu: BuildMenu
var _mover: RoomMoveTool
var _cam: Camera3D
var _main: Node3D
var _cafe_id := 0
var _bag_id := 0
var _hover_centre := Vector2i(-1, -1)


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_beat("init")
	_guard = Thread.new()
	_guard.start(_watch)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


## Guard thread: a frozen main thread never reaches _process, so check from here.
func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var idle_ms := Time.get_ticks_msec() - _heartbeat_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS:
			print("PROBE_INVALID hang stage=%s no heartbeat for %d ms" % [stage, idle_ms])
			OS.crash("room move tool plate probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _finish() -> void:
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _run() -> void:
	var world_seed := randi()
	seed(world_seed)
	print("PROBE world_seed=", world_seed)
	_main = load(MAIN_SCENE).instantiate()
	var clock := _main.get_node_or_null("SimClock") as SimClock
	if clock != null:
		clock.seed_rng(world_seed)
	root.add_child(_main)
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_build = _main.get_node("BuildMode")
	_menu = _main.get_node("BuildMenu")
	_mover = _build.room_mover
	await _frames(10)
	_build_layout()
	if _failed:
		_finish()
		return
	await _plates()
	_finish()


## Glides the camera so the middle of `areas` sits at SCREEN_AIM of the
## viewport (above the HUD's hint card), from `distance`, and waits until it
## stops moving. A second glide corrects for the camera's tilt.
func _frame_on(areas: Array[Rect2i], distance: float) -> void:
	_beat("aim_camera")
	var rig := _main.get_node("TycoonCamera") as TycoonCamera
	var box := areas[0]
	for area in areas:
		box = box.merge(area)
	var goal := (_at(box.position) + _at(box.end - Vector2i.ONE)) / 2.0
	var aim := goal
	for round in 2:
		rig.glide_to(aim, distance)
		await _settle(rig)
		var spot := root.get_visible_rect().size * SCREEN_AIM
		var hit: Variant = _build.grid_point(
			_cam.project_ray_origin(spot), _cam.project_ray_normal(spot)
		)
		print("CAMERA round=%d box=%s aim=%s spot_hits=%s" % [round, box, aim, hit])
		if hit == null:
			break
		aim += goal - (hit as Vector3)
		aim.y = goal.y


func _settle(rig: TycoonCamera) -> void:
	var last := Vector3.INF
	var still := 0
	for i in 600:
		await process_frame
		var eye := _cam.global_position
		still = still + 1 if eye.distance_to(last) < 0.001 else 0
		last = eye
		if still >= 10:
			break
	print(
		"CAMERA eye=%s still_frames=%d distance=%.1f" % [_cam.global_position, still, rig.distance]
	)
	if still < 10:
		_invalid("the camera did not settle")


func _at(cell: Vector2i) -> Vector3:
	return _build.grid.cell_to_world(cell)


func _rect_at(centre: Vector2i, size: Vector2i) -> Rect2i:
	return Rect2i(centre - (size - Vector2i.ONE) / 2, size)


func _place(def_id: StringName, anchor: Vector2i, facing: int) -> int:
	var result := _build.grid.apply(BuildEdit.place_object(def_id, anchor, facing))
	print(
		(
			"PLACE %s at=%s facing=%d ok=%s id=%d"
			% [def_id, anchor, facing, result.ok, result.object_id]
		)
	)
	if not result.ok:
		_invalid("could not place %s at %s: %s" % [def_id, anchor, result.reason_text()])
	return result.object_id


func _drag_room(tool: BuildMode.Tool, rect: Rect2i) -> int:
	_build.set_tool(tool)
	_build.begin_area(_at(rect.position))
	_build.move_area(_at(rect.end - Vector2i.ONE))
	_build.finish_area()
	return _build.grid.room_at(rect.position)


func _build_layout() -> void:
	# Own the land under the strip and the bare spot, so no move is refused for land.
	var own: Array[Vector2i] = []
	for y in range(FLOOR_MIN.y, BARE_CENTRE.y + 2):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
			own.append(Vector2i(x, y))
	if _build.land_tool != null and _build.land_tool.land != null:
		_build.land_tool.land.own_around(own)
	_build.set_tool(BuildMode.Tool.FLOOR)
	_build.begin_area(_at(FLOOR_MIN))
	_build.move_area(_at(FLOOR_MAX))
	_build.finish_area()
	if _build.grid.floor_at(FLOOR_MAX) == BuildGrid.FLOOR_NONE:
		_invalid("the floor strip was not laid: %s" % _build.status_text())
		return
	_cafe_id = _drag_room(BuildMode.Tool.CAFE_ROOM, CAFE)
	var toilet_id := _drag_room(BuildMode.Tool.TOILET_ROOM, TOILET)
	_bag_id = _drag_room(BuildMode.Tool.BAG_ROOM, BAG_ROOM)
	print(
		(
			"ROOMS cafe=%d %s toilet=%d %s bag=%d %s"
			% [_cafe_id, CAFE, toilet_id, TOILET, _bag_id, BAG_ROOM]
		)
	)
	if _cafe_id == 0 or toilet_id == 0 or _bag_id == 0:
		_invalid("a room was not marked: %s" % _build.status_text())
		return
	_place(&"trash_can", Vector2i(28, 12), 0)
	_place(&"plant_pot_2a", Vector2i(26, 13), 0)
	_place(&"trash_can", Vector2i(28, 14), 0)
	for cell: Vector2i in [BELT_INSIDE, BELT_BEND, BELT_OUT]:
		_place(BeltShaper.BELT, cell, 1)
	_place(BeltShaper.DESK, Vector2i(37, 15), 0)
	var near: Array[Vector2i] = []
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
			near.append(Vector2i(x, y))
	var shaped := _build.grid.apply_sequence(
		BeltShaper.reshape_edits(_build.grid, near), Callable()
	)
	print("BELTS shaped ok=%s %s" % [shaped.ok, _belts()])


## The belt pieces near the cafe, as "cell:def:facing".
func _belts() -> Array[String]:
	var out: Array[String] = []
	for y in range(FLOOR_MIN.y, FLOOR_MAX.y + 1):
		for x in range(FLOOR_MIN.x, FLOOR_MAX.x + 1):
			var id := _build.grid.object_at(Vector2i(x, y))
			if id == 0:
				continue
			var obj := _build.grid.get_object(id)
			if String(obj["def"]).begins_with("baggage_belt") and obj["anchor"] == Vector2i(x, y):
				out.append("%s:%s:%d" % [Vector2i(x, y), obj["def"], obj["facing"]])
	return out


func _hover(centre: Vector2i) -> void:
	_hover_centre = centre
	_build.pointer_override = _cam.unproject_position(_at(centre))
	await _frames(SETTLE_FRAMES)


## How many of the drawn objects' meshes carry a material override (the dim).
func _dimmed_meshes() -> int:
	var count := 0
	for id in _build.grid.object_ids():
		var node := _build.object_node(id)
		if node == null:
			continue
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			if (mesh as MeshInstance3D).material_override != null:
				count += 1
	return count


func _object_meshes() -> int:
	var count := 0
	for id in _build.grid.object_ids():
		var node := _build.object_node(id)
		if node != null:
			count += node.find_children("*", "MeshInstance3D", true, false).size()
	return count


func _report(label: String) -> void:
	var meshes := _mover.ghost_node().find_children("*", "MeshInstance3D", true, false)
	var pieces := 0
	for child in _mover.ghost_node().get_children():
		if child.name != "Room":
			pieces += 1
	var reason := _menu.ghost_reason()
	var build_ghost := _build.get_node_or_null("Ghost") as Node3D
	print(
		(
			"STATE %s active=%s turns=%d ghost_meshes=%d ghost_pieces=%d dim=%d dimmed_meshes=%d/%d"
			% [
				label,
				_mover.active,
				_mover.turns,
				meshes.size(),
				pieces,
				_mover.get_node("RoomMoveDim").get_child_count(),
				_dimmed_meshes(),
				_object_meshes()
			]
		)
	)
	print(
		(
			"HUD %s status='%s' cost='%s' card_visible=%s card='%s' build_ghost_children=%d"
			% [
				label,
				_menu.status_label().text,
				_menu.preview_text(),
				reason.visible,
				reason.text() if reason.visible else "",
				build_ghost.get_child_count() if build_ghost != null and build_ghost.visible else 0
			]
		)
	)


func _ghost_colour() -> Color:
	var slab := _mover.ghost_node().get_node_or_null("Room") as MeshInstance3D
	if slab == null:
		return Color.TRANSPARENT
	return (slab.material_override as StandardMaterial3D).albedo_color


func _plates() -> void:
	_build.set_tool(BuildMode.Tool.CAFE_ROOM)
	_beat("pick_up")
	# BuildView draws the pieces at the end of the frame that placed them, so a
	# pick-up in that frame would find no node to dim.
	await _frames(SETTLE_FRAMES)
	var lifted := _mover.pick_up(_at(CAFE.position + Vector2i(1, 1)), &"cafe")
	print("PICK_UP cafe lifted=%s room_id=%d" % [lifted, _mover.room_id])
	if not lifted:
		_invalid("the cafe was not lifted: %s" % _mover.status_text())
		return
	# a. green ghost over the free floored spot, the original dimmed.
	var free_rect := _rect_at(FREE_CENTRE, CAFE.size)
	await _hover(FREE_CENTRE)
	_report("a_free")
	print("COST a_free price=%s" % _mover.preview_price())
	if _ghost_colour() != BuildMode.VALID_TINT:
		_invalid("a: the ghost is not green (%s)" % _ghost_colour())
	await _plate("a_free", [free_rect, CAFE])
	# b. bare ground: the cost line shows the floor only.
	var bare_rect := _rect_at(BARE_CENTRE, CAFE.size)
	await _hover(BARE_CENTRE)
	_report("b_bare")
	var floor_cells := 0
	for y in range(bare_rect.position.y, bare_rect.end.y):
		for x in range(bare_rect.position.x, bare_rect.end.x):
			if _build.grid.floor_at(Vector2i(x, y)) == BuildGrid.FLOOR_NONE:
				floor_cells += 1
	print("COST b_bare unfloored_cells=%d price=%s" % [floor_cells, _mover.preview_price()])
	await _plate("b_bare", [bare_rect])
	# c. turned once over the free spot.
	_mover.rotate_turns()
	await _hover(FREE_CENTRE)
	_report("c_turned")
	var turned_rect := _mover.plan_at(FREE_CENTRE).to_rect
	print("TURN c_turned to_rect=%s" % turned_rect)
	await _plate("c_turned", [turned_rect, CAFE])
	_mover.rotate_turns()
	_mover.rotate_turns()
	_mover.rotate_turns()
	# d. red over the toilet: status line and ghost card.
	var toilet_rect := _rect_at(TOILET_CENTRE, CAFE.size)
	await _hover(TOILET_CENTRE)
	_report("d_toilet")
	if _ghost_colour() != BuildMode.INVALID_TINT:
		_invalid("d: the ghost is not red (%s)" % _ghost_colour())
	if not _menu.ghost_reason().visible:
		_invalid("d: the ghost card is not shown")
	await _plate("d_toilet", [toilet_rect, CAFE])
	# g. one cell east: the ghost slab lies over the dim slab of the original.
	var overlap_centre := Vector2i(27, 13)
	await _hover(overlap_centre)
	_report("g_overlap")
	await _plate("g_overlap", [_rect_at(overlap_centre, CAFE.size), CAFE])
	# f. set down on the free spot, the belts reshaped.
	await _hover(FREE_CENTRE)
	print("BELTS before %s" % [_belts()])
	var result := _mover.set_down(FREE_CENTRE)
	await _frames(SETTLE_FRAMES)
	var moved: Rect2i = _build.grid.get_room(_cafe_id).get("rect", Rect2i())
	print(
		(
			"SET_DOWN ok=%s rect=%s status='%s' active=%s belts=%s"
			% [
				result != null and result.ok,
				moved,
				_menu.status_label().text,
				_mover.active,
				_belts()
			]
		)
	)
	_report("f_set_down")
	if moved != free_rect:
		_invalid("f: the cafe is at %s, expected %s" % [moved, free_rect])
	await _plate("f_set_down", [free_rect, CAFE])
	var undone := _build.undo()
	await _frames(SETTLE_FRAMES)
	var back: Rect2i = _build.grid.get_room(_cafe_id).get("rect", Rect2i())
	print(
		(
			"UNDO ok=%s rect=%s status='%s' belts=%s"
			% [undone != null and undone.ok, back, _menu.status_label().text, _belts()]
		)
	)
	if back != CAFE:
		_invalid("f: after undo the cafe is at %s, expected %s" % [back, CAFE])
	await _plate("f_undo", [free_rect, CAFE])
	# e. the bag room with a check-in desk is not lifted.
	_build.set_tool(BuildMode.Tool.BAG_ROOM)
	await _hover(BAG_ROOM.position + Vector2i(1, 1))
	var bag_lifted := _mover.pick_up(_at(BAG_ROOM.position + Vector2i(1, 1)), &"bag_room")
	await _frames(SETTLE_FRAMES)
	print("PICK_UP bag lifted=%s mover_status='%s'" % [bag_lifted, _mover.status_text()])
	_report("e_desk")
	if bag_lifted:
		_invalid("e: the bag room with a check-in desk was lifted")
	await _plate("e_desk", [BAG_ROOM])


func _slab_centre(area: Rect2i) -> Vector3:
	var low := _at(area.position)
	var high := _at(area.end - Vector2i.ONE)
	return (low + high) / 2.0 + Vector3(0.0, 0.1, 0.0)


## Each rectangle's four corners and centre must project inside the viewport
## with a margin; they are printed.
func _in_frame(label: String, area: Rect2i) -> bool:
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var low := _at(area.position) - Vector3(0.5, -0.1, 0.5)
	var high := _at(area.end - Vector2i.ONE) + Vector3(0.5, 0.1, 0.5)
	var points: Array[Vector3] = [
		low, Vector3(high.x, low.y, low.z), high, Vector3(low.x, low.y, high.z), _slab_centre(area)
	]
	for p in points:
		var s := _cam.unproject_position(p)
		var inside := frame.has_point(s) and not _cam.is_position_behind(p)
		print("INFRAME %s rect=%s screen=(%.0f,%.0f) ok=%s" % [label, area, s.x, s.y, inside])
		if not inside:
			_invalid("%s: %s of %s is outside the frame" % [label, p, area])
			return false
	return true


## The rectangle's centre must not be under the hint card, the tray or the bar.
func _clear_of_hud(label: String, area: Rect2i) -> bool:
	var at := _cam.unproject_position(_slab_centre(area))
	var hint := (_main.get_node("StaffPanel") as StaffPanel).hint_label()
	var covers: Array[Control] = [hint.get_parent() as Control, _menu.bar()]
	if _menu.is_tray_open():
		covers.append(_menu.tray())
	var under: Array[String] = []
	for cover in covers:
		if cover != null and cover.is_visible_in_tree() and cover.get_global_rect().has_point(at):
			under.append(String(cover.name))
	print("HUDCOVER %s rect=%s screen=(%.0f,%.0f) under=%s" % [label, area, at.x, at.y, under])
	if not under.is_empty():
		_invalid("%s: %s is under the HUD (%s)" % [label, area, under])
		return false
	return true


## A sight line from the camera to the rectangle's centre against the box of
## every visible mesh outside BuildMode whose top is above the floor, except a
## mesh whose box holds the target (the ground). Prints the blockers.
func _clear_sight(label: String, area: Rect2i) -> bool:
	var p := _slab_centre(area)
	var blockers := {}
	for node in _main.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if _build.is_ancestor_of(mesh) or not mesh.is_visible_in_tree():
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		if box.end.y < GROUND_TOP_M or box.has_point(p):
			continue
		if box.intersects_segment(_cam.global_position, p) != null:
			blockers[mesh.get_path()] = true
	print("SIGHT %s rect=%s blockers=%s" % [label, area, blockers.keys()])
	if not blockers.is_empty():
		_invalid("%s: %s is hidden by %s" % [label, area, blockers.keys()])
		return false
	return true


## Frames the camera on `areas`, puts the pointer back over the hovered cell
## (the ghost follows it), proves each area in frame, in sight and clear of the
## HUD's hint card, tray and bar, then saves the plate.
func _plate(label: String, areas: Array[Rect2i]) -> void:
	await _frame_on(areas, VIEW_DISTANCE)
	if _hover_centre.x >= 0:
		_build.pointer_override = _cam.unproject_position(_at(_hover_centre))
	await _frames(SETTLE_FRAMES)
	if _mover.active:
		_report(label + "_framed")
	for area in areas:
		if (
			not _in_frame(label, area)
			or not _clear_sight(label, area)
			or not _clear_of_hud(label, area)
		):
			return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("room_move_%s.png" % label)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])
