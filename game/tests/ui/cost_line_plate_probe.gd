extends SceneTree
## Windowed plate probe for the build menu's CostLine card (board 72ed0ceb) on
## the real main.tscn: a Floor rectangle held mid-drag, so the line shows its
## cost over the 3D apron. It runs at 1920x1080 with the UI scale at 1.0 and at
## 1280x720 with the UI scale at 1.25 (Window.content_scale_factor). At each it
## proves the CostLine is visible, lies inside the window and clear of every
## other drawn HUD rectangle (HudRects.collect), and that the world point under
## the pointer projects inside the frame, then saves one plate. A failed check,
## or a plate that does not save, prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; hold the windowed lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://tests/ui/cost_line_plate_probe.gd

const OUT_REL := "res://../tools/blender/out/cost-line"
const FOCUS_CELL := Vector2i(20, 10)
const DRAG_SIZE := Vector2i(7, 3)
const MARGIN_PX := 8.0
## Window size, UI scale and plate name of each run.
const CONFIGS := [
	[Vector2i(1920, 1080), 1.0, "cost_card_1920_scale1p0"],
	[Vector2i(1280, 720), 1.25, "cost_card_1280_scale1p25"],
]
## A drawn rectangle this large is the frame or a backdrop, not a HUD panel.
const BACKDROP_SHARE := 0.5

var _failed := false
var _main: Node3D
var _mode: BuildMode
var _menu: BuildMenu
var _cam: Camera3D


func _initialize() -> void:
	var probe_seed := randi()
	seed(probe_seed)
	print("PROBE seed=", probe_seed)
	_run.call_deferred()


func _run() -> void:
	_main = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_mode = _main.get_node("BuildMode") as BuildMode
	_menu = _main.get_node("BuildMenu") as BuildMenu
	var hud := _main.get_node("PassengerHud") as PassengerHud
	await _frames(3)
	hud.press_starter_terminal()
	var rig := _main.get_node("TycoonCamera") as TycoonCamera
	_cam = rig.get_node("Camera3D") as Camera3D
	var drag := _unfloored_rect()
	rig.position = _mode.grid.cell_to_world(drag.position)
	rig.distance = 42.0
	rig.zoom(1.0)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_mode.grid.cell_to_world(drag.position))
	_mode.move_area(_mode.grid.cell_to_world(drag.end - Vector2i.ONE))
	for config: Array in CONFIGS:
		DisplayServer.window_set_size(config[0])
		root.content_scale_factor = config[1]
		await _frames(20)
		if root.size != config[0]:
			_invalid("the window is %s, not %s" % [root.size, config[0]])
		print(
			(
				"PROBE scale=%s window=%s layout=%s"
				% [config[1], root.size, root.get_visible_rect().size]
			)
		)
		await _check_and_plate(drag, config[2])
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _check_and_plate(drag: Rect2i, plate: String) -> void:
	var subject := _mode.grid.cell_to_world(drag.end - Vector2i.ONE)
	var screen := _cam.unproject_position(subject)
	root.warp_mouse(screen)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	await _frames(8)
	var cost := _menu.preview_label()
	var rect := cost.get_global_rect()
	var view := root.get_visible_rect()
	print(
		(
			"PROBE %s cost='%s' visible=%s rect=%s view=%s"
			% [plate, cost.text, cost.visible, rect, view]
		)
	)
	print("PROBE %s subject screen=%s" % [plate, screen])
	if not cost.visible or cost.text == "":
		_invalid("%s: the CostLine is not showing a cost" % plate)
	if not view.grow(-MARGIN_PX).encloses(rect):
		_invalid("%s: the CostLine is not inside the window" % plate)
	if not view.grow(-MARGIN_PX).has_point(screen):
		_invalid("%s: the world point under the pointer is outside the frame" % plate)
	var counted := 0
	for other in HudRects.collect(_menu, 1.0):
		if other.is_equal_approx(rect) or other.get_area() >= view.get_area() * BACKDROP_SHARE:
			continue
		counted += 1
		if other.intersects(rect):
			_invalid("%s: the CostLine overlaps the HUD rectangle %s" % [plate, other])
	print("PROBE %s other HUD rects checked=%d" % [plate, counted])
	if counted == 0:
		_invalid("%s: no HUD rectangle was collected, so the overlap check proves nothing" % plate)
	await RenderingServer.frame_post_draw
	var out_dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join(plate + ".png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	if err != OK:
		_invalid("%s: the plate did not save (error %d)" % [plate, err])


func _invalid(why: String) -> void:
	_failed = true
	print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## The rectangle of DRAG_SIZE nearest FOCUS_CELL whose floor still costs money.
func _unfloored_rect() -> Rect2i:
	var best := Rect2i(FOCUS_CELL, DRAG_SIZE)
	var best_d := INF
	for y in _mode.grid.size.y:
		for x in _mode.grid.size.x:
			var area := Rect2i(Vector2i(x, y), DRAG_SIZE)
			if (
				not _mode.grid.in_bounds(area.end - Vector2i.ONE)
				or _menu._price_floor_rect(area) <= 0
			):
				continue
			var d := Vector2(area.position - FOCUS_CELL).length()
			if d < best_d:
				best = area
				best_d = d
	print("PROBE drag rect %s distance %s" % [best, best_d])
	if best_d == INF:
		_invalid("no rectangle of the grid has a floor cost")
	return best
