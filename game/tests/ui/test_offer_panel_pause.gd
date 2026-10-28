class_name TestOfferPanelPause
extends GdUnitTestSuite
## OfferPanel pauses the sim clock while the sheet is open and gives the player
## back the speed they had (paused included) when it closes. A speed the player
## picks while it is open wins (decision the-airline-offers-panel-pauses-the-
## game-while-it-is-open).

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
	_sim = FlightSim.new()
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


func test_opening_pauses_and_closing_restores_a_running_game() -> void:
	_press_speed(1)
	_panel.open()
	assert_bool(_clock.paused).is_true()
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(1)


func test_closing_restores_triple_speed() -> void:
	_press_speed(3)
	_panel.open()
	assert_bool(_clock.paused).is_true()
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_closing_leaves_a_game_that_was_paused_paused() -> void:
	_press_speed(2)
	_press_speed(0)
	_panel.open()
	_panel.close()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(2)


func test_the_toggle_button_pauses_and_restores_the_same_way() -> void:
	_press_speed(2)
	_panel.toggle_button().pressed.emit()
	assert_bool(_clock.paused).is_true()
	_panel.toggle_button().pressed.emit()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_a_speed_picked_while_open_is_kept_on_close() -> void:
	_press_speed(1)
	_panel.open()
	_press_speed(3)
	await get_tree().process_frame
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_speed_picked_while_open_beats_a_paused_game_from_before() -> void:
	_press_speed(2)
	_press_speed(0)
	_panel.open()
	_press_speed(3)
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_resuming_the_same_speed_while_open_is_kept_on_close() -> void:
	_press_speed(2)
	_panel.open()
	_press_speed(2)
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_pausing_again_after_a_resume_while_open_is_kept_on_close() -> void:
	_press_speed(2)
	_panel.open()
	_press_speed(2)
	await get_tree().process_frame
	_press_speed(0)
	await get_tree().process_frame
	_panel.close()
	assert_bool(_clock.paused).is_true()


func test_closing_a_closed_sheet_leaves_the_clock_alone() -> void:
	_press_speed(3)
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)
	_press_speed(0)
	_panel.close()
	assert_bool(_clock.paused).is_true()


func test_opening_twice_still_restores_the_speed_from_before_the_first_open() -> void:
	_press_speed(3)
	_panel.open()
	_panel.open()
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_panel_with_no_clock_still_opens_and_closes() -> void:
	var bare := OfferPanel.new()
	bare.desk = _desk
	bare.flights = _sim
	_port.add_child(bare)
	bare.open()
	assert_bool(bare.is_open()).is_true()
	bare.close()
	assert_bool(bare.is_open()).is_false()


## A successful load puts the saved clock in place and closes the sheet; the
## state held from before the load is never written back over it.
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


func test_a_failed_load_leaves_the_sheet_open_and_the_pause_held() -> void:
	_press_speed(3)
	_panel.open()
	_save.loaded.emit(false)
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_true()
	_panel.close()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_panel_leaving_the_tree_while_open_restores_the_clock() -> void:
	_press_speed(3)
	_panel.open()
	_panel.free()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_panel_leaving_the_tree_after_the_player_took_over_leaves_the_clock() -> void:
	_press_speed(1)
	_panel.open()
	_press_speed(3)
	_panel.free()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_panel_leaving_the_tree_keeps_a_game_that_was_paused_paused() -> void:
	_press_speed(0)
	_panel.open()
	_panel.free()
	assert_bool(_clock.paused).is_true()
