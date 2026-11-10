class_name TestAlertRailFit
extends GdUnitTestSuite
## How the right rail (AlertStack, decision hud-grid-and-rails-one-spacing-grid-
## centred-top-row-right-ra, part 3) decides what fits, in PassengerHud at
## layout px 1536x864: the newest card must fit too, a card is measured through
## real container layout (a row of wrapped labels included), a steady rail
## measures nothing frame after frame, and a load drops a flight result still
## waiting to be posted.

const VIEW := Vector2i(1536, 864)

var _port: SubViewport
var _world: PassengerTestWorld
var _hud: PassengerHud
var _save: SaveGame


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_port = SubViewport.new()
	_port.size = VIEW
	add_child(_port)
	_save = SaveGame.new()
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	_hud.save_game = _save
	_hud.alert_settings_path = SaveTestKit.run_path("alert_rail_fit_setting")
	_port.add_child(_hud)


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	_port.free()
	_save.free()
	_world.free_all()


func _stack() -> AlertStack:
	return _hud.find_child("AlertStack", false, false) as AlertStack


func _settle() -> void:
	for i in 3:
		_hud.refresh()
		await get_tree().process_frame


## The rail's lowest y with the build tray closed.
func _stop() -> float:
	return VIEW.y - (BuildMenu.MARGIN + BuildMenu.BAR_H) - HudLayout.GROUP_GAP


## The room the cards have: from under the header row to the stop line.
func _room() -> float:
	var stack := _stack()
	var header := stack.find_child("AlertsHeader", false, false) as Control
	var top := (
		stack.global_position.y
		+ header.get_combined_minimum_size().y
		+ stack.get_theme_constant("separation")
	)
	return _stop() - top


func _block(height: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, height)
	return card


## A card holding a row of two wrapped labels that share its width.
func _row_card() -> PanelContainer:
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	card.add_child(row)
	for i in 2:
		var label := Label.new()
		label.text = "Check-in queue full: three desks full, passengers wait outside (%d)" % i
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
	return card


func test_a_newest_card_too_tall_for_the_room_is_hidden_and_counted() -> void:
	await _settle()
	var stack := _stack()
	var card := _block(_room() + HudLayout.UNIT)
	stack.post_notice(&"huge", card, 0.0, "Huge", "")
	var ever := card.is_visible_in_tree()
	for i in 3:
		_hud.refresh()
		ever = ever or card.is_visible_in_tree()
		await get_tree().process_frame
		ever = ever or card.is_visible_in_tree()
	var rail := stack.room_rect()
	print(
		(
			"FIT_HUGE room=%.0f shown=%s more=%d rail=%s"
			% [_room(), stack.shown_keys(), stack.more_count(), rail]
		)
	)
	assert_bool(ever).is_false()
	assert_array(stack.shown_keys()).is_empty()
	assert_int(stack.more_count()).is_equal(1)
	assert_float(rail.end.y).is_less_equal(_stop())
	# Control: alone, a card one unit shorter than the room shows.
	stack.drop_notice(&"huge")
	var fits := _block(_room() - HudLayout.UNIT)
	stack.post_notice(&"fits", fits, 0.0, "Fits", "")
	await _settle()
	assert_array(stack.shown_keys()).is_equal([&"fits"])


## A row of two wrapped labels near the stop line: measured at the full width
## each it would look short enough; laid out for real each has half, wraps more
## and does not fit. The newest card is a block sized so the row misses the room
## by a little; with a block a little shorter it fits.
func test_a_row_of_wrapped_labels_is_measured_as_it_lays_out() -> void:
	await _settle()
	var stack := _stack()
	var probe := _row_card()
	stack.post_notice(&"probe", probe, 0.0, "Probe", "")
	await _settle()
	var real := probe.size.y
	var label := probe.find_child("*", true, false).get_child(0) as Control
	print("FIT_ROW real=%.0f label=%s" % [real, label.size])
	# Control: the labels really share the row, so each wraps at under half.
	assert_float(label.size.x).is_less(HudLayout.RAIL_W / 2.0)
	stack.drop_notice(&"probe")
	var gap := float(stack.find_child("AlertCards", false, false).get_theme_constant("separation"))
	for miss in [HudLayout.UNIT, -HudLayout.UNIT]:
		var row := _row_card()
		stack.post_notice(&"row", row, 0.0, "Row", "")
		var block := _block(_room() - gap - real + miss)
		stack.post_notice(&"block", block, 0.0, "Block", "")
		var ever := row.is_visible_in_tree()
		for i in 3:
			_hud.refresh()
			ever = ever or row.is_visible_in_tree()
			await get_tree().process_frame
			ever = ever or row.is_visible_in_tree()
		print("FIT_ROW miss=%d shown=%s ever=%s" % [miss, stack.shown_keys(), ever])
		assert_bool(ever).is_equal(miss < 0)
		assert_bool(stack.shown_keys().has(&"row")).is_equal(miss < 0)
		assert_float(stack.room_rect().end.y).is_less_equal(_stop())
		stack.drop_notice(&"row")
		stack.drop_notice(&"block")


func test_a_steady_rail_does_not_measure_again_every_frame() -> void:
	var stack := _stack()
	stack.post_notice(&"a", _row_card(), 0.0, "A", "")
	stack.post_notice(&"b", _block(64.0), 0.0, "B", "")
	for i in 6:
		_hud.refresh()
		await get_tree().process_frame
	var settled := stack.measures
	for i in 5:
		_hud.refresh()
		await get_tree().process_frame
	print("FIT_STEADY settled=%d after=%d" % [settled, stack.measures])
	assert_int(settled).is_greater(0)
	assert_int(stack.measures).is_equal(settled)
	# Control: a new card is measured.
	stack.post_notice(&"c", _block(64.0), 0.0, "C", "")
	_hud.refresh()
	assert_int(stack.measures).is_greater(settled)


## Doors close (the result waits for the next refresh), then a save loads: the
## waiting result belongs to the old world and never reaches the rail.
func test_a_load_drops_a_result_still_waiting_to_be_posted() -> void:
	_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(21)
	_save.loaded.emit(true)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_false()
	assert_int(_stack().history_lines().size()).is_equal(0)


func test_a_failed_load_keeps_the_waiting_result() -> void:
	_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(21)
	_save.loaded.emit(false)
	_hud.refresh()
	assert_bool(_hud.is_result_open()).is_true()
