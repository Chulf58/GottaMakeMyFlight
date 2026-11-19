extends SceneTree
## Windowed UI plate probe for the D5 demo audio settings controls on both
## title.tscn (expanded AudioSettingsCard below the main menu panel) and
## main.tscn (GameMenu open on Settings with AudioSettingsCard above gameplay
## settings). Verifies every panel, button, slider and label lies inside the
## 1920x1080 viewport with zero sibling overlaps before saving plates to
## tools/blender/out/audio-ui/.
##
## Run (windowed takes the one project-wide slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <worktree>/game \
##     -s res://spike/audio_ui_probe.gd

const IntroClose := preload("res://spike/intro_close.gd")
const GAME_AUDIO := preload("res://audio/game_audio.gd")
const OUT_REL := "res://../tools/blender/out/audio-ui"
const WINDOW := Vector2i(1920, 1080)
const MARGIN := 8.0
const LIMIT_FRAMES := 1200

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
		print("PROBE_INVALID: the probe ran past %d frames" % LIMIT_FRAMES)
		_cleanup()
		quit(1)
	return false


func _run() -> void:
	_seed = IntroClose.seed_or_random()
	print("PROBE world_seed=%d display=%s" % [_seed, DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		print("PROBE_INVALID: run it windowed")
		quit(1)
		return
	var pid := OS.get_process_id()
	_slot_dir = "user://probe_audio_slots_%d" % pid
	_audio_cfg = "user://probe_audio_cfg_%d.cfg" % pid
	_alerts_cfg = "user://probe_audio_alerts_%d.cfg" % pid
	_departures_cfg = "user://probe_audio_dep_%d.cfg" % pid
	_quit_cfg = "user://probe_audio_quit_%d.cfg" % pid
	SaveSlots.dir = _slot_dir
	DirAccess.make_dir_recursive_absolute(_slot_dir)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(WINDOW)
	root.content_scale_factor = 1.0
	var audio := root.get_node_or_null("GameAudio") as GAME_AUDIO
	_expect(audio != null, "GameAudio autoload present")
	if _failed:
		_cleanup()
		quit(1)
		return
	audio.set_settings_path(_audio_cfg)
	audio.set_master_volume(0.80)
	audio.set_ambience_volume(0.65)
	audio.set_sfx_volume(0.85)
	audio.set_muted(false)
	await _frames(5)
	await _plate_title()
	if not _failed:
		await _plate_esc_menu(audio)
	print("PROBE done failed=%s" % _failed)
	_cleanup()
	quit(1 if _failed else 0)


func _plate_title() -> void:
	change_scene_to_file(GameBoot.TITLE_SCENE)
	await _frames(8)
	var title := current_scene as TitleScreen
	_expect(title != null, "title scene loaded")
	if _failed:
		return
	title.button("Audio").pressed.emit()
	await _frames(6)
	_expect(title.audio_card.is_visible_in_tree(), "title audio_card is visible")
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN)
	var panel := title.find_child("Panel", true, false) as Control
	var audio_btn := title.button("Audio")
	var card := title.audio_card
	var panel_rect := panel.get_global_rect()
	var btn_rect := audio_btn.get_global_rect()
	var card_rect := card.get_global_rect()
	print("RECT title panel=%s audio_btn=%s audio_card=%s" % [panel_rect, btn_rect, card_rect])
	_expect(view.encloses(panel_rect), "title panel in viewport")
	_expect(view.encloses(btn_rect), "title Audio button in viewport")
	_expect(view.encloses(card_rect) and card_rect.size.y > 120.0, "title audio_card in viewport")
	_expect(not panel_rect.intersects(card_rect), "title panel and audio_card do not overlap")
	_expect(not btn_rect.intersects(card_rect), "title Audio button and audio_card do not overlap")
	_check_controls_fit(card, "title_audio_card")
	await _save_plate("title_audio_card.png")


func _plate_esc_menu(audio: GAME_AUDIO) -> void:
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
	clock.set_paused(true)
	await _frames(6)
	print("COMPARE ambience_playing=%s (want true)" % audio.is_ambience_playing())
	_expect(audio.is_ambience_playing(), "gameplay ambience is playing in main.tscn")
	var menu := main.get_node("GameMenu") as GameMenu
	_expect(menu.open(), "GameMenu opened")
	menu.press_settings()
	await _frames(6)
	var view := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN)
	var panel := menu.find_child("Panel", true, false) as Control
	var settings_page := menu.incidents_switch().get_parent() as Control
	var panel_rect := panel.get_global_rect()
	var card_rect := menu.audio_card.get_global_rect()
	var settings_rect := settings_page.get_global_rect()
	print(
		"RECT esc panel=%s audio_card=%s settings_page=%s" % [panel_rect, card_rect, settings_rect]
	)
	_expect(view.encloses(panel_rect), "esc panel in viewport")
	_expect(view.encloses(card_rect), "esc audio_card in viewport")
	_expect(view.encloses(settings_rect), "esc settings_page in viewport")
	_expect(
		not card_rect.intersects(settings_rect), "esc audio_card and settings_page do not overlap"
	)
	_check_controls_fit(panel, "esc_audio_card")
	await _save_plate("esc_audio_card.png")
	menu.close()


func _check_controls_fit(scope: Control, tag: String) -> void:
	var outer := scope.get_global_rect().grow(2.0)
	for node in scope.find_children("*", "Control", true, false):
		var ctrl := node as Control
		if not ctrl.is_visible_in_tree():
			continue
		if ctrl is Label or ctrl is Button or ctrl is HSlider:
			var rect := ctrl.get_global_rect()
			_expect(
				outer.encloses(rect), "%s %s inside %s (%s)" % [tag, ctrl.name, scope.name, rect]
			)


func _save_plate(filename: String) -> void:
	if _failed:
		return
	await _frames(3)
	var path := _out_dir.path_join(filename)
	var image := root.get_texture().get_image()
	print("PLATE %s size=%s" % [path, image.get_size()])
	_expect(image.save_png(path) == OK, "saved " + path)


func _cleanup() -> void:
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
