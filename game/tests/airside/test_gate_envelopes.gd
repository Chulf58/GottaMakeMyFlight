class_name TestGateEnvelopes
extends GdUnitTestSuite
## Gates and their stand envelopes (decision runway-and-taxi-technical-design-
## movement-plan-analytic-bookings-planned-pauses, section 3, and the user's
## "Allowed, gate size drops" answer): a gate desk needs its small envelope
## clear and not overlapping another gate's, so exits 19 m apart both make
## gates and 18 m apart do not; a desk whose exit has no room for a small swing
## is refused GATE_NO_ROOM, and one whose way north to the lane is built over
## GATE_ROUTE_BLOCKED; each gate's max_class drops when the player builds into
## its unused larger space, with a warning first; and every edit under the
## envelope of the largest class booked at a gate is refused GATE_ROUTE, the
## same whether it comes as a click, a wall, an undo or a template paste.
##
## The starter shell with its exit at (20, 112); the stand point is at x -26.
## Its gate desk stands at (19, 115). The cells are those of
## test_stand_envelope.gd, north of the shell in row 100.

const SITE := preload("res://build/terminal_site.tres")
const EXIT := Vector2i(20, 112)
const DESK := Vector2i(19, 115)
const SMALL_CELL := Vector2i(17, 100)
const MEDIUM_CELL := Vector2i(32, 100)
const LARGE_CELL := Vector2i(45, 100)
const WAY_CELL := Vector2i(17, 20)
const FREE_CELL := Vector2i(60, 100)

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	_grid.warner = _gates.edit_warning


func _desk(at: Vector2i) -> BuildResult:
	return _grid.apply(BuildEdit.place_object(GateDesks.DESK, at, 0))


func _floor(cell: Vector2i) -> BuildResult:
	return _grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))


## A copy of the starter shell `east` cells east of it, with its exit `east`
## cells east of EXIT.
func _shell_east(east: int) -> void:
	for result in _grid.apply_batch(
		ReferenceTerminal.shell_edits(SITE.starter_offset + Vector2i(east, 0))
	):
		assert_bool(result.ok).is_true()


func _accept(id: String, minute: int, plane_class: String) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["plane_size"] = plane_class
	terms["booked_passengers"] = PlaneClasses.passenger_range(plane_class)[0]
	assert_bool(_flights.accept_contract(terms)).is_true()
	assert_str(_flights.contract_of(id)["gate"]).is_equal("A")


func test_exits_19_m_apart_make_two_gates() -> void:
	_shell_east(19)
	assert_bool(_desk(DESK).ok).is_true()
	var east := _desk(DESK + Vector2i(19, 0))
	print("19 m: %s, gates %s" % [east.ok, _gates.gate_ids()])
	assert_bool(east.ok).is_true()
	assert_array(_gates.gate_ids()).is_equal(["A", "B"])


func test_exits_18_m_apart_overlap_and_the_refusal_names_19_m() -> void:
	_shell_east(18)
	assert_bool(_desk(DESK).ok).is_true()
	var east := _desk(DESK + Vector2i(18, 0))
	print("18 m: %s" % east.reason_text())
	assert_int(east.reason).is_equal(BuildResult.Reason.GATE_STAND_OVERLAP)
	assert_str(east.reason_text()).contains("19 m between exits")
	assert_array(_gates.gate_ids()).is_equal(["A"])


func test_a_desk_with_no_room_for_a_small_swing_is_refused() -> void:
	assert_bool(_floor(SMALL_CELL).ok).is_true()
	var refused := _desk(DESK)
	print("no room: %s" % refused.reason_text())
	assert_int(refused.reason).is_equal(BuildResult.Reason.GATE_NO_ROOM)
	assert_str(refused.reason_text()).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.GATE_NO_ROOM]
	)
	assert_array(_gates.gate_ids()).is_empty()
	# A control: with the floor gone the same desk makes a gate.
	assert_bool(_grid.apply(BuildEdit.remove_floor(SMALL_CELL)).ok).is_true()
	assert_bool(_desk(DESK).ok).is_true()
	assert_array(_gates.gate_ids()).is_equal(["A"])


func test_a_desk_whose_way_north_to_the_lane_is_built_over_is_refused() -> void:
	assert_bool(_floor(WAY_CELL).ok).is_true()
	var refused := _desk(DESK)
	print("route blocked: %s" % refused.reason_text())
	assert_int(refused.reason).is_equal(BuildResult.Reason.GATE_ROUTE_BLOCKED)
	assert_array(_gates.gate_ids()).is_empty()
	# A control: with the floor gone the same desk makes a gate.
	assert_bool(_grid.apply(BuildEdit.remove_floor(WAY_CELL)).ok).is_true()
	assert_bool(_desk(DESK).ok).is_true()


func test_max_class_drops_when_the_unused_larger_space_is_built_into() -> void:
	assert_bool(_desk(DESK).ok).is_true()
	var seen := [_gates.max_class("A")]
	# Medium flights are booked: the large-only space is still free to build.
	_accept("M", 620, PlaneClasses.MEDIUM)
	var warning := _grid.edit_warning(BuildEdit.paint_floor(LARGE_CELL, BuildGrid.FLOOR_TILE, 1))
	var free_warning := _grid.edit_warning(
		BuildEdit.paint_floor(FREE_CELL, BuildGrid.FLOOR_TILE, 1)
	)
	var built := _floor(LARGE_CELL)
	seen.append(_gates.max_class("A"))
	print("max class %s; warning '%s'; free cell warning '%s'" % [seen, warning, free_warning])
	assert_bool(built.ok).is_true()
	assert_array(seen).is_equal(["large", "medium"])
	assert_str(warning).is_equal("Gate A will then take planes up to medium")
	assert_str(free_warning).is_empty()


func test_an_edit_under_the_booked_class_envelope_is_refused_naming_the_gate() -> void:
	assert_bool(_desk(DESK).ok).is_true()
	_accept("L", 620, PlaneClasses.LARGE)
	var refused := _floor(LARGE_CELL)
	var wall := _grid.apply(BuildEdit.place_wall(MEDIUM_CELL, BuildGrid.Side.NORTH))
	var free := _floor(FREE_CELL)
	print(
		"large booked: %s; wall: %s; free %s" % [refused.reason_text(), wall.reason_text(), free.ok]
	)
	assert_int(refused.reason).is_equal(BuildResult.Reason.GATE_ROUTE)
	assert_str(refused.reason_text()).ends_with("gate A, a large plane")
	assert_int(wall.reason).is_equal(BuildResult.Reason.GATE_ROUTE)
	assert_int(_grid.floor_at(LARGE_CELL)).is_equal(BuildGrid.FLOOR_NONE)
	assert_str(_gates.max_class("A")).is_equal("large")
	# A control: outside every envelope the same edit is built.
	assert_bool(free.ok).is_true()


func test_an_undo_inside_the_booked_envelope_is_refused_on_the_copy() -> void:
	assert_bool(_desk(DESK).ok).is_true()
	assert_bool(_floor(LARGE_CELL).ok).is_true()
	var receipt := BuildReceipt.new()
	_grid.recorder = receipt
	assert_bool(_grid.apply(BuildEdit.remove_floor(LARGE_CELL)).ok).is_true()
	_grid.recorder = null
	_accept("L", 620, PlaneClasses.LARGE)
	var snapshot := _grid.to_snapshot()
	var done := [null]
	await (
		assert_error(func() -> void: done[0] = BuildUndo.commit(_grid, receipt, null)).is_success()
	)
	var result: BuildResult = done[0]
	print("undo: %s" % result.reason_text())
	assert_int(result.reason).is_equal(BuildResult.Reason.GATE_ROUTE)
	assert_dict(_grid.to_snapshot()).is_equal(snapshot)


func test_a_template_paste_inside_the_booked_envelope_is_refused_whole() -> void:
	# A cafe saved off a block far east of the stand.
	var block := Rect2i(70, 20, 6, 5)
	var edits: Array[BuildEdit] = []
	for y in range(block.position.y, block.end.y):
		for x in range(block.position.x, block.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_grid.apply_batch(edits)
	var room := _grid.apply(BuildEdit.place_room(Rect2i(71, 21, 4, 3), &"cafe")).room_id
	var template := RoomTemplate.capture(_grid, room)
	assert_object(template).is_not_null()
	assert_bool(_desk(DESK).ok).is_true()
	_accept("L", 620, PlaneClasses.LARGE)
	# The same calls TemplatePaste.plan_at() makes: the plan on a trial copy.
	var inside := BuildUndo.trial_copy_of(_grid).apply_sequence(
		template.plan(LARGE_CELL, 0, _grid), BeltShaper.crossing_problem
	)
	var outside := BuildUndo.trial_copy_of(_grid).apply_sequence(
		template.plan(FREE_CELL + Vector2i(10, 0), 0, _grid), BeltShaper.crossing_problem
	)
	print("paste inside: %s; outside: %s" % [inside.reason_text(), outside.ok])
	assert_int(inside.reason).is_equal(BuildResult.Reason.GATE_ROUTE)
	assert_bool(outside.ok).is_true()
	assert_int(_grid.floor_at(LARGE_CELL)).is_equal(BuildGrid.FLOOR_NONE)


func test_the_three_refusal_texts() -> void:
	var texts := {}
	for reason in [
		BuildResult.Reason.GATE_NO_ROOM,
		BuildResult.Reason.GATE_ROUTE_BLOCKED,
		BuildResult.Reason.GATE_ROUTE,
	]:
		texts[reason] = BuildResult.refused(reason).reason_text()
	print("texts %s" % [texts])
	assert_str(texts[BuildResult.Reason.GATE_NO_ROOM]).is_equal(
		"No room for a plane outside this exit. Keep the ground north of it clear"
	)
	assert_str(texts[BuildResult.Reason.GATE_ROUTE_BLOCKED]).is_equal(
		"Something blocks the way from this exit to the taxi lane. Clear a path north"
	)
	assert_str(texts[BuildResult.Reason.GATE_ROUTE]).is_equal(
		"A booked flight's plane needs this ground. Move its flights in Departures first"
	)
