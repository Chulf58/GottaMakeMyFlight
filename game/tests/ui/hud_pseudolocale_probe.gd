extends SceneTree
## Plates the HUD with pseudolocalization on (PseudoLocale, expansion 0.4), to see
## clipping in the top row, the money slot, the speed buttons, the left column,
## the game menu and the intro (board T3). Windowed, on the real main.tscn. Each
## plate proves its subject first: the named nodes lie inside the window and the
## first label is bracketed, otherwise PROBE_INVALID and exit 1. Every Button and
## Label inside a plate's crop is measured: its text width against its own width.
##
## A label set through tr() is translated again when it draws, so the profile
## brackets it twice; the measured text here is the stored text, so a plate shows
## about twice the 40% expansion a real translation would.
##
## Run (windowed takes the one project-wide slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <worktree>/game \
##     -s res://tests/ui/hud_pseudolocale_probe.gd [-- --single | --english]

const OUT_DIR := "C:/Users/chulf/Gotta-make-my-flight/tools/blender/out/locale/t3"
const WINDOW := Vector2i(1920, 1080)
const MARGIN := 4.0

var _failed := false
var _clipped: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world_seed := randi()
	print("PROBE world_seed=%d display=%s" % [world_seed, DisplayServer.get_name()])
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(WINDOW)
	root.content_scale_factor = 1.0
	await _frames(5)
	var english := OS.get_cmdline_user_args().has("--english")
	if not english:
		PseudoLocale.enable(0.4)
	# A text already through tr() is translated again when its Label draws, so the profile
	# brackets it twice. --single stops that second pass: each text is expanded once, as a
	# real translation would be, and a string set without tr() shows no bracket at all.
	if OS.get_cmdline_user_args().has("--single"):
		root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	clock.seed_rng(world_seed)
	var hud := main.find_children("*", "PassengerHud", true, false)[0] as PassengerHud
	hud.alert_settings_path = "user://hud_probe_alerts.cfg"
	hud.departures_settings_path = "user://hud_probe_departures.cfg"
	hud.unlock_guide().mode = UnlockGuide.Mode.PROFILE
	root.add_child(main)
	clock.set_paused(true)
	await _frames(8)
	hud.dismiss_intro()
	await _frames(5)
	var single := OS.get_cmdline_user_args().has("--single")
	var tag := "english_" if english else ("single_" if single else "")
	_prove_subjects(main, hud)
	await _plate(tag + "top_row", Rect2i(0, 0, 1920, 210))
	await _left_column(main, tag)
	await _game_menu(main, tag)
	await _intro(tag)
	PseudoLocale.disable()
	print("PROBE clipped labels: %d" % _clipped.size())
	for line in _clipped:
		print("  CLIPPED ", line)
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _prove_subjects(main: Node, hud: PassengerHud) -> void:
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var money := main.find_child("MoneySlot", true, false) as Control
	var time := hud.find_child("Clock", true, false) as Label
	var speeds: Array[Button] = []
	for button in hud.find_children("*", "Button", true, false):
		var tip := (button as Button).tooltip_text
		if (button as Button).toggle_mode and (tip.contains("Space") or tip.contains("Shift+")):
			speeds.append(button)
	_expect(money != null and view.encloses(money.get_global_rect()), "money slot is not in frame")
	_expect(time != null and view.encloses(time.get_global_rect()), "the clock is not in frame")
	_expect(speeds.size() == 4, "speed buttons found: %d" % speeds.size())
	for button in speeds:
		_expect(view.encloses(button.get_global_rect()), "a speed button is outside the window")
	print(
		(
			"PROBE subjects money=%s clock=%s speeds=%s"
			% [money.get_global_rect(), time.get_global_rect(), speeds.map(_rect_of)]
		)
	)
	print("PROBE first labels time='%s' money='%s'" % [time.text, _label_in(money).text])
	if not OS.get_cmdline_user_args().has("--english"):
		_expect(time.text.begins_with("["), "the clock is not bracketed: '%s'" % time.text)


func _rect_of(control: Control) -> Rect2:
	return control.get_global_rect()


func _label_in(parent: Node) -> Label:
	return parent.find_children("*", "Label", true, false)[0] as Label


func _left_column(main: Node, tag: String) -> void:
	var mood := main.find_child("MoodToggle", true, false) as Button
	_expect(mood != null, "no mood toggle")
	mood.button_pressed = true
	await _frames(6)
	var legend := main.find_child("MoodLegendCard", true, false) as Control
	_expect(legend != null and legend.is_visible_in_tree(), "the legend card is not shown")
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for node_name in ["MoodToggle", "HintsToggle", "HintsReset", "MoodLegendCard"]:
		var node := main.find_child(node_name, true, false) as Control
		_expect(node != null and view.encloses(node.get_global_rect()), node_name + " not in frame")
		print("PROBE left column %s=%s" % [node_name, node.get_global_rect() if node else "none"])
	await _plate(tag + "left_column", Rect2i(0, 0, 760, 420))
	mood.button_pressed = false


func _game_menu(main: Node, tag: String) -> void:
	var menu := main.get_node("GameMenu") as GameMenu
	_expect(menu.open(), "the game menu did not open")
	await _frames(6)
	var panel := menu.find_child("Panel", true, false) as Control
	_expect(panel != null, "no menu panel")
	_expect(menu.resume_button() != null, "no resume button")
	await _plate(tag + "game_menu", Rect2i(panel.get_global_rect().grow(24.0)))
	menu.close()
	await _frames(3)


func _intro(tag: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	var dialog := IntroDialogue.new()
	layer.add_child(dialog)
	await _frames(8)
	var box := dialog.find_child("Body", true, false) as Control
	_expect(box != null and box.is_visible_in_tree(), "the intro body is not shown")
	print("PROBE intro body='%s' rect=%s" % [dialog.body_text().left(60), box.get_global_rect()])
	await _plate(tag + "intro", Rect2i(0, 420, 1920, 660), dialog)
	layer.queue_free()
	await _frames(3)


## Measures every visible Button and Label inside `crop`, then saves the plate.
func _plate(plate: String, crop: Rect2i, scope: Node = null) -> void:
	await _frames(3)
	var rect := Rect2(crop)
	var start: Node = scope if scope != null else root
	for control in start.find_children("*", "Control", true, false):
		if not (control is Button or control is Label) or not control.is_visible_in_tree():
			continue
		if not rect.intersects(control.get_global_rect()):
			continue
		_measure(plate, control)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUT_DIR.path_join(plate + ".png")
	var err := (
		image.get_region(Rect2i(crop).intersection(Rect2i(Vector2i.ZERO, root.size))).save_png(path)
	)
	print("PLATE saved %s err=%d" % [path, err])
	_expect(err == OK, "plate %s was not saved" % plate)


func _measure(plate: String, control: Control) -> void:
	var text: String = control.text
	if text == "":
		return
	# A text already through tr() is bracketed once; atr() would bracket it again, which a
	# real translation never gets, so measure the stored text as it is.
	var shown := text if text.begins_with("[") else control.atr(text)
	var font := control.get_theme_font("font")
	var size := control.get_theme_font_size("font_size")
	var pad := 0.0
	if control is Button:
		var box := control.get_theme_stylebox("normal")
		pad = box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
	var wrap := control is Label and (control as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
	var width := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + pad
	var clipped := not wrap and width > control.size.x + 0.5
	if clipped:
		_clipped.append(
			"%s %s '%s' %.0f px in %.0f px" % [plate, control.name, shown, width, control.size.x]
		)
	print(
		(
			"  LABEL %s %s '%s' w=%.0f box=%.0f clipped=%s"
			% [plate, control.name, shown, width, control.size.x, clipped]
		)
	)


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_failed = true
		print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
