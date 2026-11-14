class_name TestOfferPanelChoice
extends GdUnitTestSuite
## The three offer cards read as a choice (decision airline-offers-stay-accept-
## many-the-three-offer-cards-read-a): each card says plainly whether it fits
## the gates now or needs another gate, and shows its daily earnings (booked
## passengers times the fee per passenger), so the three compare at a glance.
## The fit and earnings lines sit directly under the airline and destination.

const HUD_THEME := preload("res://ui/hud_theme.tres")

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
	# 10:00, 12:00 (clashes with 10:00 at the one gate) and 20:00, each with its
	# own passengers and fee so the earnings differ from card to card.
	var offers := TestOfferBoard.day_records(0, [600, 720, 1200])
	var terms := [[12, 25], [16, 32], [15, 32]]
	for i in offers.size():
		offers[i]["booked_passengers"] = terms[i][0]
		offers[i]["fee_per_passenger"] = terms[i][1]
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)
	_panel.open()


func after_test() -> void:
	_port.free()


func test_daily_earnings_are_passengers_times_the_fee() -> void:
	var offer := TestOfferBoard.record("O0N9", 0, 600)
	offer["booked_passengers"] = 15
	offer["fee_per_passenger"] = 32
	assert_int(OfferPanel.daily_earnings(offer)).is_equal(480)
	assert_str(OfferPanel.earnings_text(offer)).is_equal("$480 a day")


func test_each_card_shows_its_own_daily_earnings() -> void:
	var expected := {"O0N1": "$300 a day", "O0N2": "$512 a day", "O0N3": "$480 a day"}
	for id in _panel.card_ids():
		print("%s earnings line '%s'" % [id, _panel.earnings_text_of(id)])
		assert_str(_panel.earnings_text_of(id)).is_equal(expected[id])
		assert_str(_panel.card_text(id)).contains(expected[id])


func test_a_fitting_card_says_it_fits_now_in_the_good_look() -> void:
	assert_str(OfferPanel.FITS_TEXT).is_equal("Fits your gates now")
	for id in _panel.card_ids():
		assert_str(_panel.fit_text(id)).is_equal(OfferPanel.FITS_TEXT)
		assert_str(_panel.fit_label(id).theme_type_variation).is_equal("HudGoodText")


## Accepting 10:00 leaves 12:00 clashing at the one gate while a second gate
## would take it; 20:00 still fits. The clashing card says it needs another gate
## in the problem look, and its earnings stay on the card.
func test_a_clashing_card_says_it_needs_another_gate() -> void:
	_panel.accept_button("O0N1").pressed.emit()
	assert_str(OfferPanel.NEEDS_GATE_TEXT).is_equal("Needs another gate")
	assert_str(_panel.fit_text("O0N2")).is_equal(OfferPanel.NEEDS_GATE_TEXT)
	assert_str(_panel.fit_label("O0N2").theme_type_variation).is_equal("HudProblemText")
	assert_str(_panel.fit_text("O0N3")).is_equal(OfferPanel.FITS_TEXT)
	assert_str(_panel.earnings_text_of("O0N2")).is_equal("$512 a day")


## Fit and earnings are the two lines under the title, so the cards compare by
## reading down the same two rows.
func test_the_fit_and_earnings_lines_follow_the_title() -> void:
	for id in _panel.card_ids():
		var lines := _panel.card_text(id).split("\n")
		var offer := _desk.board.offer_of(id)
		assert_str(lines[0]).is_equal("%s to %s" % [offer["airline"], offer["destination"]])
		assert_str(lines[1]).is_equal(_panel.fit_text(id))
		assert_str(lines[2]).is_equal(OfferPanel.earnings_text(offer))
		assert_str(lines[3]).starts_with("Departs ")


func test_the_new_lines_fit_the_card_text_width() -> void:
	var label := Label.new()
	label.theme = HUD_THEME
	label.theme_type_variation = &"HudSmall"
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	assert_int(size).is_greater(0)
	var offer := TestOfferBoard.record("O0N9", 0, 600)
	offer["booked_passengers"] = 120
	offer["fee_per_passenger"] = 60
	for text: String in [
		OfferPanel.FITS_TEXT, OfferPanel.NEEDS_GATE_TEXT, OfferPanel.earnings_text(offer)
	]:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		print("%.0f px: %s" % [width, text])
		assert_float(width).is_greater(50.0)
		assert_float(width).is_less_equal(OfferPanel.CARD_TEXT_W)
	label.free()
