class_name TestRepairPlanSideExit
extends GdUnitTestSuite
## Where RepairPlan looks for a new exit on a site faces out the way the live
## stand's exit does (slice S5 of design airside-all-around-technical-design-
## one-route-source-per-con): west for a west stand, east for an east one, north
## for a north one, so a repaired exit walks out to the stand's plane door.

const SITE := preload("res://build/terminal_site.tres")
## A small grid inside the site's frame keeps the scan of every spot short.
const SIZE := Vector2i(24, 16)
const STAND_CELL := Vector2i(12, 8)

var _grid: BuildGrid


func before() -> void:
	_grid = BuildGrid.new(SIZE, SITE.grid_origin + Vector3(90.0, 0.0, 100.0))
	_grid.check_staff_reach = false


## The way-out steps of RepairPlan._door_sources() for an exit with the live
## stand `stand`: step -> how many spots face out by it.
func _way_outs(stand: Dictionary) -> Dictionary:
	var plan := RepairPlan.new()
	plan._site = SITE
	plan._layout.site = SITE
	plan._layout.stand = stand
	plan._grid = _grid
	plan._layout.rebuild(_grid)
	var out := {}
	for source: Dictionary in plan._door_sources(&"exit_door"):
		var edits: Array[BuildEdit] = source["door_edits"]
		var step := DoorPlacement.back_step(edits[edits.size() - 1].facing)
		out[step] = int(out.get(step, 0)) + 1
	return out


func test_new_exit_spots_face_out_the_way_the_live_stand_does() -> void:
	for side: String in StandPlacement.SIDES:
		var stand := StandPlacement.for_cell(_grid, STAND_CELL, 0, side)
		var way_outs := _way_outs(stand)
		print("%s stand: way-out steps %s" % [side, way_outs])
		assert_array(way_outs.keys()).is_equal([StandPlacement.OUT_STEP[side]])
		assert_int(way_outs[StandPlacement.OUT_STEP[side]]).is_greater(SIZE.x)
