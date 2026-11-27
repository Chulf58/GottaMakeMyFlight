extends SceneTree
## Windowed Vulkan plate probe for `wall_belt_hatch.glb`, BuildView cutaway
## jamb stubs, and live BaggageSim/BaggageViews suitcase transit through a hatch.
##
## Run (one windowed Godot run project-wide):
##   tools/godot.sh --display-driver windows --rendering-driver vulkan \
##     --audio-driver Dummy --path game -s res://spike/belt_wall_hatch_probe.gd
##
## Saves under tools/blender/out/wall-belt-hatch/:
## - godot_closeup_west.png
## - godot_closeup_east.png
## - godot_play_cutaway.png
## - godot_distance.png

const OUT_REL := "res://../tools/blender/out/wall-belt-hatch"
const CAMERA := "res://camera/tycoon_camera.tscn"
const GRID := Vector2i(16, 16)
const HATCH_CELL := Vector2i(7, 6)
const MARGIN_PX := 8.0

var _out_dir := ""
var _failed := false
var _headless := false
var _mode: BuildMode
var _view: BuildView
var _bag_views: BaggageViews
var _cam: Camera3D
var _close_cam: Camera3D


func _initialize() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for _i in count:
		await process_frame
	if not _headless:
		await RenderingServer.frame_post_draw


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed_val := rng.randi()
	print("PROBE seed=%d" % seed_val)

	var site := _studio()
	var clock := SimClock.new()
	clock.seed_rng(seed_val)
	site.add_child(clock)
	clock.set_process(false)
	var finances := Finances.new()
	finances.clock = clock
	site.add_child(finances)
	finances.wallet.balance = 100000
	var flights := FlightSim.new()
	flights.clock = clock
	site.add_child(flights)
	flights.add_flight("FL1", PassengerTestWorld.starts_with(3900, 4000))

	_mode = BuildMode.new()
	_mode.grid_size = GRID
	_mode.finances = finances
	_mode.initial_tool = BuildMode.Tool.NONE
	site.add_child(_mode)
	_view = _mode.get_node("BuildView") as BuildView

	var bag_sim := BaggageSim.new()
	site.add_child(bag_sim)
	bag_sim.bind(clock, flights, _mode.grid)
	_bag_views = BaggageViews.new()
	_bag_views.clock = clock
	_bag_views.sim = bag_sim
	site.add_child(_bag_views)

	var desk_id := _build_terminal()
	_view.refresh(_mode.grid)

	# Keep ghost cleanly hidden and let the floating build-cost badge finish fading.
	_mode.set_process(false)
	BuildGhost.clear(_mode)
	_mode._ghost.visible = false
	await _frames(90)

	var bag := bag_sim.check_in(1, "FL1", desk_id)
	if bag == null:
		_invalid("check_in returned null")
		quit(1)
		return
	var bag2: Bag = null
	for tick_i in range(120):
		clock.tick += 1
		clock.ticked.emit(clock.tick)
		if bag2 == null and tick_i >= 18:
			bag2 = bag_sim.check_in(2, "FL1", desk_id)
		if bag.cell == HATCH_CELL + Vector2i(1, 0) and bag.remain_mm <= 600:
			break
	if bag.cell != HATCH_CELL + Vector2i(1, 0):
		_invalid("bag never reached hatch exit cell; cell=%s state=%d" % [bag.cell, bag.state])
		quit(1)
		return
	clock.tick += 1
	clock.ticked.emit(clock.tick)
	await _frames(6)
	if _bag_views.active_count() < 1:
		_invalid("BaggageViews shows no active bag")
		quit(1)
		return
	var bag_node := _bag_views.node_for(bag.id)
	var bag_pos := bag_node.global_position if bag_node != null else Vector3.ZERO
	print(
		(
			"BAG cell=%s remain_mm=%d world=%s active_views=%d"
			% [bag.cell, bag.remain_mm, bag_pos, _bag_views.active_count()]
		)
	)

	var rig := load(CAMERA).instantiate() as Node3D
	site.add_child(rig)
	var iso_cam := rig.get_node("Camera3D") as Camera3D
	_close_cam = Camera3D.new()
	_close_cam.fov = 45.0
	site.add_child(_close_cam)

	var hatch_center := BuildView.wall_transform(_mode.grid, HATCH_CELL, BuildGrid.Side.EAST).origin
	var hatch_points := _corners(_wall_box(HATCH_CELL, BuildGrid.Side.EAST))
	var focus_pt := hatch_center + Vector3(0.0, 1.15, 0.0)

	# 1. Close-up from West bay (inside terminal room, wall_belt_hatch full height).
	_view.cutaway_enabled = false
	_cam = _close_cam
	_close_cam.current = true
	_close_cam.position = focus_pt + Vector3(-2.6, 1.05, 2.8)
	_close_cam.look_at(focus_pt, Vector3.UP)
	await _frames(6)
	_capture_plate("godot_closeup_west.png", hatch_points, bag_pos, true)

	# 2. Close-up from East bay (inside bag room, opposite face of hatch + exiting bag).
	_close_cam.position = focus_pt + Vector3(2.6, 1.05, 2.7)
	_close_cam.look_at(focus_pt, Vector3.UP)
	await _frames(6)
	_capture_plate("godot_closeup_east.png", hatch_points, bag_pos, true)

	# 3. Close-up with WallCutaway enabled: 78 mm jamb stubs clearing +-0.42 m rails.
	_view.cutaway_enabled = true
	_close_cam.position = hatch_center + Vector3(-1.85, 1.65, 1.95)
	_close_cam.look_at(hatch_center + Vector3(0.0, 0.35, 0.0), Vector3.UP)
	_view.update_cutaway((_close_cam.global_position - hatch_center).normalized())
	await _frames(6)
	if _view.piece_counts().get("wall_belt_hatch", 0) != 0:
		_invalid("godot_closeup_cutaway.png: hatch wall was not cut away")
	var stub_points := _corners(_wall_stub_box(HATCH_CELL, BuildGrid.Side.EAST))
	_capture_plate("godot_closeup_cutaway.png", stub_points, bag_pos, false)

	# 4. Angled play view with WallCutaway active (proves jamb stubs clear belt rails).
	_view.cutaway_enabled = true
	_cam = iso_cam
	iso_cam.current = true
	rig.position = hatch_center
	rig.yaw = 0.65
	rig.distance = 12.0
	rig.zoom(1.0)
	await _frames(6)
	_view.update_cutaway((_cam.global_position - hatch_center).normalized())
	await _frames(4)
	_capture_plate("godot_play_cutaway.png", hatch_points, bag_pos, false)

	# 4. Distance terminal shot (cutaway off so hatch + wall row + glass wall read in context).
	_view.cutaway_enabled = false
	rig.position = _mode.grid.cell_to_world(Vector2i(7, 6))
	rig.yaw = -0.68
	rig.distance = 12.0
	rig.zoom(1.0)
	await _frames(6)
	_capture_plate("godot_distance.png", hatch_points, bag_pos, true)

	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _build_terminal() -> int:
	var grid := _mode.grid
	for y in range(4, 11):
		for x in range(4, 12):
			_must(grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1)))
	for x in range(4, 12):
		_must(grid.apply(BuildEdit.place_wall(Vector2i(x, 4), BuildGrid.Side.NORTH)))
		_must(grid.apply(BuildEdit.place_wall(Vector2i(x, 10), BuildGrid.Side.SOUTH)))
	for y in range(4, 11):
		_must(grid.apply(BuildEdit.place_wall(Vector2i(4, y), BuildGrid.Side.WEST)))
		_must(grid.apply(BuildEdit.place_wall(Vector2i(11, y), BuildGrid.Side.EAST)))
		var kind := BuildGrid.WallKind.GLASS if y == 8 or y == 9 else BuildGrid.WallKind.PLAIN
		_must(grid.apply(BuildEdit.place_wall(Vector2i(7, y), BuildGrid.Side.EAST, kind)))

	var desk_res := grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(4, 7), 0))
	_must(desk_res)
	_must(grid.apply(BuildEdit.place_room(Rect2i(9, 5, 3, 3), BeltShaper.BAG_ROOM)))
	_must(_mode.lay_belt(Vector2i(5, 6), Vector2i(9, 6)))
	if not grid.has_belt_hatch(HATCH_CELL, BuildGrid.Side.EAST):
		_invalid("hatch failed to open at %s EAST" % HATCH_CELL)
	return desk_res.object_id


func _must(result: BuildResult) -> void:
	if not result.ok:
		_invalid("edit refused: %s" % result.reason_text())


func _capture_plate(
	file: String, hatch_points: Array[Vector3], bag_pos: Vector3, check_wall_count: bool
) -> void:
	var ok := _prove_ghost_hidden(file)
	ok = _prove_in_frame(file, hatch_points) and ok
	ok = _prove_in_frame(file + "_bag", [bag_pos]) and ok
	var except_edges := [
		Vector3i(HATCH_CELL.x, HATCH_CELL.y, BuildGrid.Side.EAST),
		Vector3i(HATCH_CELL.x + 1, HATCH_CELL.y, BuildGrid.Side.WEST),
	]
	var mid := (
		BuildView.wall_transform(_mode.grid, HATCH_CELL, BuildGrid.Side.EAST).origin
		+ Vector3(0.0, 0.75, 0.0)
	)
	ok = _prove_clear(file, mid, except_edges) and ok
	if check_wall_count and _view.piece_counts().get("wall_belt_hatch", 0) != 1:
		_invalid("%s: expected 1 wall_belt_hatch mesh, got %s" % [file, _view.piece_counts()])
		ok = false
	if not ok:
		return
	if _headless:
		print("HEADLESS dry run, no PNG saved for %s" % file)
		return
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


func _prove_ghost_hidden(tag: String) -> bool:
	if not _mode._ghost.visible:
		return true
	for child in _mode._ghost.get_children():
		if not child.is_queued_for_deletion():
			_invalid("%s: ghost still visible with child %s" % [tag, child.name])
			return false
	return true


func _wall_box(cell: Vector2i, side: int) -> AABB:
	var local := AABB(
		Vector3(-0.5, 0.0, -BuildView.WALL_THICKNESS / 2.0),
		Vector3(1.0, BuildView.WALL_HEIGHT, BuildView.WALL_THICKNESS)
	)
	return BuildView.wall_transform(_mode.grid, cell, side) * local


func _wall_stub_box(cell: Vector2i, side: int) -> AABB:
	var local := AABB(
		Vector3(-0.5, 0.0, -BuildView.WALL_THICKNESS / 2.0),
		Vector3(1.0, InteriorKit.STUB_HEIGHT, BuildView.WALL_THICKNESS)
	)
	return BuildView.wall_transform(_mode.grid, cell, side) * local


func _corners(box: AABB) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in 8:
		pts.append(box.get_endpoint(i))
	return pts


func _prove_in_frame(tag: String, points: Array[Vector3]) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in points:
		var s := _cam.unproject_position(p)
		low = low.min(s)
		high = high.max(s)
		if _cam.is_position_behind(p) or not rect.has_point(s):
			_invalid("%s: %s -> (%.0f, %.0f) outside %s" % [tag, p, s.x, s.y, rect])
			return false
	print(
		(
			"INFRAME %s box=(%.0f,%.0f)-(%.0f,%.0f) px_h=%.0f"
			% [tag, low.x, low.y, high.x, high.y, high.y - low.y]
		)
	)
	return true


func _prove_clear(tag: String, point: Vector3, except: Array) -> bool:
	for edge in WallCutaway.wall_edges(_mode.grid):
		var c := Vector2i(edge.x, edge.y)
		var k := Vector3i(c.x, c.y, edge.z)
		if except.has(k) or _view.cut_edges().has(k):
			continue
		if _wall_box(c, edge.z).intersects_segment(_cam.global_position, point) != null:
			_invalid("%s: wall %s occludes subject" % [tag, edge])
			return false
	print("CLEAR %s unobstructed from %s to %s" % [tag, _cam.global_position, point])
	return true


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
			Vector3(0.866025, 0.0, -0.5),
			Vector3(-0.353553, 0.707107, -0.612372),
			Vector3(0.353553, 0.707107, 0.612372)
		),
		Vector3(0.0, 20.0, 0.0)
	)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.4
	sun.shadow_blur = 2.0
	sun.directional_shadow_max_distance = 410.0
	studio.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700.0, 700.0)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.36, 0.5, 0.3)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	ground.position.y = -0.1
	studio.add_child(ground)
	root.add_child(studio)
	return studio
