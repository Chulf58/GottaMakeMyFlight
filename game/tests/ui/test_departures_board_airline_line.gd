class_name TestDeparturesBoardAirlineLine
extends GdUnitTestSuite
## Each Live Ops Departures row is two lines (decisions departures-list-row-
## shows-the-airline-on-a-second-line, departures-live-ops-drawer-and-
## actionable-on-time-hud-stat): line 1 has the time, destination, and
## boarded/booked progress (with no Gate or End buttons); line 2 has the
## airline's full name in small grey text (HudHint), never trimmed or cut; the
## list keeps its HudLayout.LIST_W width. The next flight's "doors close" caption
## stays under line 2.

const GATES: Array[String] = ["C", "A", "B"]
const LONGEST := "Skyline Global"

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard
var _rows: Control


func before() -> void:
	_sim = FlightSim.new()
	_clock = SimClock.new()
	_sim.gate_source = func() -> Array[String]: return GATES
	_sim.open_airport()
	_accept("X", 600, "Oslo", LONGEST)
	_accept("Y", 660, "Rome", "Gotta Air")
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_airline_line")
	_board.flights = _sim
	_board.clock = _clock
	add_child(_board)
	_board.set_shown(true)
	for i in 3:
		await get_tree().process_frame
	_rows = _board.find_child("Rows", true, false)


func after() -> void:
	var path := _board.settings_path
	_board.free()
	_sim.free()
	_clock.free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")


func _accept(id: String, minute: int, destination: String, airline: String) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["destination"] = destination
	terms["airline"] = airline
	assert_bool(_sim.accept_contract(terms)).is_true()


func _row_box(id: String, day: int) -> VBoxContainer:
	return _rows.find_child("FlightRow_%s" % FlightTimetable.occurrence_id(id, day), true, false)


func _airline(id: String, day: int) -> Label:
	return _rows.find_child("Airline_%s_%d" % [id, day], true, false) as Label


func _line_one(id: String, day: int) -> HBoxContainer:
	return _row_box(id, day).get_child(0) as HBoxContainer


func test_every_today_contract_row_has_the_full_airline_name_on_its_own_line() -> void:
	var expected := {"X": LONGEST, "Y": "Gotta Air"}
	for id: String in expected:
		var label := _airline(id, 0)
		print("airline label ", id, " day 0: ", label)
		assert_object(label).is_not_null()
		assert_str(label.text).starts_with(expected[id])
		assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
		assert_bool(label.clip_text).is_false()
		assert_object(_airline(id, 1)).is_null()


func test_the_airline_line_is_small_grey_text_under_line_one() -> void:
	var label := _airline("X", 0)
	assert_str(String(label.theme_type_variation)).is_equal("HudHint")
	assert_int(label.get_index()).is_equal(_line_one("X", 0).get_index() + 1)


func test_the_airline_name_is_not_cut_at_the_list_width() -> void:
	var label := _airline("X", 0)
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var wide := font.get_string_size(LONGEST, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	print("airline width ", wide, " label width ", label.size.x, " lines ", label.get_line_count())
	assert_float(wide).is_greater(20.0)
	assert_float(label.size.x).is_greater(wide)
	assert_int(label.get_line_count()).is_equal(1)
	for id in ["X", "Y"]:
		assert_int(_airline(id, 0).get_line_count()).is_equal(1)


func test_the_list_stays_at_its_set_width() -> void:
	var panel := _board.find_child("DeparturesPanel", true, false) as Control
	print("panel width ", panel.size.x)
	assert_float(panel.size.x).is_equal_approx(float(HudLayout.LIST_W), 0.5)


func test_line_one_has_time_destination_boarded_booked_and_no_gate_or_end_buttons() -> void:
	var line_one := _line_one("X", 0)
	var head := line_one.get_child(0) as Label
	var boarded := line_one.get_child(1) as Label
	print("line one: ", head.text, " | ", boarded.text)
	assert_str(head.text).is_equal("10:00  Oslo")
	assert_str(head.text).not_contains(LONGEST)
	assert_str(boarded.text).is_equal("0/40 boarded")
	assert_array(_board.find_children("Gate_*", "Button", true, false)).is_empty()
	assert_array(_board.find_children("End_*", "Button", true, false)).is_empty()


func test_the_doors_close_line_stays_under_the_airline_of_the_next_flight_only() -> void:
	var found := _board.find_children("DoorsClose", "Label", true, false)
	assert_int(found.size()).is_equal(1)
	var doors := found[0] as Label
	assert_str(doors.text).starts_with("doors close")
	var row_box := _row_box("X", 0)
	assert_object(doors.get_parent()).is_same(row_box)
	assert_object(row_box.get_child(doors.get_index() - 1)).is_same(_airline("X", 0))
	assert_object(row_box.get_child(doors.get_index() - 2)).is_same(_line_one("X", 0))


func test_entries_carry_the_head_and_the_airline() -> void:
	var rows: Array[Dictionary] = []
	for entry in DeparturesBoard.entries_for(_sim, _clock.tick):
		if entry["kind"] == "row":
			rows.append(entry)
	assert_str(rows[0]["head"]).is_equal("10:00  Oslo")
	assert_str(rows[0]["airline"]).is_equal(LONGEST)
	assert_str(rows[1]["head"]).is_equal("11:00  Rome")
	assert_str(rows[1]["airline"]).is_equal("Gotta Air")
