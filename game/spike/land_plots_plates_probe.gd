extends SceneTree
## Windowed plate probe for the land plots (board ee9914e6): the owned-land
## outline in build mode, the Buy land tool's dim fill on buyable plots, the
## hovered plot's price, a plot bought with one click, and the refusals (a plot
## out of reach, a plot the wallet cannot pay, floor painted on land not owned).
## Boots main.tscn with a new random world seed (printed), then saves:
##   p1_outline_build_mode  the site with the Floor tool picked: the teal outline
##                          round a new game's land (columns 0-1, rows 3-5);
##   p2_buy_tool_fills      the Buy land tool picked: a dim fill on each buyable plot;
##   p3_hover_price         the pointer on plot (2, 4): green tint, price over it;
##   p4_bought              after one click on (2, 4): the outline runs round it;
##   p5_refused_far         the pointer on (3, 2), touching no owned plot: red tint;
##   p6_refused_broke       money spent down, the pointer on (2, 3): red, price shown;
##   p7_floor_refused       the Floor tool on unowned cell (80, 110): red ghost, reason.
## Every plate first projects its subject points into the viewport (with a margin, in
## front of the camera, off the HUD bar, tray and hint card) and casts a physics ray
## from the camera to each; a point out of frame, under the HUD or behind a collider
## prints PROBE_INVALID and the probe exits 1. It also checks the state each plate
## shows (tool, visibility, status text) and prints it.
##
## Run (one windowed Godot run project-wide, holding tools/blender/out/.windowed.lock):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path game \
##     -s res://spike/land_plots_plates_probe.gd
##
## Plates go to tools/blender/out/land-plots/.

const OUT_REL := "res://../tools/blender/out/land-plots"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 16.0
const SETTLE_FRAMES := 30
## Overview zooms tried nearest first until the plate's subject fits.
const FIT_DISTANCES: Array[float] = [100.0, 120.0, 140.0, 165.0, 190.0, 220.0, 260.0, 300.0]
const CLOSE_DISTANCE := 70.0
const BUY := Vector2i(2, 4)
const FAR := Vector2i(3, 2)
const DEAR := Vector2i(2, 3)
const UNOWNED_CELL := Vector2i(80, 110)

var _out_dir := ""
var _failed := false
var _sheet: Array[Image] = []
var _main: Node3D
var _cam: Camera3D
var _rig: Node3D
var _build: BuildMode
var _menu: BuildMenu
var _outline: BuildableOutline
var _staff: StaffPanel
var _land: LandPlots


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
	(_main.get_node("SimClock") as SimClock).seed_rng(randi())
	root.add_child(_main)
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_rig = _main.get_node("TycoonCamera")
	_build = _main.get_node("BuildMode")
	_menu = _main.get_node("BuildMenu")
	_outline = _main.get_node("BuildableOutline")
	_staff = _main.get_node("StaffPanel")
	_land = _build.land_tool.land
	await _frames(20)
	print("OWNED %s BUYABLE %s" % [_land.owned_plots(), _land.buyable_plots()])

	_build.set_tool(BuildMode.Tool.FLOOR)
	_point_at(Vector2(1, 1))
	_expect(_outline.is_visible_in_tree(), "p1: outline hidden in build mode")
	var corners := Array(_outline.outline_points())
	var p1_focus := _centre(corners)
	await _plate("p1_outline_build_mode", p1_focus, await _fit(p1_focus, corners), corners)

	_build.set_tool(BuildMode.Tool.BUY_LAND)
	_expect(_build.land_tool.is_visible_in_tree(), "p2: buy tool fills hidden")
	var middles: Array = []
	for plot in _land.buyable_plots():
		middles.append(_middle(plot))
	var p2_focus := _centre(middles)
	await _plate("p2_buy_tool_fills", p2_focus, await _fit(p2_focus, middles), middles)

	var buy_focus := _middle(BUY)
	_rig.position = buy_focus
	await _point_to(buy_focus, CLOSE_DISTANCE)
	var label := _build.land_tool.price_label()
	_expect(label.visible, "p3: no price over the hovered plot")
	_expect(_build.status_text().begins_with("Click to buy"), "p3: status " + _build.status_text())
	print(
		"P3 label=%s status=%s cost=%s" % [label.text, _build.status_text(), _menu.preview_text()]
	)
	await _plate("p3_hover_price", buy_focus, CLOSE_DISTANCE, [buy_focus, label.global_position])

	var wallet := _build.wallet()
	var before := wallet.balance
	var bought := _build.apply_at(buy_focus)
	_expect(bought != null and bought.ok, "p4: the click did not buy the plot")
	print(
		(
			"P4 bought=%s paid=%d corners=%d"
			% [_land.is_owned(BUY), before - wallet.balance, _outline.outline_points().size()]
		)
	)
	_expect(_outline.outline_points().size() == 8, "p4: outline does not run round the bought plot")
	await _plate("p4_bought", buy_focus, CLOSE_DISTANCE, _plot_corners(BUY))

	var far_focus := _middle(FAR)
	await _point_to(far_focus, CLOSE_DISTANCE)
	_expect(
		_build.status_text() == BuildResult.REASON_TEXT[BuildResult.Reason.LAND_NOT_TOUCHING],
		"p5: status " + _build.status_text()
	)
	print(
		(
			"P5 status=%s label_visible=%s"
			% [_build.status_text(), _build.land_tool.price_label().visible]
		)
	)
	await _plate("p5_refused_far", far_focus, CLOSE_DISTANCE, [far_focus])

	wallet.spend(wallet.balance - 100, Wallet.Category.BUILD)
	var dear_focus := _middle(DEAR)
	await _point_to(dear_focus, CLOSE_DISTANCE)
	_expect(
		_build.status_text() == BuildResult.REASON_TEXT[BuildResult.Reason.CANT_AFFORD],
		"p6: status " + _build.status_text()
	)
	var refused := _build.apply_at(dear_focus)
	_expect(
		refused != null and not refused.ok and not _land.is_owned(DEAR), "p6: a buy went through"
	)
	print(
		(
			"P6 status=%s label=%s cost=%s balance=%d"
			% [
				_build.status_text(),
				_build.land_tool.price_label().text,
				_menu.preview_text(),
				wallet.balance
			]
		)
	)
	await _plate(
		"p6_refused_broke",
		dear_focus,
		CLOSE_DISTANCE,
		[dear_focus, _build.land_tool.price_label().global_position]
	)

	_build.set_tool(BuildMode.Tool.FLOOR)
	var cell_at := _build.grid.cell_to_world(UNOWNED_CELL)
	await _point_to(cell_at, 30.0)
	_expect(
		_build.status_text().contains(BuildResult.REASON_TEXT[BuildResult.Reason.LAND_NOT_OWNED]),
		"p7: status " + _build.status_text()
	)
	print(
		(
			"P7 status=%s ghost_reason=%s"
			% [_build.status_text(), _menu.ghost_reason().is_visible_in_tree()]
		)
	)
	await _plate("p7_floor_refused", cell_at, 30.0, [cell_at])

	_save_contact_sheet()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_invalid(msg)


func _middle(plot: Vector2i) -> Vector3:
	var cells := _land.plot_cells(plot)
	var at := Vector2(cells.position) + Vector2(cells.size) / 2.0
	var o := _build.grid.origin
	return Vector3(o.x + at.x, o.y, o.z + at.y)


func _plot_corners(plot: Vector2i) -> Array:
	var cells := _land.plot_cells(plot)
	var o := _build.grid.origin
	var out := []
	for c in [
		cells.position,
		Vector2i(cells.end.x, cells.position.y),
		cells.end,
		Vector2i(cells.position.x, cells.end.y)
	]:
		# A little inside, so the point is on the plot, not on its neighbour's edge.
		var inward := (Vector2(cells.get_center()) - Vector2(c)).normalized() * 0.5
		out.append(Vector3(o.x + c.x + inward.x, o.y, o.z + c.y + inward.y))
	return out


## The middle of the points' bounding box on the ground.
func _centre(points: Array) -> Vector3:
	var low: Vector3 = points[0]
	var high: Vector3 = points[0]
	for p: Vector3 in points:
		low = low.min(p)
		high = high.max(p)
	return (low + high) / 2.0


## The nearest of FIT_DISTANCES that puts every point in frame and off the HUD,
## or the furthest.
func _fit(focus: Vector3, points: Array) -> float:
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	for distance in FIT_DISTANCES:
		_rig.position = focus
		_rig.target_distance = distance
		_rig.distance = distance
		await _frames(SETTLE_FRAMES)
		var fits := true
		for p: Vector3 in points:
			var s := _cam.unproject_position(p)
			var under := _hud_rects().any(func(r: Rect2) -> bool: return r.has_point(s))
			fits = fits and not _cam.is_position_behind(p) and frame.has_point(s) and not under
		print("FIT focus=%s distance=%.0f fits=%s" % [focus, distance, fits])
		if fits:
			return distance
	return FIT_DISTANCES[-1]


func _point_at(screen: Variant) -> void:
	_build.pointer_override = Vector2(-1, -1) if screen == null else screen


## Frames the camera on `focus` and puts the pointer on it.
func _point_to(focus: Vector3, distance: float) -> void:
	_rig.position = focus
	_rig.target_distance = distance
	_rig.distance = distance
	await _frames(SETTLE_FRAMES)
	_point_at(_cam.unproject_position(focus))
	await _frames(6)


func _hud_rects() -> Array[Rect2]:
	var out: Array[Rect2] = [_menu.bar().get_global_rect()]
	if _menu.is_tray_open():
		out.append(_menu.tray().get_global_rect())
	var card := _staff.hint_card()
	if card.is_visible_in_tree():
		out.append(card.get_global_rect())
	return out


func _plate(label: String, focus: Vector3, distance: float, points: Array) -> void:
	_rig.position = focus
	_rig.target_distance = distance
	_rig.distance = distance
	await _frames(SETTLE_FRAMES)
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var space := _cam.get_world_3d().direct_space_state
	for p: Vector3 in points:
		var s := _cam.unproject_position(p)
		var under_hud := _hud_rects().any(func(r: Rect2) -> bool: return r.has_point(s))
		var query := PhysicsRayQueryParameters3D.create(_cam.global_position, p + Vector3.UP * 0.05)
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
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var path := _out_dir.path_join("%s.png" % label)
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	_sheet.append(img)
	print(
		(
			"PLATE saved %s camera=%s distance=%.1f tool=%d"
			% [path, _cam.global_position, distance, _build.tool]
		)
	)


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
		@warning_ignore("integer_division")
		sheet.blit_rect(small, Rect2i(Vector2i.ZERO, tile), Vector2i(i % cols, i / cols) * tile)
	var path := _out_dir.path_join("contact_sheet.png")
	if sheet.save_png(path) != OK:
		_invalid("could not save " + path)
		return
	print("SHEET saved %s plates=%d" % [path, _sheet.size()])
