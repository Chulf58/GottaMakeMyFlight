extends SceneTree
## Windowed plate probe for the build menu's CostLine card (board 72ed0ceb) on
## the real main.tscn: a Floor rectangle held mid-drag with the pointer over the
## world, so the line shows its cost over the 3D apron. It proves the CostLine is
## visible, lies inside the window and clear of the bar and the money slot, and
## that the world point under the pointer projects inside the frame, then saves
## one full plate and prints the rects. A failed check prints PROBE_INVALID and
## exits 1.
##
## Run (one windowed Godot run project-wide; hold the windowed lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://tests/ui/cost_line_plate_probe.gd

const OUT_REL := "res://../tools/blender/out/cost-line"
const FOCUS_CELL := Vector2i(20, 10)
const DRAG_SIZE := Vector2i(7, 3)
const MARGIN_PX := 8.0

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
	await _frames(20)
	print("PROBE window=%s" % root.size)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_mode.grid.cell_to_world(drag.position))
	_mode.move_area(_mode.grid.cell_to_world(drag.end - Vector2i.ONE))
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
	print("PROBE cost text='%s' visible=%s rect=%s view=%s" % [cost.text, cost.visible, rect, view])
	print("PROBE subject screen=%s" % screen)
	print(
		(
			"PROBE tool=%s area=%s preview='%s'"
			% [_mode.tool, _mode.dragged_area(), _menu.preview_text()]
		)
	)
	if not cost.visible or cost.text == "":
		_invalid("the CostLine is not showing a cost")
	if not view.grow(-MARGIN_PX).encloses(rect):
		_invalid("the CostLine is not inside the window")
	if not view.grow(-MARGIN_PX).has_point(screen):
		_invalid("the world point under the pointer is outside the frame")
	var bar := _menu.bar().get_global_rect()
	var money := (_menu.find_child("MoneySlot", true, false) as Control).get_global_rect()
	print("PROBE bar=%s money=%s" % [bar, money])
	if rect.intersects(bar) or rect.intersects(money):
		_invalid("the CostLine overlaps the bar or the money slot")
	await RenderingServer.frame_post_draw
	var out_dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join("cost_card_1920.png")
	var err := root.get_texture().get_image().save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


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
