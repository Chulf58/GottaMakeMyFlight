class_name TestGateDesksUnlinked
extends GdUnitTestSuite
## Why a gate desk has no gate (GateDesks.unlinked(), Gates 2/4): a desk whose
## exit went has no north exit in reach (NO_EXIT); a desk whose only exit in
## reach is another gate's names that gate (EXIT_TAKEN); a desk whose free exit
## would overlap a gate's stand names that gate (STAND_OVERLAP). Linked desks
## are never listed.
##
## The site of test_gate_desks.gd: the starter shell with its exit at (20, 112)
## and a copy 44 cells east with its exit at (64, 112).

const SITE := preload("res://build/terminal_site.tres")
const EAST := Vector2i(44, 0)
const EXIT_WEST := Vector2i(20, 112)
const EXIT_EAST := EXIT_WEST + EAST
const DESK_WEST := Vector2i(19, 115)
const DESK_EAST := DESK_WEST + EAST
## A second north exit in the starter shell's wall, 9 m west of its exit.
const EXIT_NEAR := Vector2i(11, 112)

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


## A north exit opened in a shell's north wall at `cell`.
func _open_exit(cell: Vector2i) -> BuildResult:
	assert_bool(_grid.apply(BuildEdit.remove_wall(cell, BuildGrid.Side.NORTH)).ok).is_true()
	var exit := _grid.apply(BuildEdit.place_object(&"exit_door", cell, 0))
	assert_bool(exit.ok).is_true()
	return exit


func test_linked_desks_are_not_listed() -> void:
	assert_bool(_desk(DESK_WEST).ok).is_true()
	assert_bool(_desk(DESK_EAST).ok).is_true()
	print("gates %s, unlinked %s" % [_gates.gate_ids(), _gates.unlinked()])
	assert_array(_gates.gate_ids()).is_equal(["A", "B"])
	assert_dict(_gates.unlinked()).is_empty()


func test_a_desk_whose_exit_went_has_no_exit_in_reach() -> void:
	var west := _desk(DESK_WEST)
	var east := _desk(DESK_EAST)
	assert_bool(_grid.apply(BuildEdit.remove_object(_grid.object_at(EXIT_WEST))).ok).is_true()
	var unlinked := _gates.unlinked()
	print("after the west exit went: gates %s, unlinked %s" % [_gates.gate_ids(), unlinked])
	assert_array(unlinked.keys()).is_equal([west.object_id])
	assert_int(unlinked[west.object_id]["why"]).is_equal(GateDesks.Unlinked.NO_EXIT)
	assert_str(unlinked[west.object_id]["gate"]).is_empty()
	# A control: the east desk keeps its gate and is not listed.
	assert_bool(unlinked.has(east.object_id)).is_false()
	assert_array(_gates.gate_ids()).is_equal(["B"])


func test_a_desk_whose_only_exit_is_another_gates_names_that_gate() -> void:
	assert_bool(_desk(DESK_WEST).ok).is_true()
	# Built past the guard (which refuses it with GATE_NO_EXIT): the one exit in
	# its reach is gate A's.
	_grid.guard = Callable()
	var second := _desk(DESK_WEST + Vector2i(-3, -1))
	_grid.guard = _gates.edit_problem
	assert_bool(second.ok).is_true()
	var unlinked := _gates.unlinked()
	print("second desk by gate A's exit: %s" % [unlinked])
	assert_int(unlinked[second.object_id]["why"]).is_equal(GateDesks.Unlinked.EXIT_TAKEN)
	assert_str(unlinked[second.object_id]["gate"]).is_equal("A")
	(
		assert_array(
			GateDesks.exits_in_reach(_grid, GateDesks.desk_footprint(_grid, second.object_id))
		)
		. is_equal([_grid.object_at(EXIT_WEST)])
	)


func test_a_desk_whose_free_exit_would_overlap_a_gate_names_that_gate() -> void:
	var west := _desk(DESK_WEST)
	# Its exit goes, a gate is made by a second exit 9 m west, and the exit comes
	# back: its stand would overlap the new gate's, so the west desk stays
	# unlinked (test_gate_desks.gd, the last case).
	assert_bool(_grid.apply(BuildEdit.remove_object(_grid.object_at(EXIT_WEST))).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.remove_wall(EXIT_NEAR, BuildGrid.Side.NORTH)).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.place_object(&"exit_door", EXIT_NEAR, 0)).ok).is_true()
	assert_bool(_desk(EXIT_NEAR + Vector2i(0, 3)).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.place_object(&"exit_door", EXIT_WEST, 0)).ok).is_true()
	var unlinked := _gates.unlinked()
	print("gates %s, unlinked %s" % [_gates.bindings, unlinked])
	assert_array(unlinked.keys()).is_equal([west.object_id])
	assert_int(unlinked[west.object_id]["why"]).is_equal(GateDesks.Unlinked.STAND_OVERLAP)
	assert_str(unlinked[west.object_id]["gate"]).is_equal(_gates.gate_ids()[0])


func test_a_usable_farther_exit_means_no_letter_not_an_overlap() -> void:
	var west := _desk(DESK_WEST)
	var gate_a := _gates.binding_of("A")
	# A third shell 25 cells east of the starter, with two more exits in its
	# north wall: the near one 16 m east of gate A's exit, under the 19 m the
	# small swings need, so its stand overlaps A's; the far one 20 m east, so it
	# does not.
	for result in _grid.apply_batch(
		ReferenceTerminal.shell_edits(SITE.starter_offset + Vector2i(25, 0))
	):
		assert_bool(result.ok).is_true()
	var near_cell := EXIT_WEST + Vector2i(16, 0)
	var far_cell := EXIT_WEST + Vector2i(20, 0)
	var near := _open_exit(near_cell)
	var far := _open_exit(far_cell).object_id
	# A desk 2 cells from the near exit and 3 from the far one, built past the
	# guard and the links (its links come from `only_a` below).
	_grid.guard = Callable()
	var desk := _desk(near_cell + Vector2i(0, 2))
	assert_bool(desk.ok).is_true()
	var a_stand := StandPlacement.for_exit(_grid, gate_a["exit"])
	var overlaps := [
		GateDesks.stands_overlap(StandPlacement.for_exit(_grid, near.object_id), a_stand),
		GateDesks.stands_overlap(StandPlacement.for_exit(_grid, far), a_stand),
	]
	var order := GateDesks.exits_in_reach(_grid, GateDesks.desk_footprint(_grid, desk.object_id))
	# Every letter in use: gate A is the only link, and the desk has none though
	# its far exit is usable (what refresh() leaves when _free_letter() is "").
	var only_a: Array[Dictionary] = [gate_a]
	var unlinked := GateDesks.unlinked_on(_grid, only_a)
	print(
		(
			"exits nearest first %s (near %d, far %d), overlap A %s, unlinked %s"
			% [order, near.object_id, far, overlaps, unlinked]
		)
	)
	assert_array(order).is_equal([near.object_id, far])
	assert_array(overlaps).is_equal([true, false])
	assert_bool(unlinked.has(west.object_id)).is_false()
	assert_int(unlinked[desk.object_id]["why"]).is_equal(GateDesks.Unlinked.NO_LETTER)
	# A control: with the far exit also overlapping (taken away), the overlap is
	# the reason.
	assert_bool(_grid.apply(BuildEdit.remove_object(far)).ok).is_true()
	var only_near := GateDesks.unlinked_on(_grid, only_a)
	print("far exit gone: %s" % [only_near])
	assert_int(only_near[desk.object_id]["why"]).is_equal(GateDesks.Unlinked.STAND_OVERLAP)
	assert_str(only_near[desk.object_id]["gate"]).is_equal("A")


func test_exits_in_reach_are_nearest_first_within_the_link_reach() -> void:
	var footprint := BuildCatalog.get_def(GateDesks.DESK).footprint(Vector2i(14, 115), 0)
	_grid.apply(BuildEdit.remove_wall(EXIT_NEAR, BuildGrid.Side.NORTH))
	assert_bool(_grid.apply(BuildEdit.place_object(&"exit_door", EXIT_NEAR, 0)).ok).is_true()
	var near := _grid.object_at(EXIT_NEAR)
	var west := _grid.object_at(EXIT_WEST)
	var cells := [
		GateDesks.reach_cells(_grid, footprint, near), GateDesks.reach_cells(_grid, footprint, west)
	]
	print("cells to the near exit and the west exit: %s" % [cells])
	assert_array(GateDesks.exits_in_reach(_grid, footprint)).is_equal([near])
	# A control: a footprint between them reaches both, 4 cells each, so the
	# lower id (the shell's west exit) first.
	var between := BuildCatalog.get_def(GateDesks.DESK).footprint(Vector2i(15, 113), 0)
	assert_array(GateDesks.exits_in_reach(_grid, between)).is_equal([west, near])
