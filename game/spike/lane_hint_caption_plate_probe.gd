extends SceneTree
## Windowed plates for the lane-hint caption placement: the real main scene with
## the starter terminal built and one security arch with no lane parts added in a
## corner of the grid, so it carries the "Needs a tray table" caption. The sign
## is then put (a) where its home caption would sit under the Offers button and
## (b) near the top edge of the screen, and each time the caption must end up
## inside the frame by MissMarkers.VIEW_MARGIN_PX and clear of every visible HUD
## control that takes the mouse.
## Boots main with a new random sim seed (printed). Before it saves a plate it
## proves its subjects: the hint sign exists and is visible, its icon projects
## inside the frame, the Offers button is visible, and the unmoved caption
## really is under the button (a) or outside the frame (b). It prints the
## rectangles it compared. Otherwise it prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --resolution 1536x864 \
##     --path game -s res://spike/lane_hint_caption_plate_probe.gd
##
## The plates go to tools/blender/out/lane-hint-caption/.

const PlateSight := preload("res://spike/plate_sight.gd")
const OUT_REL := "res://../tools/blender/out/lane-hint-caption"
const MAIN_SCENE := "res://main/main.tscn"

const SIGN_ICON_SLACK := 4.0

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


## Every visible control under a canvas layer that takes the mouse, in screen
## pixels, found the way a player would meet them (not through MissMarkers).
func _hud_controls(node: Node, to_screen: float, found: Array[Rect2], names: Array[String]) -> void:
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is CanvasLayer and not (child as CanvasLayer).visible:
			continue
		if child is Control and (child as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			var control := child as Control
			found.append(
				Rect2(control.get_global_rect().position * to_screen, control.size * to_screen)
			)
			names.append(str(control.name))
			continue
		_hud_controls(child, to_screen, found, names)


func _find_offers(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text.begins_with("Offers"):
			return child as Button
		var inner := _find_offers(child)
		if inner != null:
			return inner
	return null


## Moves the hint sign to a screen point (layout pixels) and lays out again.
func _put_sign(markers: MissMarkers, arch: int, cam: Camera3D, layout_point: Vector2) -> void:
	var sign := markers.hint_sign_for(arch)
	sign.global_position = cam.project_position(layout_point, 60.0)
	markers.set("_dirty", true)


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node3D = load(MAIN_SCENE).instantiate()
	var clock: SimClock = main.get_node("SimClock")
	var seed := randi()
	clock.seed_rng(seed)
	print("PROBE sim_seed=", seed, " window=", root.size, " ui_scale=", root.content_scale_factor)
	root.add_child(main)
	clock.set_paused(true)
	await _frames(5)
	(main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var build_mode := main.get_node("BuildMode") as BuildMode
	build_mode.set_tool(BuildMode.Tool.NONE)
	await _frames(20)
	var sim: PassengerSim = main.get_node("PassengerSim")
	var grid := build_mode.grid
	var corner := grid.size - Vector2i(10, 10)
	for y in 6:
		for x in 6:
			grid.apply(BuildEdit.paint_floor(corner + Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var placed := grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, corner + Vector2i(2, 2), 0))
	print("PROBE arch placed ok=", placed.ok, " at ", corner + Vector2i(2, 2))
	if not placed.ok:
		_invalid("the arch was refused: %s" % placed.reason_text())
		quit(1)
		return
	await _frames(20)
	var incomplete := MissSignals.incomplete_arches(sim)
	print("PROBE incomplete_arches=", incomplete)
	if incomplete.is_empty():
		_invalid("no arch is incomplete, so there is no lane-hint caption")
		quit(1)
		return
	var arch: int = incomplete[0]
	var markers: MissMarkers = (main.get_node("PassengerViews") as PassengerViews).get_node(
		"MissMarkers"
	)
	var cam: Camera3D = (main.get_node("TycoonCamera") as Node).get_node("Camera3D")
	var offers := _find_offers(main)
	if offers == null or not offers.is_visible_in_tree():
		_invalid("the Offers button is not visible")
		quit(1)
		return
	var hint := markers.hint_sign_for(arch)
	var caption := hint.get_node("Caption") as Label3D
	print("PROBE hint text=", caption.text)
	var layout := root.get_visible_rect().size
	var cases := [
		{
			"name": "01_under_offers_button",
			"point": offers.get_global_rect().get_center() + Vector2(0.0, 66.0)
		},
		{"name": "02_top_edge", "point": Vector2(layout.x * 0.5, 40.0)},
	]
	for case: Dictionary in cases:
		_put_sign(markers, arch, cam, case["point"])
		await _frames(3)
		var img := await PlateSight.grab(self)
		var to_screen := float(img.get_height()) / layout.y
		var point := cam.unproject_position(hint.global_position) * to_screen
		var frame := Rect2(Vector2.ZERO, Vector2(img.get_size()))
		var inner := frame.grow(-MissMarkers.VIEW_MARGIN_PX)
		var lift := caption.offset.y - MissMarkers.SIGN_PX - MissMarkers.CAPTION_GAP_PX
		var home := MissMarkers.caption_rect(point, caption.text)
		var rect := MissMarkers.caption_rect(point, caption.text, lift, caption.offset.x)
		var controls: Array[Rect2] = []
		var names: Array[String] = []
		_hud_controls(main, to_screen, controls, names)
		var button := Rect2(offers.get_global_rect().position * to_screen, offers.size * to_screen)
		print("CASE ", case["name"], " point=", point, " frame=", frame)
		print("CASE home=", home, " moved=", rect, " visible=", caption.visible)
		print("CASE hud_controls=", names.size(), " offers=", button)
		if not frame.grow(-SIGN_ICON_SLACK).has_point(point):
			_invalid("%s: the icon point %s is not inside the frame" % [case["name"], point])
		if not hint.visible or not caption.visible:
			_invalid("%s: the hint sign or its caption is hidden" % case["name"])
		if case["name"] == "01_under_offers_button":
			if not home.intersects(button):
				_invalid(
					(
						"%s: the unmoved caption is not under the button, nothing engaged"
						% case["name"]
					)
				)
		elif inner.encloses(home):
			_invalid("%s: the unmoved caption is inside the frame, nothing engaged" % case["name"])
		if not inner.encloses(rect):
			_invalid("%s: the caption %s is not inside the frame margin" % [case["name"], rect])
		for i in controls.size():
			if rect.intersects(controls[i]):
				_invalid(
					(
						"%s: the caption %s is over the control %s %s"
						% [case["name"], rect, names[i], controls[i]]
					)
				)
		var path := out_dir.path_join(str(case["name"]) + ".png")
		img.save_png(path)
		print("PLATE ", path, " size=", img.get_size())
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)
