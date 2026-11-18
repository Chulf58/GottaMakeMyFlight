extends SceneTree
## Windowed plates and boot flow of the title screen (decision title-menu-with-
## continue-new-airport-load-and-quit-autosave), the project's main scene. The
## saves live in a folder of this run's own (SaveSlots.dir), never the player's.
##
##   a: the title with no save (Continue and Load greyed), plated.
##   b: New Airport boots main.tscn through the real scene change; the intro is
##      closed and the clock must run (tick grows). A manual save is written,
##      then the game is set running at 3x.
##   c: back to the title: Continue enabled, plated. Continue boots main.tscn
##      on the save, which must come back at the saved tick, paused at 1x.
##   d: the title with PseudoLocale on (+40%), plated; every button's text must
##      fit its button.
##
## Before each plate every menu button's rect is printed and must lie inside the
## viewport with a margin, otherwise PROBE_INVALID and exit 1. The world seed is
## printed and can be replayed with `-- --seed=N`.
##
## Run (windowed takes the one project-wide slot):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy --path <worktree>/game \
##     -s res://spike/title_boot_probe.gd
## The plates go to tools/blender/out/d2b/.

const IntroClose := preload("res://spike/intro_close.gd")
const OUT_REL := "res://../tools/blender/out/d2b"
const WINDOW := Vector2i(1920, 1080)
const MARGIN := 8.0
const LIMIT_FRAMES := 3000
const BUTTONS: Array[String] = ["Continue", "NewAirport", "Load", "Quit"]

var _out_dir := ""
var _failed := false
var _seed := 0
var _slot_dir := ""
var _frames_run := 0
var _saved_tick := -1


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
	_slot_dir = "user://probe_d2b_%d" % OS.get_process_id()
	SaveSlots.dir = _slot_dir
	DirAccess.make_dir_recursive_absolute(_slot_dir)
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(WINDOW)
	node_added.connect(_seed_clock)
	await _frames(5)
	await _title_empty()
	if not _failed:
		await _new_airport()
	if not _failed:
		await _continue()
	if not _failed:
		await _pseudo()
	print("PROBE done failed=%s" % _failed)
	_cleanup()
	quit(1 if _failed else 0)


func _seed_clock(node: Node) -> void:
	if node is SimClock:
		(node as SimClock).seed_rng(_seed)


func _cleanup() -> void:
	for path in SaveSlots.all_paths():
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	DirAccess.remove_absolute(_slot_dir)


func _title_empty() -> void:
	var title := await _to_title()
	print(
		(
			"COMPARE a continue_disabled=%s load_disabled=%s (want true true)"
			% [title.button("Continue").disabled, title.button("Load").disabled]
		)
	)
	_expect(title.button("Continue").disabled and title.button("Load").disabled, "a greyed")
	await _plate("a_title_no_save", title)


func _new_airport() -> void:
	var title := current_scene as TitleScreen
	title.button("NewAirport").pressed.emit()
	await _frames(10)
	var main := current_scene
	_expect(main != null and main.has_node("SimClock"), "b main is the current scene")
	if _failed:
		return
	var reason: String = IntroClose.close(main)
	_expect(reason == "", "b " + reason)
	var clock := main.get_node("SimClock") as SimClock
	var tick_before := clock.tick
	await _frames(30)
	print("COMPARE b scene=%s tick %d -> %d (want growth)" % [main.name, tick_before, clock.tick])
	_expect(clock.tick > tick_before, "b the clock runs after New Airport")
	(main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	var save := main.get_node("SaveGame") as SaveGame
	for i in 60:
		await _frames(1)
		if save.save_problem() == "":
			break
	_expect(save.save_to_file(SaveSlots.manual_path()), "b manual save written")
	var saved_tick := clock.tick
	print("COMPARE b saved_tick=%d path=%s" % [saved_tick, SaveSlots.manual_path()])
	clock.set_speed(3)
	clock.set_paused(false)
	await _frames(10)
	print("COMPARE b running tick=%d speed=%d paused=%s" % [clock.tick, clock.speed, clock.paused])
	_expect(clock.tick > saved_tick, "b the game ran on after the save")
	_saved_tick = saved_tick


func _continue() -> void:
	var title := await _to_title()
	print("COMPARE c continue_disabled=%s (want false)" % title.button("Continue").disabled)
	_expect(not title.button("Continue").disabled, "c Continue enabled with a save")
	await _plate("c_title_with_save", title)
	title.press_load()
	await _frames(3)
	var view := root.get_visible_rect().grow(-MARGIN)
	var listed := title.save_list().paths()
	print("COMPARE e listed=%s (want [%s])" % [listed, SaveSlots.manual_path()])
	_expect(listed == [SaveSlots.manual_path()], "e the manual save is listed")
	for path in listed:
		var rect := title.save_list().button_for(path).get_global_rect()
		print("RECT e_title_load_page %s %s in=%s" % [path.get_file(), rect, view.encloses(rect)])
		_expect(view.encloses(rect) and rect.size.x > 100.0, "e %s in frame" % path)
	if not _failed:
		var image := root.get_texture().get_image()
		image.save_png(_out_dir.path_join("e_title_load_page.png"))
		print("PLATE e_title_load_page size=%s" % image.get_size())
	title.press_back()
	await _frames(3)
	title.button("Continue").pressed.emit()
	await _frames(10)
	var main := current_scene
	_expect(main != null and main.has_node("SimClock"), "c main is the current scene")
	if _failed:
		return
	var clock := main.get_node("SimClock") as SimClock
	await _frames(10)
	print(
		(
			"COMPARE c loaded tick=%d saved=%d paused=%s speed=%d (want equal, true, 1)"
			% [clock.tick, _saved_tick, clock.paused, clock.speed]
		)
	)
	_expect(clock.tick == _saved_tick, "c loaded at the saved tick")
	_expect(clock.paused and clock.speed == 1, "c loaded paused at 1x")


func _pseudo() -> void:
	PseudoLocale.enable()
	var title := await _to_title()
	for button_name in BUTTONS:
		var button := title.button(button_name)
		var need := button.get_combined_minimum_size().x
		print(
			(
				"COMPARE d %s text='%s' need=%.0f width=%.0f"
				% [button_name, button.text, need, button.size.x]
			)
		)
		_expect(button.text.begins_with("["), "d %s routed" % button_name)
		_expect(need <= button.size.x + 0.5, "d %s fits" % button_name)
	await _plate("d_title_pseudo", title)
	PseudoLocale.disable()


func _to_title() -> TitleScreen:
	change_scene_to_file(GameBoot.TITLE_SCENE)
	await _frames(8)
	var title := current_scene as TitleScreen
	_expect(title != null, "the title is the current scene")
	return title


func _plate(label: String, title: TitleScreen) -> void:
	var view := root.get_visible_rect().grow(-MARGIN)
	for button_name in BUTTONS:
		var rect := title.button(button_name).get_global_rect()
		print("RECT %s %s %s in=%s" % [label, button_name, rect, view.encloses(rect)])
		_expect(
			view.encloses(rect) and rect.size.x > 100.0, "%s %s in frame" % [label, button_name]
		)
	if _failed:
		return
	await _frames(3)
	var path := _out_dir.path_join("%s.png" % label)
	var image := root.get_texture().get_image()
	print("PLATE %s %s size=%s" % [label, path, image.get_size()])
	image.save_png(path)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		print("PROBE_INVALID: %s" % what)
		_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
