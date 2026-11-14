class_name TestAlertSourcesStations
extends GdUnitTestSuite
## The closed-station alert causes (AlertSources.closed_stations): stations
## with nobody on duty, and stations whose staff spot is blocked or out of
## staff's reach. Their station signs lost their captions (decision calm-view-
## technical-design-shared-hover-target-reusing-click, part 3), so the alert
## cards carry the problem; each card appears once its cause has held and
## clears itself when it is fixed (AlertBoard).

var _w: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _w != null:
		_w.free_all()
		_w = null


func _keys(causes: Array[Dictionary]) -> Array[StringName]:
	var keys: Array[StringName] = []
	for cause in causes:
		keys.append(cause["key"])
	return keys


func _cause(causes: Array[Dictionary], key: StringName) -> Dictionary:
	for cause in causes:
		if cause["key"] == key:
			return cause
	return {}


## The reference terminal, its first desk's staff spot under a seat row (as only
## an old save can hold it: TestLanesSkipStaffSpots' world).
func _blocked_spot_world() -> int:
	var source := BuildGrid.new()
	ReferenceTerminal.build(source)
	var data := source.to_snapshot()
	var next: int = data["next_object_id"]
	(data["objects"] as Array).append(
		{"id": next, "def": "seat_row", "anchor": [11, 10], "facing": 0}
	)
	data["next_object_id"] = next + 1
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	_w = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_w.step()
	var desks: Array = ReferenceTerminal.object_ids(grid)["desks"]
	return desks[0]


func test_a_fully_staffed_terminal_has_no_station_cause() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.step()
	print("closed %s" % [MissSignals.closed_stations(_w.sim)])
	assert_array(MissSignals.closed_stations(_w.sim)).is_empty()
	assert_array(AlertSources.closed_stations(_w.sim)).is_empty()


func test_unstaffed_stations_are_one_cause_that_goes_when_staffed() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_w.step()
	var closed := MissSignals.closed_stations(_w.sim)
	var causes := AlertSources.closed_stations(_w.sim)
	print("closed %s causes %s" % [closed, causes])
	assert_int(closed.size()).is_greater(1)
	assert_array(_keys(causes)).is_equal([AlertSources.NO_STAFF])
	var cause := causes[0]
	assert_str(cause["title"]).is_equal("Nobody on duty")
	assert_str(cause["detail"]).is_equal(
		"%d stations are closed · hire staff on the Staff card" % closed.size()
	)
	# It points at the closed stations, one place each up to MAX_TARGETS.
	var targets: Array = cause["targets"]
	assert_int(targets.size()).is_equal(mini(closed.size(), AlertSources.MAX_TARGETS))
	assert_vector(targets[0]).is_equal(AlertSources.object_point(_w.sim.grid, closed[0]))
	StaffTestKit.staff_all(_w.staff)
	_w.step()
	assert_array(MissSignals.closed_stations(_w.sim)).is_empty()
	assert_array(AlertSources.closed_stations(_w.sim)).is_empty()


func test_a_blocked_staff_spot_is_its_own_cause() -> void:
	var blocked := _blocked_spot_world()
	var causes := AlertSources.closed_stations(_w.sim)
	print("causes %s" % [causes])
	assert_array(_keys(causes)).is_equal([AlertSources.STAFF_SPOT])
	var cause := causes[0]
	assert_str(cause["title"]).is_equal("Staff can't get to work")
	assert_str(cause["detail"]).is_equal("1 station is closed · staff can't reach the staff spot")
	assert_vector((cause["targets"] as Array)[0]).is_equal(
		AlertSources.object_point(_w.sim.grid, blocked)
	)
	# Firing the check-in staff closes the other desk too: a second cause.
	_w.staff.fire(StaffMember.Role.CHECKIN)
	var both := AlertSources.closed_stations(_w.sim)
	assert_array(_keys(both)).is_equal([AlertSources.NO_STAFF, AlertSources.STAFF_SPOT])
	# The blocked desk is counted once, under its staff spot, not as unstaffed.
	assert_str(_cause(both, AlertSources.NO_STAFF)["detail"]).starts_with("1 station is")


func test_a_station_the_player_closed_raises_no_card() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.step()
	var desk: int = _w.sim.layout.desks[0]
	assert_bool(_w.staff.closures.set_closed(desk, true)).is_true()
	# The control: the desk is closed, by the player.
	assert_array(MissSignals.closed_stations(_w.sim)).contains([desk])
	assert_str(MissSignals.closed_reason(_w.sim, desk)).is_equal(MissSignals.PLAYER_CLOSED_REASON)
	assert_array(AlertSources.closed_stations(_w.sim)).is_empty()


## Through AlertBoard: the card appears once the cause held QUEUE_HOLD_TICKS and
## clears QUEUE_HOLD_TICKS after the stations are staffed.
func test_the_nobody_on_duty_card_appears_and_clears_itself() -> void:
	_w = PassengerTestWorld.reference_world()
	_w.auto_staff = false
	_w.step()
	var board := AlertBoard.new()
	var start := _w.sim.tick
	board.update(AlertSources.closed_stations(_w.sim), start)
	assert_dict(board.alert(AlertSources.NO_STAFF)).is_empty()
	board.update(AlertSources.closed_stations(_w.sim), start + AlertSources.QUEUE_HOLD_TICKS)
	print("after the hold: %s" % [board.alert(AlertSources.NO_STAFF)])
	assert_dict(board.alert(AlertSources.NO_STAFF)).is_not_empty()
	StaffTestKit.staff_all(_w.staff)
	_w.step()
	var fixed := start + AlertSources.QUEUE_HOLD_TICKS + 1
	board.update(AlertSources.closed_stations(_w.sim), fixed)
	assert_dict(board.alert(AlertSources.NO_STAFF)).is_not_empty()
	board.update(AlertSources.closed_stations(_w.sim), fixed + AlertSources.QUEUE_HOLD_TICKS)
	assert_dict(board.alert(AlertSources.NO_STAFF)).is_empty()


## Through the real AlertStack (what the game draws): a station with nobody on
## duty and a blocked staff spot each get a card once the cause has held, and
## each card clears itself when its cause is fixed.
func test_both_station_causes_reach_the_alert_stack_and_clear_through_it() -> void:
	var blocked := _blocked_spot_world()
	# Firing the check-in staff closes the other desk too: both causes at once.
	_w.staff.fire(StaffMember.Role.CHECKIN)
	_w.auto_staff = false
	var stack: AlertStack = auto_free(AlertStack.new())
	stack.settings_path = SaveTestKit.run_path("alert_stack_stations")
	stack.sim = _w.sim
	add_child(stack)
	stack.refresh()
	assert_array(stack.card_keys()).is_empty()
	_w.run_to(_w.sim.tick + AlertSources.QUEUE_HOLD_TICKS)
	stack.refresh()
	print("cards after the hold: %s" % [stack.card_keys()])
	assert_array(stack.card_keys()).contains_exactly(
		[AlertSources.NO_STAFF, AlertSources.STAFF_SPOT]
	)
	assert_str(stack.card_text(AlertSources.NO_STAFF)).contains("Nobody on duty")
	assert_str(stack.card_text(AlertSources.STAFF_SPOT)).contains("Staff can't get to work")
	# Fix both: hire everyone and take the seat row off the staff spot.
	var seat: int = _w.sim.grid.object_at(Vector2i(11, 10))
	assert_int(seat).is_greater(0)
	assert_bool(_w.grid.apply(BuildEdit.remove_object(seat)).ok).is_true()
	StaffTestKit.staff_all(_w.staff)
	_w.step()
	assert_bool(MissSignals.closed_stations(_w.sim).has(blocked)).is_false()
	assert_array(AlertSources.closed_stations(_w.sim)).is_empty()
	stack.refresh()
	_w.run_to(_w.sim.tick + AlertSources.QUEUE_HOLD_TICKS)
	stack.refresh()
	print("cards after the fix: %s" % [stack.card_keys()])
	assert_array(stack.card_keys()).is_empty()
