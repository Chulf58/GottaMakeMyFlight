class_name TestSpareStandPerf
extends GdUnitTestSuite
## Regression test for SpareStand.find / GateDesks.spare_stand multi-second
## main-thread stall after a build edit in build mode on main.tscn.

const MAIN := "res://main/main.tscn"

var _main: Node
var _clock: SimClock
var _flights: FlightSim
var _gates: GateDesks
var _grid: BuildGrid


func before() -> void:
	_main = load(MAIN).instantiate()
	add_child(_main)
	_clock = _main.get_node("SimClock") as SimClock
	_clock.set_paused(true)
	_flights = _main.get_node("FlightSim") as FlightSim
	_gates = _main.get_node("GateDesks") as GateDesks
	_grid = (_main.get_node("BuildMode") as BuildMode).grid
	var placed := _grid.apply(ReferenceTerminal.gate_desk_edit(ReferenceTerminal.offset_on(_grid)))
	assert_bool(placed.ok).is_true()
	assert_bool(_flights.open_airport()).is_true()


func after() -> void:
	_main.free()


func test_spare_stand_after_build_edit_on_main_stays_under_budget() -> void:
	# Simulate a terminal wall edit that triggers GateDesks.refresh(), clearing _spare_stands.
	var anchor := ReferenceTerminal.offset_on(_grid) + ReferenceTerminal.GATE_DESK_CELL
	var edit := BuildEdit.place_wall(anchor + Vector2i(1, 0), 0)
	assert_bool(_grid.apply(edit).ok).is_true()

	var t_med := Time.get_ticks_usec()
	var med := _gates.spare_stand(PlaneClasses.MEDIUM)
	var med_ms := (Time.get_ticks_usec() - t_med) / 1000.0

	var t_large := Time.get_ticks_usec()
	var large := _gates.spare_stand(PlaneClasses.LARGE)
	var large_ms := (Time.get_ticks_usec() - t_large) / 1000.0

	print(
		(
			"PERF SpareStand after build edit: medium=%.1f ms (found=%s), large=%.1f ms (found=%s)"
			% [med_ms, not med.is_empty(), large_ms, not large.is_empty()]
		)
	)
	assert_bool(StandPlacement.is_stand(med)).is_true()
	assert_bool(StandPlacement.is_stand(large)).is_true()
	assert_float(med_ms).is_less(250.0)
	assert_float(large_ms).is_less(250.0)

	# A second apron edit covering the returned stand's parked cell must
	# invalidate both _spare_stands and _spare_prefix.
	var parked := _grid.world_to_cell(StandPlacement.stand_point(med))
	assert_bool(_grid.apply(BuildEdit.paint_floor(parked, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	var med_after := _gates.spare_stand(PlaneClasses.MEDIUM)
	assert_dict(med_after).is_not_equal(med)
