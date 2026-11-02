class_name TestGateDesks
extends GdUnitTestSuite
## Gate desks make gates (GateDesks; decision gates-technical-design-gate-
## desks-link-to-north-exits-one-st, points 1 and 6): a desk links to the
## nearest free north exit within 4 cells and gets the first free letter; the
## link is sticky; a desk with no exit, or whose stand would overlap another
## gate's, is refused before it is built; removing a gate moves its contracts
## to the other gates first, and is refused while a flight is due there or
## while a contract fits no other gate. The links survive a save.
##
## Two starter shells stand on the site: the starter one with its exit at
## (20, 112) and a copy 44 cells east with its exit at (64, 112), 44 m apart,
## so their stands' sweeps (41.2 m wide) do not meet.

const SITE := preload("res://build/terminal_site.tres")
const EAST := Vector2i(44, 0)
const EXIT_WEST := Vector2i(20, 112)
const EXIT_EAST := EXIT_WEST + EAST
const DESK_WEST := Vector2i(19, 115)
const DESK_EAST := DESK_WEST + EAST
## A second north exit in the starter shell's wall, 9 m west of its exit.
const EXIT_NEAR := Vector2i(11, 112)
## By the entrance, far from every exit.
const DESK_NOWHERE := Vector2i(12, 125)

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	for result in _grid.apply_batch(ReferenceTerminal.shell_edits(SITE.starter_offset + EAST)):
		assert_bool(result.ok).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem


func _desk(at: Vector2i) -> BuildResult:
	return _grid.apply(BuildEdit.place_object(GateDesks.DESK, at, 0))


func _accept(id: String, minute: int) -> String:
	assert_bool(_flights.accept_contract(TestFlightContracts.terms(id, minute))).is_true()
	return _flights.contract_of(id)["gate"]


func test_a_desk_links_to_the_nearest_north_exit_and_gives_flights_a_gate() -> void:
	assert_array(_flights.gate_ids()).is_empty()
	var west := _desk(DESK_WEST)
	var east := _desk(DESK_EAST)
	print("bindings %s" % [_gates.bindings])
	assert_bool(west.ok).is_true()
	assert_bool(east.ok).is_true()
	(
		assert_array(_gates.bindings)
		. is_equal(
			[
				{"gate": "A", "desk": west.object_id, "exit": _grid.object_at(EXIT_WEST)},
				{"gate": "B", "desk": east.object_id, "exit": _grid.object_at(EXIT_EAST)},
			]
		)
	)
	assert_array(_flights.gate_ids()).is_equal(["A", "B"])
	assert_str(_accept("X", 600)).is_equal("A")
	assert_str(_accept("Y", 660)).is_equal("B")


func test_a_desk_with_no_free_exit_in_reach_is_refused() -> void:
	var far := _desk(DESK_NOWHERE)
	assert_int(far.reason).is_equal(BuildResult.Reason.GATE_NO_EXIT)
	assert_bool(_desk(DESK_WEST).ok).is_true()
	# The one exit in reach is taken by the first desk.
	var second := _desk(DESK_WEST + Vector2i(-3, -1))
	print("far: %s; second by a taken exit: %s" % [far.reason_text(), second.reason_text()])
	assert_int(second.reason).is_equal(BuildResult.Reason.GATE_NO_EXIT)
	assert_array(_gates.gate_ids()).is_equal(["A"])


func test_a_desk_whose_stand_would_overlap_another_gates_is_refused() -> void:
	assert_bool(_desk(DESK_WEST).ok).is_true()
	_add_exit(EXIT_NEAR)
	var near := _desk(EXIT_NEAR + Vector2i(0, 3))
	print("overlap: %s" % near.reason_text())
	assert_int(near.reason).is_equal(BuildResult.Reason.GATE_STAND_OVERLAP)
	assert_str(near.reason_text()).contains("gate A")
	# The text names the spacing the sweeps need and the fix (board 99678753).
	var need := StandPlacement.EXIT_SPACING_CELLS
	assert_str(near.reason_text()).contains("%d m between exits" % need)
	assert_str(near.reason_text()).contains("Widen the terminal")
	assert_array(_gates.gate_ids()).is_equal(["A"])
	# A control: the east desk, 44 m away, is accepted.
	assert_bool(_desk(DESK_EAST).ok).is_true()


func test_a_link_stays_when_a_nearer_exit_is_built() -> void:
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, Vector2i(17, 113), 0))
	assert_bool(desk.ok).is_true()
	var first := _grid.object_at(EXIT_WEST)
	assert_int(_gates.bindings[0]["exit"]).is_equal(first)
	var nearer := _add_exit(Vector2i(16, 112))
	print("linked exit %d, nearer exit %d" % [_gates.bindings[0]["exit"], nearer])
	assert_int(_gates.bindings[0]["exit"]).is_equal(first)
	# A control: with no link kept, the desk would take the nearer exit.
	var fresh := GateDesks.links_on(_grid, [] as Array[Dictionary])
	assert_int(fresh[0]["exit"]).is_equal(nearer)


func test_removing_a_gate_moves_its_contracts_to_another_gate_first() -> void:
	var west := _desk(DESK_WEST)
	assert_bool(_desk(DESK_EAST).ok).is_true()
	assert_str(_accept("X", 600)).is_equal("A")
	var removed := _grid.apply(BuildEdit.remove_object(west.object_id))
	print(
		(
			"removal %s, X at %s, gates %s"
			% [removed.ok, _flights.contract_of("X")["gate"], _gates.gate_ids()]
		)
	)
	assert_bool(removed.ok).is_true()
	assert_str(_flights.contract_of("X")["gate"]).is_equal("B")
	assert_array(_flights.gate_ids()).is_equal(["B"])


func test_removing_the_only_gate_with_a_contract_is_refused_naming_it() -> void:
	var west := _desk(DESK_WEST)
	assert_str(_accept("X", 600)).is_equal("A")
	var removed := _grid.apply(BuildEdit.remove_object(west.object_id))
	var exit := _grid.apply(BuildEdit.remove_object(_grid.object_at(EXIT_WEST)))
	print("desk removal: %s; exit removal: %s" % [removed.reason_text(), exit.reason_text()])
	assert_int(removed.reason).is_equal(BuildResult.Reason.GATE_FLIGHTS_STUCK)
	assert_str(removed.reason_text()).contains("X")
	assert_int(exit.reason).is_equal(BuildResult.Reason.GATE_FLIGHTS_STUCK)
	assert_bool(GateDesks.is_desk(_grid, west.object_id)).is_true()
	assert_str(_flights.contract_of("X")["gate"]).is_equal("A")


func test_removing_a_gate_with_a_flight_due_is_refused_until_it_has_left() -> void:
	var west := _desk(DESK_WEST)
	assert_bool(_desk(DESK_EAST).ok).is_true()
	var starts := FlightSim.schedule_starts(1000)
	assert_bool(_flights.add_flight("ONE", starts, "A")).is_true()
	var removed := _grid.apply(BuildEdit.remove_object(west.object_id))
	print("with ONE due: %s" % removed.reason_text())
	assert_int(removed.reason).is_equal(BuildResult.Reason.GATE_IN_USE)
	assert_str(removed.reason_text()).contains("ONE")
	_flights.on_tick(starts[FlightSim.State.DEPARTED])
	assert_bool(_grid.apply(BuildEdit.remove_object(west.object_id)).ok).is_true()


func test_a_batch_that_removes_two_gates_counts_both_as_gone() -> void:
	var west := _desk(DESK_WEST)
	var east := _desk(DESK_EAST)
	assert_str(_accept("X", 600)).is_equal("A")
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_object(west.object_id), BuildEdit.remove_object(east.object_id)
	]
	var results := _grid.apply_batch(edits)
	print(
		(
			"batch: %s, %s; X at %s"
			% [results[0].ok, results[1].reason_text(), _flights.contract_of("X")["gate"]]
		)
	)
	assert_bool(results[0].ok).is_true()
	assert_int(results[1].reason).is_equal(BuildResult.Reason.GATE_FLIGHTS_STUCK)
	assert_str(_flights.contract_of("X")["gate"]).is_equal("B")
	assert_array(_gates.gate_ids()).is_equal(["B"])


func test_a_letter_a_running_contract_names_is_not_given_to_a_new_gate() -> void:
	var west := _desk(DESK_WEST)
	assert_str(_accept("X", 600)).is_equal("A")
	# The west gate is saved as B (a load), so only contract X still names A.
	var data := _gates.to_snapshot()
	data["gates"][0]["gate"] = "B"
	assert_bool(_gates.from_snapshot(data)).is_true()
	assert_bool(_desk(DESK_EAST).ok).is_true()
	print("gates after the load and a new desk: %s" % [_gates.gate_ids()])
	assert_array(_gates.gate_ids()).is_equal(["B", "C"])
	assert_int(_gates.bindings[0]["desk"]).is_equal(west.object_id)


func test_the_links_round_trip_a_snapshot_and_bad_ones_are_refused() -> void:
	var west := _desk(DESK_WEST)
	assert_bool(_desk(DESK_EAST).ok).is_true()
	var data: Dictionary = JSON.parse_string(JSON.stringify(_gates.to_snapshot()))
	var loaded := GateDesks.checked(data, _grid)
	assert_array(loaded["gates"]).is_equal(_gates.bindings)
	var exit_west := _grid.object_at(EXIT_WEST)
	var bad := {
		"letter": {"gate": "a", "desk": west.object_id, "exit": exit_west},
		"desk": {"gate": "A", "desk": exit_west, "exit": exit_west},
		"exit": {"gate": "A", "desk": west.object_id, "exit": west.object_id},
		"keys": {"gate": "A", "desk": west.object_id},
	}
	for why: String in bad:
		var broken := data.duplicate(true)
		broken["gates"][0] = bad[why]
		var refused := GateDesks.checked(broken, _grid)
		print("%s: %s" % [why, refused.get("error", "accepted")])
		assert_bool(refused.has("error")).is_true()
	var twice := data.duplicate(true)
	twice["gates"][1]["exit"] = exit_west
	assert_str(GateDesks.checked(twice, _grid).get("error", "")).contains("used twice")
	var version := data.duplicate(true)
	version["save_version"] = 2
	assert_bool(GateDesks.checked(version, _grid).has("error")).is_true()


func test_a_saved_set_the_links_would_not_make_is_refused() -> void:
	assert_bool(_desk(DESK_WEST).ok).is_true()
	var data := _gates.to_snapshot()
	# A desk with no saved gate that refresh() would link on load.
	var missing := data.duplicate(true)
	(missing["gates"] as Array).clear()
	# Desks built past the guard (as a hand-made save could hold them): one by
	# the entrance, out of every exit's reach, and one by a second north exit
	# whose stand overlaps gate A's.
	_grid.guard = Callable()
	var far := _desk(DESK_NOWHERE)
	var near_exit := _add_exit(EXIT_NEAR)
	var near := _desk(EXIT_NEAR + Vector2i(0, 3))
	_grid.guard = _gates.edit_problem
	assert_bool(far.ok and near.ok).is_true()
	var out_of_reach := data.duplicate(true)
	out_of_reach["gates"][0]["desk"] = far.object_id
	var overlapping := data.duplicate(true)
	(overlapping["gates"] as Array).append({"gate": "B", "desk": near.object_id, "exit": near_exit})
	var errors := {}
	for why: String in ["missing", "out_of_reach", "overlapping"]:
		var broken: Dictionary = {
			"missing": missing, "out_of_reach": out_of_reach, "overlapping": overlapping
		}[why]
		errors[why] = GateDesks.checked(broken, _grid).get("error", "accepted")
	print("set checks: %s" % [errors])
	assert_str(errors["missing"]).contains("no saved gate")
	assert_str(errors["out_of_reach"]).contains("out of its exit's reach")
	assert_str(errors["overlapping"]).contains("overlapping stands")
	# A control: the live set is accepted.
	assert_bool(GateDesks.checked(data, _grid).has("gates")).is_true()


func test_an_exit_built_by_a_desk_with_no_gate_never_links_an_overlapping_gate() -> void:
	var west := _desk(DESK_WEST)
	# Its exit goes (no flight is due), so the west desk has no gate.
	assert_bool(_grid.apply(BuildEdit.remove_object(_grid.object_at(EXIT_WEST))).ok).is_true()
	assert_array(_gates.gate_ids()).is_empty()
	# A gate by a second north exit, 9 m west.
	_add_exit(EXIT_NEAR)
	assert_bool(_desk(EXIT_NEAR + Vector2i(0, 3)).ok).is_true()
	# The exit comes back within the west desk's reach. Its stand would overlap
	# the new gate's, so the west desk stays without a gate.
	var back := _grid.apply(BuildEdit.place_object(&"exit_door", EXIT_WEST, 0))
	print("exit back: %s; bindings %s" % [back.ok, _gates.bindings])
	assert_bool(back.ok).is_true()
	assert_array(_gates.gate_ids()).is_equal(["A"])
	(
		assert_bool(
			_gates.bindings.any(func(b: Dictionary) -> bool: return b["desk"] == west.object_id)
		)
		. is_false()
	)
	for i in _gates.bindings.size():
		for j in range(i + 1, _gates.bindings.size()):
			var a := StandPlacement.for_exit(_grid, _gates.bindings[i]["exit"])
			var b := StandPlacement.for_exit(_grid, _gates.bindings[j]["exit"])
			assert_bool(GateDesks.stands_overlap(a, b)).is_false()


## Opens a north exit in the starter shell's wall at `cell`; its id.
func _add_exit(cell: Vector2i) -> int:
	assert_bool(_grid.apply(BuildEdit.remove_wall(cell, BuildGrid.Side.NORTH)).ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", cell, 0))
	assert_bool(placed.ok).is_true()
	return placed.object_id


func test_the_refusal_spacing_is_the_least_whole_gap_that_clears_two_stands() -> void:
	var need := StandPlacement.EXIT_SPACING_CELLS
	var base := StandPlacement.make(1, 20.5, 112.0)
	var apart := StandPlacement.make(2, 20.5 + need, 112.0)
	var one_short := StandPlacement.make(3, 20.5 + need - 1, 112.0)
	print(
		(
			"spacing %d, overlap at %d: %s, at %d: %s"
			% [
				need,
				need,
				GateDesks.stands_overlap(base, apart),
				need - 1,
				GateDesks.stands_overlap(base, one_short)
			]
		)
	)
	assert_int(need).is_greater(0)
	assert_bool(GateDesks.stands_overlap(base, apart)).is_false()
	assert_bool(GateDesks.stands_overlap(base, one_short)).is_true()
