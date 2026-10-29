class_name TestBuildMenuOffers
extends GdUnitTestSuite
## Build mode and the Offers sheet both pause the clock (decisions build-mode-
## pauses-the-game-while-a-build-tray-is-open-closin and the-airline-offers-
## panel-pauses-the-game-while-it-is-open) and must compose: the sheet closing
## inside build mode leaves the game paused, and a tray opened over the sheet
## ends with the speed the player had before the sheet.

const STRUCTURE := 0

var _port: SubViewport
var _clock: SimClock
var _mode: BuildMode
var _menu: BuildMenu
var _panel: OfferPanel


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	var desk := OfferDesk.new()
	var sim := FlightSim.new()
	_port.add_child(desk)
	_port.add_child(sim)
	var saved := TestOfferBoard.save_of(TestOfferBoard.day_records(0, [600, 660, 1200]))
	assert_bool(desk.board.from_snapshot(saved)).is_true()
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_menu.clock = _clock
	_port.add_child(_menu)
	_panel = OfferPanel.new()
	_panel.desk = desk
	_panel.flights = sim
	_panel.clock = _clock
	_panel.build_mode = _mode
	_panel.save_game = SaveGame.new()
	_port.add_child(_panel.save_game)
	_port.add_child(_panel)


func after_test() -> void:
	_port.free()


func _press_speed(value: int) -> void:
	_clock.set_paused(value == 0)
	if value > 0:
		_clock.set_speed(value)


func test_closing_the_offers_sheet_inside_build_mode_keeps_the_game_paused() -> void:
	_press_speed(2)
	_menu.press_category(STRUCTURE)
	_menu.build_session.sync()
	_panel.open()
	await get_tree().process_frame
	_panel.close()
	_menu.build_session.sync()
	assert_bool(_menu.build_session.active).is_true()
	assert_bool(_clock.paused).is_true()
	_menu.press_category(STRUCTURE)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_a_tray_opened_over_the_offers_sheet_restores_the_speed_before_it() -> void:
	_press_speed(3)
	_panel.open()
	_menu.press_category(STRUCTURE)
	assert_bool(_panel.is_open()).is_false()
	_menu.build_session.sync()
	assert_bool(_menu.build_session.active).is_true()
	assert_bool(_clock.paused).is_true()
	_menu.press_category(STRUCTURE)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)
