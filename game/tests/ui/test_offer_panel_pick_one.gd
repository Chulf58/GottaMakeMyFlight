class_name TestOfferPanelPickOne
extends GdUnitTestSuite
## Side-by-side Pick-1-of-3 OfferPanel layout, Pass action, and spin-away
## discard animation (decision airline-offers-pick-1-of-3-side-by-side-spin-
## away-discard).

var _port: SubViewport
var _desk: OfferDesk
var _sim: FlightSim
var _panel: OfferPanel


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_desk = OfferDesk.new()
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_sim = FlightSim.new()
	_sim.open_airport()
	_port.add_child(_desk)
	_port.add_child(_sim)
	var offers := TestOfferBoard.day_records(0, [600, 780, 1200])
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)


func after_test() -> void:
	_port.free()


func test_daily_cards_are_laid_out_side_by_side_within_viewport_at_supported_sizes() -> void:
	for layout: Vector2i in [Vector2i(1920, 1080), Vector2i(1536, 864), Vector2i(1280, 720)]:
		_port.size = layout
		_panel.open()
		await get_tree().process_frame
		await get_tree().process_frame
		assert_bool(_panel.daily_row() is HBoxContainer).is_true()
		var r0 := _panel.card("O0N1").get_global_rect()
		var r1 := _panel.card("O0N2").get_global_rect()
		var r2 := _panel.card("O0N3").get_global_rect()
		assert_float(r0.position.x).is_less(r1.position.x)
		assert_float(r1.position.x).is_less(r2.position.x)
		assert_float(r0.position.y).is_equal_approx(r1.position.y, 1.0)
		assert_float(r1.position.y).is_equal_approx(r2.position.y, 1.0)
		var sheet_rect := _panel.sheet().get_global_rect()
		assert_bool(Rect2(Vector2.ZERO, Vector2(layout)).encloses(sheet_rect)).is_true()
		assert_bool(sheet_rect.encloses(r0)).is_true()
		assert_bool(sheet_rect.encloses(r1)).is_true()
		assert_bool(sheet_rect.encloses(r2)).is_true()
		_panel.close()


func test_pass_button_declines_all_daily_offers_and_spins_all_away() -> void:
	_panel.open()
	await get_tree().process_frame
	_panel.pass_button().pressed.emit()
	assert_array(_sim.contract_ids()).is_empty()
	for id in ["O0N1", "O0N2", "O0N3"]:
		assert_str(_desk.board.offer_of(id)["status"]).is_equal(OfferBoard.DECLINED)
	assert_array(_desk.board.open_offers()).is_empty()
	assert_bool(_panel.is_discard_animating()).is_true()
	await get_tree().create_timer(0.20).timeout
	for id in ["O0N1", "O0N2", "O0N3"]:
		var c := _panel.card(id)
		assert_float(absf(c.rotation)).is_greater(0.01)
		assert_float(c.modulate.a).is_less(1.0)
	var safety := 0
	while _panel.is_discard_animating() and safety < 30:
		safety += 1
		await get_tree().create_timer(0.05).timeout
	await get_tree().process_frame
	assert_array(_panel.card_ids()).is_empty()
	assert_str(_panel.message()).is_equal(OfferPanel.EMPTY_TEXT)
	assert_str(_panel.toggle_button().text).is_equal("Offers (0)")


func test_early_close_mid_discard_animation_cleans_up_without_orphans() -> void:
	_panel.open()
	await get_tree().process_frame
	_panel.accept_button("O0N1").pressed.emit()
	assert_bool(_panel.is_discard_animating()).is_true()
	_panel.close()
	assert_bool(_panel.is_discard_animating()).is_false()
	assert_object(_panel.discard_tween()).is_null()
	assert_array(_panel.card_ids()).is_empty()
	await get_tree().process_frame
