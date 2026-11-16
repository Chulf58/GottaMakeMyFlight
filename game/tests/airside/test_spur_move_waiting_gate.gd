class_name TestSpurMoveWaitingGate
extends GdUnitTestSuite
## A gate past the west spur waits for the taxiway works (user ruling airside-
## construction-works-are-a-visible-stage-props-mark-th, point 4; decision
## side-spur-move-design-s7-stands-carry-lane-x-the-wanted-spur): a second shell
## far west, on the grid's side land (land == null), has its west exit 29 m
## from the spur at x -124, too near for any plane. Its desk still links, at the
## spur its own stand pushes to (SideSpurs.link_stand()), and the gate says
## "Waiting for taxiway works" and takes no contract until the spur moves. With
## nothing flying the side is quiet, so the spur moves on the next tick, the
## gate takes planes, and one notice on the rail says the taxiway has moved.

const SITE := preload("res://build/terminal_site.tres")
## The second shell's offset from the starter's: 62 cells west.
const WEST_SHELL := Vector2i(-62, 0)

var _base: SiteGrid
var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _stack: AlertStack


func before() -> void:
	_base = SpurMoveKit.base_grid()
	for result in _base.apply_batch(
		ReferenceTerminal.shell_edits(SITE.starter_offset + WEST_SHELL)
	):
		assert_bool(result.ok).is_true()


func before_test() -> void:
	_grid = _base.clone() as SiteGrid
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_stack = auto_free(AlertStack.new()) as AlertStack
	add_child(_stack)
	_gates = auto_free(GateDesks.new()) as GateDesks
	add_child(_gates)
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	var at := SpurMoveKit.WEST_EXIT + SITE.starter_offset + WEST_SHELL
	assert_bool(_grid.apply(BuildEdit.remove_wall(at, BuildGrid.Side.WEST)).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.place_object(&"exit_door", at, 3)).ok).is_true()
	var desk := SpurMoveKit.WEST_DESK + SITE.starter_offset + WEST_SHELL
	var placed := _grid.apply(BuildEdit.place_object(GateDesks.DESK, desk, 0))
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()


func test_a_gate_past_the_spur_waits_then_takes_planes_once_it_moves() -> void:
	var stand: Dictionary = _gates.stands["A"]
	var depth := float(stand["x"]) - StandPlacement.lane_x_of(stand)
	var ground: Dictionary = _gates.gate_grounds()["A"]
	print(
		(
			"gate A sill %.2f, %.2f m from the spur; class now '%s', on the wanted spur %s '%s'"
			% [
				stand["x"],
				depth,
				ground["max_class"],
				ground["next"]["stand"]["lane_x"],
				ground["next"]["max_class"]
			]
		)
	)
	assert_float(depth).is_less(SideSpurs.stand_depth())
	assert_str(ground["max_class"]).is_equal("")
	assert_str(ground["next"]["max_class"]).is_not_equal("")
	assert_bool(_gates.waits_on_spur("A")).is_true()
	assert_str(GateLinksView.caption_text("A", "", GateWalk.NO_ROUTE, true)).is_equal(
		"Gate A\n%s" % GateDesks.WAITING_TEXT
	)
	var terms := SpurMoveKit.terms("C1")
	var waiting := _flights.accept_problem(terms)
	print("accept while waiting: '%s'" % waiting)
	assert_str(waiting).is_not_equal("")
	var moved: Array[String] = []
	_flights.spur_moved.connect(func(side: String) -> void: moved.append(side))
	_flights.on_tick(_flights.tick + 1)
	print(
		(
			"after a tick: moved %s, spur %s, class '%s'"
			% [moved, _gates.spur_x, _gates.max_class("A")]
		)
	)
	assert_array(moved).is_equal(["W"])
	assert_bool(_gates.waits_on_spur("A")).is_false()
	assert_str(_gates.max_class("A")).is_not_equal("")
	assert_str(_flights.accept_problem(terms)).is_equal("")
	var notices := _stack.board().history().filter(
		func(entry: Dictionary) -> bool: return entry["key"] == GateDesks.SPUR_KEY
	)
	print("notices %s" % [notices])
	assert_object(_stack.notice_card(GateDesks.SPUR_KEY)).is_not_null()
	assert_int(notices.size()).is_equal(1)
	assert_str(str(notices[0])).contains("The west taxiway has moved")
