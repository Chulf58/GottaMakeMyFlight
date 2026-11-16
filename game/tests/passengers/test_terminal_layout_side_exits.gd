class_name TestTerminalLayoutSideExits
extends GdUnitTestSuite
## An exit's walk outside leads over the edge its own stand faces (slice S5 of
## design airside-all-around-technical-design-one-route-source-per-con): an exit
## on the grid's west edge whose gate stand is a west one walks straight out
## there, and one on the east edge to an east stand likewise, where a walk to
## the north edge would find no way and put the door out of service. Control: an
## exit on the north row walks out over the north edge as before.

const SITE := preload("res://build/terminal_site.tres")
## A row in the middle of the grid.
const ROW := 114

var _grid: BuildGrid
var _west: int
var _east: int
var _north: int


func before() -> void:
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var last := _grid.size.x - 1
	_west = _exit(Vector2i(0, ROW), Vector2i(1, ROW), 3)
	_east = _exit(Vector2i(last, ROW), Vector2i(last - 1, ROW), 1)
	_north = _exit(Vector2i(60, 0), Vector2i(60, 1), 0)


## An exit door at `cell` facing `facing`, served from the floored `inside`.
func _exit(cell: Vector2i, inside: Vector2i, facing: int) -> int:
	for each in [cell, inside]:
		var painted := _grid.apply(BuildEdit.paint_floor(each, BuildGrid.FLOOR_TILE, 1))
		assert_bool(painted.ok).is_true()
	var placed := _grid.apply(BuildEdit.place_object(&"exit_door", cell, facing))
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	return placed.object_id


func _stand(exit_id: int, side: String) -> Dictionary:
	return StandPlacement.for_cell(_grid, _grid.get_object(exit_id)["anchor"], exit_id, side)


func test_a_side_exit_on_the_grid_edge_walks_out_over_its_own_side() -> void:
	var layout := TerminalLayout.new()
	layout.site = SITE
	layout.by_gate = true
	layout.exit_stands = {
		_west: _stand(_west, StandPlacement.WEST),
		_east: _stand(_east, StandPlacement.EAST),
		_north: _stand(_north, StandPlacement.NORTH),
	}
	layout.rebuild(_grid)
	print("routes %s, out of service %s" % [layout.outside_routes, layout.out_of_service])
	for exit_id in [_west, _east, _north]:
		assert_bool(layout.outside_routes.has(exit_id)).is_true()
		assert_bool(layout.out_of_service.has(exit_id)).is_false()
		var anchor: Vector2i = _grid.get_object(exit_id)["anchor"]
		assert_array(layout.outside_routes[exit_id]).is_equal([anchor])
