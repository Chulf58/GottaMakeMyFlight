class_name TestHintsGate
extends GdUnitTestSuite
## The gate desk and seats hints (board D3a, decision first-time-hints-gain-
## place-gate-desk-and-place-seats-the-hi): the gate desk shows when the player
## opens the Gates category or once check-in and security are placed, and the
## seats hint follows once a gate has its desk.

var _path: String


func before_test() -> void:
	_path = SaveTestKit.run_path("hints_gate")
	DirAccess.remove_absolute(_path)


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


func _world(over := {}) -> Dictionary:
	var world := {
		"desks": 1,
		"scanners": 1,
		"arches": 0,
		"gate_desks": 0,
		"seats": 0,
		"shortage_roles": [],
		"hiring_roles": [],
		"max_toilet_need": 0,
		"max_hunger": 0,
		"stalls": 1,
		"cafes": 1,
	}
	world.merge(over, true)
	return world


func _settled(world: Dictionary) -> Hints:
	var hints := Hints.new()
	hints.forced_mode = Hints.Mode.PROFILE
	hints.settings_path = _path
	add_child(hints)
	auto_free(hints)
	hints.advance(Hints.GRACE_S + 0.1, world, [])
	return hints


func _run(hints: Hints, seconds: float, world: Dictionary, open: Array = []) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(0.25, left)
		hints.advance(step, world, open)
		left -= step


func test_opening_the_gates_category_shows_the_gate_desk_hint() -> void:
	var hints := _settled(_world())
	_run(hints, 1.0, _world(), ["Gates"])
	assert_bool(hints.is_showing()).is_false()
	_run(hints, HintRules.HOLD_S, _world(), ["Gates"])
	print("GATES OPEN shown=%s text=%s" % [hints.shown_id(), hints.body_label().text])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_GATE_DESK)
	assert_str(hints.body_label().text).is_equal(HintRules.text(HintRules.PLACE_GATE_DESK))
	assert_bool(hints.is_seen(HintRules.PLACE_GATE_DESK)).is_true()


func test_placing_check_in_and_security_shows_the_gate_desk_hint_with_no_category() -> void:
	var before := _world({"desks": 0, "scanners": 0})
	var hints := _settled(before)
	_run(hints, 1.0, before)
	_run(hints, HintRules.HOLD_S + 0.5, _world())
	print("PLACED shown=%s" % hints.shown_id())
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_GATE_DESK)


func test_the_gate_desk_hint_is_not_due_before_security_stands() -> void:
	var world := _world({"scanners": 0})
	var hints := _settled(world)
	_run(hints, HintRules.HOLD_S + 1.0, world, ["Gates"])
	assert_str(hints.shown_id()).is_not_equal(HintRules.PLACE_GATE_DESK)
	assert_bool(hints.is_seen(HintRules.PLACE_GATE_DESK)).is_false()


func test_the_seats_hint_shows_on_the_gates_category_once_a_gate_has_its_desk() -> void:
	var world := _world({"gate_desks": 1})
	var hints := _settled(world)
	_run(hints, HintRules.HOLD_S + 1.0, world, ["Gates"])
	print("SEATS shown=%s text=%s" % [hints.shown_id(), hints.body_label().text])
	assert_str(hints.shown_id()).is_equal(HintRules.PLACE_SEATS)
	assert_bool(hints.is_seen(HintRules.PLACE_GATE_DESK)).is_false()


func test_a_seated_gate_needs_no_seats_hint() -> void:
	var world := _world({"gate_desks": 1, "seats": 2})
	var hints := _settled(world)
	_run(hints, Hints.IDLE_S + 5.0, world, ["Gates"])
	assert_bool(hints.is_showing()).is_false()
