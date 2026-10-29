extends SceneTree
## Windowed plate probe for the Wall row drag and the Remove tool's wall pick.
##
## Run (one windowed Godot run project-wide; take the slot lock first):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/wall_tools_plate_probe.gd
##
## Builds a 12 x 8 room (floor, walls all round) in a BuildMode on a 24 x 24
## grid and looks at it through the real TycoonCamera, at the default zoom
## (home_distance, where a wall is a few dozen pixels tall) and at a close zoom
## to inspect:
##   (a) the Wall tool mid-drag: a row pressed south of the room and dragged
##       diagonally, which must show as one straight ghost row along x with its
##       length and cost on the status line, and nothing placed yet;
##   (b) the Remove tool hovering the room's far wall at mid-height, which must
##       pick the wall (a ray through the wall's face reaches the floor well
##       behind it) and show it in the orange remove tint.
## Each subject must project inside the frame and have an unobstructed ray from
## the camera, or the probe prints PROBE_INVALID and exits 1. Run with
## --headless instead of the display flags for a dry run of the checks only (no
## plates). Plates go to tools/blender/out/wall_tools/.

const OUT_REL := "res://../tools/blender/out/wall_tools"
const CAMERA := "res://camera/tycoon_camera.tscn"
const GRID := Vector2i(24, 24)
const ROOM_MIN := Vector2i(6, 8)
const ROOM_MAX := Vector2i(17, 15)
## The far wall the Remove hover picks: the room's north edge (the camera looks
## north), so no cutaway stub hides it.
const HOVER_WALL := Vector2i(11, 8)
const ROW_PRESS := Vector2i(6, 19)
const ROW_DRAG := Vector2i(17, 20)
const MARGIN_PX := 8.0
const ZOOMS := [["default", -1.0], ["close", 24.0]]

var _out_dir := ""
var _failed := false
var _headless := false
var _mode: BuildMode
var _cam: Camera3D


func _initialize() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	if not _headless:
		await RenderingServer.frame_post_draw


func _run() -> void:
	var site := _studio()
	_mode = BuildMode.new()
	_mode.grid_size = GRID
	_mode.initial_tool = BuildMode.Tool.NONE
	site.add_child(_mode)
	var view: BuildView = _mode.get_node("BuildView")
	_build_room()
	view.refresh(_mode.grid)
	var rig: Node3D = load(CAMERA).instantiate()
	site.add_child(rig)
	_cam = rig.get_node("Camera3D")
	_cam.make_current()
	var focus := _mode.grid.cell_to_world(Vector2i(11, 14))
	for zoom in ZOOMS:
		rig.position = focus
		rig.yaw = 0.0
		rig.distance = zoom[1] if zoom[1] > 0.0 else rig.home_distance
		rig.zoom(1.0)
		await _frames(6)
		print("CAMERA %s distance=%.1f pos=%s" % [zoom[0], rig.distance, _cam.global_position])
		await _row_plate(zoom[0])
		await _remove_plate(zoom[0], view)
	print("PROBE done failed=%s walls_left=%d" % [_failed, _wall_count()])
	quit(1 if _failed else 0)


func _build_room() -> void:
	var grid := _mode.grid
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
			_must(grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1)))
	for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
		_must(grid.apply(BuildEdit.place_wall(Vector2i(x, ROOM_MIN.y), BuildGrid.Side.NORTH)))
		_must(grid.apply(BuildEdit.place_wall(Vector2i(x, ROOM_MAX.y), BuildGrid.Side.SOUTH)))
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		_must(grid.apply(BuildEdit.place_wall(Vector2i(ROOM_MIN.x, y), BuildGrid.Side.WEST)))
		_must(grid.apply(BuildEdit.place_wall(Vector2i(ROOM_MAX.x, y), BuildGrid.Side.EAST)))


func _must(result: BuildResult) -> void:
	if not result.ok:
		_invalid("room edit refused: %s" % result.reason_text())


func _wall_count() -> int:
	return WallCutaway.wall_edges(_mode.grid).size()


## A ground point 0.45 m from the middle of `cell` toward `side`.
func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _mode.grid.cell_to_world(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


## The box of one wall edge, as the view draws it.
func _wall_box(cell: Vector2i, side: int, grow := 0.0) -> AABB:
	var local := AABB(
		Vector3(-0.5 - grow, 0.0, -BuildView.WALL_THICKNESS / 2.0 - grow),
		Vector3(
			1.0 + 2.0 * grow, BuildView.WALL_HEIGHT + grow, BuildView.WALL_THICKNESS + 2.0 * grow
		)
	)
	return BuildView.wall_transform(_mode.grid, cell, side) * local


func _corners(box: AABB) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in 8:
		points.append(box.get_endpoint(i))
	return points


## True when every point projects inside the viewport with a margin and is in
## front of the camera; prints each screen position.
func _prove_in_frame(tag: String, points: Array[Vector3]) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in points:
		var s := _cam.unproject_position(p)
		low = low.min(s)
		high = high.max(s)
		if _cam.is_position_behind(p) or not rect.has_point(s):
			_invalid("%s: %s projects to (%.0f,%.0f), outside the frame" % [tag, p, s.x, s.y])
			return false
	print(
		(
			"INFRAME %s screen_box=(%.0f,%.0f)-(%.0f,%.0f) px_h=%.0f"
			% [tag, low.x, low.y, high.x, high.y, high.y - low.y]
		)
	)
	return true


## True when no wall other than `except` (cell, side) stands between the camera
## and `point`.
func _prove_clear(tag: String, point: Vector3, except: Array) -> bool:
	for edge in WallCutaway.wall_edges(_mode.grid):
		var cell := Vector2i(edge.x, edge.y)
		if except.has(Vector3i(cell.x, cell.y, edge.z)):
			continue
		if _wall_box(cell, edge.z).intersects_segment(_cam.global_position, point) != null:
			_invalid("%s: wall %s hides the subject" % [tag, edge])
			return false
	print("CLEAR %s no other wall between the camera and %s" % [tag, point])
	return true


func _save_plate(file: String) -> void:
	if _headless:
		print("HEADLESS dry run, no plate for %s" % file)
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


## (a) The Wall tool pressed south of the room and dragged diagonally.
func _row_plate(zoom_name: String) -> void:
	var tag := "row_%s" % zoom_name
	var before := _wall_count()
	_mode.set_tool(BuildMode.Tool.WALL)
	var press := _near_edge(ROW_PRESS, BuildGrid.Side.NORTH)
	_mode.begin_row(press)
	_mode.move_row(_near_edge(ROW_DRAG, BuildGrid.Side.NORTH))
	var row_cells: Array[Vector2i] = []
	for x in range(ROW_PRESS.x, ROW_DRAG.x + 1):
		row_cells.append(Vector2i(x, ROW_PRESS.y))
	var first := _wall_box(row_cells.front(), BuildGrid.Side.NORTH)
	var last := _wall_box(row_cells.back(), BuildGrid.Side.NORTH)
	var points := _corners(first)
	points.append_array(_corners(last))
	var ok := _prove_in_frame(tag, points)
	var middle := _wall_box(row_cells[row_cells.size() / 2], BuildGrid.Side.NORTH)
	ok = _prove_clear(tag, middle.get_center(), []) and ok
	_mode.pointer_override = _cam.unproject_position(middle.get_center())
	await _frames(6)
	var ghost := _mode.get_node("Ghost") as Node3D
	print(
		(
			"ROW %s status='%s' ghost_boxes=%d visible=%s walls_before=%d walls_now=%d"
			% [
				tag,
				_mode.status_text(),
				ghost.get_child_count(),
				ghost.visible,
				before,
				_wall_count()
			]
		)
	)
	if ghost.get_child_count() != row_cells.size() or not ghost.visible:
		_invalid("%s: the ghost is not the whole row of %d" % [tag, row_cells.size()])
	if not _mode.status_text().begins_with("Wall row of %d" % row_cells.size()):
		_invalid("%s: the status line does not give the row length" % tag)
	if _wall_count() != before:
		_invalid("%s: a wall was placed before release" % tag)
	if ok:
		_save_plate("%s.png" % tag)
	_mode.cancel_area()
	_mode.pointer_override = Vector2(-1.0, -1.0)
	if _wall_count() != before:
		_invalid("%s: cancelling placed walls" % tag)


## (b) The Remove tool over the far wall, at the pixel of its mid-height.
func _remove_plate(zoom_name: String, view: BuildView) -> void:
	var tag := "remove_%s" % zoom_name
	_mode.set_tool(BuildMode.Tool.REMOVE)
	var box := _wall_box(HOVER_WALL, BuildGrid.Side.NORTH)
	var mid := box.get_center()
	var ok := _prove_in_frame(tag, _corners(box))
	var hover_edge := Vector3i(HOVER_WALL.x, HOVER_WALL.y, BuildGrid.Side.NORTH)
	ok = _prove_clear(tag, mid, [hover_edge]) and ok
	if view.cut_edges().has(hover_edge):
		_invalid("%s: the hovered wall is cut to a stub, pick another" % tag)
		ok = false
	var screen := _cam.unproject_position(mid)
	_mode.pointer_override = screen
	await _frames(6)
	var ray_from := _cam.project_ray_origin(screen)
	var ground: Variant = _mode.grid_point(ray_from, _cam.project_ray_normal(screen))
	var edit := _mode.hover_edit()
	var ghost := _mode.get_node("Ghost") as Node3D
	var distance_behind: float = absf((ground as Vector3).z - mid.z) if ground != null else -1.0
	print(
		(
			(
				"REMOVE %s pixel=(%.0f,%.0f) ground=%s behind_wall_m=%.2f kind=%s cell=%s "
				+ "side=%s ghost_boxes=%d status='%s'"
			)
			% [
				tag,
				screen.x,
				screen.y,
				ground,
				distance_behind,
				edit.kind if edit != null else -1,
				edit.cell if edit != null else "-",
				edit.side if edit != null else -1,
				ghost.get_child_count(),
				_mode.status_text()
			]
		)
	)
	if edit == null or edit.kind != BuildEdit.Kind.REMOVE_WALL:
		_invalid("%s: the hover did not pick the wall" % tag)
		ok = false
	elif edit.cell != HOVER_WALL or edit.side != BuildGrid.Side.NORTH:
		_invalid("%s: the hover picked another wall" % tag)
		ok = false
	if distance_behind <= BuildMode.WALL_PICK_DISTANCE:
		_invalid("%s: the pointer's ground point is within the old band, no proof of the fix" % tag)
		ok = false
	if ghost.get_child_count() != 1 or not ghost.visible:
		_invalid("%s: the ghost is not one visible box" % tag)
		ok = false
	if ok:
		_save_plate("%s.png" % tag)
	_mode.pointer_override = Vector2(-1.0, -1.0)


func _studio() -> Node3D:
	var studio := Node3D.new()
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	studio.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(
		Basis(
			Vector3(0.866025, 0, -0.5),
			Vector3(-0.353553, 0.707107, -0.612372),
			Vector3(0.353553, 0.707107, 0.612372)
		),
		Vector3(0, 20, 0)
	)
	sun.shadow_enabled = true
	studio.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.36, 0.5, 0.3)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	ground.position.y = -0.1
	studio.add_child(ground)
	root.add_child(studio)
	return studio
