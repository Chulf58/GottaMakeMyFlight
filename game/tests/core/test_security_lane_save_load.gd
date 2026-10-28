class_name TestSecurityLaneSaveLoad
extends GdUnitTestSuite
## A whole-world save holding a security lane loads, and the lane is a
## staffable station: its arch is listed with the scanners, its primary
## officer spot comes from the lane geometry (StaffPosts), and the rescue
## grant's repair plan counts it. This inverts the old save gate
## (test_security_lane_save_gate), which refused such a save while the lane
## feature flag was off because StaffSim could not staff a lane; lane
## staffing (Security 5/8) removed the flag and the gate. One boot of
## main.tscn for the file; the lane is built, saved, and taken down again.

const SEED := 2_810_026

var _main: Node
var _save: SaveGame
var _grid: BuildGrid
## The save, through JSON as a file holds it, with a whole lane in its grid.
var _with_lane := {}
var _arch_cell := BuildObjectDef.NO_CELL


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	SaveTestKit.start_airport(_main)
	SaveTestKit.step(_main)
	_grid = (_main.get_node("BuildMode") as BuildMode).grid
	var ids := _build_lane()
	if not ids.is_empty():
		# A grid edit settles on the next tick; a save waits for it.
		SaveTestKit.step(_main)
		var data := _save.snapshot()
		_with_lane = JSON.parse_string(JSON.stringify(data, "", true, true))
		for id in ids:
			_grid.apply(BuildEdit.remove_object(id))
		SaveTestKit.step(_main)


func after() -> void:
	_main.free()


## Builds a whole lane, facing 0 and mirror RIGHT, on the first stretch of
## the building area with no object on it, flooring the cells that have none
## (the starter terminal itself has no room for a lane), and returns its
## object ids (arch first), or an empty array when none fits.
func _build_lane() -> Array[int]:
	for y in _grid.size.y:
		for x in _grid.size.x:
			var anchor := Vector2i(x, y)
			var lane := SecurityLanes.geometry(anchor, 0, SecurityLanes.RIGHT)
			if not _floor_lane(SecurityLanes.lane_cells(lane)):
				continue
			var ids := _place_lane(lane)
			if ids.is_empty():
				continue
			var lanes := SecurityLaneBuilder.recognise(_grid)
			if lanes.is_complete(ids[0]):
				_arch_cell = anchor
				return ids
			for id in ids:
				_grid.apply(BuildEdit.remove_object(id))
	var none: Array[int] = []
	return none


## Floors every bare cell of `cells` when none holds an object and the grid
## accepts floor on each bare one; false, changing nothing, otherwise.
func _floor_lane(cells: Array[Vector2i]) -> bool:
	var paint: Array[BuildEdit] = []
	for cell in cells:
		if not _grid.in_bounds(cell) or _grid.object_at(cell) != 0:
			return false
		if _grid.floor_at(cell) == BuildGrid.FLOOR_NONE:
			var edit := BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)
			if not _grid.validate(edit).ok:
				return false
			paint.append(edit)
	for edit in paint:
		assert_bool(_grid.apply(edit).ok).is_true()
	return true


## Places the arch and parts; on any refusal takes back what it placed.
func _place_lane(lane: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for part in [SecurityLanes.ARCH] + SecurityLaneBuilder.PARTS:
		var cell: Vector2i = lane["arch"] if part == SecurityLanes.ARCH else lane[part]
		var result := _grid.apply(BuildEdit.place_object(part, cell, 0))
		if not result.ok:
			for id in ids:
				_grid.apply(BuildEdit.remove_object(id))
			ids.clear()
			return ids
		ids.append(result.object_id)
	return ids


func _arches(grid: BuildGrid) -> Array[int]:
	var out: Array[int] = []
	for id in grid.object_ids():
		if grid.get_object(id)["def"] == SecurityLanes.ARCH:
			out.append(id)
	return out


func test_the_saved_grid_loads_a_lane_with_an_officer_spot() -> void:
	print("lane arch at %s" % _arch_cell)
	assert_bool(_with_lane.is_empty()).override_failure_message("no room for a lane").is_false()
	var staged := BuildGrid.new()
	var loaded := staged.from_snapshot(_with_lane["grid"])
	var layout := TerminalLayout.new()
	layout.rebuild(staged)
	assert_bool(loaded).is_true()
	var arches := _arches(staged)
	assert_int(arches.size()).is_equal(1)
	assert_bool(layout.scanners.has(arches[0])).is_true()
	assert_bool(layout.is_usable(arches[0])).is_true()
	# The arch has no StaffSpots spot; its officer spot is the lane's.
	var primary := StaffPosts.spot(staged, layout, arches[0], StaffMember.Slot.PRIMARY)
	var lane := SecurityLanes.geometry(_arch_cell, 0, SecurityLanes.RIGHT)
	print("primary spot %s, lane primary_spot %s" % [primary, lane["primary_spot"]])
	assert_that(StaffSpots.spot_of(staged, arches[0])).is_equal(BuildObjectDef.NO_CELL)
	assert_that(primary).is_equal(lane["primary_spot"])
	assert_bool(StaffPosts.blocked(staged, layout, arches[0])).is_false()


func test_the_whole_world_save_with_a_lane_loads() -> void:
	assert_bool(_with_lane.is_empty()).is_false()
	var sim: PassengerSim = _main.get_node("PassengerSim")
	var loaded := _save.load_world(_with_lane)
	print("message: %s" % _save.message_text())
	assert_bool(loaded).override_failure_message(_save.message_text()).is_true()
	var arches := _arches(sim.grid)
	assert_int(arches.size()).is_equal(1)
	assert_bool(sim.layout.scanners.has(arches[0])).is_true()
	assert_bool(sim.layout.security_lanes.is_complete(arches[0])).is_true()
	assert_bool(RepairPlan.has_working_path(sim.grid, sim.layout)).is_true()
