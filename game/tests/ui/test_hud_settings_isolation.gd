class_name TestHudSettingsIsolation
extends GdUnitTestSuite
## A gdUnit4 run never reads or writes the player's user://hud_settings.cfg
## (anti-pattern a-test-that-builds-passengerhud-or-main-tscn-on-the-default,
## board 6459e892). A suite that builds a PassengerHud or main.tscn on the
## default settings path sees defaults, whatever the player last toggled in a
## playtest, and a toggle it makes never reaches the player's file.
##
## These tests write the REAL default path with a raw FileAccess, since
## HudFlagSetting is the thing under test. The player's file is backed up before
## each test and put back byte for byte afterwards, or deleted if it did not
## exist.

const PLAYER_CHOICES := (
	"[hud]\n\ndepartures_board=false\nalert_cards=false\nmood_overlay=true\n"
	+ "need_icons=false\ncamera_angle=2\n"
)

var _world: PassengerTestWorld
var _existed := false
var _backup := PackedByteArray()


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_existed = FileAccess.file_exists(HudFlagSetting.PATH)
	if _existed:
		_backup = FileAccess.get_file_as_bytes(HudFlagSetting.PATH)
	_write_player_file(PLAYER_CHOICES.to_utf8_buffer())


func after_test() -> void:
	if _existed:
		_write_player_file(_backup)
	else:
		DirAccess.remove_absolute(HudFlagSetting.PATH)
	if _world != null:
		_world.free_all()
		_world = null


func _write_player_file(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(HudFlagSetting.PATH, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_buffer(bytes)
	file.close()


func _player_file() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(HudFlagSetting.PATH)


func _board_on_defaults() -> DeparturesBoard:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	var hud := PassengerHud.new()
	hud.clock = _world.clock
	hud.flights = _world.flights
	hud.sim = _world.sim
	add_child(hud)
	auto_free(hud)
	return hud.find_child("DeparturesBoard", true, false) as DeparturesBoard


func test_the_departures_board_ignores_the_players_hidden_choice() -> void:
	var board := _board_on_defaults()
	assert_object(board).is_not_null()
	assert_bool(board.is_shown()).is_true()


func test_a_toggle_on_the_default_path_leaves_the_players_file_alone() -> void:
	var board := _board_on_defaults()
	board.set_shown(false)
	board.set_shown(true)
	assert_array(_player_file()).is_equal(PLAYER_CHOICES.to_utf8_buffer())


func test_every_hud_setting_reads_its_default_from_the_default_path() -> void:
	var who := "test"
	var path := HudFlagSetting.PATH
	assert_bool(HudFlagSetting.load_flag(path, DeparturesBoard.SETTING_KEY, true, who)).is_true()
	assert_bool(HudFlagSetting.load_flag(path, AlertStack.SETTING_KEY, true, who)).is_true()
	assert_bool(HudFlagSetting.load_flag(path, MoodOverlay.SETTING_KEY, false, who)).is_false()
	assert_bool(HudFlagSetting.load_flag(path, NeedIconsToggle.SETTING_KEY, true, who)).is_true()
	assert_int(HudFlagSetting.load_int(path, TycoonCamera.ANGLE_KEY, -1, who)).is_equal(-1)


func test_a_save_to_the_default_path_does_not_reach_the_players_file() -> void:
	HudFlagSetting.save_flag(HudFlagSetting.PATH, "hints", false, "test")
	HudFlagSetting.save_int(HudFlagSetting.PATH, TycoonCamera.ANGLE_KEY, 1, "test")
	assert_array(_player_file()).is_equal(PLAYER_CHOICES.to_utf8_buffer())


func test_an_explicit_path_still_round_trips() -> void:
	var path := SaveTestKit.run_path("hud_settings_isolation")
	HudFlagSetting.save_flag(path, "hints", false, "test")
	assert_bool(HudFlagSetting.load_flag(path, "hints", true, "test")).is_false()
	DirAccess.remove_absolute(path)
