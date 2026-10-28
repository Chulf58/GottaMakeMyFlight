extends SceneTree
## Plates the intro dialogue in the real game at 1920x1080. It boots main.tscn
## through change_scene_to_packed, as a normal launch does (current_scene is set
## before _ready), so PassengerHud's own gate opens the intro. Then it checks the
## clock stays paused at tick 0, the dialogue parts are on screen and nothing is
## layered above them, saves the open plate and a close crop, presses Space, and
## checks the dialogue closed and the clock runs at 1x before saving the after plate.
##
## Windowed, from the repo root (hold the one windowed slot):
##   Godot_v4.7.2-stable_win64_console.exe --path game --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy -s res://spike/intro_dialogue_plate_probe.gd
## Plates go to tools/blender/out/intro-dialogue/. PROBE_INVALID and exit 1 on a
## failed check.

const MAIN := "res://main/main.tscn"
const OUT_DIR := "res://../tools/blender/out/intro-dialogue"
const SCREEN := Vector2i(1920, 1080)
const MARGIN := 16.0
const OPEN_FRAMES := 40
const AFTER_FRAMES := 40

var _stage := 0
var _frames := 0
var _hud: PassengerHud
var _clock: SimClock
var _tick_at_open := -1


func _initialize() -> void:
	IntroDialogue.shown_this_session = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	change_scene_to_packed(load(MAIN))


func _process(_delta: float) -> bool:
	_frames += 1
	match _stage:
		0:
			return _wait_for_scene()
		1:
			return _check_open()
		2:
			return _check_after()
	return true


func _wait_for_scene() -> bool:
	if current_scene == null:
		if _frames > 60:
			return _invalid("main.tscn never became the current scene")
		return false
	_hud = current_scene.get_node("PassengerHud") as PassengerHud
	_clock = current_scene.get_node("SimClock") as SimClock
	print("PROBE world_seed=%d" % _clock.rng.seed)
	print(
		"PROBE intro_open=%s paused=%s tick=%d" % [_hud.intro() != null, _clock.paused, _clock.tick]
	)
	if not (_hud.intro() != null):
		return _invalid("a normal boot did not open the intro")
	_tick_at_open = _clock.tick
	_stage = 1
	_frames = 0
	return false


func _check_open() -> bool:
	if _frames < OPEN_FRAMES:
		return false
	var rects := _hud.intro().part_rects()
	var problem := _clock_problem()
	if problem == "":
		problem = _layout_problem(rects)
	if problem != "":
		return _invalid(problem)
	var image := root.get_texture().get_image()
	var box: Rect2 = rects["box"]
	var crop := box.merge(rects["portrait"]).merge(rects["nameplate"]).grow(12.0)
	# The part rects are in layout space (the content scale); the image is in
	# window pixels.
	var factor := Vector2(image.get_size()) / root.get_visible_rect().size
	var crop_px := Rect2(crop.position * factor, crop.size * factor)
	crop_px = crop_px.intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
	print("PROBE crop layout=%s factor=%s pixels=%s" % [crop, factor, crop_px])
	if not _save(image, "intro_open_1080p.png"):
		return _invalid("the open plate did not save")
	if not _save(image.get_region(Rect2i(crop_px)), "intro_open_crop.png"):
		return _invalid("the crop plate did not save")
	_press(KEY_SPACE, true)
	_press(KEY_SPACE, false)
	_stage = 2
	_frames = 0
	return false


func _clock_problem() -> String:
	# The window is checked by its pixels: the content scale (project.godot)
	# gives the HUD a smaller layout size than the window.
	var size := root.size
	print(
		(
			"PROBE window=%s layout=%s paused=%s tick=%d (at open %d)"
			% [size, root.get_visible_rect().size, _clock.paused, _clock.tick, _tick_at_open]
		)
	)
	if size != SCREEN:
		return "the window is %s, not %s" % [size, SCREEN]
	if not _clock.paused or _clock.tick != _tick_at_open or _tick_at_open != 0:
		return "the clock ran while the intro was open"
	return ""


## In frame with a margin, clear of the build tray, and not under another layer.
func _layout_problem(rects: Dictionary) -> String:
	var layout_size := root.get_visible_rect().size
	var screen := Rect2(Vector2.ONE * MARGIN, layout_size - Vector2.ONE * 2.0 * MARGIN)
	for part in rects:
		var rect: Rect2 = rects[part]
		print("PROBE in_frame %s rect=%s inside=%s" % [part, rect, screen.encloses(rect)])
		if not rect.has_area() or not screen.encloses(rect):
			return "%s is not inside the screen with a %d px margin" % [part, MARGIN]
	# A new game starts with no tool, so the tray is closed at boot; the box must
	# still clear the space the tray and its status line take when one opens.
	var menu := current_scene.get_node("BuildMenu") as BuildMenu
	var mode := current_scene.get_node("BuildMode") as BuildMode
	print("PROBE start_tool=%d tray_open=%s" % [mode.tool, menu.is_tray_open()])
	if mode.tool != BuildMode.Tool.NONE:
		return "BuildMode did not start with no tool (tool %d)" % mode.tool
	if menu.is_tray_open():
		return "the build tray is open at launch"
	var tray_top := minf(
		menu.tray().get_global_rect().position.y, menu.status_label().get_global_rect().position.y
	)
	var box: Rect2 = rects["box"]
	print(
		(
			"PROBE tray_open=%s tray_top=%.0f box_bottom=%.0f"
			% [menu.is_tray_open(), tray_top, box.end.y]
		)
	)
	if box.end.y > tray_top:
		return "the box covers the build tray"
	# Occlusion: the dialogue is visible and its own CanvasLayer is above every
	# other layer in the scene.
	var intro := _hud.intro()
	var own := intro.get_parent() as CanvasLayer
	var top_other := -1000
	for node in root.find_children("*", "CanvasLayer", true, false):
		if node != own:
			top_other = maxi(top_other, (node as CanvasLayer).layer)
	var own_layer := own.layer if own != null else -1000
	print(
		(
			"PROBE intro_visible=%s intro_layer=%d top_other_layer=%d"
			% [intro.is_visible_in_tree(), own_layer, top_other]
		)
	)
	if not intro.is_visible_in_tree() or own == null or top_other >= own_layer:
		return "the intro is hidden or another CanvasLayer is drawn over it"
	return ""


func _check_after() -> bool:
	if _frames < AFTER_FRAMES:
		return false
	print(
		(
			"PROBE after intro_open=%s paused=%s speed=%d tick=%d"
			% [_hud.intro() != null, _clock.paused, _clock.speed, _clock.tick]
		)
	)
	if (_hud.intro() != null) or _clock.paused or _clock.speed != 1 or _clock.tick <= _tick_at_open:
		return _invalid("Space did not close the intro and start the clock at 1x")
	if root.find_child("IntroLayer", true, false) != null:
		return _invalid("the intro layer is still in the tree")
	if not _save(root.get_texture().get_image(), "intro_after_1080p.png"):
		return _invalid("the after plate did not save")
	print("PROBE done")
	quit(0)
	return true


func _press(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _save(image: Image, file: String) -> bool:
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(file))
	var err := image.save_png(path)
	print("PROBE plate %s err=%d size=%s" % [path, err, image.get_size()])
	return err == OK


func _invalid(why: String) -> bool:
	print("PROBE_INVALID %s" % why)
	quit(1)
	return true
