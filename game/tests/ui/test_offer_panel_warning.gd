class_name TestOfferPanelWarning
extends GdUnitTestSuite
## The offer sheet carries the airlines' warning while the airport rating is
## below RatingFormula.WARN_BELOW (decision airport-rating-1-5-stars-over-a-
## rolling-3-days-mostly-made-o): it says so on the sheet and on the button's
## tooltip, counts the low days left before contracts end, follows the rating's
## changed signal and is gone when the rating recovers.

var _port: SubViewport
var _rating: AirportRating
var _desk: OfferDesk
var _panel: OfferPanel


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_rating = AirportRating.new()
	_desk = OfferDesk.new()
	_desk.rating = _rating
	var sim := FlightSim.new()
	_port.add_child(_rating)
	_port.add_child(_desk)
	_port.add_child(sim)
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = sim
	_port.add_child(_panel)


func after_test() -> void:
	_port.free()


func _miss(count: int, tick := 10) -> void:
	for i in count:
		_rating.record_passenger(tick, false, 0)


func _make(count: int, tick := 10) -> void:
	for i in count:
		_rating.record_passenger(tick, true, PassengerSim.MOOD_MAX)


func test_no_warning_while_the_rating_is_fine() -> void:
	assert_str(_panel.warning_text()).is_empty()
	assert_bool(_panel.warning_label().visible).is_false()
	assert_str(_panel.toggle_button().tooltip_text).is_empty()
	_make(10)
	assert_str(_panel.warning_text()).is_empty()


func test_a_low_rating_shows_the_warning_and_the_days_left() -> void:
	_miss(10)
	assert_bool(_rating.warning()).is_true()
	var text := _panel.warning_text()
	assert_str(text).contains("below 2 stars")
	assert_str(text).contains("3 more low days")
	assert_bool(_panel.warning_label().visible).is_true()
	assert_str(_panel.toggle_button().tooltip_text).is_equal(text)


func test_the_count_follows_the_low_day_ends() -> void:
	_miss(10)
	_rating.on_tick(GameCalendar.day_start(1))
	assert_int(_rating.low_days()).is_equal(1)
	assert_str(_panel.warning_text()).contains("2 more low days")
	_rating.on_tick(GameCalendar.day_start(2))
	assert_int(_rating.low_days()).is_equal(2)
	assert_str(_panel.warning_text()).contains("1 more low day.")


func test_no_count_is_shown_once_the_low_days_are_used_up() -> void:
	for day in 4:
		_miss(5, GameCalendar.day_start(day))
	assert_int(_rating.low_days()).is_greater_equal(RatingFormula.LOW_DAYS_TO_END)
	assert_bool(_rating.warning()).is_true()
	assert_str(_panel.warning_text()).contains("below 2 stars")
	assert_str(_panel.warning_text()).not_contains("more low")


func test_the_warning_goes_when_the_rating_recovers() -> void:
	_miss(10)
	assert_str(_panel.warning_text()).is_not_empty()
	_make(100)
	assert_bool(_rating.warning()).is_false()
	assert_str(_panel.warning_text()).is_empty()
	assert_bool(_panel.warning_label().visible).is_false()
	assert_str(_panel.toggle_button().tooltip_text).is_empty()


func test_a_warning_already_there_when_the_panel_opens_is_shown() -> void:
	var late := OfferPanel.new()
	late.desk = _desk
	late.flights = _panel.flights
	_miss(10)
	_port.add_child(late)
	assert_str(late.warning_text()).contains("below 2 stars")


func test_the_warning_does_not_rebuild_the_cards() -> void:
	_desk.board.ensure_day(0, RandomNumberGenerator.new())
	var card := _panel.card(_panel.card_ids()[0])
	_miss(10)
	assert_object(_panel.card(_panel.card_ids()[0])).is_same(card)


func test_a_panel_with_a_desk_that_has_no_rating_has_no_warning() -> void:
	var sim := FlightSim.new()
	var bare := OfferDesk.new()
	var panel := OfferPanel.new()
	_port.add_child(bare)
	_port.add_child(sim)
	panel.desk = bare
	panel.flights = sim
	_port.add_child(panel)
	assert_str(panel.warning_text()).is_empty()


func _airline_left(airline := "Gotta Air", destination := "Oslo") -> Dictionary:
	var contract := TestFlightContracts.terms("AM", 480)
	contract["airline"] = airline
	contract["destination"] = destination
	return contract


func test_a_contract_ending_is_announced_on_the_sheet_and_the_button() -> void:
	_miss(10)
	assert_str(_panel.notice_text()).is_empty()
	assert_bool(_panel.notice_label().visible).is_false()
	_desk.contract_ended.emit(_airline_left("Nordic Wing", "Rome"))
	assert_str(_panel.notice_text()).is_equal(OfferPanel.ended_message("Nordic Wing", "Rome"))
	assert_str(_panel.notice_text()).contains("Nordic Wing to Rome has ended its contract")
	assert_bool(_panel.notice_label().visible).is_true()
	assert_str(_panel.toggle_button().tooltip_text).contains("Nordic Wing to Rome")


func test_the_last_ending_replaces_the_one_before() -> void:
	_miss(10)
	_desk.contract_ended.emit(_airline_left("Sunhop", "Berlin"))
	_desk.contract_ended.emit(_airline_left("Blue Fjord", "Athens"))
	assert_str(_panel.notice_text()).contains("Blue Fjord to Athens")
	assert_str(_panel.notice_text()).not_contains("Sunhop")


func test_the_ending_notice_goes_when_the_rating_recovers() -> void:
	_miss(10)
	_desk.contract_ended.emit(_airline_left())
	_make(100)
	assert_bool(_rating.warning()).is_false()
	assert_str(_panel.notice_text()).is_empty()
	assert_bool(_panel.notice_label().visible).is_false()
