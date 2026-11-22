class_name TestClockHolders
extends GdUnitTestSuite
## Modal dialogs (UnlockGuide) still hold the clock through ClockHolds, while
## BuildSession and OfferPanel never take or release ClockHolds holds (ruling
## player-owns-clock-and-persistent-build-undo-no-auto-pause-on-trays-offers-planner-direct-delete).

var _port: SubViewport
var _clock: SimClock
var _panel: OfferPanel
var _mode: BuildMode
var _session: BuildSession
var _guide: UnlockGuide


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	# Out of the tree: the sheet reads only its board, and a desk with no clock
	# would complain on _ready.
	var desk: OfferDesk = auto_free(OfferDesk.new())
	desk.runway = Runway.new(PlaneClasses.LARGE)
	var sim := FlightSim.new()
	sim.open_airport()
	_port.add_child(sim)
	_panel = OfferPanel.new()
	_panel.desk = desk
	_panel.flights = sim
	_panel.clock = _clock
	_port.add_child(_panel)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_port.add_child(_mode)
	_session = BuildSession.new()
	_session.build_mode = _mode
	_session.clock = _clock
	_port.add_child(_session)
	_guide = UnlockGuide.new()
	_guide.clock = _clock
	_port.add_child(_guide)


func after_test() -> void:
	_port.free()


## What the HUD's keys do: 0 pauses, 1 to 3 run at that speed.
func _press_speed(value: int) -> void:
	_clock.set_paused(value == 0)
	if value > 0:
		_clock.set_speed(value)


func _start_building() -> void:
	_session.set_building(true)
	_session.sync()


func _ticks_after(seconds: float) -> int:
	var before := _clock.tick
	_clock.advance(seconds)
	return _clock.tick - before


func test_build_mode_and_offers_take_no_holds_and_leave_clock_running() -> void:
	_press_speed(3)
	_start_building()
	_panel.open()
	assert_bool(_session.active).is_true()
	assert_bool(_panel.is_open()).is_true()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_bool(_clock.paused).is_false()
	assert_int(_ticks_after(0.11)).is_equal(6)
	_panel.close()
	_session.set_building(false)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_game_paused_before_both_stays_paused_after_both() -> void:
	_press_speed(2)
	_press_speed(0)
	_start_building()
	_panel.open()
	_session.set_building(false)
	_panel.close()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(2)


func test_the_unlock_dialog_still_holds_the_clock_regardless_of_build_mode_or_offers() -> void:
	_press_speed(3)
	_start_building()
	_panel.open()
	_guide.open_dialog([2])
	assert_bool(_guide.is_open()).is_true()
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_session.set_building(false)
	_panel.close()
	assert_bool(_clock.paused).is_true()
	_guide.dismiss()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_a_resume_while_the_unlock_dialog_is_open_waits_for_it_to_close() -> void:
	_press_speed(0)
	_guide.open_dialog([2])
	_press_speed(3)
	assert_bool(_clock.paused).is_true()
	assert_int(_ticks_after(0.11)).is_equal(0)
	_guide.dismiss()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_offers_opened_under_the_unlock_dialog_opens_immediately_without_a_hold() -> void:
	_press_speed(1)
	_guide.open_dialog([2])
	_panel.open()
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_true()
	_guide.dismiss()
	assert_bool(_clock.paused).is_false()
	_panel.close()
	assert_bool(_clock.paused).is_false()


## The old dialog's layer leaves the tree a frame after a replacement; that
## must not close the new dialog or end its hold.
func test_a_replaced_unlock_dialog_leaving_never_closes_the_new_one() -> void:
	_press_speed(2)
	_guide.open_dialog([2])
	var old_layer := _guide.dialog().get_parent()
	_guide.open_dialog([3])
	var current := _guide.dialog()
	assert_object(current.get_parent()).is_not_same(old_layer)
	for i in 5:
		if not is_instance_valid(old_layer):
			break
		await get_tree().process_frame
	assert_bool(is_instance_valid(old_layer)).is_false()
	assert_bool(_guide.is_open()).is_true()
	assert_object(_guide.dialog()).is_same(current)
	assert_bool(_clock.paused).is_true()
	assert_int(_ticks_after(0.11)).is_equal(0)
	# Control: closing the new dialog releases the hold.
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_ticks_after(0.11)).is_equal(4)


func test_a_load_drops_every_holders_hold_and_the_clock_comes_back_paused_at_1x() -> void:
	_press_speed(3)
	_start_building()
	_panel.open()
	_guide.open_dialog([2])
	var data := _clock.to_snapshot()
	data["paused"] = true
	data["speed"] = 1
	assert_bool(_clock.from_snapshot(data)).is_true()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(1)
	_press_speed(2)
	assert_bool(_clock.paused).is_false()
