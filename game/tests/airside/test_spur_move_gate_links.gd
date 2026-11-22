class_name TestSpurMoveGateLinks
extends GdUnitTestSuite
## Review fixes for gates and the side spurs they share (decision side-spur-
## move-design-s7-stands-carry-lane-x-the-wanted-spur), on the starter shell
## plus a second shell on the grid's west side land (land == null):
## - a later gate that would push the shared spur out is checked against the
##   earlier gates on that farther spur, and refused when they would meet;
## - a new west exit counts as a stand in a build's spur trial only when the
##   links would make it a gate;
## - a gate removal's moved contracts are checked on the gates and spurs the
##   removal leaves, in the same trial.

const SITE := preload("res://build/terminal_site.tres")

var _base: SiteGrid
var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks


## A FlightPlans in which contract C1's occurrences get no plan whenever they
## would fly from a stand on spur x -124 at gate B: a stand the moved contract
## cannot use there (a stub, as test_flight_planner_wiring.gd's).
class NoPlanAtGateB:
	extends FlightPlans

	func plan_day(world: Dictionary, day: int) -> Dictionary:
		var out := super(world, day)
		for req: Dictionary in FlightPlans.requests(world, day):
			var parts := FlightTimetable.parse_occurrence(req["id"])
			if parts.is_empty() or parts["contract"] != "C1":
				continue
			var stand: Dictionary = req["stand"]
			var at_b := false
			for contract: Dictionary in world["contracts"]:
				at_b = at_b or (contract["id"] == "C1" and contract["gate"] == "B")
			if (
				at_b
				and is_equal_approx(StandPlacement.lane_x_of(stand), -StandPlacement.SIDE_LANE_X)
			):
				out[req["id"]] = {
					"ok": false, "reason": GroundPlanner.TAXI_BUSY, "pauses": {}, "bookings": []
				}
		return out


func before() -> void:
	_base = SpurMoveKit.base_grid()


func before_test() -> void:
	_grid = _base.clone() as SiteGrid
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks


## A second shell `offset` cells from the starter's, built before the guard.
func _shell(offset: Vector2i) -> void:
	for result in _grid.apply_batch(ReferenceTerminal.shell_edits(SITE.starter_offset + offset)):
		assert_bool(result.ok).is_true()


func _bind() -> void:
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem


## Opens the west exit of the shell at `offset` from the starter's and returns
## its id.
func _west_exit(offset: Vector2i) -> int:
	var at := SpurMoveKit.WEST_EXIT + SITE.starter_offset + offset
	assert_bool(_grid.apply(BuildEdit.remove_wall(at, BuildGrid.Side.WEST)).ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", at, 3))
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	return placed.object_id


func _desk_edit(offset: Vector2i) -> BuildEdit:
	return BuildEdit.place_object(
		GateDesks.DESK, SpurMoveKit.WEST_DESK + SITE.starter_offset + offset, 0
	)


## Two west stands on an empty site: A out from cell (95, 116) (sill x -33) and
## B out from cell (18, 131), 15 m south (sill x -110), whose own sill pushes
## the west spur to x -180.86. Each on its own spur (SideSpurs.at_link_lane())
## meets nothing, which is all the link check asked before; on the spur they
## would share, A's way out reaches B's swing square, so B is unfit for a gate
## beside A (STAND_OVERLAP), and so is A beside B. Alone each is fit. With a
## shell built around B, its own floor would block A's way out first, so the
## check is shown on the stands themselves.
func test_a_gate_that_pushes_the_shared_spur_out_is_checked_on_that_spur() -> void:
	var grid := SiteGrid.new(SITE)
	var a := SideSpurs.at_link_lane(
		grid, StandPlacement.for_cell(grid, Vector2i(95, 116), 0, StandPlacement.WEST)
	)
	var b := SideSpurs.at_link_lane(
		grid, StandPlacement.for_cell(grid, Vector2i(18, 131), 0, StandPlacement.WEST)
	)
	var shared := GateDesks.at_common_lanes(grid, [a, b] as Array[Dictionary])
	print(
		(
			"own spurs %.2f / %.2f: meet %s; shared spur %.2f: meet %s"
			% [
				a["lane_x"],
				b["lane_x"],
				GateDesks.stands_overlap(a, b),
				shared[0]["lane_x"],
				GateDesks.stands_overlap(shared[0], shared[1])
			]
		)
	)
	assert_float(a["lane_x"]).is_equal(-StandPlacement.SIDE_LANE_X)
	assert_bool(GateDesks.stands_overlap(a, b)).is_false()
	assert_bool(GateDesks.stands_overlap(shared[0], shared[1])).is_true()
	var none: Array[Dictionary] = []
	assert_int(GateDesks.stand_unfit(grid, a, none)).is_equal(-1)
	assert_int(GateDesks.stand_unfit(grid, b, none)).is_equal(-1)
	assert_int(GateDesks.stand_unfit(grid, b, [a] as Array[Dictionary])).is_equal(
		GateDesks.Unlinked.STAND_OVERLAP
	)
	assert_int(GateDesks.stand_unfit(grid, a, [b] as Array[Dictionary])).is_equal(
		GateDesks.Unlinked.STAND_OVERLAP
	)


## A desk whose gate ended when its exit went, then a floor cell in the swing
## square of the stand out from that exit: putting the exit back links nothing,
## so the build's spur trial reads the spur the build wants, not the one that
## stand would push to.
func test_a_new_exit_counts_as_a_stand_only_when_it_would_be_a_gate() -> void:
	var shell := Vector2i(-62, 0)
	_shell(shell)
	_bind()
	var exit := _west_exit(shell)
	var desk := _grid.apply(_desk_edit(shell))
	assert_bool(desk.ok).is_true()
	var stand := StandPlacement.for_exit(_grid, exit)
	assert_bool(_grid.apply(BuildEdit.remove_object(exit)).ok).is_true()
	assert_array(_gates.gate_ids()).is_empty()
	var swing := _grid.world_to_cell(StandPlacement.stand_point(stand))
	assert_bool(_grid.apply(SpurMoveKit.floor_at(swing)).ok).is_true()
	var at := SpurMoveKit.WEST_EXIT + SITE.starter_offset + shell
	var put_back := BuildEdit.place_object(&"exit_door", at, 3)
	var after := SpurTrial.wanted_after(_gates, _grid, put_back)
	var build := SideSpurs.build_lanes(_grid)
	print(
		(
			"wanted after the exit %s; the build's %s; that stand would push to %.2f"
			% [after, build, SideSpurs.stand_lane("W", float(stand["x"]))]
		)
	)
	assert_float(after["W"]).is_equal(build["W"])
	assert_float(after["W"]).is_greater(SideSpurs.stand_lane("W", float(stand["x"])))
	# Control: the exit, put back, links no gate.
	assert_bool(_grid.apply(put_back).ok).is_true()
	assert_array(_gates.gate_ids()).is_empty()


## Gate A is a shell's west exit far out (sill x -95, 20 rows south), gate B the
## starter's; once the spur moves out for A, contract C1 books gate A. Removing
## A's desk moves C1 to gate B and lets the spur back in to x -124, where (the
## stub says) C1 cannot fly from gate B: the removal is refused with
## SPUR_STRANDS naming C1, though the move fits on the spur as it is.
func test_a_gate_removal_checks_its_moves_on_the_spurs_it_leaves() -> void:
	var shell := Vector2i(-62, 20)
	_shell(shell)
	_bind()
	_west_exit(shell)
	var desk_a := _grid.apply(_desk_edit(shell))
	assert_bool(desk_a.ok).is_true()
	_west_exit(Vector2i.ZERO)
	assert_bool(_grid.apply(_desk_edit(Vector2i.ZERO)).ok).is_true()
	assert_array(_gates.gate_ids()).is_equal(["A", "B"])
	_flights.on_tick(_flights.tick + 1)
	assert_bool(_flights.spur_pending("W")).is_false()
	_flights._plans = NoPlanAtGateB.new()
	_flights._trial_plans = NoPlanAtGateB.new()
	# Both stands take small planes on the spur out at A (print shows why).
	print("classes %s" % [_gates.classes])
	var terms := SpurMoveKit.terms("C1")
	terms["plane_size"] = PlaneClasses.SMALL
	terms["booked_passengers"] = 6
	assert_bool(_flights.accept_contract(terms)).is_true()
	assert_str(_flights.contract_of("C1")["gate"]).is_equal("A")
	var removal := BuildEdit.remove_object(desk_a.object_id)
	var plan: Dictionary = _flights.move_plan(["A"] as Array[String], ["B"] as Array[String])
	var after := SpurTrial.wanted_after(_gates, _grid, removal)
	print("spur %s, after the removal %s; move plan %s" % [_gates.spur_x, after, plan])
	assert_dict(plan["moves"]).is_equal({"C1": "B"})
	assert_float(after["W"]).is_equal(-StandPlacement.SIDE_LANE_X)
	var refused := _grid.validate(removal)
	print("removal: %s" % refused.reason_text())
	assert_int(refused.reason).is_equal(BuildResult.Reason.SPUR_STRANDS)
	assert_str(refused.detail).is_equal(FlightLabel.of(_flights, false, "C1"))
	assert_array(_gates.gate_ids()).is_equal(["A", "B"])
