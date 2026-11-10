class_name TestOfferPanelWarning
extends GdUnitTestSuite
## While the airport rating is below RatingFormula.WARN_BELOW the airlines warn
## (decision airport-rating-1-5-stars-over-a-rolling-3-days-mostly-made-o), and
## when one ends its contract the player is told. Both are coral cards on the
## right rail (AlertStack.post_notice, HUD 6/7, decision hud-grid-and-rails-one-
## spacing-grid-centred-top-row-right-ra part 6), no longer lines on the Offers
## sheet: the warning counts the low days left, follows the rating's changed
## signal and goes when the rating recovers; the ended notice stays until it is
## clicked. Both write a history line. The button's tooltip keeps the warning.
## Until HUD 6/7 these were sheet labels and this file read them there.

var _port: SubViewport
var _rating: AirportRating
var _desk: OfferDesk
var _stack: AlertStack
var _panel: OfferPanel
var _path: String


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_path = SaveTestKit.run_path("offer_warning_rail_setting")
	_stack = AlertStack.new()
	_stack.settings_path = _path
	_port.add_child(_stack)
	_rating = AirportRating.new()
	_desk = OfferDesk.new()
	_desk.runway = Runway.new(PlaneClasses.LARGE)
	_desk.rating = _rating
	var sim := FlightSim.new()
	_port.add_child(_rating)
	_port.add_child(_desk)
	_port.add_child(sim)
	_panel = OfferPanel.new()
	_panel.desk = _desk
	_panel.flights = sim
	_panel.alerts = _stack
	_port.add_child(_panel)


func after_test() -> void:
	_port.free()
	DirAccess.remove_absolute(_path)


func _miss(count: int, tick := 10) -> void:
	for i in count:
		_rating.record_passenger(tick, false, 0)


func _make(count: int, tick := 10) -> void:
	for i in count:
		_rating.record_passenger(tick, true, PassengerSim.MOOD_MAX)


## A rail card's title and detail, one per line; "" when no card is up.
func _words(key: StringName) -> String:
	var card := _stack.notice_card(key)
	if card == null:
		return ""
	var lines := PackedStringArray()
	for label in card.find_children("*", "Label", true, false):
		lines.append((label as Label).text)
	return "\n".join(lines)


func _left_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


func _airline_left(airline := "Gotta Air", destination := "Oslo") -> Dictionary:
	var contract := TestFlightContracts.terms("AM", 480)
	contract["airline"] = airline
	contract["destination"] = destination
	return contract


func test_no_warning_while_the_rating_is_fine() -> void:
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_null()
	assert_str(_panel.warning_text()).is_empty()
	assert_str(_panel.toggle_button().tooltip_text).is_empty()
	_make(10)
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_null()
	assert_array(_stack.history_lines()).is_empty()


func test_a_low_rating_puts_a_coral_warning_on_the_rail_with_the_days_left() -> void:
	_miss(10)
	assert_bool(_rating.warning()).is_true()
	var card := _stack.notice_card(OfferPanel.WARNING_KEY)
	assert_object(card).is_not_null()
	assert_str(_words(OfferPanel.WARNING_KEY)).contains("below 2 stars")
	assert_str(_words(OfferPanel.WARNING_KEY)).contains("3 more low days")
	assert_str(card.theme_type_variation).is_equal("HudCardCoral")
	assert_str(_panel.warning_text()).contains("below 2 stars")
	assert_str(_panel.toggle_button().tooltip_text).is_equal(_panel.warning_text())


func test_the_sheet_has_no_warning_line_and_shows_only_offers() -> void:
	_desk.board.ensure_day(0, RandomNumberGenerator.new())
	_miss(10)
	_desk.contract_ended.emit(_airline_left())
	assert_object(_panel.find_child("OfferWarning", true, false)).is_null()
	assert_object(_panel.find_child("OfferNotice", true, false)).is_null()
	var cards := _panel.find_child("OfferCards", true, false) as Container
	assert_int(cards.get_child_count()).is_equal(_panel.card_ids().size())
	assert_int(cards.get_child_count()).is_greater(0)
	for label in _panel.find_children("*", "Label", true, false):
		var text := (label as Label).text
		assert_str(text).not_contains("below 2 stars")
		assert_str(text).not_contains("ended its contract")


func test_the_count_follows_the_low_day_ends_and_reposts_under_the_same_key() -> void:
	_miss(10)
	var first := _stack.notice_card(OfferPanel.WARNING_KEY)
	_rating.on_tick(GameCalendar.day_start(1))
	assert_int(_rating.low_days()).is_equal(1)
	assert_str(_words(OfferPanel.WARNING_KEY)).contains("2 more low days")
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_not_same(first)
	_rating.on_tick(GameCalendar.day_start(2))
	assert_str(_words(OfferPanel.WARNING_KEY)).contains("1 more low day.")
	var warnings := 0
	for line in _stack.history_lines():
		warnings += 1 if line.contains(OfferPanel.WARNING_TITLE) else 0
	assert_int(warnings).is_equal(3)


func test_an_unchanged_warning_is_not_posted_again() -> void:
	_miss(10)
	var card := _stack.notice_card(OfferPanel.WARNING_KEY)
	_miss(2)
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_same(card)
	card.gui_input.emit(_left_click())
	_miss(2)
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_null()


func test_no_count_is_shown_once_the_low_days_are_used_up() -> void:
	for day in 4:
		_miss(5, GameCalendar.day_start(day))
	assert_int(_rating.low_days()).is_greater_equal(RatingFormula.LOW_DAYS_TO_END)
	assert_bool(_rating.warning()).is_true()
	assert_str(_words(OfferPanel.WARNING_KEY)).contains("below 2 stars")
	assert_str(_words(OfferPanel.WARNING_KEY)).not_contains("more low")


func test_the_warning_card_goes_when_the_rating_recovers() -> void:
	_miss(10)
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_not_null()
	_make(100)
	assert_bool(_rating.warning()).is_false()
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_null()
	assert_str(_panel.warning_text()).is_empty()
	assert_str(_panel.toggle_button().tooltip_text).is_empty()


func test_a_warning_already_there_when_the_panel_opens_is_posted() -> void:
	_miss(10)
	_stack.drop_notice(OfferPanel.WARNING_KEY)
	var late := OfferPanel.new()
	late.desk = _desk
	late.flights = _panel.flights
	late.alerts = _stack
	_port.add_child(late)
	assert_str(_words(OfferPanel.WARNING_KEY)).contains("below 2 stars")


func test_the_rail_is_found_through_its_group_when_not_set() -> void:
	var late := OfferPanel.new()
	late.desk = _desk
	late.flights = _panel.flights
	_miss(10)
	_stack.drop_notice(OfferPanel.WARNING_KEY)
	_port.add_child(late)
	assert_str(_words(OfferPanel.WARNING_KEY)).contains("below 2 stars")


func test_the_warning_does_not_rebuild_the_cards() -> void:
	_desk.board.ensure_day(0, RandomNumberGenerator.new())
	var card := _panel.card(_panel.card_ids()[0])
	_miss(10)
	assert_object(_panel.card(_panel.card_ids()[0])).is_same(card)


func test_a_panel_with_a_desk_that_has_no_rating_has_no_warning() -> void:
	var sim := FlightSim.new()
	var bare := OfferDesk.new()
	bare.runway = Runway.new(PlaneClasses.LARGE)
	var panel := OfferPanel.new()
	_port.add_child(bare)
	_port.add_child(sim)
	panel.desk = bare
	panel.flights = sim
	panel.alerts = _stack
	_port.add_child(panel)
	assert_str(panel.warning_text()).is_empty()
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_null()


func test_a_contract_ending_posts_a_coral_card_that_stays_until_clicked() -> void:
	_miss(10)
	assert_object(_stack.notice_card(OfferPanel.ENDED_KEY)).is_null()
	_desk.contract_ended.emit(_airline_left("Nordic Wing", "Rome"))
	var card := _stack.notice_card(OfferPanel.ENDED_KEY)
	assert_object(card).is_not_null()
	assert_str(_words(OfferPanel.ENDED_KEY)).contains(
		OfferPanel.ended_message("Nordic Wing", "Rome")
	)
	assert_str(card.theme_type_variation).is_equal("HudCardCoral")
	assert_str(_panel.toggle_button().tooltip_text).contains("Nordic Wing to Rome")
	_stack.advance(100000.0)
	assert_object(_stack.notice_card(OfferPanel.ENDED_KEY)).is_same(card)
	card.gui_input.emit(_left_click())
	assert_object(_stack.notice_card(OfferPanel.ENDED_KEY)).is_null()


func test_the_last_ending_replaces_the_one_before() -> void:
	_miss(10)
	_desk.contract_ended.emit(_airline_left("Sunhop", "Berlin"))
	_desk.contract_ended.emit(_airline_left("Blue Fjord", "Athens"))
	assert_str(_words(OfferPanel.ENDED_KEY)).contains("Blue Fjord to Athens")
	assert_str(_words(OfferPanel.ENDED_KEY)).not_contains("Sunhop")


func test_the_ended_notice_stays_after_the_rating_recovers() -> void:
	_miss(10)
	_desk.contract_ended.emit(_airline_left())
	_make(100)
	assert_bool(_rating.warning()).is_false()
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_null()
	assert_object(_stack.notice_card(OfferPanel.ENDED_KEY)).is_not_null()


func test_both_notices_are_in_the_history() -> void:
	_miss(10)
	_desk.contract_ended.emit(_airline_left("Nordic Wing", "Rome"))
	var text := "\n".join(_stack.history_lines())
	assert_str(text).contains(OfferPanel.WARNING_TITLE)
	assert_str(text).contains("below 2 stars")
	assert_str(text).contains(OfferPanel.ENDED_TITLE)
	assert_str(text).contains("Nordic Wing to Rome has ended its contract")
	_make(100)
	assert_str("\n".join(_stack.history_lines())).contains("below 2 stars")


func test_a_load_clears_the_posted_words_so_a_low_rating_posts_again() -> void:
	_miss(10)
	_desk.contract_ended.emit(_airline_left())
	_panel._on_loaded(true)
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_null()
	assert_object(_stack.notice_card(OfferPanel.ENDED_KEY)).is_null()
	await await_idle_frame()
	assert_str(_words(OfferPanel.WARNING_KEY)).contains("below 2 stars")
	assert_object(_stack.notice_card(OfferPanel.ENDED_KEY)).is_null()
