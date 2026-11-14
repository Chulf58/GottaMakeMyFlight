class_name TestFlightPlannerLabelRoom
extends GdUnitTestSuite
## A planner bar keeps its label clear of the departure tick without touching the
## theme: the HudGate variation's StyleBoxes are shared by every button on that
## gate colour (Departures Gate buttons, Move choices, other bars), so a bar must
## not write its own right margin into them (board bed80bdd). Each bar's label is
## a child Label whose room ends before that bar's own tick.

const GATES: Array[String] = ["A", "B", "C"]
const STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]

var _port: SubViewport
var _planner: FlightPlanner
var _sim: FlightSim
var _clock: SimClock
## The Gate A right margins as the theme has them, read before the planner opens.
var _pristine: Array[float] = []


func after_test() -> void:
	if _port != null:
		_port.free()
		_port = null


func _boot(size: Vector2i) -> Button:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.open_airport()
	_sim.gate_source = func() -> Array[String]: return GATES
	for spec: Array in [["X", 600, "Oslo"], ["Z", 1230, "Paris"]]:
		var terms := TestFlightContracts.terms(spec[0], spec[1])
		terms["destination"] = spec[2]
		assert_bool(_sim.accept_contract(terms)).is_true()
	_port = SubViewport.new()
	_port.size = size
	add_child(_port)
	# A Departures-style Gate A button, built before the planner opens.
	var gate_button := Button.new()
	gate_button.theme = BuildMenu.HUD_THEME
	gate_button.theme_type_variation = GateColours.variation_of("A")
	_port.add_child(gate_button)
	_pristine = _margins(gate_button)
	_planner = FlightPlanner.new()
	_planner.flights = _sim
	_planner.clock = _clock
	_port.add_child(_planner)
	_planner.open()
	await await_idle_frame()
	await await_idle_frame()
	return gate_button


func _rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _margins(button: Button) -> Array[float]:
	var margins: Array[float] = []
	for state in STATES:
		margins.append(button.get_theme_stylebox(state).get_content_margin(SIDE_RIGHT))
	return margins


func _assert_label_ends_before_tick(bar: Button) -> float:
	var label := FlightPlanner.bar_label(bar)
	assert_object(label).is_not_null()
	var tick := _rect(bar.find_child("DepartureTick", false, false) as Control)
	var label_end := _rect(label).end.x
	print("  %s label ends %.1f, tick at %.1f" % [bar.name, label_end, tick.position.x])
	assert_float(label_end).is_less(tick.position.x)
	assert_float(_rect(label).position.x).is_greater_equal(_rect(bar).position.x)
	return label_end - _rect(bar).position.x


func test_bars_leave_the_shared_gate_theme_styleboxes_alone() -> void:
	var gate_button := await _boot(Vector2i(1536, 864))
	var x := _planner.bar_button("X", 0)
	var z := _planner.bar_button("Z", 0)
	assert_str(str(x.theme_type_variation)).is_equal(str(z.theme_type_variation))
	assert_str(str(x.theme_type_variation)).is_equal(str(gate_button.theme_type_variation))
	# Narrow bar Z by half: its resize must not leak into the theme.
	z.anchor_right = z.anchor_left + (z.anchor_right - z.anchor_left) * 0.5
	await await_idle_frame()
	await await_idle_frame()
	_port.size = Vector2i(1280, 720)
	await await_idle_frame()
	await await_idle_frame()
	print("gate A right margins before %s after %s" % [_pristine, _margins(gate_button)])
	assert_array(_margins(gate_button)).is_equal(_pristine)
	assert_array(_margins(x)).is_equal(_pristine)
	assert_array(_margins(z)).is_equal(_pristine)


func test_each_bars_label_room_ends_before_its_own_tick() -> void:
	await _boot(Vector2i(1536, 864))
	var x := _planner.bar_button("X", 0)
	var z := _planner.bar_button("Z", 0)
	var x_room := _assert_label_ends_before_tick(x)
	var z_room := _assert_label_ends_before_tick(z)
	# Narrowing Z moves Z's label end and leaves X's where it was.
	z.anchor_right = z.anchor_left + (z.anchor_right - z.anchor_left) * 0.5
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_assert_label_ends_before_tick(x)).is_equal_approx(x_room, 0.5)
	assert_float(_assert_label_ends_before_tick(z)).is_less(z_room - 1.0)
	# A smaller viewport narrows both, and each label still stops short of its tick.
	_port.size = Vector2i(1280, 720)
	await await_idle_frame()
	await await_idle_frame()
	_assert_label_ends_before_tick(x)
	_assert_label_ends_before_tick(z)


func test_the_label_takes_the_buttons_font_and_colour_and_the_button_text_is_empty() -> void:
	await _boot(Vector2i(1536, 864))
	var x := _planner.bar_button("X", 0)
	var label := FlightPlanner.bar_label(x)
	assert_str(x.text).is_empty()
	assert_str(label.text).is_equal(x.get_meta(FlightPlanner.FULL_TEXT))
	assert_object(label.get_theme_color("font_color")).is_equal(x.get_theme_color("font_color"))
	assert_int(label.get_theme_font_size("font_size")).is_equal(x.get_theme_font_size("font_size"))
	assert_object(label.get_theme_font("font")).is_same(x.get_theme_font("font"))
	assert_int(label.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
