extends SceneTree
## Plates every build menu tray and one item hover card with pseudolocalization
## on (PseudoLocale, expansion 0.4), to see clipping. Windowed, on the real
## main.tscn with every tier unlocked. For each tray it prints each card label's
## shown text, its pixel width and its slot width, and which labels are clipped;
## the plate proves its subject first: every card of the tray lies inside the
## window and the first card's name is bracketed, otherwise PROBE_INVALID and
## exit 1.
##
## Run (windowed takes the one project-wide slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <worktree>/game \
##     -s res://tests/ui/build_menu_pseudolocale_probe.gd

const OUT_DIR := "C:/Users/chulf/Gotta-make-my-flight/tools/blender/out/locale/t1"
const WINDOW := Vector2i(1920, 1080)
const TRAY_CROP := Rect2i(380, 640, 1160, 440)
const HOVER_FRAMES := 240
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
	PseudoLocale.enable(0.4)
	var main: Node3D = (load("res://main/main.tscn") as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	clock.seed_rng(world_seed)
	var hud := main.find_children("*", "PassengerHud", true, false)[0] as PassengerHud
	hud.unlock_guide().mode = UnlockGuide.Mode.PROFILE
	root.add_child(main)
	clock.set_paused(true)
	await _frames(5)
	var menu := main.find_children("*", "BuildMenu", true, false)[0] as BuildMenu
	var unlocks := main.get_node("BuildUnlocks") as BuildUnlocks
	var rating := main.get_node("AirportRating") as AirportRating
	for i in 400:
		rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in 600:
		unlocks.note_made()
	unlocks.check()
	await _frames(8)
	hud.unlock_guide().dismiss()
	await _frames(5)
	print("PROBE tier=%d paused=%s" % [unlocks.tier(), clock.paused])
	_expect(unlocks.tier() == 4, "tier is %d, not 4" % unlocks.tier())
	var categories := BuildMenuCatalog.categories()
	for i in categories.size():
		if (
			i == BuildMenuCatalog.remove_category()
			or OS.get_cmdline_user_args().has("--hover-only")
		):
			continue
		await _tray(menu, i, categories[i])
	await _hover_card(menu)
	PseudoLocale.disable()
	print("PROBE clipped labels: %d" % _clipped.size())
	for line in _clipped:
		print("  CLIPPED ", line)
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _tray(menu: BuildMenu, index: int, category: Dictionary) -> void:
	menu.press_category(index)
	await _frames(6)
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN)
	var shown := 0
	var first_name := ""
	for tool: BuildMode.Tool in category["tools"]:
		var card := menu.card(tool)
		if card == null or not card.is_visible_in_tree():
			continue
		shown += 1
		_expect(view.encloses(card.get_global_rect()), "card %s is outside the window" % tool)
		for label: Label in card.find_children("*", "Label", true, false):
			if label.text == "":
				continue
			# A name that went through shown() is already bracketed once; atr() would bracket
			# it again, which a real translation never gets, so measure it as stored.
			var text := label.text if label.text.begins_with("[") else label.atr(label.text)
			if first_name == "":
				first_name = text
			var font := label.get_theme_font("font")
			var size := label.get_theme_font_size("font_size")
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var clipped := width > label.size.x + 0.5
			if clipped:
				_clipped.append(
					(
						"tray %d %s: '%s' %.0f px in %.0f px"
						% [index, category["name"], text, width, label.size.x]
					)
				)
			print(
				(
					"  LABEL tray=%d tool=%s '%s' w=%.0f slot=%.0f clipped=%s"
					% [index, tool, text, width, label.size.x, clipped]
				)
			)
	print(
		"PLATE tray=%d name=%s cards=%d first='%s'" % [index, category["name"], shown, first_name]
	)
	_expect(shown > 0, "tray %d shows no card" % index)
	_expect(
		first_name.begins_with("["),
		"tray %d first label is not bracketed: '%s'" % [index, first_name]
	)
	var slug := String(category["name"]).to_lower().replace(" ", "_").replace("-", "_")
	await _save("tray_%02d_%s" % [index, slug], TRAY_CROP)


func _hover_card(menu: BuildMenu) -> void:
	var index := BuildMenuCatalog.category_of(BuildMode.Tool.CAFE_ROOM)
	menu.press_category(index)
	await _frames(6)
	var card := menu.card(BuildMode.Tool.CAFE_ROOM)
	var centre := card.get_global_rect().get_center()
	_expect(
		Rect2(Vector2.ZERO, root.get_visible_rect().size).has_point(centre),
		"the cafe card centre %s is outside the window" % centre
	)
	var motion := InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	root.warp_mouse(centre)
	root.push_input(motion, true)
	var shown: Array = []
	for i in HOVER_FRAMES:
		await process_frame
		shown = root.find_children("ItemInfoCard", "VBoxContainer", true, false)
		if not shown.is_empty():
			break
	_expect(not shown.is_empty(), "the hover card never appeared")
	if shown.is_empty():
		return
	await _frames(4)
	var box := shown[0] as Control
	# The hover card lives in a tooltip popup window; its rect is that window on screen.
	var popup := box.get_window()
	var rect := Rect2(popup.position, popup.size)
	print("PLATE hover card rect=%s centre_of_cafe_card=%s" % [rect, centre])
	_expect(
		Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN).encloses(rect),
		"the hover card is outside the window"
	)
	var texts: Array[String] = []
	for label: Label in box.find_children("*", "Label", true, false):
		texts.append(label.atr(label.text))
	print("  HOVER ", texts)
	_expect(texts[0].begins_with("["), "the hover card name is not bracketed: '%s'" % texts[0])
	var crop := Rect2i(rect.grow(24.0))
	await _save("hover_card", crop.intersection(Rect2i(Vector2i.ZERO, root.size)))


func _save(plate: String, crop: Rect2i) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := OUT_DIR.path_join(plate + ".png")
	var err := image.get_region(crop).save_png(path)
	print("PLATE saved %s err=%d" % [path, err])
	_expect(err == OK, "plate %s was not saved" % plate)


func _expect(condition: bool, why: String) -> void:
	if not condition:
		_failed = true
		print("PROBE_INVALID: ", why)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
