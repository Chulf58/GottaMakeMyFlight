extends SceneTree

const IntroClose := preload("res://spike/intro_close.gd")
const LOCALE_SETTINGS := preload("res://locale/locale_settings.gd")
const GAME_AUDIO := preload("res://audio/game_audio.gd")
const OUT_REL := "res://../tools/blender/out/t8_locale"
const WINDOW := Vector2i(1280, 720)
const MARGIN := 6.0
const LIMIT_FRAMES := 1500

var _out_dir := ""
var _failed := false
var _seed := 0
var _frames_run := 0
var _slot_dir := ""
var _audio_cfg := ""
var _alerts_cfg := ""
var _departures_cfg := ""
var _quit_cfg := ""


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_frames_run += 1
	if _frames_run > LIMIT_FRAMES:
		print("PROBE_INVALID: ran past %d frames" % LIMIT_FRAMES)
		_cleanup()
		quit(1)
	return false


func _run() -> void:
	_seed = IntroClose.seed_or_random()
	print("PROBE world_seed=%d display=%s" % [_seed, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		print("PROBE_INVALID: run windowed with --display-driver windows --rendering-driver vulkan")
		quit(1)
		return
	var pid := OS.get_process_id()
	_slot_dir = "user://probe_t8_slots_%d" % pid
	_audio_cfg = "user://probe_t8_audio_%d.cfg" % pid
	_alerts_cfg = "user://probe_t8_alerts_%d.cfg" % pid
	_departures_cfg = "user://probe_t8_dep_%d.cfg" % pid
	_quit_cfg = "user://probe_t8_quit_%d.cfg" % pid
	SaveSlots.dir = _slot_dir
	DirAccess.make_dir_recursive_absolute(_slot_dir)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(WINDOW)
	var audio := root.get_node_or_null("GameAudio") as GAME_AUDIO
	if audio != null:
		audio.set_settings_path(_audio_cfg)
		audio.set_muted(true)
	await _frames(4)
	await _plate_glyph_grid()
	if not _failed:
		await _plate_title_ja()
	if not _failed:
		await _plate_ingame_zh_cn()
	print("PROBE done failed=%s" % _failed)
	_cleanup()
	quit(1 if _failed else 0)


func _plate_glyph_grid() -> void:
	var settings := root.get_node("LocaleSettings") as LOCALE_SETTINGS
	root.content_scale_factor = 1.0
	var layer := CanvasLayer.new()
	layer.name = "GlyphGridPlate"
	var bg := ColorRect.new()
	bg.color = TitleScreen.BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	layer.add_child(margin)
	var root_col := VBoxContainer.new()
	root_col.add_theme_constant_override("separation", 12)
	margin.add_child(root_col)
	var heading := Label.new()
	heading.text = "Core Steam 10 — Bundled Font Coverage (700 / 800 / 850 + Label3D)"
	heading.theme = BuildMenu.HUD_THEME
	heading.theme_type_variation = &"HudLarge"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_col.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	root_col.add_child(grid)
	var base_font := load(LOCALE_SETTINGS.BASE_FONT_PATH) as FontFile
	var f700 := _variation(base_font, 700)
	var f800 := _variation(base_font, 800)
	var f850 := _variation(base_font, 850)
	var label3d_parts := PackedStringArray()
	for code in LOCALE_SETTINGS.codes():
		settings.apply_locale(code, false)
		var endonym := LOCALE_SETTINGS.display_name(code)
		var line700 := (
			"%s  |  %s"
			% [
				TranslationServer.translate("New Airport", "menu"),
				TranslationServer.translate("Language"),
			]
		)
		var line850 := (
			"%s  ·  %s  ·  %s"
			% [
				TranslationServer.translate("Check-in desk", "build menu"),
				TranslationServer.translate("Gate {gate}", "gate caption").format({"gate": "A"}),
				TranslationServer.translate("Closed", "sign caption"),
			]
		)
		var checked := 0
		var missing := 0
		for txt: String in [endonym, line700, line850]:
			for i in txt.length():
				var cp := txt.unicode_at(i)
				if cp <= 32:
					continue
				checked += 1
				if not CaptionFont.font().has_char(cp):
					missing += 1
		print("GLYPH_CHECK locale=%s chars=%d missing=%d" % [code, checked, missing])
		_expect(missing == 0, "zero missing glyphs for %s" % code)
		label3d_parts.append(endonym)
		var card := PanelContainer.new()
		card.theme = BuildMenu.HUD_THEME
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)
		box.add_child(_styled_line("%s (%s)" % [endonym, code], f800, 18))
		box.add_child(_styled_line(line700, f700, 15))
		box.add_child(_styled_line(line850, f850, 15))
	var strip := SubViewportContainer.new()
	strip.custom_minimum_size = Vector2(0.0, 124.0)
	strip.stretch = true
	root_col.add_child(strip)
	var sub := SubViewport.new()
	sub.own_world_3d = true
	sub.size = Vector2i(1244, 124)
	strip.add_child(sub)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 3.2)
	cam.fov = 35.0
	sub.add_child(cam)
	var world_label := CaptionFont.apply(Label3D.new())
	settings.apply_locale("zh_CN", false)
	var row1 := "  ·  ".join(label3d_parts.slice(0, 5))
	var row2 := "  ·  ".join(label3d_parts.slice(5, 10))
	world_label.text = "Label3D: %s\n%s" % [row1, row2]
	world_label.font_size = 44
	world_label.outline_size = 10
	world_label.outline_modulate = MarkerIcons.OUTLINE
	world_label.modulate = Color(0.99, 0.97, 0.92)
	world_label.pixel_size = 0.012
	sub.add_child(world_label)
	var scene := Node.new()
	scene.add_child(layer)
	if current_scene != null:
		current_scene.free()
	root.add_child(scene)
	current_scene = scene
	await _frames(5)
	var projected := cam.unproject_position(world_label.global_position)
	print("LABEL3D_STRIP projected=%s sub_size=%s" % [projected, sub.size])
	_expect(
		Rect2(Vector2.ZERO, Vector2(sub.size)).grow(-4.0).has_point(projected),
		"Label3D strip centered in 3D viewport"
	)
	await _save_plate("01_all_10_locales_glyph_grid.png")
	settings.apply_locale("en", false)


func _variation(base: FontFile, weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {2003265652: weight}
	return fv


func _styled_line(text: String, font: Font, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _plate_title_ja() -> void:
	var settings := root.get_node("LocaleSettings") as LOCALE_SETTINGS
	root.content_scale_factor = 1.25
	settings.apply_locale("en", false)
	change_scene_to_file(GameBoot.TITLE_SCENE)
	await _frames(8)
	var title := current_scene as TitleScreen
	_expect(title != null, "title scene loaded")
	if _failed:
		return
	var picker := title.language_picker
	_expect(picker != null and picker.is_visible_in_tree(), "title LanguagePicker visible")
	var ja_idx := LOCALE_SETTINGS.codes().find("ja")
	picker.option_button().select(ja_idx)
	picker.option_button().item_selected.emit(ja_idx)
	await _frames(6)
	_expect(settings.current_locale() == "ja", "live switched to ja")
	_expect(title.button("NewAirport").text == "新しい空港", "NewAirport translated to ja")
	_expect(picker.label().text == "言語", "Language label translated to ja")
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN)
	var audio_rect := title.button("Audio").get_global_rect()
	var picker_rect := picker.get_global_rect()
	var panel_rect := (title.find_child("Panel", true, false) as Control).get_global_rect()
	print("RECT title_ja panel=%s audio=%s picker=%s" % [panel_rect, audio_rect, picker_rect])
	_expect(view.encloses(panel_rect), "title panel inside 1280x720")
	_expect(view.encloses(audio_rect), "title Audio inside 1280x720")
	_expect(view.encloses(picker_rect), "title LanguagePicker inside 1280x720")
	_expect(not audio_rect.intersects(picker_rect), "Audio and LanguagePicker do not overlap")
	_expect(not panel_rect.intersects(picker_rect), "Panel and LanguagePicker do not overlap")
	await _save_plate("02_title_screen_ja_1280.png")


func _plate_ingame_zh_cn() -> void:
	var settings := root.get_node("LocaleSettings") as LOCALE_SETTINGS
	root.content_scale_factor = 1.25
	settings.apply_locale("en", false)
	var main := (load(GameBoot.MAIN_SCENE) as PackedScene).instantiate()
	var clock := main.get_node("SimClock") as SimClock
	clock.seed_rng(_seed)
	var hud := main.get_node("PassengerHud") as PassengerHud
	hud.alert_settings_path = _alerts_cfg
	hud.departures_settings_path = _departures_cfg
	var recorder := main.get_node_or_null("QuitLogRecorder") as QuitLogRecorder
	if recorder != null:
		recorder.settings_path = _quit_cfg
	if current_scene != null:
		current_scene.free()
	root.add_child(main)
	current_scene = main
	await _frames(8)
	var close_err: String = IntroClose.close(main)
	_expect(close_err == "", "intro closed: " + close_err)
	hud.press_starter_terminal()
	var mode := main.get_node("BuildMode") as BuildMode
	var build_menu := main.get_node("BuildMenu") as BuildMenu
	var apron := main.get_node("ApronStand") as ApronStand
	if apron != null:
		apron.links_view().set_building(true)
	var tycoon_cam := main.get_node_or_null("TycoonCamera") as TycoonCamera
	if tycoon_cam != null:
		tycoon_cam.position.x -= 12.0
	clock.set_paused(true)
	await _frames(8)
	var cam := main.get_viewport().get_camera_3d()
	var caption_node: Label3D = null
	if apron != null and not apron.links_view().gate_captions().is_empty():
		caption_node = apron.links_view().gate_captions()[0]
	var world_pos := (
		caption_node.global_position if caption_node != null else Vector3(0.0, 1.0, 0.0)
	)
	var projected := cam.unproject_position(world_pos)
	print(
		(
			"WORLD_SUBJECT pos=%s projected=%s captions=%d rooms=%d"
			% [
				world_pos,
				projected,
				apron.links_view().gate_captions().size() if apron != null else 0,
				mode.grid.room_ids().size(),
			]
		)
	)
	_expect(
		Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-10.0).has_point(projected),
		"world gate caption projected in frame"
	)
	var menu := main.get_node("GameMenu") as GameMenu
	_expect(menu.open(), "GameMenu opened")
	menu.press_settings()
	await _frames(4)
	var zh_idx := LOCALE_SETTINGS.codes().find("zh_CN")
	menu.language_picker.option_button().select(zh_idx)
	menu.language_picker.option_button().item_selected.emit(zh_idx)
	await _frames(6)
	_expect(settings.current_locale() == "zh_CN", "live switched to zh_CN")
	_expect(menu.incidents_switch().text == "突发事件", "Incidents translated to zh_CN")
	_expect(
		build_menu.category_button(0).tooltip_text == "建筑结构",
		"BuildMenu tab tooltip translated to zh_CN"
	)
	if caption_node != null:
		print("GATE_CAPTION_ZH=%s" % caption_node.text.replace("\n", " / "))
		_expect(caption_node.text.contains("登机口"), "Gate caption translated to zh_CN")
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN)
	var panel := menu.find_child("Panel", true, false) as Control
	var panel_rect := panel.get_global_rect()
	var card_rect := menu.audio_card.get_global_rect()
	var picker_rect := menu.language_picker.get_global_rect()
	var settings_parent := menu.incidents_switch().get_parent() as Control
	var settings_rect := settings_parent.get_global_rect()
	print(
		(
			"RECT ingame_zh panel=%s audio=%s picker=%s settings=%s"
			% [panel_rect, card_rect, picker_rect, settings_rect]
		)
	)
	_expect(view.encloses(panel_rect), "GameMenu panel inside 1280x720")
	_expect(not card_rect.intersects(picker_rect), "audio_card and language_picker non-overlapping")
	_expect(
		not picker_rect.intersects(settings_rect),
		"language_picker and settings_page non-overlapping"
	)
	await _save_plate("03_ingame_zh_cn_menu_and_world_1280.png")
	menu.close()


func _save_plate(filename: String) -> void:
	if _failed:
		return
	await _frames(3)
	var path := _out_dir.path_join(filename)
	var image := root.get_texture().get_image()
	print("PLATE %s size=%s" % [path, image.get_size()])
	_expect(image.save_png(path) == OK, "saved " + path)


func _cleanup() -> void:
	var settings := root.get_node_or_null("LocaleSettings") as LOCALE_SETTINGS
	if settings != null:
		settings.apply_locale("en", false)
	var audio := root.get_node_or_null("GameAudio") as GAME_AUDIO
	if audio != null:
		audio.reset_for_test()
	for path in [_audio_cfg, _alerts_cfg, _departures_cfg, _quit_cfg]:
		if path != "":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _slot_dir != "":
		for path in SaveSlots.all_paths():
			DirAccess.remove_absolute(path)
			DirAccess.remove_absolute(path + ".tmp")
		DirAccess.remove_absolute(_slot_dir)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		print("PROBE_INVALID: %s" % what)
		_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
