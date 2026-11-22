class_name TestOfferPanelMoneyTraits
extends GdUnitTestSuite
## The money traits on an offer card: Signing bonus and Miss fine show in the
## trait line like the other traits, and an offer from a loyal airline adds
## "Loyal: +10%" at the end of the same line.

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
	# Gotta Air flew its fifth Loyal airline day on day 5, so its day 6 offers
	# carry the loyal raise.
	var records := TestOfferBoard.day_records(6, [600, 720, 840])
	records[0]["traits"] = {"up": "signing_bonus", "down": "miss_fine", "level": 2}
	records[0]["loyal"] = true
	records[0]["fee_per_passenger"] = 55
	records[1]["traits"] = {}
	records[1]["loyal"] = true
	records[1]["fee_per_passenger"] = 50
	# An airline with no Loyal count, so its offer carries no loyal mark.
	records[2]["airline"] = "Sunhop"
	var data := TestOfferBoard.save_of(records)
	data["loyalty"] = {"Gotta Air": {"days": OfferTraits.LOYAL_DAYS, "last_day": 5}}
	assert_bool(_desk.board.from_snapshot(data)).is_true()
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)
	_panel.open()


func after_test() -> void:
	_port.free()


func _label(id: String, side: String) -> Label:
	return _panel.trait_row(id).get_node(side)


func test_signing_bonus_and_miss_fine_show_with_their_amounts() -> void:
	assert_str(_label("O6N1", "Up").text).is_equal("Signing bonus $300")
	assert_str(_label("O6N1", "Down").text).is_equal("Miss fine $20")
	assert_str(_label("O6N1", "Up").tooltip_text).contains("$300")
	assert_str(_label("O6N1", "Down").tooltip_text).contains("$20")
	assert_str(_label("O6N1", "Down").theme_type_variation).is_equal("HudProblemText")


func test_a_loyal_airlines_offer_shows_loyal_at_the_end_of_the_trait_line() -> void:
	for id in ["O6N1", "O6N2"]:
		var loyal := _label(id, "Loyal")
		assert_bool(loyal.visible).is_true()
		assert_str(loyal.text).is_equal(OfferTraits.LOYAL_LABEL)
		assert_str(loyal.theme_type_variation).is_equal("HudGoodText")
		assert_int(loyal.get_index()).is_equal(_panel.trait_row(id).get_child_count() - 1)
	assert_str(_panel.card_text("O6N2")).contains(
		"%s\n%s\nDeparts " % [OfferTraits.PLAIN_LABEL, OfferTraits.LOYAL_LABEL]
	)
	assert_bool(_label("O6N3", "Loyal").visible).is_false()


func test_a_three_label_trait_line_fits_the_card_text_width() -> void:
	var row := _panel.trait_row("O6N1")
	assert_float(row.get_combined_minimum_size().x).is_less_equal(OfferPanel.CARD_TEXT_W)
