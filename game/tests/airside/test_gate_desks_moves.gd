class_name TestGateDesksMoves
extends GdUnitTestSuite
## A removal that moves flights to another gate says so (decision gates-
## technical-design-gate-desks-link-to-north-exits-one-st, point 6; smoke
## playtest 11, board f0fbae3c item a): the build ghost's warning names the
## move before it is committed ("Blue Fjord to Oslo moves to Gate B", "2
## flights move to Gate B"), and one coral notice on the right rail says
## "... moved to Gate B" once it is. A removal that moves nothing says nothing.
##
## Two starter shells stand on the site (gates A west, B east), as in
## test_gate_desks.gd; the rail is an AlertStack in the tree, found by its group.

const SITE := preload("res://build/terminal_site.tres")
const EAST := Vector2i(44, 0)
const EXIT_WEST := Vector2i(20, 112)
const DESK_WEST := Vector2i(19, 115)
const DESK_EAST := DESK_WEST + EAST

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _stack: AlertStack
var _west: BuildResult
var _east: BuildResult


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	for result in _grid.apply_batch(ReferenceTerminal.shell_edits(SITE.starter_offset + EAST)):
		assert_bool(result.ok).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_stack = auto_free(AlertStack.new()) as AlertStack
	add_child(_stack)
	_gates = auto_free(GateDesks.new()) as GateDesks
	add_child(_gates)
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	_grid.warner = _gates.edit_warning
	_west = _grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK_WEST, 0))
	_east = _grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK_EAST, 0))
	assert_array(_gates.gate_ids()).is_equal(["A", "B"])


func _accept(id: String, minute: int, airline := "Gotta Air") -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["airline"] = airline
	assert_bool(_flights.accept_contract(terms)).is_true()
	assert_str(_flights.contract_of(id)["gate"]).is_equal("A")


## The notices the rail has written to its history for the move.
func _notices() -> Array:
	return _stack.board().history().filter(
		func(entry: Dictionary) -> bool: return entry["key"] == GateDesks.MOVED_KEY
	)


func _preview(object_id: int) -> String:
	return BuildStatus.front_warning(_grid, BuildEdit.remove_object(object_id))


func test_the_preview_names_the_flight_and_the_gate_it_moves_to() -> void:
	_accept("X", 620, "Blue Fjord")
	var preview := _preview(_west.object_id)
	print("preview: '%s'" % preview)
	assert_str(preview).is_equal("Blue Fjord to Oslo moves to Gate B")
	# Previewing builds nothing and moves nothing.
	assert_bool(GateDesks.is_desk(_grid, _west.object_id)).is_true()
	assert_str(_flights.contract_of("X")["gate"]).is_equal("A")
	assert_array(_notices()).is_empty()


func test_removing_the_exit_previews_the_same_move() -> void:
	_accept("X", 620, "Blue Fjord")
	var preview := _preview(_grid.object_at(EXIT_WEST))
	print("exit preview: '%s'" % preview)
	assert_str(preview).is_equal("Blue Fjord to Oslo moves to Gate B")


func test_several_flights_to_one_gate_read_as_one_line() -> void:
	_accept("X", 620)
	_accept("Y", 840)
	_accept("Z", 1100)
	assert_str(_preview(_west.object_id)).is_equal("3 flights move to Gate B")
	assert_bool(_grid.apply(BuildEdit.remove_object(_west.object_id)).ok).is_true()
	var notices := _notices()
	assert_int(notices.size()).is_equal(1)
	assert_str(notices[0]["detail"]).is_equal("3 flights moved to Gate B")
	assert_object(_stack.notice_card(GateDesks.MOVED_KEY)).is_not_null()


func test_the_commit_posts_one_notice_naming_the_move() -> void:
	_accept("X", 620, "Blue Fjord")
	var removed := _grid.apply(BuildEdit.remove_object(_west.object_id))
	assert_bool(removed.ok).is_true()
	assert_str(_flights.contract_of("X")["gate"]).is_equal("B")
	var notices := _notices()
	print("notices: %s" % [notices])
	assert_int(notices.size()).is_equal(1)
	assert_str(notices[0]["title"]).is_equal(GateDesks.MOVED_TITLE)
	assert_str(notices[0]["detail"]).is_equal("Blue Fjord to Oslo moved to Gate B")
	var card := _stack.notice_card(GateDesks.MOVED_KEY)
	assert_object(card).is_not_null()
	var words := PackedStringArray()
	for label in card.find_children("*", "Label", true, false):
		words.append((label as Label).text)
	assert_array(words).contains(["Blue Fjord to Oslo moved to Gate B"])


func test_a_removal_that_moves_nothing_says_nothing() -> void:
	_accept("X", 620)
	# Control: the same kind of removal, at the gate that holds the contract,
	# does preview and notify, so the silence below is not a dead path.
	assert_str(_preview(_west.object_id)).is_not_empty()
	# Gate B holds no contract: removing its desk ends the gate and moves nothing.
	assert_str(_preview(_east.object_id)).is_empty()
	var removed := _grid.apply(BuildEdit.remove_object(_east.object_id))
	assert_bool(removed.ok).is_true()
	assert_array(_gates.gate_ids()).is_equal(["A"])
	assert_str(_flights.contract_of("X")["gate"]).is_equal("A")
	assert_array(_notices()).is_empty()
	assert_object(_stack.notice_card(GateDesks.MOVED_KEY)).is_null()
