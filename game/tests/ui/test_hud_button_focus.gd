class_name TestHudButtonFocus
extends GdUnitTestSuite
## A HUD button never keeps keyboard focus after a click, so Space (pause) and
## Enter do not press it again (smoke playtest 4: a Space tap after clicking
## Hire Security hired a second officer). Every Button a panel creates is
## FOCUS_NONE; the panels with no button of their own (RoomPanel) are not here.

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func _taps(key: Key) -> Array[InputEventKey]:
	var events: Array[InputEventKey] = []
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		events.append(event)
	return events


func _buttons_of(node: Node) -> Array[BaseButton]:
	var found: Array[BaseButton] = []
	for child in node.find_children("*", "BaseButton", true, false):
		found.append(child as BaseButton)
	return found


func test_space_and_enter_after_a_hire_click_do_not_hire_again() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	var panel: StaffPanel = auto_free(StaffPanel.new())
	panel.staff = _w.staff
	add_child(panel)
	var hire := panel.hire_button(StaffMember.Role.SECURITY)
	# What a mouse click does: a focusable button takes keyboard focus.
	if hire.focus_mode != Control.FOCUS_NONE:
		hire.grab_focus()
	hire.pressed.emit()
	assert_int(_w.staff.count(StaffMember.Role.SECURITY)).is_equal(1)
	for key in [KEY_SPACE, KEY_ENTER]:
		for event in _taps(key):
			get_viewport().push_input(event)
	assert_int(_w.staff.count(StaffMember.Role.SECURITY)).is_equal(1)
	assert_object(get_viewport().gui_get_focus_owner()).is_null()


func test_every_staff_panel_button_is_focus_none() -> void:
	_w = PassengerTestWorld.reference_world()
	var panel: StaffPanel = auto_free(StaffPanel.new())
	panel.staff = _w.staff
	add_child(panel)
	var buttons := _buttons_of(panel)
	assert_int(buttons.size()).is_equal(4)
	for button in buttons:
		assert_int(button.focus_mode).is_equal(Control.FOCUS_NONE)


func test_every_offer_panel_button_is_focus_none() -> void:
	var port := SubViewport.new()
	add_child(port)
	var desk := OfferDesk.new()
	var sim := FlightSim.new()
	port.add_child(desk)
	port.add_child(sim)
	(
		assert_bool(
			desk.board.from_snapshot(
				TestOfferBoard.save_of(TestOfferBoard.day_records(0, [600, 660, 1200]))
			)
		)
		. is_true()
	)
	var panel := OfferPanel.new()
	panel.desk = desk
	panel.flights = sim
	port.add_child(panel)
	panel.open()
	var buttons := _buttons_of(panel)
	# The toggle plus Accept and Decline on each of the three cards.
	assert_int(buttons.size()).is_equal(7)
	for button in buttons:
		assert_int(button.focus_mode).is_equal(Control.FOCUS_NONE)
	port.free()


func test_the_flight_result_dismiss_button_is_focus_none() -> void:
	var panel: FlightResultPanel = auto_free(FlightResultPanel.new())
	add_child(panel)
	var buttons := _buttons_of(panel)
	assert_int(buttons.size()).is_equal(1)
	assert_int(buttons[0].focus_mode).is_equal(Control.FOCUS_NONE)
