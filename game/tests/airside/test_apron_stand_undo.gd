class_name TestApronStandUndo
extends GdUnitTestSuite
## Undoing a removal while a plane is on the stand (decision plane-stand-design-
## airside-moves-110-m-north-stand-snaps-to, point 4): the undo puts the piece
## back, which builds inside the plane's area, so the guard refuses it. BuildUndo
## tries the undo on a copy of the grid first; the copy carries the guard, so
## the refusal comes from the copy and the live grid is never asked, instead of
## the copy accepting what the live grid then refuses (an error).

const SITE := preload("res://build/terminal_site.tres")
## Under the parked plane at the starter stand (x -26, z -115).
const FOOTPRINT_CELL := Vector2i(17, 95)
## Well east of everything the plane sweeps (x 17).
const FREE_CELL := Vector2i(60, 30)
const FIRST := 1000

var _grid: SiteGrid
var _flights: FlightSim
var _apron: ApronStand
var _starts: Array[int] = []


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.bind(_grid, SITE, _flights)
	_grid.guard = _apron.edit_problem
	_starts = FlightSim.schedule_starts(FIRST)


## Floor at `cell` built, then removed while recording; returns the receipt.
func _removed_floor(cell: Vector2i) -> BuildReceipt:
	assert_bool(_grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	var receipt := BuildReceipt.new()
	_grid.recorder = receipt
	assert_bool(_grid.apply(BuildEdit.remove_floor(cell)).ok).is_true()
	_grid.recorder = null
	return receipt


func _plane_to_the_stand() -> void:
	assert_bool(_flights.add_flight("F1", _starts)).is_true()
	_flights.on_tick(_starts[FlightSim.State.BOARDING])
	assert_array(_apron.guard_rects()).is_not_empty()


func test_undoing_a_removal_inside_the_plane_area_is_refused_by_the_guard() -> void:
	var receipt := _removed_floor(FOOTPRINT_CELL)
	_plane_to_the_stand()
	var snapshot := _grid.to_snapshot()
	var done := [null]
	# No error: the copy refuses the undo, the live grid is never asked.
	await (
		assert_error(func() -> void: done[0] = BuildUndo.commit(_grid, receipt, null)).is_success()
	)
	var result: BuildResult = done[0]
	print("undo inside the plane area: %s (%d)" % [result.reason_text(), result.reason])
	assert_int(result.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_int(_grid.floor_at(FOOTPRINT_CELL)).is_equal(BuildGrid.FLOOR_NONE)
	assert_dict(_grid.to_snapshot()).is_equal(snapshot)


func test_the_same_undo_outside_the_plane_area_still_works() -> void:
	var receipt := _removed_floor(FREE_CELL)
	_plane_to_the_stand()
	var result := BuildUndo.commit(_grid, receipt, null)
	print("undo outside the plane area: %s" % [result.ok])
	assert_bool(result.ok).is_true()
	assert_int(_grid.floor_at(FREE_CELL)).is_equal(BuildGrid.FLOOR_TILE)


func test_the_undo_is_taken_once_the_plane_has_left() -> void:
	var receipt := _removed_floor(FOOTPRINT_CELL)
	_plane_to_the_stand()
	_flights.on_tick(_starts[FlightSim.State.TAKEOFF])
	assert_array(_apron.guard_rects()).is_empty()
	var result := BuildUndo.commit(_grid, receipt, null)
	assert_bool(result.ok).is_true()
	assert_int(_grid.floor_at(FOOTPRINT_CELL)).is_equal(BuildGrid.FLOOR_TILE)
