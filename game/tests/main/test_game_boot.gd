class_name TestGameBoot
extends GdUnitTestSuite
## main.tscn boots in New or Load mode (decision title-menu-with-continue-new-
## airport-load-and-quit-autosave). With no GameBoot.load_path it is a new
## airport, as before. With one, SaveGame takes the path as the scene enters the
## tree and loads it through load_from_file once the whole scene is ready; the
## game comes back paused at 1x (decision loading-a-save-always-comes-back-
## paused-at-1x-speed-with-hin). A refused boot load leaves its message in
## GameBoot.refusal for the title screen. Each case boots its own scene. The
## fixtures live in a folder of this run's own, which SaveSlots.dir points at
## before either scene is built, so nothing touches the player's saves.

const SEED := 18_112_027

var _dir := SaveTestKit.run_dir("test_game_boot")
var _dir_before := ""
var _path := _dir.path_join("good.json")
var _bad_path := _dir.path_join("bad.json")
var _saved_tick := 0
var _main: Node
var _shown_before := false


func before() -> void:
	_dir_before = SaveSlots.dir
	SaveSlots.dir = _dir
	DirAccess.make_dir_recursive_absolute(_dir)
	var source := SaveTestKit.boot(self, SEED)
	(source.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	for i in 40:
		SaveTestKit.step(source)
	(source.get_node("PassengerHud") as PassengerHud).press_speed(3)
	assert_bool(SaveTestKit.save_game(source).save_to_file(_path)).is_true()
	_saved_tick = (source.get_node("SimClock") as SimClock).tick
	source.free()
	var bad := FileAccess.open(_bad_path, FileAccess.WRITE)
	bad.store_string('{"save_version": 1}')
	bad.close()


func after() -> void:
	for path in [_path, _bad_path]:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	DirAccess.remove_absolute(_dir)
	SaveSlots.dir = _dir_before


func before_test() -> void:
	_shown_before = IntroDialogue.shown_this_session
	GameBoot.load_path = ""
	GameBoot.refusal = ""


func after_test() -> void:
	if is_instance_valid(_main):
		_main.free()
	GameBoot.load_path = ""
	GameBoot.refusal = ""
	IntroDialogue.shown_this_session = _shown_before


## Instantiates main.tscn, adds it and waits for its deferred calls.
func _boot() -> Array[bool]:
	var seen: Array[bool] = []
	_main = load(GameBoot.MAIN_SCENE).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	var save: SaveGame = _main.get_node("SaveGame")
	save.loaded.connect(func(ok: bool) -> void: seen.append(ok))
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	return seen


func test_the_main_scene_constant_names_main_tscn() -> void:
	assert_str(GameBoot.MAIN_SCENE).is_equal(SaveTestKit.MAIN)
	assert_bool(ResourceLoader.exists(GameBoot.TITLE_SCENE)).is_true()


func test_new_mode_boots_a_fresh_airport_and_loads_nothing() -> void:
	var seen := await _boot()
	var clock: SimClock = _main.get_node("SimClock")
	print("new: loaded=%s tick=%d" % [seen, clock.tick])
	assert_array(seen).is_empty()
	assert_int(clock.tick).is_less(_saved_tick)


func test_load_mode_loads_the_file_and_comes_back_paused_at_1x() -> void:
	GameBoot.start_load(_path, func(_scene: String) -> Error: return OK)
	var seen := await _boot()
	var clock: SimClock = _main.get_node("SimClock")
	print("load: loaded=%s tick=%d saved=%d" % [seen, clock.tick, _saved_tick])
	assert_array(seen).is_equal([true])
	assert_int(clock.tick).is_equal(_saved_tick)
	assert_bool(clock.paused).is_true()
	assert_int(clock.speed).is_equal(1)
	assert_str(GameBoot.load_path).is_equal("")
	assert_str(GameBoot.refusal).is_equal("")


func test_a_refused_boot_load_leaves_its_message_for_the_title() -> void:
	GameBoot.start_load(_bad_path, func(_scene: String) -> Error: return OK)
	var seen := await _boot()
	print("refused: loaded=%s refusal='%s'" % [seen, GameBoot.refusal])
	assert_array(seen).is_equal([false])
	assert_str(GameBoot.refusal).contains("Load failed")
	assert_str(GameBoot.refusal).is_equal(SaveTestKit.save_game(_main).message_text())
