class_name TestStaffSpotLegacy
extends GdUnitTestSuite
## A layout saved before staff spots still loads: a station whose spot is
## blocked or shared is reported by StaffSpots.blocked(), and removing one of
## two stations sharing a spot keeps the other's spot protected. The starting
## layouts have every spot free (decision
## staff-spot-design-a-derived-staff-spot-behind-each-desk-and, point 3).

const DESK := &"checkin_desk"
const SCANNER := &"security_scanner"
const SEATS := &"seat_row"
const SHELL := preload("res://build/toon_terminal_shell.tres")


## `objects` as [def, anchor, facing] put straight into a snapshot of a
## floored grid, past today's placement rules, then loaded into a fresh grid.
func _legacy_grid(objects: Array) -> BuildGrid:
	var data := PassengerTestWorld.floored(Vector2i(12, 10)).to_snapshot()
	var entries := []
	for i in objects.size():
		var anchor: Vector2i = objects[i][1]
		entries.append(
			{
				"id": i + 1,
				"def": str(objects[i][0]),
				"anchor": [anchor.x, anchor.y],
				"facing": objects[i][2]
			}
		)
	data["objects"] = entries
	data["next_object_id"] = objects.size() + 1
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(JSON.parse_string(JSON.stringify(data)))).is_true()
	return grid


func test_a_save_with_a_blocked_spot_loads_and_reports_that_station() -> void:
	# The seat row stands on the first desk's spot (3, 2).
	var grid := _legacy_grid(
		[[DESK, Vector2i(3, 3), 0], [DESK, Vector2i(7, 3), 0], [SEATS, Vector2i(2, 2), 0]]
	)
	assert_int(grid.object_ids().size()).is_equal(3)
	print(
		"blocked: first %s, second %s" % [StaffSpots.blocked(grid, 1), StaffSpots.blocked(grid, 2)]
	)
	assert_bool(StaffSpots.blocked(grid, 1)).is_true()
	assert_bool(StaffSpots.blocked(grid, 2)).is_false()
	assert_bool(StaffSpots.blocked(grid, 3)).is_false()


func test_a_shared_spot_blocks_both_until_one_station_goes() -> void:
	# The scanner at (2, 1) and the desk at (3, 3) both stand staff on (3, 2).
	var grid := _legacy_grid([[SCANNER, Vector2i(2, 1), 0], [DESK, Vector2i(3, 3), 0]])
	assert_bool(StaffSpots.blocked(grid, 1)).is_true()
	assert_bool(StaffSpots.blocked(grid, 2)).is_true()
	assert_bool(grid.apply(BuildEdit.remove_object(1)).ok).is_true()
	assert_bool(StaffSpots.blocked(grid, 2)).is_false()
	var seats := grid.apply(BuildEdit.place_object(SEATS, Vector2i(2, 2), 0))
	print("seat row on the kept spot: %s" % seats.reason_text())
	assert_int(seats.reason).is_equal(BuildResult.Reason.STAFF_SPOT)
	assert_int(seats.blocking_object_id).is_equal(2)
	assert_int(grid.apply(BuildEdit.remove_floor(Vector2i(3, 2))).reason).is_equal(
		BuildResult.Reason.STAFF_SPOT
	)


func test_removing_the_desk_of_a_shared_spot_keeps_the_scanner_protected() -> void:
	var grid := _legacy_grid([[SCANNER, Vector2i(2, 1), 0], [DESK, Vector2i(3, 3), 0]])
	assert_bool(grid.apply(BuildEdit.remove_object(2)).ok).is_true()
	assert_bool(StaffSpots.blocked(grid, 1)).is_false()
	var floor_gone := grid.apply(BuildEdit.remove_floor(Vector2i(3, 2)))
	assert_int(floor_gone.reason).is_equal(BuildResult.Reason.STAFF_SPOT)
	assert_int(floor_gone.blocking_object_id).is_equal(1)


func test_the_reference_terminal_has_every_spot_free() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var ids := ReferenceTerminal.object_ids(grid)
	var stations: Array = ids["desks"] + ids["scanners"]
	assert_int(stations.size()).is_equal(4)
	for station: int in stations:
		print("reference station %d spot %s" % [station, StaffSpots.spot_of(grid, station)])
		assert_bool(StaffSpots.blocked(grid, station)).is_false()


func test_the_hand_built_terminal_builds_with_every_spot_free() -> void:
	var mode := BuildMode.new()
	mode.shell = SHELL
	add_child(mode)
	var terminal := HandBuiltTerminal.new(mode)
	terminal.build()
	print("hand-built: applied %d, refused %s" % [terminal.applied, terminal.refused])
	assert_array(terminal.refused).is_empty()
	var stations := 0
	for id in mode.grid.object_ids():
		if StaffSpots.has_spot(StringName(mode.grid.get_object(id)["def"])):
			stations += 1
			assert_bool(StaffSpots.blocked(mode.grid, id)).is_false()
	assert_int(stations).is_equal(4)
	mode.free()
