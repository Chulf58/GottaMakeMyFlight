class_name TestOfferPanelFit
extends GdUnitTestSuite
## Each offer card says before Accept whether the offer fits now and why not
## (decision airline-offers-2-a-day-fit-the-free-gate-slots-1-needs-more, point
## 6). The fit line is advice, apart from the click refusal, and it follows the
## timetable: an accept on the sheet and an opening of the sheet rewrite it.

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
	# 10:00, 12:00 (still inside 10:00's 195 minutes at the gate) and 20:00.
	var offers := TestOfferBoard.day_records(0, [600, 720, 1200])
	assert_bool(_desk.board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = _sim
	_port.add_child(_panel)


func after_test() -> void:
	_port.free()


func test_every_card_says_it_fits_on_an_empty_timetable() -> void:
	for id in _panel.card_ids():
		print("%s: %s" % [id, _panel.fit_text(id)])
		assert_str(_panel.fit_text(id)).is_equal(FlightFit.FITS_TEXT)
		assert_str(_panel.card_text(id)).contains(FlightFit.FITS_TEXT)
		assert_str(_panel.fit_label(id).theme_type_variation).is_equal("HudGoodText")


## Accepting 10:00 rewrites the 12:00 card at once: it now needs another gate,
## said in the problem look, while its click refusal line stays empty.
func test_an_accept_rewrites_the_other_cards_fit_line() -> void:
	_panel.open()
	_panel.accept_button("O0N1").pressed.emit()
	assert_str(_desk.board.offer_of("O0N1")["status"]).is_equal(OfferBoard.ACCEPTED)
	print("after accepting 10:00: 12:00 says '%s'" % _panel.fit_text("O0N2"))
	assert_str(_panel.fit_text("O0N2")).is_equal(FlightFit.ANOTHER_GATE_TEXT)
	assert_str(_panel.fit_label("O0N2").theme_type_variation).is_equal("HudProblemText")
	assert_str(_panel.fit_text("O0N3")).is_equal(FlightFit.FITS_TEXT)
	assert_bool(_panel.refusal_label("O0N2").visible).is_false()


## Accept still checks at the click: the refused card shows its refusal, and
## the advice line stays as it was beside it.
func test_the_click_refusal_and_the_fit_line_are_separate() -> void:
	_panel.open()
	_panel.accept_button("O0N1").pressed.emit()
	_panel.accept_button("O0N2").pressed.emit()
	assert_str(_desk.board.offer_of("O0N2")["status"]).is_equal(OfferBoard.OPEN)
	assert_str(_panel.refusal_text("O0N2")).contains("Can't accept")
	assert_str(_panel.fit_text("O0N2")).is_equal(FlightFit.ANOTHER_GATE_TEXT)
	assert_str(_panel.card_text("O0N2")).contains(FlightFit.ANOTHER_GATE_TEXT)


## Every fit line FlightFit can give fits on one card line, in the HUD font.
func test_every_fit_line_fits_the_card_text_width() -> void:
	var label := Label.new()
	label.theme = load("res://ui/hud_theme.tres")
	label.theme_type_variation = &"HudSmall"
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	assert_int(size).is_greater(0)
	for text: String in [
		FlightFit.FITS_TEXT,
		FlightFit.ANOTHER_GATE_TEXT,
		FlightFit.GATE_AND_TAXI_TEXT,
		FlightFit.TAXI_TEXT,
		FlightFit.NIGHT_TEXT,
		FlightFit.RUNWAY_TEXT % "medium",
		FlightFit.STAND_TEXT % "medium",
		FlightFit.NO_STAND_TEXT,
	]:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		print("%.0f px: %s" % [width, text])
		assert_float(width).is_greater(50.0)
		assert_float(width).is_less_equal(OfferPanel.CARD_TEXT_W)
	label.free()


## A contract taken while the sheet was closed shows on the cards when it opens.
func test_opening_the_sheet_rewrites_the_fit_lines() -> void:
	assert_str(_panel.fit_text("O0N3")).is_equal(FlightFit.FITS_TEXT)
	assert_bool(_sim.accept_contract(TestFlightFit.terms("EVE", 1260))).is_true()
	_panel.open()
	print("after a 21:00 contract, 20:00 says '%s'" % _panel.fit_text("O0N3"))
	assert_str(_panel.fit_text("O0N3")).is_not_equal(FlightFit.FITS_TEXT)
	assert_str(_panel.fit_text("O0N1")).is_equal(FlightFit.FITS_TEXT)
