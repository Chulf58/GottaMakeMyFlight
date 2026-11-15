class_name TestFlightPlanner
extends GdUnitTestSuite
## The flight planner sheet (decision flight-planner-a-full-screen-day-planner-
## with-one-row-per-ga, slice 1): rows, bars and colours from the FlightSim, a
## refresh on planning_changed and on a load, Move and End through the
## Departures list's own flows, the pause and the P key.

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim
var _clock: SimClock
var _planner: FlightPlanner


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.open_airport()
	_sim.gate_source = func() -> Array[String]: return GATES
	_planner = FlightPlanner.new()
	_planner.flights = _sim
	_planner.clock = _clock
	add_child(_planner)


func after_test() -> void:
	_planner.free()


func _accept(id: String, minute: int, destination: String) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["destination"] = destination
	assert_bool(_sim.accept_contract(terms)).is_true()


## X 10:00 Oslo on A, Y 11:00 Rome on B, Z 20:00 Paris on A (X's hold ends 11:02).
func _three_contracts() -> void:
	_accept("X", 600, "Oslo")
	_accept("Y", 660, "Rome")
	_accept("Z", 20 * 60, "Paris")


func _press(button: Button) -> void:
	assert_object(button).is_not_null()
	button.pressed.emit()


func test_bars_and_move_choices_take_gate_variations_with_no_override() -> void:
	_three_contracts()
	_planner.open()
	var y := _planner.bar_button("Y", 0)
	assert_str(str(y.theme_type_variation)).is_equal("HudGateB")
	_press(y)
	var selected := _planner.bar_button("Y", 0)
	assert_str(str(selected.theme_type_variation)).is_equal("HudGateSelB")
	var choice := _planner.find_child("Move_C", true, false) as Button
	assert_str(str(choice.theme_type_variation)).is_equal("HudGateC")
	for button in [_planner.bar_button("X", 0), selected, choice]:
		for state in [&"normal", &"hover", &"pressed", &"disabled"]:
			assert_bool(button.has_theme_stylebox_override(state)).is_false()
		assert_bool(button.has_theme_color_override("font_color")).is_false()
	var outline := selected.get_theme_stylebox("normal") as StyleBoxFlat
	# The selected bar keeps the 2 px button border of the HUD grid and stands out by
	# the HUD's teal accent outline drawn just outside it (user ruling flight-planner-
	# selected-bar-2-px-teal-accent-outline; test_gate_colours pins every variation).
	var teal := selected.get_theme_stylebox("normal", "HudButtonTeal") as StyleBoxFlat
	assert_int(outline.border_width_left).is_equal(2)
	assert_object(outline.border_color).is_equal(teal.bg_color)
	assert_float(outline.expand_margin_left).is_greater(0.0)
	assert_object(outline.bg_color).is_equal(GateColours.of("B"))


func test_the_sheet_is_hidden_until_opened_and_the_toggle_sits_beside_departures() -> void:
	var toggle := _planner.toggle_button()
	print("toggle: ", toggle.position, " ", toggle.size, " ", toggle.text)
	assert_bool(_planner.is_open()).is_false()
	assert_str(toggle.text).is_equal("Planner (P)")
	assert_float(toggle.position.y).is_equal(LeftColumn.slot_top(LeftColumn.SLOT_DEPARTURES))
	assert_float(toggle.position.x).is_equal(
		float(HudLayout.MARGIN + HudLayout.TOGGLE_W + HudLayout.GAP)
	)
	assert_float(toggle.position.x + toggle.size.x).is_equal(
		float(HudLayout.MARGIN + HudLayout.LIST_W)
	)


func test_open_shows_one_row_per_gate_with_the_gate_colour_on_its_header() -> void:
	_three_contracts()
	_planner.open()
	assert_bool(_planner.is_open()).is_true()
	assert_array(_planner.row_gates()).is_equal(["A", "B", "C"])
	for gate_id in ["A", "B", "C"]:
		var box := (
			(_planner.part("GateHead_" + gate_id) as PanelContainer).get_theme_stylebox("panel")
			as StyleBoxFlat
		)
		assert_object(box.bg_color).is_equal(GateColours.of(gate_id))
		assert_object(_planner.part("Track_" + gate_id)).is_not_null()


func test_each_contract_is_one_bar_on_its_gate_in_the_gate_colour() -> void:
	_three_contracts()
	_planner.open()
	print("bars: ", _planner.bar_buttons().map(func(b: Button) -> String: return b.name))
	var x := _planner.bar_button("X", 0)
	var y := _planner.bar_button("Y", 0)
	var z := _planner.bar_button("Z", 0)
	assert_object(x.get_parent()).is_equal(_planner.part("Track_" + "A"))
	assert_object(y.get_parent()).is_equal(_planner.part("Track_" + "B"))
	assert_object(z.get_parent()).is_equal(_planner.part("Track_" + "A"))
	# The text is the full label or, when the bar is too tight, the destination alone.
	assert_str(x.get_meta(FlightPlanner.FULL_TEXT)).is_equal("10:00  Oslo")
	assert_str(x.get_meta(FlightPlanner.SHORT_TEXT)).is_equal("Oslo")
	assert_array(["10:00  Oslo", "Oslo"]).contains([FlightPlanner.bar_text(x)])
	assert_object((x.get_theme_stylebox("normal") as StyleBoxFlat).bg_color).is_equal(
		GateColours.of("A")
	)
	assert_object((y.get_theme_stylebox("normal") as StyleBoxFlat).bg_color).is_equal(
		GateColours.of("B")
	)
	# The bar's anchors are the hold's place in the day.
	var starts := FlightTimetable.starts_for(_sim.contract_of("X"), 0)
	var day_start := GameCalendar.day_start(0)
	assert_float(x.anchor_left).is_equal_approx(
		float(starts[0] - day_start) / GameCalendar.TICKS_PER_DAY, 0.0001
	)
	assert_float(x.anchor_right).is_equal_approx(
		float(starts[FlightSim.State.DEPARTED] - day_start) / GameCalendar.TICKS_PER_DAY, 0.0001
	)
	assert_object(x.find_child("DepartureTick", false, false)).is_not_null()


func test_planning_changed_redraws_the_rows() -> void:
	_three_contracts()
	_planner.open()
	assert_array(_planner.row_gates()).is_equal(["A", "B", "C"])
	_sim.gate_source = func() -> Array[String]: return ["A", "B", "C", "D"]
	_sim.check_planning_changed()
	await await_idle_frame()
	print("rows after a new gate: ", _planner.row_gates())
	assert_array(_planner.row_gates()).is_equal(["A", "B", "C", "D"])
	assert_object(_planner.part("Track_" + "D")).is_not_null()


func test_a_change_while_closed_shows_when_opened() -> void:
	_three_contracts()
	_planner.open()
	_planner.close()
	_accept("W", 15 * 60, "Rome")
	_planner.open()
	assert_object(_planner.bar_button("W", 0)).is_not_null()


func test_a_load_closes_the_sheet_and_the_next_open_shows_the_loaded_world() -> void:
	_three_contracts()
	_planner.open()
	var snapshot := _sim.to_snapshot()
	_accept("W", 15 * 60, "Rome")
	_planner.refresh()
	assert_object(_planner.bar_button("W", 0)).is_not_null()
	_sim.from_snapshot(snapshot)
	print("open after load: ", _planner.is_open(), " clock paused: ", _clock.paused)
	assert_bool(_planner.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	_planner.open()
	assert_object(_planner.bar_button("W", 0)).is_null()
	assert_object(_planner.bar_button("X", 0)).is_not_null()


func test_the_day_follows_the_clock() -> void:
	_three_contracts()
	_clock.tick = GameCalendar.tick_at(2, 9 * 60)
	_planner.open()
	assert_int(_planner.shown_day()).is_equal(2)
	assert_object(_planner.bar_button("X", 2)).is_not_null()
	assert_object(_planner.bar_button("X", 0)).is_null()
	_clock.tick = GameCalendar.tick_at(3, 9 * 60)
	await await_idle_frame()
	assert_int(_planner.shown_day()).is_equal(3)


func test_a_bar_click_offers_only_the_gates_the_flight_fits() -> void:
	_three_contracts()
	_planner.open()
	_press(_planner.bar_button("Y", 0))
	print("summary: ", _planner.summary_text())
	assert_str(_planner.selected_contract()).is_equal("Y")
	assert_str(_planner.summary_text()).is_equal("11:00  Rome  Gate B")
	# A is taken by X at that hour, B is Y's own: only C is offered.
	assert_object(_planner.part("Move_" + "C") as Button).is_not_null()
	assert_object(_planner.part("Move_" + "A") as Button).is_null()
	assert_object(_planner.part("Move_" + "B") as Button).is_null()
	assert_object(_planner.part("EndContract") as Button).is_not_null()


func test_choosing_a_gate_moves_the_contract_through_the_departures_flow() -> void:
	_three_contracts()
	_planner.open()
	_press(_planner.bar_button("Y", 0))
	_press(_planner.part("Move_" + "C") as Button)
	print("moved: ", _sim.contract_of("Y")["gate"], " ", _planner.message_text())
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("C")
	assert_str(_planner.message_text()).is_equal(DeparturesBoard.MOVED_TEXT % ["Rome", "C"])
	assert_object(_planner.bar_button("Y", 0).get_parent()).is_equal(_planner.part("Track_" + "C"))
	assert_str(_planner.selected_contract()).is_equal("Y")


func test_a_refused_move_says_why_and_keeps_the_selection() -> void:
	_three_contracts()
	_planner.open()
	_press(_planner.bar_button("Y", 0))
	var stale := _planner.part("Move_C") as Button
	# Gate C loses its stand between the click that listed it and the press.
	_sim.gate_source = func() -> Array[String]: return ["A", "B"]
	_press(stale)
	print("refusal: ", _planner.message_text())
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("B")
	assert_str(_planner.message_text()).is_equal(DeparturesBoard.BUSY_TEXT % "C")
	assert_str(_planner.selected_contract()).is_equal("Y")


func test_end_asks_first_then_ends_the_contract() -> void:
	_three_contracts()
	_planner.open()
	_press(_planner.bar_button("Z", 0))
	_press(_planner.part("EndContract") as Button)
	assert_object(_planner.part("ConfirmEnd") as Button).is_not_null()
	assert_bool(_sim.active_contract_ids().has("Z")).is_true()
	_press(_planner.part("KeepContract") as Button)
	assert_bool(_sim.active_contract_ids().has("Z")).is_true()
	assert_object(_planner.part("ConfirmEnd") as Button).is_null()
	_press(_planner.part("EndContract") as Button)
	_press(_planner.part("ConfirmEnd") as Button)
	print("end message: ", _planner.message_text())
	assert_bool(_sim.active_contract_ids().has("Z")).is_false()
	assert_str(_planner.message_text()).is_equal(DeparturesBoard.ENDED_TEXT % "Paris")
	assert_str(_planner.selected_contract()).is_equal("")


func test_the_planner_pauses_the_clock_like_the_offers_sheet() -> void:
	_planner.open()
	assert_bool(_clock.paused).is_true()
	_planner.close()
	assert_bool(_clock.paused).is_false()
	_planner.open()
	_planner.toggle_button().pressed.emit()
	assert_bool(_planner.is_open()).is_false()
	assert_bool(_clock.paused).is_false()


func test_close_button_and_the_p_key_open_and_close_the_sheet() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_P
	key.pressed = true
	assert_bool(key.is_action_pressed(FlightPlanner.ACTION)).is_true()
	_planner._shortcut_input(key)
	assert_bool(_planner.is_open()).is_true()
	_press(_planner.part("PlannerClose") as Button)
	assert_bool(_planner.is_open()).is_false()
	_planner._shortcut_input(key)
	_planner._shortcut_input(key)
	assert_bool(_planner.is_open()).is_false()


func test_an_unchanged_world_does_not_rebuild_the_grid_every_frame() -> void:
	_three_contracts()
	_planner.open()
	var builds := _planner.rebuild_count()
	for i in 4:
		await await_idle_frame()
	assert_int(_planner.rebuild_count()).is_equal(builds)
