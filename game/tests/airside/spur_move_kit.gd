class_name SpurMoveKit
extends RefCounted
## The airport the side spur move tests share (decision side-spur-move-design-
## s7-stands-carry-lane-x-the-wanted-spur, slice S7b): the starter shell with a
## west gate A (the west exit and desk of test_gate_desks_side.gd), an open
## FlightSim and GateDesks guarding the site grid. The grid's land is null, the
## test seam that lets a test build on the grid's west edge column, past the
## spur at x -124 (SiteGrid.land).

const SITE := preload("res://build/terminal_site.tres")
const WEST_EXIT := Vector2i(10, 6)
const WEST_DESK := Vector2i(12, 5)
## A grid cell on the west edge far south of every stand and way out: building
## it pushes the west spur out to the edge less the band (x -149.8), and no
## envelope of gate A's on either spur reaches it.
const WING := Vector2i(0, 149)
## WING on the east edge, for an east gate.
const WING_EAST := Vector2i(255, 149)
const EAST_EXIT := Vector2i(21, 4)
## Gate A's contracts depart at 12:00, so their first day is issued after the
## airport opens at tick 0 (06:00).
const MINUTE := 12 * 60


## The starter shell on a fresh site grid, built once per file.
static func base_grid() -> SiteGrid:
	var grid := SiteGrid.new(SITE)
	if not StarterShell.place(grid, SITE.starter_offset):
		push_error("SpurMoveKit: the starter shell did not place")
	return grid


## Opens `sim`, binds `gates` to `grid` and it, guards the grid, and links gate
## A to the shell's west exit. Returns the exit's id, or 0 when a step failed.
static func west_gate(grid: SiteGrid, sim: FlightSim, gates: GateDesks) -> int:
	sim.open_airport()
	gates.bind(grid, sim)
	grid.guard = gates.edit_problem
	var at := WEST_EXIT + SITE.starter_offset
	if not grid.apply(BuildEdit.remove_wall(at, BuildGrid.Side.WEST)).ok:
		return 0
	var exit := grid.apply(BuildEdit.place_object(&"exit_door", at, 3))
	if not exit.ok:
		return 0
	if not (
		grid.apply(BuildEdit.place_object(GateDesks.DESK, WEST_DESK + SITE.starter_offset, 0)).ok
	):
		return 0
	return exit.object_id if gates.gate_ids() == ["A"] else 0


## west_gate() on the east side: the shell's east exit two rows from its north-
## east corner, linked by the shell's gate desk cell, which is nearer it than
## the north exit (test_gate_desks_side.gd).
static func east_gate(grid: SiteGrid, sim: FlightSim, gates: GateDesks) -> int:
	sim.open_airport()
	gates.bind(grid, sim)
	grid.guard = gates.edit_problem
	var at := EAST_EXIT + SITE.starter_offset
	if not grid.apply(BuildEdit.remove_wall(at, BuildGrid.Side.EAST)).ok:
		return 0
	var exit := grid.apply(BuildEdit.place_object(&"exit_door", at, 1))
	var desk := ReferenceTerminal.GATE_DESK_CELL + SITE.starter_offset
	if not exit.ok or not grid.apply(BuildEdit.place_object(GateDesks.DESK, desk, 0)).ok:
		return 0
	return exit.object_id if gates.gate_ids() == ["A"] else 0


## Medium-plane terms departing at `minute` (TestFlightContracts.terms()).
static func terms(id: String, minute := MINUTE) -> Dictionary:
	return TestFlightContracts.terms(id, minute)


## The floor edit at `cell`.
static func floor_at(cell: Vector2i) -> BuildEdit:
	return BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 0)


## The start tick of every state of flight `id`.
static func starts(sim: FlightSim, id: String) -> Array[int]:
	var out: Array[int] = []
	for state in FlightSim.STATE_COUNT:
		out.append(sim.state_start(id, state))
	return out


## The departure minute of a second contract at gate A that holds the gate a
## minute after the first one's DEPARTED, on the longer of gate A's pair now and
## its pair on the spur WING pushes to: its issue then comes before the first
## one's TAKEOFF, and the two clear each other at the gate on either spur.
static func straddle_minute(gates: GateDesks) -> int:
	var stand: Dictionary = gates.stands["A"]
	var wing_x := gates.grid.origin.x - SideSpurs.build_clearance()
	var held := maxi(
		FlightTimetable.reserved_ticks(TaxiTimes.for_stand(stand)),
		FlightTimetable.reserved_ticks(
			TaxiTimes.for_stand(StandPlacement.with_lane_x(stand, wing_x))
		)
	)
	return MINUTE + ceili(float(held + 20) / GameCalendar.TICKS_PER_MINUTE)
