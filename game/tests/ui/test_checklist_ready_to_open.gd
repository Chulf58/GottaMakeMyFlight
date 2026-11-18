class_name TestChecklistReadyToOpen
extends GdUnitTestSuite
## Every opening line is done one tick before the airport opens: the last member
## goes on duty, and AirportGate opens at the start of the next tick. A paused
## clock holds that moment, and the card then had nothing to list, so it showed
## only "To open the airport" (D3 playtest, board D3a point 5; measured in
## spike/checklist_title_only_probe.gd, with room_below 1125 so not a room
## problem). The title now says the airport is ready to open.

const LIMIT_TICKS := 4000

var _w: PassengerTestWorld
var _gate: AirportGate
var _panel: StaffPanel


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
	_w = null


func _make() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_gate = auto_free(AirportGate.new())
	_gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	_panel.gate = _gate
	add_child(_panel)


func _all_on_duty() -> bool:
	var ids := _w.staff.member_ids()
	for id in ids:
		if _w.staff.get_member(id).state != StaffMember.State.ON_DUTY:
			return false
	return not ids.is_empty()


## Hires for every closed desk and scanner, then steps one tick at a time until
## every member is on duty. The flights are told of no gate meanwhile, so the
## airport waits at the tick the last member arrives, the moment a paused clock
## holds in the scene (where the opening comes one tick after the arrival).
## Returns whether the airport was still closed then.
func _step_to_last_arrival() -> bool:
	_w.flights.gate = null
	for station in MissSignals.closed_stations(_w.sim):
		var desk := _w.sim.layout.desks.has(station)
		_w.staff.hire(StaffMember.Role.CHECKIN if desk else StaffMember.Role.SECURITY)
	_w.step()
	while not _all_on_duty() and _w.clock.tick < LIMIT_TICKS:
		_w.step()
	return not _gate.is_open()


func test_the_card_says_the_airport_is_ready_while_every_line_is_done_and_it_is_closed() -> void:
	_make()
	var closed := _step_to_last_arrival()
	var unmet := _gate.unmet()
	var title := _panel.hint_label().text
	print("tick %d closed=%s unmet=%s title='%s'" % [_w.clock.tick, closed, unmet, title])
	assert_bool(closed).is_true()
	assert_array(unmet).is_empty()
	assert_bool(_gate.ready_to_open()).is_true()
	assert_str(title).is_equal(Checklist.TITLE_READY)
	assert_bool(_panel.hint_label().is_visible_in_tree()).is_true()
	# The opening takes the card out of the ready state.
	assert_bool(_gate.open()).is_true()
	assert_bool(_gate.is_open()).is_true()
	assert_str(_panel.hint_label().text).is_not_equal(Checklist.TITLE_READY)
	assert_str(_panel.hint_label().text).is_not_equal(Checklist.TITLE_CLOSED)


func test_the_title_stays_to_open_the_airport_while_a_line_is_still_to_do() -> void:
	_make()
	_panel.refresh()
	assert_array(_gate.unmet()).is_not_empty()
	assert_bool(_gate.ready_to_open()).is_false()
	assert_str(_panel.hint_label().text).is_equal(Checklist.TITLE_CLOSED)
