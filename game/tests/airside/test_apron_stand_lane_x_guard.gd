class_name TestApronStandLaneXGuard
extends GdUnitTestSuite
## The one stand's guard is worked out once per tick (ApronStand._tick_key),
## and a west stand's taxi-out guard depends on its spur, lane_x (decision
## side-spur-move-design-s7-stands-carry-lane-x-the-wanted-spur, slice S7a). So
## a live stand that moves only to another spur, at the same tick, gets a new
## guard: the cells guarded are those of the stand now live, not the cached
## ones of the stand before.

const SITE := preload("res://build/terminal_site.tres")
## The west stand's exit cell, a step along the grid from the starter exit
## (test_apron_stand_parked_guard.gd's).
const WEST_STEP := Vector2i(80, -37)
const WIDE := 174.0


func test_a_live_stand_moved_only_to_another_spur_gets_a_new_guard_at_once() -> void:
	var flights := auto_free(FlightSim.new()) as FlightSim
	var apron := auto_free(ApronStand.new()) as ApronStand
	var grid := SiteGrid.new(SITE)
	assert_bool(StarterShell.place(grid, SITE.starter_offset)).is_true()
	apron.bind(grid, SITE, flights)
	var starts := FlightSim.schedule_starts(1000)
	assert_bool(flights.add_flight("F1", starts)).is_true()
	var taxi_out: int = starts[FlightSim.State.TAXI_OUT]
	var takeoff: int = starts[FlightSim.State.TAKEOFF]
	flights.on_tick(taxi_out + (takeoff - taxi_out) / 4)
	assert_int(flights.state_of("F1")).is_equal(FlightSim.State.TAXI_OUT)
	var exit_cell := ReferenceTerminal.EXIT_CELL + SITE.starter_offset
	var near := StandPlacement.for_cell(grid, exit_cell + WEST_STEP, 3, StandPlacement.WEST)
	var far := StandPlacement.with_lane_x(near, -WIDE)
	apron.live = near
	var near_cells := apron.guarded_cells().duplicate()
	apron.live = far
	var far_cells := apron.guarded_cells()
	var fresh := StandPlacement.cells_under(grid, apron.guard_rects())
	print(
		(
			"tick %d: %d cells at lane_x %.0f, %d at %.0f, %d worked out afresh"
			% [
				flights.tick,
				near_cells.size(),
				near["lane_x"],
				far_cells.size(),
				far["lane_x"],
				fresh.size()
			]
		)
	)
	assert_int(near_cells.size()).is_greater(0)
	assert_int(fresh.size()).is_greater(0)
	assert_dict(fresh).is_not_equal(near_cells)
	assert_dict(far_cells).is_equal(fresh)
