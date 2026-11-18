class_name TestSaveGameAutosave
extends GdUnitTestSuite
## The day-rollover autosave (decision title-menu-with-continue-new-airport-load-
## and-quit-autosave): the first tick of a new game day queues a save to the
## autosave that is due, written once a save is allowed, and the two autosave
## files take turns. A tick on the same day writes nothing, and a load starts
## counting from the loaded day. One boot of main.tscn, slots in a folder of
## this run's own. Cases feed on_tick() ticks of days later than any fed
## before (_new_day_tick), so no case needs a load to start over; only the load
## case loads.

const SEED := 18_112_026

var _dir := SaveTestKit.run_dir("test_save_game_autosave")
var _dir_before := ""
var _main: Node
var _save: SaveGame
var _clock: SimClock
## The latest game day a case has fed to on_tick().
var _last_day := 0


func before() -> void:
	_dir_before = SaveSlots.dir
	SaveSlots.dir = _dir
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_clock = _main.get_node("SimClock")
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	# The cafe settles on the next tick; a save waits for it.
	SaveTestKit.step(_main)
	_last_day = GameCalendar.day_of(_clock.tick)


func after() -> void:
	_main.free()
	_remove_files()
	DirAccess.remove_absolute(_dir)
	SaveSlots.dir = _dir_before


func before_test() -> void:
	_remove_files()
	_save.autosave_pending = ""


func _remove_files() -> void:
	for path in SaveSlots.all_paths():
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")


## The first tick of a day later than any fed so far.
func _new_day_tick() -> int:
	_last_day += 1
	return GameCalendar.day_start(_last_day)


## The first tick of the day after the clock's.
func _clock_next_day_tick() -> int:
	return GameCalendar.day_start(GameCalendar.day_of(_clock.tick) + 1)


func test_the_scene_feeds_the_clock_ticks_to_the_autosave() -> void:
	assert_bool(_clock.ticked.is_connected(_save.on_tick)).is_true()


func test_the_first_tick_of_a_new_day_writes_the_first_autosave() -> void:
	var paths := SaveSlots.autosave_paths()
	_save.on_tick(_new_day_tick())
	print("pending: %s" % _save.autosave_pending)
	assert_str(_save.autosave_pending).is_equal(paths[0])
	assert_bool(_save.retry_autosave()).is_true()
	assert_bool(FileAccess.file_exists(paths[0])).is_true()
	assert_bool(FileAccess.file_exists(paths[1])).is_false()
	assert_str(_save.autosave_pending).is_equal("")


func test_the_two_autosaves_take_turns_day_after_day() -> void:
	var paths := SaveSlots.autosave_paths()
	var written: Array[String] = []
	for day in 4:
		_save.on_tick(_new_day_tick())
		written.append(_save.autosave_pending)
		assert_bool(_save.retry_autosave()).is_true()
	print("written: %s" % [written])
	assert_array(written).is_equal([paths[0], paths[1], paths[0], paths[1]])
	for path in paths:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_int(int(data["save_version"])).is_equal(SaveGame.SAVE_VERSION)


func test_a_later_tick_on_the_same_day_writes_nothing() -> void:
	var tick := _new_day_tick()
	_save.on_tick(tick)
	assert_bool(_save.retry_autosave()).is_true()
	_save.on_tick(tick + 1)
	_save.on_tick(tick + GameCalendar.TICKS_PER_DAY - 1)
	assert_str(_save.autosave_pending).is_equal("")
	assert_bool(_save.retry_autosave()).is_false()
	assert_bool(FileAccess.file_exists(SaveSlots.autosave_paths()[0])).is_true()
	assert_bool(FileAccess.file_exists(SaveSlots.autosave_paths()[1])).is_false()


## A save is refused between a build edit and the next tick: the autosave waits
## and is written once the refusal clears.
func test_a_refused_autosave_waits_for_the_next_allowed_moment() -> void:
	_save.on_tick(_new_day_tick())
	_save.passengers.cafes.deadlines_stale = true
	assert_str(_save.save_problem()).is_not_equal("")
	assert_bool(_save.retry_autosave()).is_false()
	assert_str(_save.autosave_pending).is_equal(SaveSlots.autosave_paths()[0])
	_save.passengers.cafes.deadlines_stale = false
	assert_bool(_save.retry_autosave()).is_true()
	assert_bool(FileAccess.file_exists(SaveSlots.autosave_paths()[0])).is_true()


## A load drops a queued autosave (it was for the old world) and counts days
## from the loaded clock, so its own day writes nothing.
func test_a_load_drops_the_queued_autosave_and_counts_from_the_loaded_day() -> void:
	var data: Variant = JSON.parse_string(JSON.stringify(_save.snapshot()))
	_save.on_tick(_new_day_tick())
	assert_str(_save.autosave_pending).is_not_equal("")
	assert_bool(_save.load_world(data)).is_true()
	assert_str(_save.autosave_pending).is_equal("")
	_save.on_tick(_clock.tick + 1)
	assert_str(_save.autosave_pending).is_equal("")
	_save.on_tick(_clock_next_day_tick())
	assert_str(_save.autosave_pending).is_equal(SaveSlots.autosave_paths()[0])


## Loading an autosave makes it the last one written, so the next rollover
## writes the other slot and the loaded file stays as the fallback.
func test_loading_an_autosave_makes_the_next_rollover_write_the_other_slot() -> void:
	var paths := SaveSlots.autosave_paths()
	_save.on_tick(_new_day_tick())
	assert_bool(_save.retry_autosave()).is_true()
	_save.on_tick(_new_day_tick())
	assert_bool(_save.retry_autosave()).is_true()
	# paths[1] was written last. Load paths[0], the older timeline.
	assert_bool(_save.load_from_file(paths[0])).is_true()
	_save.on_tick(_clock_next_day_tick())
	print("after loading %s: pending %s" % [paths[0], _save.autosave_pending])
	assert_str(_save.autosave_pending).is_equal(paths[1])
	# And loading the other one flips it, so the rule is not a fixed slot.
	assert_bool(_save.load_from_file(paths[1])).is_true()
	_save.on_tick(_clock_next_day_tick())
	assert_str(_save.autosave_pending).is_equal(paths[0])


## Loading the manual save names no autosave slot: rotation forgets the last
## write and the older autosave is written (the first on a tie).
func test_loading_a_manual_save_makes_the_next_rollover_write_the_older_autosave() -> void:
	var paths := SaveSlots.autosave_paths()
	_save.on_tick(_new_day_tick())
	assert_bool(_save.retry_autosave()).is_true()
	# paths[1] is newer or tied, and the last write is paths[0]: without the
	# reset the next write would go to paths[1].
	assert_bool(_save.save_to_file(paths[1])).is_true()
	assert_bool(_save.save_to_file(SaveSlots.manual_path())).is_true()
	assert_bool(_save.load_from_file(SaveSlots.manual_path())).is_true()
	_save.on_tick(_clock_next_day_tick())
	print("after loading the manual save: pending %s" % _save.autosave_pending)
	assert_str(_save.autosave_pending).is_equal(paths[0])
