class_name TestDeparturesBoardAirlineLine
extends GdUnitTestSuite
## Each Departures row is two lines (decision departures-list-row-shows-the-
## airline-on-a-second-line, user-ruled 2026-11-12, board 6e77bed2): line 1 has
## the time, the destination and the Gate and End buttons; line 2 has the
## airline's full name in small grey text (HudHint), never trimmed or cut; the
## list keeps its HudLayout.LIST_W width. The next flight's "doors close" caption
## stays under the airline line (decision flight-panel-the-next-departing-
## flight-s-row-shows-a-doors-c).
##
## Tick 0 is 06:00. X leaves at 10:00 (the next flight) and Y at 11:00.

const GATES: Array[String] = ["C", "A", "B"]
const LONGEST := "Skyline Global"

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard
var _rows: Control


## The world and the board are built once for the file; no case changes them
## (the status word cases, which move the clock, are in
## test_departures_board_airline_status.gd).
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


func _airline(id: String, day: int) -> Label:
	return _rows.find_child("Airline_%s_%d" % [id, day], true, false) as Label


func _line_one(id: String, day: int) -> HBoxContainer:
	return _board.gate_button(id, day).get_parent() as HBoxContainer


func test_every_contract_row_has_the_full_airline_name_on_its_own_line() -> void:
	var expected := {"X": LONGEST, "Y": "Gotta Air"}
	for id: String in expected:
		for day in [0, 1]:
			var label := _airline(id, day)
			print("airline label ", id, " day ", day, ": ", label)
			assert_object(label).is_not_null()
			assert_str(label.text).starts_with(expected[id])
			assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_NO_TRIMMING)
			assert_bool(label.clip_text).is_false()


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
	# Control: the label was laid out and the name has a real width.
	assert_float(wide).is_greater(20.0)
	assert_float(label.size.x).is_greater(wide)
	assert_int(label.get_line_count()).is_equal(1)
	for id in ["X", "Y"]:
		assert_int(_airline(id, 0).get_line_count()).is_equal(1)


func test_the_list_stays_at_its_set_width() -> void:
	var panel := _board.find_child("DeparturesPanel", true, false) as Control
	print("panel width ", panel.size.x)
	assert_float(panel.size.x).is_equal_approx(float(HudLayout.LIST_W), 0.5)


func test_line_one_has_the_time_the_destination_and_both_buttons() -> void:
	var line_one := _line_one("X", 0)
	var head := line_one.get_child(0) as Label
	print("line one: ", head.text)
	assert_str(head.text).is_equal("10:00  Oslo")
	assert_str(head.text).not_contains(LONGEST)
	assert_object(_board.gate_button("X", 0).get_parent()).is_same(line_one)
	assert_object(_board.end_button("X", 0).get_parent()).is_same(line_one)


func test_the_doors_close_line_stays_under_the_airline_of_the_next_flight_only() -> void:
	var found := _board.find_children("DoorsClose", "Label", true, false)
	assert_int(found.size()).is_equal(1)
	var doors := found[0] as Label
	assert_str(doors.text).starts_with("doors close")
	assert_object(_rows.get_child(doors.get_index() - 1)).is_same(_airline("X", 0))
	assert_object(_rows.get_child(doors.get_index() - 2)).is_same(_line_one("X", 0))


func test_entries_carry_the_head_and_the_airline() -> void:
	var rows: Array[Dictionary] = []
	for entry in DeparturesBoard.entries_for(_sim, _clock.tick):
		if entry["kind"] == "row":
			rows.append(entry)
	assert_str(rows[0]["head"]).is_equal("10:00  Oslo")
	assert_str(rows[0]["airline"]).is_equal(LONGEST)
	assert_str(rows[1]["head"]).is_equal("11:00  Rome")
	assert_str(rows[1]["airline"]).is_equal("Gotta Air")
