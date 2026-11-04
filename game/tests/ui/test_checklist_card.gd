class_name TestChecklistCard
extends GdUnitTestSuite
## The checklist card (decision checklist-card-shows-what-the-airport-still-
## needs): while the airport is closed it lists every unmet opening need, not
## only the first blocker, each line ticking off when done; seats are advice
## (decision checklist-card-seats-line-is-advice-not-an-opening-blocker-s); once
## open it lists the current gaps, and it hides when nothing is left.

const BLOCKER := AirportGate.Blocker

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


func _make(reference: bool) -> void:
	if reference:
		_w = PassengerTestWorld.reference_world()
	else:
		_w = PassengerTestWorld.make(
			PassengerTestWorld.floored(Vector2i(12, 12)), FlightSim.schedule_starts(0)
		)
	_w.auto_staff = false
	_gate = auto_free(AirportGate.new())
	_gate.bind(_w.flights, _w.staff)
	_panel = auto_free(StaffPanel.new())
	_panel.staff = _w.staff
	_panel.gate = _gate
	add_child(_panel)


static func _texts(lines: Array[Dictionary], done: bool) -> Array:
	var out := []
	for entry in lines:
		if entry["done"] == done:
			out.append(entry["text"])
	return out


func _counts(desks: int, scanners: int, seats: int, agents: int, officers: int) -> Dictionary:
	return {
		"desks": desks,
		"scanners": scanners,
		"seats": seats,
		"checkin_staying": agents,
		"security_staying": officers,
	}


func test_every_unmet_opening_need_has_its_own_line() -> void:
	var unmet := [BLOCKER.NO_GATE, BLOCKER.STAFF_SPOT, BLOCKER.CHECKIN_CLOSED, BLOCKER.NO_SECURITY]
	var lines := Checklist.opening_lines(unmet, _counts(1, 1, 0, 1, 0))
	print("lines %s" % [lines])
	assert_array(_texts(lines, true)).contains_exactly([Checklist.ENTRANCE])
	(
		assert_array(_texts(lines, false))
		. contains_exactly(
			[
				Checklist.STAFF_SPOT,
				"%s: %s" % [Checklist.CHECKIN, Checklist.NEXT["checkin"]["closed"]],
				"%s: %s" % [Checklist.SECURITY, Checklist.NEXT["security"]["hire"]],
				Checklist.GATE,
				Checklist.SEATS,
			]
		)
	)


func test_a_station_line_says_what_to_do_next() -> void:
	var unmet := [BLOCKER.NO_CHECKIN, BLOCKER.NO_SECURITY]
	var placing := _texts(Checklist.opening_lines(unmet, _counts(0, 0, 1, 0, 0)), false)
	var walking := _texts(Checklist.opening_lines(unmet, _counts(1, 1, 1, 1, 1)), false)
	print("placing %s, walking %s" % [placing, walking])
	assert_array(placing).contains(["Check-in desk and an agent: place a desk"])
	assert_array(placing).contains(["Security scanner and an officer: place a scanner"])
	assert_array(walking).contains(["Check-in desk and an agent: the agent is on the way"])
	assert_array(walking).contains(["Security scanner and an officer: the officer is on the way"])


func test_seats_tick_off_but_are_never_an_opening_blocker() -> void:
	var without := Checklist.opening_lines([], _counts(1, 1, 0, 1, 1))
	var with_seats := Checklist.opening_lines([], _counts(1, 1, 4, 1, 1))
	assert_array(_texts(without, false)).contains_exactly([Checklist.SEATS])
	assert_array(_texts(with_seats, false)).is_empty()
	assert_array(_texts(with_seats, true)).contains([Checklist.SEATS])


func test_a_closed_bare_floor_card_lists_all_its_needs() -> void:
	_make(false)
	var unmet := _gate.unmet()
	var todo := _panel.hint_text().split("\n")
	print("unmet %s, card '%s'" % [unmet, _panel.hint_text().replace("\n", " | ")])
	assert_int(unmet.size()).is_equal(3)
	assert_array(Array(todo)).contains([Checklist.ENTRANCE])
	assert_array(Array(todo)).contains(["Check-in desk and an agent: place a desk"])
	assert_array(Array(todo)).contains(["Security scanner and an officer: place a scanner"])
	assert_str(_panel.hint_label().text).is_equal(Checklist.TITLE_CLOSED)
	assert_bool(_panel.hint_card().visible).is_true()
	# One row per line, each with its tick box.
	assert_int(_panel.checklist().rows().size()).is_equal(_panel.card_lines().size())


func test_the_reference_card_ticks_what_stands_and_hides_once_open_with_nothing_left() -> void:
	_make(true)
	var before := _panel.card_lines()
	print("unstaffed %s" % [before])
	assert_array(_texts(before, true)).contains([Checklist.ENTRANCE, Checklist.GATE])
	assert_array(_texts(before, false)).contains(
		["Check-in desk and an agent: hire an agent on Staff"]
	)
	assert_int(StaffTestKit.staff_all(_w.staff)).is_greater(0)
	_panel.refresh()
	assert_array(_gate.unmet()).is_empty()
	assert_bool(_gate.open()).is_true()
	_panel.poll_gaps()
	print("open card '%s'" % _panel.hint_text().replace("\n", " | "))
	# Only the starter line is left; once it goes the card hides.
	assert_array(_panel.card_lines()).is_empty()
	assert_bool(_panel.hint_card().visible).is_true()
	assert_str(_panel.hint_label().text).starts_with("Open!")
	_panel._open_cue = ""
	_panel.refresh()
	assert_str(_panel.hint_text()).is_empty()
	assert_bool(_panel.hint_card().visible).is_false()


func test_an_open_airport_lists_a_toilet_gap() -> void:
	var world := {
		"desks": 1,
		"scanners": 1,
		"arches": 0,
		"shortage_roles": [],
		"hiring_roles": [],
		"max_toilet_need": ToiletSim.NEED_AT,
		"max_hunger": 0,
		"stalls": 0,
		"cafes": 0,
	}
	var lines := Checklist.gap_lines(world, 2, {})
	assert_array(_texts(lines, false)).contains_exactly([Checklist.GAPS[HintRules.TOILET]])
	world["max_toilet_need"] = 0
	assert_array(Checklist.gap_lines(world, 2, {})).is_empty()
	assert_array(_texts(Checklist.gap_lines(world, 0, {}), false)).contains_exactly(
		[Checklist.NO_SEATS]
	)


func test_a_gap_whose_tool_is_locked_names_the_unlock_instead() -> void:
	var world := {
		"desks": 1,
		"scanners": 1,
		"arches": 0,
		"shortage_roles": [],
		"hiring_roles": [],
		"max_toilet_need": 0,
		"max_hunger": CafeSim.HUNGRY_AT,
		"stalls": 1,
		"cafes": 0,
	}
	var lock := BuildUnlocks.requirement_text(BuildUnlocks.CAFE_TIER)
	var locked := _texts(Checklist.gap_lines(world, 2, {BuildMode.Tool.CAFE_ROOM: lock}), false)
	var open := _texts(Checklist.gap_lines(world, 2, {BuildMode.Tool.CAFE_ROOM: ""}), false)
	print("locked %s, open %s" % [locked, open])
	assert_array(locked).contains_exactly(["Passengers are hungry (%s)" % lock])
	assert_array(open).contains_exactly([Checklist.GAPS[HintRules.FOOD]])


func test_done_rows_are_ticked_and_dimmed() -> void:
	var card: ChecklistCard = auto_free(ChecklistCard.new())
	var lines: Array[Dictionary] = [Checklist.line("a", true), Checklist.line("b", false)]
	card.show_lines("Title", lines)
	var rows := card.rows()
	assert_int(rows.size()).is_equal(2)
	assert_bool((rows[0].get_node("Tick") as ChecklistCard.Tick).done).is_true()
	assert_bool((rows[1].get_node("Tick") as ChecklistCard.Tick).done).is_false()
	assert_float((rows[0] as Control).modulate.a).is_equal_approx(ChecklistCard.DONE_ALPHA, 0.001)
	assert_float((rows[1] as Control).modulate.a).is_equal(1.0)
	assert_str((rows[1].get_node("Text") as Label).text).is_equal("b")
