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
## replaced. They show the shield through its answers (opposing defaults come
## back as given, so nothing was read from a file). That a save to PATH is
## dropped is not tested, because seeing it needs the real file read or a real
## write if the shield were ever broken.

var _world: PassengerTestWorld
var _hud: PassengerHud


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


func test_the_default_path_is_shielded_in_a_script_run() -> void:
	assert_bool(HudFlagSetting.is_shielded(HudFlagSetting.PATH)).is_true()


func test_an_explicit_path_is_not_shielded() -> void:
	assert_bool(HudFlagSetting.is_shielded(SaveTestKit.run_path("hud_isolation"))).is_false()


func test_the_default_path_gives_back_whatever_default_it_is_asked() -> void:
	var path := HudFlagSetting.PATH
	var key := DeparturesBoard.SETTING_KEY
	assert_bool(HudFlagSetting.load_flag(path, key, true, "test")).is_true()
	assert_bool(HudFlagSetting.load_flag(path, key, false, "test")).is_false()
	assert_int(HudFlagSetting.load_int(path, TycoonCamera.ANGLE_KEY, 1, "test")).is_equal(1)
	assert_int(HudFlagSetting.load_int(path, TycoonCamera.ANGLE_KEY, 2, "test")).is_equal(2)


func test_the_departures_board_is_shown_on_the_default_path() -> void:
	var board := _hud.find_child("DeparturesBoard", true, false) as DeparturesBoard
	assert_object(board).is_not_null()
	assert_bool(board.is_shown()).is_true()


func test_an_explicit_path_still_round_trips() -> void:
	var path := SaveTestKit.run_path("hud_settings_isolation")
	HudFlagSetting.save_flag(path, "hints", false, "test")
	assert_bool(HudFlagSetting.load_flag(path, "hints", true, "test")).is_false()
	DirAccess.remove_absolute(path)
