class_name TestOfferPanelRailReset
extends GdUnitTestSuite
## The Offers warning card follows its rail (HUD 6/7): a rail that was reset or
## replaced while the rating stays low gets the warning again, and a card the
## player clicked away stays away on the same rail.

var _port: SubViewport
var _rating: AirportRating
var _stack: AlertStack
var _panel: OfferPanel
var _path: String


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_path = SaveTestKit.run_path("offer_rail_reset_setting")
	_stack = AlertStack.new()
	_stack.settings_path = _path
	_port.add_child(_stack)
	_rating = AirportRating.new()
	var desk := OfferDesk.new()
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.rating = _rating
	var sim := FlightSim.new()
	_port.add_child(_rating)
	_port.add_child(desk)
	_port.add_child(sim)
	_panel = OfferPanel.new()
	_panel.desk = desk
	_panel.flights = sim
	_port.add_child(_panel)


func after_test() -> void:
	_port.free()
	DirAccess.remove_absolute(_path)


func _miss(count: int) -> void:
	for i in count:
		_rating.record_passenger(10, false, 0)


func _warning_words() -> String:
	var card := _stack.notice_card(OfferPanel.WARNING_KEY)
	if card == null:
		return ""
	return (card.find_children("*", "Label", true, false)[1] as Label).text


func test_a_reset_rail_gets_the_warning_back_with_the_rating_unchanged() -> void:
	_miss(10)
	var first := _stack.notice_card(OfferPanel.WARNING_KEY)
	assert_object(first).is_not_null()
	_stack.reset()
	var again := _stack.notice_card(OfferPanel.WARNING_KEY)
	assert_object(again).is_not_null()
	assert_object(again).is_not_same(first)
	assert_str(_warning_words()).contains("below 2 stars")


func test_a_replaced_rail_gets_the_warning_with_the_rating_unchanged() -> void:
	_miss(10)
	_stack.free()
	_stack = AlertStack.new()
	_stack.settings_path = _path
	_port.add_child(_stack)
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_null()
	_miss(2)
	assert_str(_warning_words()).contains("below 2 stars")


func test_resetting_the_old_rail_does_not_repost_on_the_new_one() -> void:
	_miss(10)
	var old_rail := _stack
	var new_rail := AlertStack.new()
	new_rail.settings_path = _path
	_port.add_child(new_rail)
	_panel.alerts = new_rail
	_miss(2)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_object(new_rail.notice_card(OfferPanel.WARNING_KEY)).is_not_null()
	new_rail.notice_card(OfferPanel.WARNING_KEY).gui_input.emit(click)
	old_rail.reset()
	assert_object(new_rail.notice_card(OfferPanel.WARNING_KEY)).is_null()
	assert_object(old_rail.notice_card(OfferPanel.WARNING_KEY)).is_null()


func test_a_click_dismissal_still_holds_on_the_same_rail() -> void:
	_miss(10)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_stack.notice_card(OfferPanel.WARNING_KEY).gui_input.emit(click)
	_miss(2)
	assert_object(_stack.notice_card(OfferPanel.WARNING_KEY)).is_null()
