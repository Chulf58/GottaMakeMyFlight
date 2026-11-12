class_name TestIntroLoad
extends GdUnitTestSuite
## A load under the open new-game intro (decision quicksave-f5-and-quickload-f8-
## work-while-a-dialog-is-open): the intro ends the way the other dialogs do on
## a load. It is gone, the camera has its input back, no hold is left, and the
## new-game incident question does not open, so the loaded game's incident
## setting stays as the save had it. One boot of main.tscn for the file.

const SEED := 12_112_026

var _path := SaveTestKit.run_path("test_intro_load")
var _main: Node
var _save: SaveGame
var _hud: PassengerHud
var _director: IncidentDirector
var _shown_before: bool


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_save.quick_save_path = _path
	_hud = _main.get_node("PassengerHud")
	_director = _main.get_node("IncidentDirector")


func after() -> void:
	_main.free()


func before_test() -> void:
	_shown_before = IntroDialogue.shown_this_session
	IntroDialogue.shown_this_session = false


func after_test() -> void:
	IntroDialogue.shown_this_session = _shown_before
	for path in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_a_load_under_the_intro_closes_it_and_asks_nothing() -> void:
	var camera: TycoonCamera = _main.get_node("TycoonCamera")
	var menu: GameMenu = _main.get_node("GameMenu")
	var clock: SimClock = _main.get_node("SimClock")
	_director.set_enabled(true)
	assert_bool(_save.quick_save()).is_true()
	_director.set_enabled(false)
	assert_bool(_hud.open_intro()).is_true()
	assert_bool(_hud.intro() != null).is_true()
	assert_bool(camera.is_processing()).is_false()
	assert_bool(_save.quick_load()).is_true()
	assert_bool(_hud.intro() == null).is_true()
	assert_bool(menu.question() == null).is_true()
	assert_bool(camera.is_processing()).is_true()
	assert_int(clock.holds.count()).is_equal(0)
	assert_bool(_director.is_enabled()).is_true()
