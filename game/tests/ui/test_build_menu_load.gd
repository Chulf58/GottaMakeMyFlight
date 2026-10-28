class_name TestBuildMenuLoad
extends GdUnitTestSuite
## A successful load ends the status line's message hold and drops the wages-paid
## message that waited behind a rescue message: both belong to the world that was
## replaced (Sol re-check of da10a54). A failed load changes nothing.

var _port: SubViewport
var _mode: BuildMode
var _save: SaveGame
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_save = SaveGame.new()
	_port.add_child(_save)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_menu.save_game = _save
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func _text() -> String:
	return _menu.status_label().text


func _hold_rescue_with_wages_waiting() -> void:
	_menu._on_granted(50, "Rescue grant")
	_menu._on_wages_paid(60, 0)
	assert_str(_text()).is_equal("Rescue grant")


func test_a_load_during_a_rescue_hold_ends_it_and_drops_the_waiting_wages() -> void:
	_hold_rescue_with_wages_waiting()
	_save.loaded.emit(true)
	assert_str(_text()).is_equal(_mode.status_text())
	assert_str(_text()).not_contains("Rescue")
	_menu.end_grant_hold()
	assert_str(_text()).not_contains("Wages paid")
	assert_str(_text()).is_equal(_mode.status_text())


func test_the_old_timer_firing_after_a_load_shows_no_pre_load_notice() -> void:
	_hold_rescue_with_wages_waiting()
	var old_generation: int = _menu._hold_generation
	_save.loaded.emit(true)
	_menu._on_hold_timeout(old_generation)
	assert_str(_text()).not_contains("Wages paid")
	assert_str(_text()).is_equal(_mode.status_text())


func test_a_load_during_a_wages_hold_ends_it() -> void:
	_menu._on_wages_paid(60, 0)
	assert_str(_text()).is_equal("Wages paid: 60")
	_save.loaded.emit(true)
	assert_str(_text()).not_contains("Wages paid")


func test_a_message_after_a_load_holds_as_usual() -> void:
	_hold_rescue_with_wages_waiting()
	_save.loaded.emit(true)
	_menu._on_granted(50, "Second rescue")
	assert_str(_text()).is_equal("Second rescue")
	_menu.end_grant_hold()
	assert_str(_text()).is_equal(_mode.status_text())


func test_a_failed_load_keeps_the_hold_and_the_waiting_wages() -> void:
	_hold_rescue_with_wages_waiting()
	_save.loaded.emit(false)
	assert_str(_text()).is_equal("Rescue grant")
	_menu.end_grant_hold()
	assert_str(_text()).is_equal("Wages paid: 60")
