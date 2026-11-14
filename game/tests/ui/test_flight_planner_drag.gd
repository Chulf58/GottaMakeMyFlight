class_name TestFlightPlannerDrag
extends GdUnitTestSuite
## Dragging a planner bar onto another gate row (decision flight-planner-a-full-
## screen-day-planner-with-one-row-per-ga, slice 2). Every case drives the real
## viewport (anti-pattern a-main-tscn-click-test-that-calls-unhandled-input-
## directly-m): a mouse press on the bar, motion past the drag threshold with the
## left button held, and the release. X 10:00 Oslo and Z 20:00 Paris are on gate
## A, Y 11:00 Rome on B (A is taken by X at that hour), and C is empty.

const GATES: Array[String] = ["A", "B", "C"]
const PORT_SIZE := Vector2i(1536, 864)
## Far past Godot's drag threshold, so the drag starts on this motion.
const PAST_THRESHOLD := Vector2(40.0, 0.0)
## Well inside it, so a press with a little wobble stays a click.
const WOBBLE := Vector2(3.0, 0.0)

var _port: SubViewport
var _sim: FlightSim
var _clock: SimClock
var _planner: FlightPlanner
var _mouse := Vector2.ZERO
var _mask := 0


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.open_airport()
	_sim.gate_source = func() -> Array[String]: return GATES
	for spec: Array in [["X", 600, "Oslo"], ["Y", 660, "Rome"], ["Z", 1200, "Paris"]]:
		var terms := TestFlightContracts.terms(spec[0], spec[1])
		terms["destination"] = spec[2]
		assert_bool(_sim.accept_contract(terms)).is_true()
	_port = SubViewport.new()
	_port.size = PORT_SIZE
	add_child(_port)
	_planner = FlightPlanner.new()
	_planner.flights = _sim
	_planner.clock = _clock
	_port.add_child(_planner)
	_mouse = Vector2.ZERO
	_mask = 0


func after_test() -> void:
	_port.free()
	_port = null


func _open() -> void:
	_planner.open()
	await await_idle_frame()
	await await_idle_frame()


func _track(gate_id: String) -> PlannerTrack:
	var track := _planner.part("Track_" + gate_id) as PlannerTrack
	assert_object(track).is_not_null()
	return track


func _centre(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size / 2.0)


## A point on the track's lane at `hour`, half way down the row.
func _lane_at(gate_id: String, hour: float) -> Vector2:
	var track := _track(gate_id)
	return (
		track.get_global_transform_with_canvas()
		* Vector2(track.size.x * hour / 24.0, track.size.y / 2.0)
	)


func _move(to: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = to - _mouse
	event.button_mask = _mask
	event.position = to
	event.global_position = to
	_mouse = to
	_port.push_input(event)
	await await_idle_frame()


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.button_mask = _mask
	event.position = _mouse
	event.global_position = _mouse
	_port.push_input(event)
	await await_idle_frame()


## Presses on `bar`, drags past the threshold and on to `at`, button still held.
func _drag_over(bar: Button, at: Vector2) -> void:
	assert_object(bar).is_not_null()
	await _move(_centre(bar))
	await _button(true)
	await _move(_centre(bar) + PAST_THRESHOLD)
	await _move(at)
	await _move(at + Vector2(1.0, 0.0))


func _greyed() -> Dictionary:
	var greyed := {}
	for gate_id in GATES:
		greyed[gate_id] = _track(gate_id).is_greyed()
	return greyed


func test_a_drop_on_a_fitting_row_moves_the_contract_to_that_gate() -> void:
	await _open()
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("B")
	await _drag_over(_planner.bar_button("Y", 0), _centre(_track("C")))
	assert_bool(_port.gui_is_dragging()).is_true()
	await _button(false)
	await await_idle_frame()
	print(
		"after the drop: gate=", _sim.contract_of("Y")["gate"], " message=", _planner.message_text()
	)
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("C")
	assert_str(_planner.message_text()).is_equal(DeparturesBoard.MOVED_TEXT % ["Rome", "C"])
	assert_object(_planner.bar_button("Y", 0).get_parent()).is_equal(_track("C"))
	# A drag is not a click: nothing was selected on the way.
	assert_str(_planner.selected_contract()).is_equal("")


func test_a_drop_on_a_refused_row_leaves_the_gate_and_says_why() -> void:
	await _open()
	var problem := _sim.reassign_problem("Y", "A")
	var reason := DeparturesBoard.reason_text(_sim, problem, "A")
	print("refusal for Y on A: '%s' -> '%s'" % [problem, reason])
	assert_str(problem).is_not_empty()
	assert_str(reason).contains("Gate A")
	# 13:00 on A is lane, clear of X's and Z's bars.
	await _drag_over(_planner.bar_button("Y", 0), _lane_at("A", 13.0))
	assert_bool(_port.gui_is_dragging()).is_true()
	assert_str(_planner.message_text()).is_equal(reason)
	await _button(false)
	await await_idle_frame()
	print(
		"after the drop: gate=", _sim.contract_of("Y")["gate"], " message=", _planner.message_text()
	)
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("B")
	assert_str(_planner.message_text()).is_equal(reason)
	assert_object(_planner.bar_button("Y", 0).get_parent()).is_equal(_track("B"))


func test_while_dragging_refused_rows_are_greyed_and_fitting_rows_are_not() -> void:
	await _open()
	var before := _greyed()
	print("greyed before the drag: ", before)
	assert_dict(before).is_equal({"A": false, "B": false, "C": false})
	var y := _planner.bar_button("Y", 0)
	await _drag_over(y, _centre(_track("C")))
	var during := _greyed()
	print("greyed during the drag: ", during, " message over C: '%s'" % _planner.message_text())
	assert_bool(_port.gui_is_dragging()).is_true()
	# A clashes with X; C fits; B is Y's own row, not a refusal.
	assert_dict(during).is_equal({"A": true, "B": false, "C": false})
	assert_str(_planner.message_text()).is_equal(FlightPlanner.drop_text("Rome", "C"))
	assert_str(_planner.message_text()).contains("Days already issued keep their gate")
	# Over X's bar on A the row's reason shows: the bar passes the drop check to its row.
	await _move(_centre(_planner.bar_button("X", 0)))
	var reason := DeparturesBoard.reason_text(_sim, _sim.reassign_problem("Y", "A"), "A")
	print("message over X's bar: '%s'" % _planner.message_text())
	assert_str(_planner.message_text()).is_equal(reason)
	# Released over the hour labels the drag ends with no move, and the grey goes.
	await _move(_centre(_planner.part("Hours")))
	await _button(false)
	await await_idle_frame()
	print("greyed after the drag: ", _greyed())
	assert_bool(_port.gui_is_dragging()).is_false()
	assert_dict(_greyed()).is_equal({"A": false, "B": false, "C": false})
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("B")


func test_after_a_drop_an_issued_day_keeps_its_old_gate() -> void:
	for t in range(_sim.tick + 1, GameCalendar.tick_at(0, 7 * 60) + 1):
		_sim.on_tick(t)
	_clock.tick = GameCalendar.tick_at(0, 7 * 60)
	await _open()
	assert_str(_sim.contract_of("X")["gate"]).is_equal("A")
	await _drag_over(_planner.bar_button("X", 0), _centre(_track("C")))
	await _button(false)
	await await_idle_frame()
	print(
		"after the drop: gate=", _sim.contract_of("X")["gate"], " message=", _planner.message_text()
	)
	assert_str(_sim.contract_of("X")["gate"]).is_equal("C")
	assert_str(_planner.message_text()).is_equal(DeparturesBoard.MOVED_TEXT % ["Oslo", "C"])
	# Today's flight was issued at A and stays there.
	assert_object(_planner.bar_button("X", 0).get_parent()).is_equal(_track("A"))
	# Control: the next day, not yet issued, is on C.
	_clock.tick = GameCalendar.tick_at(1, 7 * 60)
	await await_idle_frame()
	await await_idle_frame()
	print("day %d: X on %s" % [_planner.shown_day(), _planner.bar_button("X", 1).get_parent().name])
	assert_object(_planner.bar_button("X", 1).get_parent()).is_equal(_track("C"))


func test_a_plain_click_on_a_bar_still_opens_move_and_end() -> void:
	await _open()
	assert_str(_planner.selected_contract()).is_equal("")
	assert_object(_planner.part("EndContract")).is_null()
	var y := _planner.bar_button("Y", 0)
	await _move(_centre(y))
	await _button(true)
	await _move(_centre(y) + WOBBLE)
	await _button(false)
	await await_idle_frame()
	print("after the click: ", _planner.selected_contract(), " summary=", _planner.summary_text())
	assert_bool(_port.gui_is_dragging()).is_false()
	assert_str(_planner.selected_contract()).is_equal("Y")
	assert_object(_planner.part("EndContract")).is_not_null()
	assert_object(_planner.part("Move_C")).is_not_null()
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("B")
