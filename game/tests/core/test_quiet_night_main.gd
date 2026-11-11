class_name TestQuietNightMain
extends GdUnitTestSuite
## On the real main scene: the QuietNight node drives the clock's fast-forward
## source, and a load still comes back paused at 1x with no fast-forward
## running (decisions quiet-nights-fast-forward-automatically-when-nothing-is-
## due and loading-a-save-always-comes-back-paused-at-1x-speed-with-hin). The
## fast-forward is not save data, so the save file carries no trace of it.

const SEED := 7_311_042

var _path := SaveTestKit.run_path("test_quiet_night_main")
var _main: Node
var _clock: SimClock


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_clock = _main.get_node("SimClock")
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	SaveTestKit.step(_main)
	assert_bool(SaveTestKit.save_game(_main).save_to_file(_path)).is_true()


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func test_the_main_scene_wires_the_quiet_night_source() -> void:
	var quiet := _main.get_node("QuietNight") as QuietNight
	assert_object(quiet).is_not_null()
	assert_bool(_clock.fast_forward_source.is_valid()).is_true()
	assert_int(_clock.fast_forward_source.call()).is_equal(quiet.stop_tick())
	# The airport is not open yet in this world, so nothing fast-forwards.
	assert_int(quiet.stop_tick()).is_equal(-1)


func test_the_save_file_has_no_fast_forward_in_it() -> void:
	var text := FileAccess.get_file_as_string(_path)
	print("save size=%d" % text.length())
	assert_int(text.length()).is_greater(0)
	assert_str(text).not_contains("fast_forward")


func test_a_load_during_a_fast_forward_comes_back_paused_at_1x_and_not_fast() -> void:
	_clock.set_paused(false)
	assert_bool(_clock.set_speed(3)).is_true()
	# As a running fast-forward leaves it between two frames.
	_clock.fast_forward_until = _clock.tick + 5000
	assert_bool(_clock.is_fast_forwarding()).is_true()
	assert_bool(SaveTestKit.save_game(_main).load_from_file(_path)).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(1)
	assert_int(_clock.fast_forward_until).is_equal(-1)
	assert_bool(_clock.is_fast_forwarding()).is_false()
