class_name TestOfferPanelPause
extends GdUnitTestSuite
## OfferPanel leaves the sim clock untouched on open, close, toggle, load, and
## tree exit (ruling
## player-owns-clock-and-persistent-build-undo-no-auto-pause-on-trays-offers-planner-direct-delete).

var _port: SubViewport
var _desk: OfferDesk
var _sim: FlightSim
var _clock: SimClock
var _panel: OfferPanel
var _save: SaveGame


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_desk = OfferDesk.new()
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_sim = FlightSim.new()
	_sim.open_airport()
	_port.add_child(_clock)
	_port.add_child(_desk)
	_port.add_child(_sim)
	_load(TestOfferBoard.day_records(0, [600, 660, 1200]))
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_save = SaveGame.new()
	_port.add_child(_save)
	_panel.clock = _clock
	_panel.save_game = _save
	_port.add_child(_panel)


func _load(offers: Array) -> void:
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()


func after_test() -> void:
	_port.free()


## What the HUD's keys do: 0 pauses, 1 to 3 run at that speed.
func _press_speed(value: int) -> void:
	_clock.set_paused(value == 0)
	if value > 0:
		_clock.set_speed(value)


func test_opening_and_closing_leaves_a_running_game_running() -> void:
	_press_speed(1)
	_panel.open()
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	_panel.close()
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(1)


func test_opening_and_closing_leaves_triple_speed_untouched() -> void:
	_press_speed(3)
	_panel.open()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_opening_and_closing_leaves_a_paused_game_paused() -> void:
	_press_speed(2)
	_press_speed(0)
	_panel.open()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(0)
	_panel.close()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(2)


func test_the_toggle_button_leaves_clock_alone() -> void:
	_press_speed(2)
	_panel.toggle_button().pressed.emit()
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_false()
	_panel.toggle_button().pressed.emit()
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_changing_speed_while_open_does_not_close_and_stays_on_close() -> void:
	_press_speed(1)
	_panel.open()
	_press_speed(3)
	await get_tree().process_frame
	assert_bool(_panel.is_open()).is_true()
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_closing_a_closed_sheet_leaves_the_clock_alone() -> void:
	_press_speed(3)
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)
	_press_speed(0)
	_panel.close()
	assert_bool(_clock.paused).is_true()


func test_a_panel_with_no_clock_still_opens_and_closes() -> void:
	var bare := OfferPanel.new()
	bare.desk = _desk
	bare.flights = _sim
	_port.add_child(bare)
	bare.open()
	assert_bool(bare.is_open()).is_true()
	bare.close()
	assert_bool(bare.is_open()).is_false()


func _load_while_open(paused: bool, speed: int) -> void:
	_clock.set_speed(speed)
	_clock.set_paused(paused)
	_save.loaded.emit(true)


func test_loading_a_running_save_closes_the_sheet_and_keeps_it_running() -> void:
	_press_speed(2)
	_panel.open()
	_load_while_open(false, 2)
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_loading_a_paused_save_at_the_same_speed_stays_paused() -> void:
	_press_speed(2)
	_panel.open()
	_load_while_open(true, 2)
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(2)


func test_loading_a_paused_save_at_another_speed_stays_paused_at_that_speed() -> void:
	_press_speed(1)
	_panel.open()
	_load_while_open(true, 3)
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(3)


func test_a_failed_load_leaves_the_sheet_open_and_clock_unchanged() -> void:
	_press_speed(3)
	_panel.open()
	_save.loaded.emit(false)
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_false()
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_panel_leaving_the_tree_while_open_leaves_the_clock_alone() -> void:
	_press_speed(3)
	_panel.open()
	_panel.free()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_panel_leaving_the_tree_keeps_a_game_that_was_paused_paused() -> void:
	_press_speed(0)
	_panel.open()
	_panel.free()
	assert_bool(_clock.paused).is_true()
