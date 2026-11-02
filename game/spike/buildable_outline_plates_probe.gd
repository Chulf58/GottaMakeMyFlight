extends SceneTree
## Windowed plate probe for the buildable-land outline (user ruling buildable-land-
## shows-as-an-outline-only-in-build-mode-the-da) and the site paving without its dark
## checker tile accents. Boots main.tscn, then saves:
##   tray_open_overview   whole plot with a build tray open: the outline all round;
##   tray_closed_overview the same view with the tray closed: no outline;
##   corner_<nw|ne|se|sw> each outline corner close up, tray open;
##   edge_floor           floor tiles laid against the south edge, tray open;
##   paving_<west|east>   the paving close up where the accent bands were, tray closed;
##   sidewalk_<west|east> the Road's sidewalk where its accents were, tray closed.
## Each plate with the outline also prints, per side, the frame's width measured on screen
## through the camera (see _print_widths), which keeps WIDTH_PX at every zoom.
## Every plate first projects its subject points into the viewport (with a margin, in
## front of the camera, off the build tray, the bar and the "Airport closed" hint card) and
## casts a physics ray from the
## camera to each; a point out of frame, under the HUD or behind a collider prints
## PROBE_INVALID and the probe exits 1.
##
## Run (one windowed Godot run project-wide):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/buildable_outline_plates_probe.gd
##
## Plates go to tools/blender/out/buildable-outline/.

const OUT_REL := "res://../tools/blender/out/buildable-outline"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 16.0
const SETTLE_FRAMES := 24
const OVERVIEW_DISTANCE := 95.0
const CLOSE_DISTANCE := 18.0
## Floor laid against the south edge for the in-context plate (cells x 40..45, y 36..39).
const EDGE_FLOOR := Rect2i(40, 36, 6, 4)

var _out_dir := ""
var _failed := false
## Every saved plate, for the contact sheet.
var _sheet: Array[Image] = []
var _main: Node3D
var _cam: Camera3D
var _rig: Node3D
var _build: BuildMode
var _menu: BuildMenu
var _outline: BuildableOutline
var _staff: StaffPanel


func _initialize() -> void:
	var world_seed := randi()
	seed(world_seed)
	print("PROBE seed=", world_seed)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("PROBE out_dir=", _out_dir)
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	root.add_child(_main)
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_rig = _main.get_node("TycoonCamera")
	_build = _main.get_node("BuildMode")
	_menu = _main.get_node("BuildMenu")
	_outline = _main.get_node("BuildableOutline")
	_staff = _main.get_node("StaffPanel")
	await _frames(20)
	_lay_edge_floor()
	var corners := _outline.outline_points()
	print("OUTLINE loops=%s corners=%s" % [_outline.loops(), corners])
	var centre := Vector3(0.0, 0.0, -80.0)
	_set_tray(true)
	await _plate("tray_open_overview", centre, OVERVIEW_DISTANCE, corners, true)
	_set_tray(false)
	await _plate("tray_closed_overview", centre, OVERVIEW_DISTANCE, corners, false)
	_set_tray(true)
	var names := ["nw", "ne", "se", "sw"]
	for i in corners.size():
		var at: Vector3 = corners[i]
		var focus := Vector3(at.x - signf(at.x) * 4.0, 0.0, at.z - signf(at.z + 80.0) * 3.0)
		await _plate("corner_" + names[i], focus, CLOSE_DISTANCE, [at], true)
	var edge_y: float = corners[0].y
	var edge_mid := Vector3(_build.grid.cell_to_world(Vector2i(42, 39)).x + 0.5, edge_y, -60.0)
	var floor_pt := _build.grid.cell_to_world(Vector2i(42, 38))
	await _plate(
		"edge_floor", edge_mid + Vector3(0, 0, -4), CLOSE_DISTANCE, [edge_mid, floor_pt], true
	)
	_set_tray(false)
	# The paving where the long dark accent bands ran (x about -33 and 33).
	for side in [["west", -33.0], ["east", 33.0]]:
		var spot := Vector3(side[1], 0.2, -78.0)
		var edges := [spot + Vector3(-4, 0, -3), spot + Vector3(4, 0, 3)]
		await _plate("paving_" + side[0], spot, CLOSE_DISTANCE, edges, false)
	# The Road's sidewalk where its tile accents were (x -27..-16 and 15..26, z -60..-58.75).
	for side in [["west", -21.5], ["east", 20.5]]:
		var walk := Vector3(side[1], 0.2, -59.4)
		var ends := [walk + Vector3(-5.5, 0, 0), walk + Vector3(5.5, 0, 0)]
		await _plate("sidewalk_" + side[0], walk + Vector3(0, 0, -2), 14.0, ends, false)
	_save_contact_sheet()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _set_tray(open: bool) -> void:
	if open and not _menu.is_tray_open():
		_menu.press_category(0)
	elif not open and _menu.is_tray_open():
		_menu.press_category(_menu.open_category())
	print(
		(
			"TRAY open=%s build_session=%s outline_visible=%s"
			% [_menu.is_tray_open(), _menu.build_session.active, _outline.is_visible_in_tree()]
		)
	)


## Floor tiles against the south edge, laid before any tray opens.
func _lay_edge_floor() -> void:
	_build.set_tool(BuildMode.Tool.FLOOR)
	var laid := 0
	for y in range(EDGE_FLOOR.position.y, EDGE_FLOOR.end.y):
		for x in range(EDGE_FLOOR.position.x, EDGE_FLOOR.end.x):
			var result := _build.apply_at(_build.grid.cell_to_world(Vector2i(x, y)))
			if result != null and result.ok:
				laid += 1
	_build.set_tool(BuildMode.Tool.NONE)
	print("FLOOR laid=%d of %d" % [laid, EDGE_FLOOR.get_area()])
	if laid != EDGE_FLOOR.get_area():
		_invalid("edge floor: laid %d of %d" % [laid, EDGE_FLOOR.get_area()])


## The bar, the open tray and the "Airport closed" hint card (StaffPanel's hint, its
## card when the label sits in one).
func _hud_rects() -> Array[Rect2]:
	var out: Array[Rect2] = [_menu.bar().get_global_rect()]
	if _menu.is_tray_open():
		out.append(_menu.tray().get_global_rect())
	var hint := _staff.hint_label()
	if hint.is_visible_in_tree():
		var card := hint.get_parent() as Control
		out.append((card if card != null else hint).get_global_rect())
	return out


func _plate(label: String, focus: Vector3, distance: float, points: Array, want: bool) -> void:
	_rig.position = focus
	_rig.target_distance = distance
	_rig.distance = distance
	await _frames(SETTLE_FRAMES)
	if _outline.is_visible_in_tree() != want:
		_invalid("%s: outline visible=%s, want %s" % [label, _outline.is_visible_in_tree(), want])
		return
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var space := _cam.get_world_3d().direct_space_state
	for p: Vector3 in points:
		var s := _cam.unproject_position(p)
		var under_hud := _hud_rects().any(func(r: Rect2) -> bool: return r.has_point(s))
		var query := PhysicsRayQueryParameters3D.create(_cam.global_position, p + Vector3.UP * 0.01)
		var hit := space.intersect_ray(query)
		print(
			(
				"INFRAME %s point=%s screen=(%.0f,%.0f) in=%s under_hud=%s ray_hit=%s"
				% [label, p, s.x, s.y, frame.has_point(s), under_hud, hit.get("collider", "none")]
			)
		)
		if _cam.is_position_behind(p) or not frame.has_point(s) or under_hud:
			_invalid("%s: %s is out of frame or under the HUD" % [label, p])
			return
		if not hit.is_empty():
			_invalid("%s: %s is hidden behind %s" % [label, p, hit["collider"]])
			return
	if want:
		_print_widths(label)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("%s.png" % label)
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	_sheet.append(img)
	print(
		(
			"PLATE saved %s camera=%s distance=%.1f outline_visible=%s"
			% [path, _cam.global_position, distance, _outline.is_visible_in_tree()]
		)
	)


## Every plate in one 3-wide sheet, 640x360 a tile, in the order they were taken.
func _save_contact_sheet() -> void:
	if _sheet.is_empty():
		return
	var tile := Vector2i(640, 360)
	var cols := 3
	var rows := ceili(_sheet.size() / float(cols))
	var sheet := Image.create(tile.x * cols, tile.y * rows, false, Image.FORMAT_RGBA8)
	for i in _sheet.size():
		var small: Image = _sheet[i].duplicate()
		small.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, tile), Vector2i(i % cols, i / cols) * tile)
	var path := _out_dir.path_join("contact_sheet.png")
	if sheet.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("SHEET saved %s plates=%d" % [path, _sheet.size()])


## Each side's frame width as measured on screen, at every piece end and piece middle
## whose outer and inner points are both in front of the camera and in the viewport:
## "perp" from the inner point to the outer edge's screen line through this piece end
## and a neighbouring one (the band's thickness across itself, what the outline
## solves), "px" from the outer point to the point straight in from it, each as
## min/mean/max in viewport pixels, and the metres at the side's middle piece end.
func _print_widths(label: String) -> void:
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var edges := _outline.side_edges()
	var names := ["north", "east", "south", "west"]
	for s in edges.size():
		var edge: PackedVector3Array = edges[s]
		var along: Array[float] = []
		var across: Array[float] = []
		for k in range(0, edge.size(), 2):
			var neighbour := k + 2 if k + 2 < edge.size() else k - 2
			var pairs := [[edge[k], edge[k + 1]]]
			if k + 2 < edge.size():
				pairs.append([(edge[k] + edge[k + 2]) / 2.0, (edge[k + 1] + edge[k + 3]) / 2.0])
			for pair in pairs:
				if (
					_cam.is_position_behind(pair[0])
					or _cam.is_position_behind(pair[1])
					or _cam.is_position_behind(edge[neighbour])
				):
					continue
				var a := _cam.unproject_position(pair[0])
				var b := _cam.unproject_position(pair[1])
				if not view.has_point(a) or not view.has_point(b):
					continue
				along.append(a.distance_to(b))
				var line := (_cam.unproject_position(edge[neighbour]) - a).normalized()
				across.append(absf((b - a).cross(line)))
		var mid := int(edge.size() / 4.0) * 2
		print(
			(
				"WIDTH %s %s points=%d perp=%s px=%s middle=%.2fm (want %.0f px)"
				% [
					label,
					names[s % 4],
					along.size(),
					_spread(across),
					_spread(along),
					edge[mid].distance_to(edge[mid + 1]),
					BuildableOutline.WIDTH_PX
				]
			)
		)


func _spread(values: Array[float]) -> String:
	if values.is_empty():
		return "none"
	var total := 0.0
	for v in values:
		total += v
	return "%.2f/%.2f/%.2f" % [values.min(), total / values.size(), values.max()]
