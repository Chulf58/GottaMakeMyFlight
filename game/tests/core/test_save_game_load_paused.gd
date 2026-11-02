class_name TestSaveGameLoadPaused
extends GdUnitTestSuite
## Loading a save always comes back paused at 1x speed, with the hint cards
## rebuilt at once (decision loading-a-save-always-comes-back-paused-at-1x-
## speed-with-hin). Speed and pause are not save data: whatever the clock was
## doing before the load, the loaded game waits for the player. The save is a
## starter terminal with no staff, so its staff hint names the hires. Each case
## boots its own main scene, which has no terminal yet and so no hint.

const SEED := 5_511_021

var _path := SaveTestKit.run_path("test_save_game_load_paused")
var _main: Node
var _clock: SimClock
var _save: SaveGame
var _panel: StaffPanel


func before() -> void:
	var source := SaveTestKit.boot(self, SEED)
	(source.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	# The cafe settles on the next tick; a save waits for it.
	SaveTestKit.step(source)
	# Saved while running at 3x, so the file itself says running and fast.
	(source.get_node("PassengerHud") as PassengerHud).press_speed(3)
	assert_bool(SaveTestKit.save_game(source).save_to_file(_path)).is_true()
	source.free()


func after() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func before_test() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_clock = _main.get_node("SimClock")
	_save = SaveTestKit.save_game(_main)
	_panel = _main.get_node("StaffPanel")


func after_test() -> void:
	_main.free()


func test_a_load_while_running_at_3x_leaves_the_game_paused_at_1x() -> void:
	(_main.get_node("PassengerHud") as PassengerHud).press_speed(3)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)
	assert_bool(_save.load_from_file(_path)).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(1)


func test_a_load_while_paused_at_2x_comes_back_paused_at_1x() -> void:
	assert_bool(_clock.set_speed(2)).is_true()
	assert_bool(_clock.paused).is_true()
	assert_bool(_save.load_from_file(_path)).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(1)


func test_a_refused_load_leaves_the_speed_and_pause_alone() -> void:
	_clock.set_paused(false)
	assert_bool(_clock.set_speed(3)).is_true()
	assert_bool(_save.load_from_file(_path + ".missing")).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_the_staff_hint_card_shows_once_after_loading_a_save_with_no_staff() -> void:
	# This world has the terminal and both hires, so its hint holds no hire line.
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	SaveTestKit.step(_main)
	(_main.get_node("Staff") as StaffSim).hire(StaffMember.Role.CHECKIN)
	(_main.get_node("Staff") as StaffSim).hire(StaffMember.Role.SECURITY)
	assert_str(_panel.hint_label().text).not_contains("Hire a")
	assert_bool(_save.load_from_file(_path)).is_true()
	assert_bool(_panel.hint_card().visible).is_true()
	assert_bool(_panel.hint_label().visible).is_true()
	assert_str(_panel.hint_label().text).contains("Hire a check-in agent")
	assert_str(_panel.hint_label().text).contains("Hire a security officer")
	assert_str(_panel.hint_label().text).is_equal(_panel.hint_text())
	assert_int(_main.find_children("StaffHintCard", "", true, false).size()).is_equal(1)
	var lines := _panel.hint_label().text.split("\n")
	var seen := {}
	for line in lines:
		assert_bool(seen.has(line)).is_false()
		seen[line] = true


func test_a_second_load_does_not_duplicate_the_staff_hint() -> void:
	(_main.get_node("PassengerHud") as PassengerHud).press_starter_terminal()
	SaveTestKit.step(_main)
	assert_bool(_save.load_from_file(_path)).is_true()
	var first := _panel.hint_label().text
	assert_bool(_save.load_from_file(_path)).is_true()
	assert_str(_panel.hint_label().text).is_equal(first)
	assert_int(_main.find_children("StaffHintCard", "", true, false).size()).is_equal(1)
