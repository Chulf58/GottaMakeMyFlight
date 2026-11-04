class_name TestStationUseCells
extends GdUnitTestSuite
## The station build ghost's use cells (decision station-build-ghost-shows-
## passenger-side-staff-spot-and-arrow, board cc5cf9e4): for every station
## kind and all four facings, the passenger and staff tiles the ghost draws
## before placing are the cells the sim reads once the piece stands
## (BuildGrid.interaction_cell, StaffSpots.spot_of, the SecurityLanes
## candidate), the arrow points from the passenger side into the station, a
## cell the sim counts as blocked shows blocked, and a gate desk shows only its
## arrow (decision gate-desk-build-ghost-shows-a-front-arrow-only).

const AT := Vector2i(8, 8)
const STATIONS := {
	BuildMode.Tool.DESK: &"checkin_desk",
	BuildMode.Tool.SCANNER: &"security_scanner",
	BuildMode.Tool.COUNTER: &"cafe_counter",
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


## The ghost's tiles by role (sorted), its blocked cells and its arrow, after
## hovering `cell` with `tool` at `facing`.
func _ghost_at(tool: BuildMode.Tool, cell: Vector2i, facing: int) -> Dictionary:
	_mode.set_tool(tool)
	_mode.facing = facing
	_mode._hover_key = ""
	_mode._update_ghost(_mode.grid.cell_to_world(cell))
	var out := {
		StationUseCells.PASSENGER: [],
		StationUseCells.STAFF: [],
		"blocked": [],
		"flow": null,
		"arrow_at": null,
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
			out["arrow_at"] = child.position
	for key in [StationUseCells.PASSENGER, StationUseCells.STAFF, "blocked"]:
		out[key].sort()
	return out


func _sorted(cells: Array) -> Array:
	var copy := cells.duplicate()
	copy.sort()
	return copy


func _clear() -> void:
	for id in _mode.grid.object_ids():
		assert_bool(_mode.grid.apply(BuildEdit.remove_object(id)).ok).is_true()


func test_desk_scanner_and_counter_tiles_match_the_sim_cells_at_every_facing() -> void:
	var compared := 0
	for tool: BuildMode.Tool in STATIONS:
		var def_id: StringName = STATIONS[tool]
		for facing in 4:
			var ghost := _ghost_at(tool, AT, facing)
			var placed := _mode.grid.apply(BuildEdit.place_object(def_id, AT, facing))
			assert_bool(placed.ok).is_true()
			var id := placed.object_id
			var passenger: Array = [_mode.grid.interaction_cell(id)]
			var staff: Array = []
			if StaffSpots.spot_of(_mode.grid, id) != BuildObjectDef.NO_CELL:
				staff.append(StaffSpots.spot_of(_mode.grid, id))
			var front := BuildObjectDef.rotate_offset(Vector2i(0, 1), facing)
			print(
				(
					"%s facing %d: ghost passenger %s staff %s flow %s | sim passenger %s staff %s"
					% [
						def_id,
						facing,
						ghost[StationUseCells.PASSENGER],
						ghost[StationUseCells.STAFF],
						ghost["flow"],
						passenger,
						staff
					]
				)
			)
			assert_array(ghost[StationUseCells.PASSENGER]).is_equal(passenger)
			assert_array(ghost[StationUseCells.STAFF]).is_equal(staff)
			assert_array(ghost["blocked"]).is_empty()
			assert_bool(StaffSpots.blocked(_mode.grid, id)).is_false()
			assert_that(ghost["flow"]).is_equal(-front)
			compared += passenger.size() + staff.size()
			_clear()
	print("cells compared: %d" % compared)
	assert_int(compared).is_equal(4 * (2 + 2 + 1))


func test_the_gate_desk_shows_only_an_arrow_in_front_pointing_in() -> void:
	for facing in 4:
		var ghost := _ghost_at(BuildMode.Tool.GATE_DESK, AT, facing)
		var front := BuildObjectDef.rotate_offset(Vector2i(0, 1), facing)
		var row := Vector3.ZERO
		var cells := BuildCatalog.get_def(GateDesks.DESK).footprint(AT, facing)
		for cell in cells:
			row += _mode.grid.cell_to_world(cell + front) / cells.size()
		print(
			(
				"gate_desk facing %d: tiles %s flow %s arrow at %s, front row centre %s"
				% [facing, ghost[StationUseCells.PASSENGER], ghost["flow"], ghost["arrow_at"], row]
			)
		)
		assert_array(ghost[StationUseCells.PASSENGER]).is_empty()
		assert_array(ghost[StationUseCells.STAFF]).is_empty()
		assert_that(ghost["flow"]).is_equal(-front)
		var at: Vector3 = ghost["arrow_at"]
		assert_float(Vector2(at.x - row.x, at.z - row.z).length()).is_less(0.01)


## [candidate, status, use_cell_states] the recogniser reports for the arch on
## `arch_cell`.
func _recognised(arch_cell: Vector2i) -> Array:
	var lanes := SecurityLanes.new()
	lanes.rebuild(_mode.grid)
	var arch := _mode.grid.object_at(arch_cell)
	return [lanes.candidate(arch), lanes.status(arch), lanes.use_cell_states(_mode.grid, arch)]


## _recognised() as the grid would be with `def_id` placed at `cell`.
func _recognised_with(def_id: StringName, cell: Vector2i, facing: int) -> Array:
	return _mode.grid.with_trial_object(
		def_id, cell, facing, func(_id: int) -> Array: return _recognised(AT)
	)


## The cells the sim names for `piece` in `lane`: [passenger, staff].
func _sim_cells(piece: StringName, lane: Dictionary) -> Array:
	match piece:
		SecurityLanes.ARCH:
			return [
				_sorted([lane["queue_entry"], lane["unpack"]]),
				_sorted([lane["primary_spot"], lane["helper_spot"]])
			]
		SecurityLanes.TRAY_TABLE:
			return [[lane["unpack"]], []]
		SecurityLanes.XRAY_BELT:
			return [[lane["arch"]], [lane["primary_spot"]]]
	return [[lane["pickup"]], []]


func _compare(label: String, ghost: Dictionary, piece: StringName, found: Array) -> void:
	var cells := _sim_cells(piece, found[0])
	var closed := []
	for cell in cells[0] + cells[1]:
		if not found[2].get(cell, true):
			closed.append(cell)
	print(
		(
			"%s: ghost passenger %s staff %s blocked %s flow %s | lane %s %s closed %s status %d"
			% [
				label,
				ghost[StationUseCells.PASSENGER],
				ghost[StationUseCells.STAFF],
				ghost["blocked"],
				ghost["flow"],
				cells[0],
				cells[1],
				_sorted(closed),
				found[1]
			]
		)
	)
	assert_array(ghost[StationUseCells.PASSENGER]).is_equal(cells[0])
	assert_array(ghost[StationUseCells.STAFF]).is_equal(cells[1])
	assert_array(ghost["blocked"]).is_equal(_sorted(closed))
	assert_that(ghost["flow"]).is_equal(-(found[0]["front"] as Vector2i))


## Builds the lane at AT for `mirror` without `missing`, ghosts it, places it
## and compares the ghost with the recognised lane's cells.
func _check_lane_piece(missing: StringName, tool: BuildMode.Tool, facing: int, mirror: int) -> int:
	var lane := SecurityLanes.geometry(AT, facing, mirror)
	if missing == SecurityLanes.ARCH:
		for part in SecurityLaneBuilder.PARTS:
			PassengerTestWorld.place(_mode.grid, part, lane[part], facing)
	else:
		var skip: Array[StringName] = [missing]
		SecurityLaneBuilder.build(_mode.grid, AT, facing, mirror, skip)
	var key := "arch" if missing == SecurityLanes.ARCH else String(missing)
	var ghost := _ghost_at(tool, lane[key], facing)
	PassengerTestWorld.place(_mode.grid, missing, lane[key], facing)
	var found := _recognised(AT)
	assert_int(found[1]).is_equal(SecurityLanes.Status.COMPLETE)
	_compare("%s facing %d mirror %d" % [missing, facing, mirror], ghost, missing, found)
	_clear()
	return ghost[StationUseCells.PASSENGER].size() + ghost[StationUseCells.STAFF].size()


func test_lane_part_tiles_match_the_recognised_lane_at_every_facing_and_mirror() -> void:
	var compared := 0
	for tool: BuildMode.Tool in LANE_TOOLS:
		for facing in 4:
			for mirror in SecurityLanes.MIRRORS:
				compared += _check_lane_piece(LANE_TOOLS[tool], tool, facing, mirror)
	print("lane cells compared: %d" % compared)
	assert_int(compared).is_equal(8 * (4 + 1 + 2 + 1))


func test_a_blocked_desk_front_or_staff_spot_shows_blocked_as_the_check_refuses() -> void:
	var front := BuildCatalog.get_def(&"checkin_desk").interaction_cell(AT, 0)
	var spot := StaffSpots.cell_of(&"checkin_desk", AT, 0)
	var open := _ghost_at(BuildMode.Tool.DESK, AT, 0)
	assert_array(open["blocked"]).is_empty()
	var blocker := SecurityLaneBuilder.block(_mode.grid, front)
	var walled := _ghost_at(BuildMode.Tool.DESK, AT, 0)
	var refusal := _mode.grid.validate(BuildEdit.place_object(&"checkin_desk", AT, 0))
	print("front %s taken: ghost %s, sim refuses %d" % [front, walled["blocked"], refusal.reason])
	assert_int(refusal.reason).is_equal(BuildResult.Reason.INTERACTION_BLOCKED)
	assert_array(walled["blocked"]).is_equal([front])
	assert_bool(_mode.grid.apply(BuildEdit.remove_object(blocker)).ok).is_true()
	SecurityLaneBuilder.block(_mode.grid, spot)
	var staffed := _ghost_at(BuildMode.Tool.DESK, AT, 0)
	refusal = _mode.grid.validate(BuildEdit.place_object(&"checkin_desk", AT, 0))
	print("spot %s taken: ghost %s, sim refuses %d" % [spot, staffed["blocked"], refusal.reason])
	assert_int(refusal.reason).is_equal(BuildResult.Reason.STAFF_SPOT)
	assert_array(staffed["blocked"]).is_equal([spot])


func test_a_desk_front_reserved_by_another_station_shows_blocked() -> void:
	# A cafe counter turned to face north uses (8, 9), the desk's front cell.
	assert_bool(_mode.grid.apply(BuildEdit.place_object(&"cafe_counter", Vector2i(8, 10), 2)).ok)
	var ghost := _ghost_at(BuildMode.Tool.DESK, AT, 0)
	var refusal := _mode.grid.validate(BuildEdit.place_object(&"checkin_desk", AT, 0))
	print("reserved front: ghost blocked %s, sim refuses %d" % [ghost["blocked"], refusal.reason])
	assert_int(refusal.reason).is_equal(BuildResult.Reason.INTERACTION_RESERVED)
	assert_array(ghost["blocked"]).is_equal([Vector2i(8, 9)])


func test_a_queue_entry_reserved_by_another_station_shows_blocked_as_the_lane_judges() -> void:
	var lane := SecurityLanes.geometry(AT, 0, SecurityLanes.RIGHT)
	var entry: Vector2i = lane["queue_entry"]
	# A cafe counter facing north one row further south uses the queue entry.
	var counter := _mode.grid.apply(
		BuildEdit.place_object(&"cafe_counter", entry + Vector2i(0, 1), 2)
	)
	assert_that(_mode.grid.interaction_cell(counter.object_id)).is_equal(entry)
	for part in SecurityLaneBuilder.PARTS:
		PassengerTestWorld.place(_mode.grid, part, lane[part], 0)
	var ghost := _ghost_at(BuildMode.Tool.ARCH, AT, 0)
	PassengerTestWorld.place(_mode.grid, SecurityLanes.ARCH, AT, 0)
	var found := _recognised(AT)
	assert_int(found[1]).is_equal(SecurityLanes.Status.NO_QUEUE_ROOM)
	assert_array(ghost["blocked"]).contains([entry])
	_compare("reserved queue entry", ghost, SecurityLanes.ARCH, found)


func test_a_wall_between_a_part_and_its_cell_shows_blocked_as_the_lane_judges() -> void:
	var lane := SecurityLanes.geometry(AT, 0, SecurityLanes.RIGHT)
	var skip: Array[StringName] = [SecurityLanes.TRAY_TABLE]
	SecurityLaneBuilder.build(_mode.grid, AT, 0, SecurityLanes.RIGHT, skip)
	# Walls on both sides of the tray cell close the step into it for either
	# mirror's lane, so LaneWall refuses the placement.
	for side in [BuildGrid.Side.WEST, BuildGrid.Side.EAST]:
		assert_bool(_mode.grid.apply(BuildEdit.place_wall(lane["tray_table"], side)).ok).is_true()
	var ghost := _ghost_at(BuildMode.Tool.TRAY_TABLE, lane["tray_table"], 0)
	var edit := BuildEdit.place_object(SecurityLanes.TRAY_TABLE, lane["tray_table"], 0)
	var check := _mode.check(edit)
	print("walled tray: ghost blocked %s, placement says %d" % [ghost["blocked"], check.reason])
	assert_int(check.reason).is_equal(BuildResult.Reason.LANE_WALL)
	assert_array(ghost["blocked"]).is_equal([lane["unpack"]])
	var found := _recognised_with(SecurityLanes.TRAY_TABLE, lane["tray_table"], 0)
	assert_int(found[1]).is_equal(SecurityLanes.Status.WALL_IN_LANE)
	_compare("walled tray", ghost, SecurityLanes.TRAY_TABLE, found)


func test_a_part_turned_the_wrong_way_shows_the_arch_lane_cells() -> void:
	var skip: Array[StringName] = [SecurityLanes.XRAY_BELT]
	SecurityLaneBuilder.build(_mode.grid, AT, 0, SecurityLanes.RIGHT, skip)
	var lane := SecurityLanes.geometry(AT, 0, SecurityLanes.RIGHT)
	var ghost := _ghost_at(BuildMode.Tool.XRAY_BELT, lane["xray_belt"], 1)
	PassengerTestWorld.place(_mode.grid, SecurityLanes.XRAY_BELT, lane["xray_belt"], 1)
	var found := _recognised(AT)
	assert_int(found[1]).is_equal(SecurityLanes.Status.PARTS_FACING)
	_compare("xray turned to facing 1", ghost, SecurityLanes.XRAY_BELT, found)


func test_an_arch_takes_the_side_the_recogniser_picks() -> void:
	var right := SecurityLanes.geometry(AT, 0, SecurityLanes.RIGHT)
	var left := SecurityLanes.geometry(AT, 0, SecurityLanes.LEFT)
	# One part on each side is a tie, so RIGHT.
	PassengerTestWorld.place(_mode.grid, SecurityLanes.TRAY_TABLE, right["tray_table"], 0)
	PassengerTestWorld.place(_mode.grid, SecurityLanes.PICKUP_TABLE, left["pickup_table"], 0)
	var tie := _ghost_at(BuildMode.Tool.ARCH, AT, 0)
	var tied := _recognised_with(SecurityLanes.ARCH, AT, 0)
	assert_int(tied[0]["mirror"]).is_equal(SecurityLanes.RIGHT)
	_compare("tie", tie, SecurityLanes.ARCH, tied)
	# A second part on the left, turned the wrong way, still counts there.
	PassengerTestWorld.place(_mode.grid, SecurityLanes.XRAY_BELT, left["xray_belt"], 3)
	var more := _ghost_at(BuildMode.Tool.ARCH, AT, 0)
	PassengerTestWorld.place(_mode.grid, SecurityLanes.ARCH, AT, 0)
	var found := _recognised(AT)
	assert_int(found[0]["mirror"]).is_equal(SecurityLanes.LEFT)
	_compare("left has more parts", more, SecurityLanes.ARCH, found)


func test_no_tiles_for_a_piece_with_no_use_side_or_a_lane_part_with_no_arch() -> void:
	var seats := _ghost_at(BuildMode.Tool.SEATS, AT, 1)
	assert_array(seats[StationUseCells.PASSENGER] + seats[StationUseCells.STAFF]).is_empty()
	assert_that(seats["flow"]).is_null()
	var lone := _ghost_at(BuildMode.Tool.TRAY_TABLE, AT, 0)
	assert_array(lone[StationUseCells.PASSENGER] + lone[StationUseCells.STAFF]).is_empty()
	# The trial write leaves the grid as it was.
	assert_int(_mode.grid.object_ids().size()).is_equal(0)
	assert_int(_mode.grid.object_at(AT)).is_equal(0)
