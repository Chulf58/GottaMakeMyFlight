class_name TestOfferPanelTraits
extends GdUnitTestSuite
## Each offer card has one trait line under its verdict row: the upside in
## HudGoodText and the downside in HudProblemText, or a muted "Plain terms" on
## the plain offer (decision airline-offer-traits-each-offer-pairs-an-upside-
## with-a-downs).

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
	_port.add_child(_desk)
	_port.add_child(_sim)
	var records := TestOfferBoard.day_records(0, [600, 720, 840])
	records[0]["traits"] = {"up": "top_fare", "down": "rush_crowd", "level": 2}
	records[0]["fee_per_passenger"] = 32
	records[2]["traits"] = {}
	records[2]["fee_per_passenger"] = 23
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(records))).is_true()
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)
	_panel.open()


func after_test() -> void:
	_port.free()


func _label(id: String, side: String) -> Label:
	return _panel.trait_row(id).get_node(side)


func test_a_paired_offer_shows_its_upside_and_downside_in_their_colours() -> void:
	assert_str(_label("O0N1", "Up").text).is_equal("Top fare +30%")
	assert_str(_label("O0N1", "Down").text).is_equal("Big rush crowd")
	assert_str(_label("O0N1", "Up").theme_type_variation).is_equal("HudGoodText")
	assert_str(_label("O0N1", "Down").theme_type_variation).is_equal("HudProblemText")
	assert_str(_label("O0N1", "Down").tooltip_text).contains("45%")
	assert_str(_panel.card_text("O0N1")).contains("Top fare +30%\nBig rush crowd")


func test_the_plain_offer_says_plain_terms_and_shows_no_downside() -> void:
	assert_str(_label("O0N3", "Up").text).is_equal(OfferTraits.PLAIN_LABEL)
	assert_str(_label("O0N3", "Up").theme_type_variation).is_equal("HudHint")
	assert_bool(_label("O0N3", "Down").visible).is_false()
	assert_str(_panel.card_text("O0N3")).contains("\n%s\nDeparts " % OfferTraits.PLAIN_LABEL)


func test_the_trait_line_sits_right_under_the_verdict_row() -> void:
	for id in _panel.card_ids():
		var verdict := _panel.fit_label(id).get_parent()
		var row := _panel.trait_row(id)
		assert_object(row.get_parent()).is_same(verdict.get_parent())
		assert_int(row.get_index()).is_equal(verdict.get_index() + 1)
