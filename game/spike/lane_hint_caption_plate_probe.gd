extends SceneTree
## Windowed plates for the lane-hint caption placement: the real main scene with
## the starter terminal built and one security arch with no lane parts added in a
## corner of the grid, so it carries the "Needs a tray table" caption. The sign
## is then put (a) where its home caption would sit under the Offers button and
## (b) near the top edge of the screen, and each time the caption must end up
## inside the frame by MissMarkers.VIEW_MARGIN_PX, clear (by CAPTION_MARGIN_PX) of
## every visible HUD control that draws something, whether or not it takes the
## mouse, and off every miss-marker icon on screen (its own included).
## Boots main with a new random sim seed (printed). Before it saves a plate it
## proves its subjects: the hint sign exists and is visible, its icon projects
## inside the frame, the Offers button is visible, and the unmoved caption
## really is under the button (a) or outside the frame (b). It prints the
## rectangles it compared. Otherwise it prints PROBE_INVALID and exits 1.
## The overlap check proves itself on synthetic rectangles first (a caption on an
## icon, on a control, a hair inside the margin, and one well clear). The user
## argument overlap_control (after --) then plants an icon on each caption, so
## the run must fail with exit 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --resolution 1536x864 \
##     --path game -s res://spike/lane_hint_caption_plate_probe.gd [-- overlap_control]
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


## True for a control that puts something on the screen: a panel, a button, a
## colour fill, a label with text, a picture, or a control with a panel style.
## The miss-marker rule's predicate, written out again here (not through
## MissMarkers) so a mistake in the game's copy cannot hide in this check.
func _draws_something(control: Control) -> bool:
	if control is Panel or control is PanelContainer or control is BaseButton:
		return true
	if control is ColorRect:
		return true
	if control is Label:
		return not (control as Label).text.is_empty()
	if control is RichTextLabel:
		return not (control as RichTextLabel).text.is_empty()
	if control is TextureRect:
		return (control as TextureRect).texture != null
	return control.has_theme_stylebox_override("panel")


## Every visible control under a visible canvas layer that draws something, in
## screen pixels, whether or not it takes the mouse. A panel or button is
## taken whole, not walked into; a layout container that draws nothing is walked
## through. Found by walking the scene the way a player meets it.
func _drawn_controls(
	node: Node, to_screen: float, found: Array[Rect2], names: Array[String]
) -> void:
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control:
			var control := child as Control
			var size := control.size * to_screen
			if _draws_something(control) and size.x * size.y > 0.0:
				found.append(Rect2(control.get_global_rect().position * to_screen, size))
				names.append(str(control.name))
				if control is Panel or control is PanelContainer or control is BaseButton:
					continue
		_drawn_controls(child, to_screen, found, names)


## The icon of every visible miss-marker sign (queue full, closed, lane hint),
## in screen pixels: the sign point is the icon's bottom centre.
func _marker_icons(markers: MissMarkers, cam: Camera3D, to_screen: float) -> Array[Rect2]:
	var icons: Array[Rect2] = []
	for child in markers.get_children():
		var sign := child as Sprite3D
		if sign == null or not sign.visible or sign.get_node_or_null("Caption") == null:
			continue
		if cam.is_position_behind(sign.global_position):
			continue
		var point := cam.unproject_position(sign.global_position) * to_screen
		var side := MissMarkers.SIGN_PX
		icons.append(Rect2(point.x - side / 2.0, point.y - side, side, side))
	return icons


## What `rect` collides with, as readable lines: a HUD control within
## CAPTION_MARGIN_PX, or any icon at all (the miss-marker rule's two clearances).
func _collisions(
	rect: Rect2, controls: Array[Rect2], names: Array[String], icons: Array[Rect2]
) -> Array[String]:
	var found: Array[String] = []
	var padded := rect.grow(MissMarkers.CAPTION_MARGIN_PX)
	for i in controls.size():
		if padded.intersects(controls[i]):
			found.append("control %s %s" % [names[i], controls[i]])
	for icon in icons:
		if rect.intersects(icon):
			found.append("icon %s" % icon)
	return found


## Proves _collisions can fail before any real caption is judged by it.
func _self_test_collisions() -> bool:
	var rect := Rect2(100.0, 100.0, 120.0, 30.0)
	var none: Array[Rect2] = []
	var no_names: Array[String] = []
	var on_icon: Array[Rect2] = [Rect2(150.0, 110.0, 56.0, 56.0)]
	var named: Array[String] = ["ctl"]
	var inside_margin: Array[Rect2] = [Rect2(rect.end.x + 3.0, 100.0, 40.0, 30.0)]
	var clear: Array[Rect2] = [Rect2(rect.end.x + 40.0, 100.0, 40.0, 30.0)]
	var seen := [
		_collisions(rect, none, no_names, on_icon).size(),
		_collisions(rect, on_icon, named, none).size(),
		_collisions(rect, inside_margin, named, none).size(),
		_collisions(rect, clear, named, clear).size(),
	]
	print("PROBE overlap self-test hits (icon, control, margin, clear)=", seen)
	return seen == [1, 1, 1, 0]


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
	var control_run := OS.get_cmdline_user_args().has("overlap_control")
	if not _self_test_collisions():
		_invalid("the overlap check missed a planted overlap or flagged a clear one")
		quit(1)
		return
	var main: Node3D = load(MAIN_SCENE).instantiate()
	# The probe builds its own terminal below, so the scene's starter shell is off.
	(main.get_node("BuildMode") as BuildMode).starter_shell = false
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
	print("PROBE terminal_offset=", ReferenceTerminal.offset_on(grid), " grid=", grid.size)
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
		_drawn_controls(main, to_screen, controls, names)
		var icons := _marker_icons(markers, cam, to_screen)
		if control_run:
			icons.append(rect.grow(-2.0))
		var button := Rect2(offers.get_global_rect().position * to_screen, offers.size * to_screen)
		print("CASE ", case["name"], " point=", point, " frame=", frame)
		print("CASE home=", home, " moved=", rect, " visible=", caption.visible)
		print("CASE hud_controls=", names.size(), " ", names, " offers=", button)
		print("CASE marker_icons=", icons.size(), " ", icons)
		if icons.is_empty():
			_invalid("%s: no miss-marker icon was found, not even the hint's own" % case["name"])
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
		var hits := _collisions(rect, controls, names, icons)
		print("CASE collisions=", hits.size(), " ", hits)
		for hit in hits:
			_invalid("%s: the caption %s collides with %s" % [case["name"], rect, hit])
		var path := out_dir.path_join(str(case["name"]) + ".png")
		img.save_png(path)
		print("PLATE ", path, " size=", img.get_size())
	print("PROBE done failed=", _failed)
	quit(1 if _failed else 0)
