class_name TestStationUseCells
extends GdUnitTestSuite
## The station build ghost's use cells (decision station-build-ghost-shows-
## passenger-side-staff-spot-and-arrow, board cc5cf9e4): for every station
## kind and all four facings, the passenger and staff tiles the ghost draws
## before placing are the cells the sim reads once the piece stands
## (BuildGrid.interaction_cell, StaffSpots.spot_of, SecurityLanes.lane), the
## arrow points from the passenger side into the station, and a blocked cell
## shows the blocked state.

const AT := Vector2i(8, 8)
const STATIONS := {
	BuildMode.Tool.DESK: &"checkin_desk",
	BuildMode.Tool.SCANNER: &"security_scanner",
	BuildMode.Tool.COUNTER: &"cafe_counter",
	BuildMode.Tool.GATE_DESK: GateDesks.DESK,
}
const LANE_TOOLS := {
	BuildMode.Tool.ARCH: SecurityLanes.ARCH,
	BuildMode.Tool.TRAY_TABLE: SecurityLanes.TRAY_TABLE,
	BuildMode.Tool.XRAY_BELT: SecurityLanes.XRAY_BELT,
	BuildMode.Tool.PICKUP_TABLE: SecurityLanes.PICKUP_TABLE,
}

var _mode: BuildMode


## A 18x18 grid floored all over.
func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(18, 18)
	add_child(_mode)
	for y in 18:
		for x in 18:
			assert_bool(_mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), 1, 1)).ok).is_true()


func after_test() -> void:
	_mode.free()


## The ghost's tiles of `role`, sorted, after hovering `cell` with `tool` at `facing`.
func _ghost_at(tool: BuildMode.Tool, cell: Vector2i, facing: int) -> Dictionary:
	_mode.set_tool(tool)
	_mode.facing = facing
	_mode._hover_key = ""
	_mode._update_ghost(_mode.grid.cell_to_world(cell))
	var out := {
		StationUseCells.PASSENGER: [], StationUseCells.STAFF: [], "blocked": [], "flow": null
	}
	for child in _mode.get_node("Ghost").get_children():
		if child.is_queued_for_deletion():
			continue
		var role: String = child.get_meta("role", "")
		if role == StationUseCells.PASSENGER or role == StationUseCells.STAFF:
			out[role].append(child.get_meta("cell"))
			if child.get_meta("blocked"):
				out["blocked"].append(child.get_meta("cell"))
		elif role == StationUseCells.ARROW:
			out["flow"] = child.get_meta("flow")
	for key in [StationUseCells.PASSENGER, StationUseCells.STAFF, "blocked"]:
		out[key].sort()
	return out


func _sorted(cells: Array) -> Array:
	var copy := cells.duplicate()
	copy.sort()
	return copy


func test_desk_scanner_counter_and_gate_desk_tiles_match_the_sim_cells_at_every_facing() -> void:
	var compared := 0
	for tool: BuildMode.Tool in STATIONS:
		var def_id: StringName = STATIONS[tool]
		for facing in 4:
			var ghost := _ghost_at(tool, AT, facing)
			var placed := _mode.grid.apply(BuildEdit.place_object(def_id, AT, facing))
			assert_bool(placed.ok).is_true()
			var id := placed.object_id
			var passenger: Array = []
			var staff: Array = []
			var def := BuildCatalog.get_def(def_id)
			var front := BuildObjectDef.rotate_offset(Vector2i(0, 1), facing)
			if def_id == GateDesks.DESK:
				# No sim cell: the row in front of the desk, no staff tile.
				for cell in GateDesks.desk_footprint(_mode.grid, id):
					passenger.append(cell + front)
			else:
				passenger.append(_mode.grid.interaction_cell(id))
				if StaffSpots.spot_of(_mode.grid, id) != BuildObjectDef.NO_CELL:
					staff.append(StaffSpots.spot_of(_mode.grid, id))
			print(
				(
					"%s facing %d: ghost passenger %s staff %s flow %s | sim passenger %s staff %s"
					% [
						def_id,
						facing,
						ghost[StationUseCells.PASSENGER],
						ghost[StationUseCells.STAFF],
						ghost["flow"],
						_sorted(passenger),
						staff
					]
				)
			)
			assert_array(ghost[StationUseCells.PASSENGER]).is_equal(_sorted(passenger))
			assert_array(ghost[StationUseCells.STAFF]).is_equal(_sorted(staff))
			assert_array(ghost["blocked"]).is_empty()
			assert_that(ghost["flow"]).is_equal(-front)
			compared += passenger.size() + staff.size()
			assert_bool(def.has_interaction or def_id == GateDesks.DESK).is_true()
			assert_bool(_mode.grid.apply(BuildEdit.remove_object(id)).ok).is_true()
	print("cells compared: %d" % compared)
	assert_int(compared).is_equal(4 * (2 + 2 + 1 + 2))


## Builds the lane at AT for `mirror` without `missing`, ghosts it, places it
## and compares the ghost with the recognised lane's cells.
func _check_lane_piece(missing: StringName, tool: BuildMode.Tool, facing: int, mirror: int) -> int:
	var arch_cell := AT
	var skip: Array[StringName] = []
	if missing == SecurityLanes.ARCH:
		for part in SecurityLaneBuilder.PARTS:
			var lane := SecurityLanes.geometry(arch_cell, facing, mirror)
			PassengerTestWorld.place(_mode.grid, part, lane[part], facing)
	else:
		skip.append(missing)
		SecurityLaneBuilder.build(_mode.grid, arch_cell, facing, mirror, skip)
	var key := "arch" if missing == SecurityLanes.ARCH else String(missing)
	var cell: Vector2i = SecurityLanes.geometry(arch_cell, facing, mirror)[key]
	var ghost := _ghost_at(tool, cell, facing)
	PassengerTestWorld.place(_mode.grid, missing, cell, facing)
	var lanes := SecurityLanes.new()
	lanes.rebuild(_mode.grid)
	var arch := _mode.grid.object_at(arch_cell)
	assert_bool(lanes.is_complete(arch)).is_true()
	var lane := lanes.lane(arch)
	var passenger: Array = []
	var staff: Array = []
	match missing:
		SecurityLanes.ARCH:
			passenger = [lane["queue_entry"], lane["unpack"]]
			staff = [lane["primary_spot"], lane["helper_spot"]]
		SecurityLanes.TRAY_TABLE:
			passenger = [lane["unpack"]]
		SecurityLanes.XRAY_BELT:
			passenger = [lane["arch"]]
			staff = [lane["primary_spot"]]
		SecurityLanes.PICKUP_TABLE:
			passenger = [lane["pickup"]]
	print(
		(
			"%s facing %d mirror %d: ghost passenger %s staff %s flow %s | lane passenger %s staff %s"
			% [
				missing,
				facing,
				mirror,
				ghost[StationUseCells.PASSENGER],
				ghost[StationUseCells.STAFF],
				ghost["flow"],
				_sorted(passenger),
				_sorted(staff)
			]
		)
	)
	assert_array(ghost[StationUseCells.PASSENGER]).is_equal(_sorted(passenger))
	assert_array(ghost[StationUseCells.STAFF]).is_equal(_sorted(staff))
	assert_that(ghost["flow"]).is_equal(-(lane["front"] as Vector2i))
	for id in _mode.grid.object_ids():
		assert_bool(_mode.grid.apply(BuildEdit.remove_object(id)).ok).is_true()
	return passenger.size() + staff.size()


func test_lane_part_tiles_match_the_recognised_lane_at_every_facing_and_mirror() -> void:
	var compared := 0
	for tool: BuildMode.Tool in LANE_TOOLS:
		for facing in 4:
			for mirror in SecurityLanes.MIRRORS:
				compared += _check_lane_piece(LANE_TOOLS[tool], tool, facing, mirror)
	print("lane cells compared: %d" % compared)
	assert_int(compared).is_equal(8 * (4 + 1 + 2 + 1))


func test_a_blocked_passenger_or_staff_cell_shows_blocked() -> void:
	var desk := BuildCatalog.get_def(&"checkin_desk")
	var front := desk.interaction_cell(AT, 0)
	var spot := StaffSpots.cell_of(&"checkin_desk", AT, 0)
	# Control: open floor, nothing blocked.
	var open := _ghost_at(BuildMode.Tool.DESK, AT, 0)
	assert_array(open["blocked"]).is_empty()
	var blocker := SecurityLaneBuilder.block(_mode.grid, front)
	var walled := _ghost_at(BuildMode.Tool.DESK, AT, 0)
	print("passenger cell %s blocked: ghost blocked %s" % [front, walled["blocked"]])
	assert_array(walled["blocked"]).is_equal([front])
	assert_bool(_mode.grid.apply(BuildEdit.remove_object(blocker)).ok).is_true()
	SecurityLaneBuilder.block(_mode.grid, spot)
	var staffed := _ghost_at(BuildMode.Tool.DESK, AT, 0)
	print("staff spot %s blocked: ghost blocked %s" % [spot, staffed["blocked"]])
	assert_array(staffed["blocked"]).is_equal([spot])
	assert_bool(_mode.check(_mode.edit_at(_mode.grid.cell_to_world(AT))).ok).is_false()


func test_a_blocked_lane_queue_cell_shows_blocked_and_the_unpack_cell_does_not() -> void:
	var lane := SecurityLanes.geometry(AT, 2, SecurityLanes.RIGHT)
	SecurityLaneBuilder.block(_mode.grid, lane["queue_entry"])
	var ghost := _ghost_at(BuildMode.Tool.ARCH, AT, 2)
	print(
		(
			"queue entry %s unpack %s: ghost blocked %s"
			% [lane["queue_entry"], lane["unpack"], ghost["blocked"]]
		)
	)
	assert_array(ghost["blocked"]).is_equal([lane["queue_entry"]])
	assert_array(ghost[StationUseCells.PASSENGER]).contains([lane["unpack"]])


func test_no_tiles_for_a_piece_with_no_use_side() -> void:
	var ghost := _ghost_at(BuildMode.Tool.SEATS, AT, 1)
	assert_array(ghost[StationUseCells.PASSENGER]).is_empty()
	assert_array(ghost[StationUseCells.STAFF]).is_empty()
	assert_that(ghost["flow"]).is_null()
