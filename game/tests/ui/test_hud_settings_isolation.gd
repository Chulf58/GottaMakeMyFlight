class_name TestHudSettingsIsolation
extends GdUnitTestSuite
## A gdUnit4 run never reads or writes the player's user://hud_settings.cfg
## (anti-pattern a-test-that-builds-passengerhud-or-main-tscn-on-the-default,
## board 6459e892). A suite that builds a PassengerHud or main.tscn on the
## default settings path sees defaults, whatever the player last toggled in a
## playtest.
##
## These tests never read, seed or write HudFlagSetting.PATH themselves: a
## crash or a killed run must not be able to leave the player's choices
## replaced. To watch the shield work they point HudFlagSetting.protected_path at
## a file of their own, seed it with the opposite of every default, and check that
## a load gives the default and a save leaves the bytes alone.

const KEY_FLAG := "departures_board"
const KEY_OFF_BY_DEFAULT := "mood_overlay"
const KEY_STEP := "camera_angle"

var _world: PassengerTestWorld
var _hud: PassengerHud
var _seeded := ""


func before() -> void:
	PassengerTestWorld.tracker = self
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	add_child(_hud)


func after() -> void:
	_hud.free()
	_world.free_all()
	PassengerTestWorld.tracker = null


func after_test() -> void:
	HudFlagSetting.protected_path = HudFlagSetting.PATH
	if _seeded != "":
		DirAccess.remove_absolute(_seeded)
		_seeded = ""


## A settings file of this run, holding the opposite of every default asked for below.
func _seed_opposites() -> String:
	_seeded = SaveTestKit.run_path("hud_isolation_seed")
	var cfg := ConfigFile.new()
	cfg.set_value(HudFlagSetting.SECTION, KEY_FLAG, false)
	cfg.set_value(HudFlagSetting.SECTION, KEY_OFF_BY_DEFAULT, true)
	cfg.set_value(HudFlagSetting.SECTION, KEY_STEP, 2)
	assert_int(cfg.save(_seeded)).is_equal(OK)
	HudFlagSetting.protected_path = _seeded
	return _seeded


func test_the_player_file_is_shielded_in_a_script_run() -> void:
	assert_str(HudFlagSetting.protected_path).is_equal(HudFlagSetting.PATH)
	assert_bool(HudFlagSetting.is_shielded(HudFlagSetting.PATH)).is_true()


func test_an_explicit_path_is_not_shielded() -> void:
	assert_bool(HudFlagSetting.is_shielded(SaveTestKit.run_path("hud_isolation"))).is_false()


func test_a_load_from_the_protected_file_gives_the_default_not_what_is_saved() -> void:
	var path := _seed_opposites()
	var who := "test"
	assert_bool(HudFlagSetting.load_flag(path, KEY_FLAG, true, who)).is_true()
	assert_bool(HudFlagSetting.load_flag(path, KEY_OFF_BY_DEFAULT, false, who)).is_false()
	assert_int(HudFlagSetting.load_int(path, KEY_STEP, 1, who)).is_equal(1)


func test_a_save_to_the_protected_file_leaves_its_bytes_alone() -> void:
	var path := _seed_opposites()
	var before := FileAccess.get_file_as_bytes(path)
	assert_int(before.size()).is_greater(0)
	HudFlagSetting.save_flag(path, KEY_FLAG, true, "test")
	HudFlagSetting.save_flag(path, "hints", false, "test")
	HudFlagSetting.save_int(path, KEY_STEP, 0, "test")
	assert_array(FileAccess.get_file_as_bytes(path)).is_equal(before)


func test_the_departures_board_is_shown_on_the_default_path() -> void:
	var board := _hud.find_child("DeparturesBoard", true, false) as DeparturesBoard
	assert_object(board).is_not_null()
	assert_bool(board.is_shown()).is_true()


func test_an_explicit_path_still_round_trips() -> void:
	var path := SaveTestKit.run_path("hud_settings_isolation")
	HudFlagSetting.save_flag(path, "hints", false, "test")
	assert_bool(HudFlagSetting.load_flag(path, "hints", true, "test")).is_false()
	DirAccess.remove_absolute(path)
