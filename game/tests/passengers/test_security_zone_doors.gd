class_name TestSecurityZoneDoors
extends GdUnitTestSuite
## Regression tests for security-divider doors (ruling 7c2e1a32):
## - Unscreened passengers cannot cross a divider door into airside (neither on
##   TO_SECURITY nor detouring to airside cafes/toilets/shops).
## - Staff can still walk through divider doors freely.
## - Landside-to-landside and airside-to-airside interior doors remain passable.
## - Removing scanners with only a divider door remaining gives NO_SECURITY.
## - Open-plan terminals without a divider remain passable everywhere.

const DIVIDER_DOOR := Vector2i(15, ReferenceTerminal.DIVIDER_Y)

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	return result


func _place_divider_door(grid: BuildGrid) -> void:
	_apply(grid, BuildEdit.place_wall(DIVIDER_DOOR, BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR))


## Builds the reference terminal with an airside-only toilet and kiosk in an
## east annex (x=22..27, y=3..8), plus a divider door at DIVIDER_DOOR.
func _reference_with_airside_facilities() -> Dictionary:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	# East annex: airside floor (22..27, 3..8) divided from landside floor (22..27, 10..15).
	var edits: Array[BuildEdit] = []
	for y in range(3, 17):
		for x in range(22, 28):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(22, 28):
		edits.append(
			BuildEdit.place_wall(Vector2i(x, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH)
		)
	for y in [4, 5, 6, 7]:
		edits.append(BuildEdit.remove_wall(Vector2i(21, y), BuildGrid.Side.EAST))
	for result in grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	EnclosureKit.close_floor(grid)
	# Put an airside toilet room (22..24, 3..8) and airside kiosk room (25..27, 3..8)
	# separated from nothing on landside.
	var toilet_room := _apply(grid, BuildEdit.place_room(Rect2i(22, 3, 3, 6), &"toilet")).room_id
	var stall := _apply(grid, BuildEdit.place_object(&"toilet_stall", Vector2i(22, 3), 0)).object_id
	var kiosk_room := _apply(grid, BuildEdit.place_room(Rect2i(25, 3, 3, 6), &"kiosk")).room_id
	var counter := (
		_apply(grid, BuildEdit.place_object(&"kiosk_counter", Vector2i(25, 3), 0)).object_id
	)
	var display := (
		_apply(grid, BuildEdit.place_object(&"kiosk_display", Vector2i(26, 5), 0)).object_id
	)
	_place_divider_door(grid)
	return {
		"grid": grid,
		"toilet_room": toilet_room,
		"stall": stall,
		"kiosk_room": kiosk_room,
		"counter": counter,
		"display": display,
	}


func test_divider_door_blocks_unscreened_passengers_and_airside_detours() -> void:
	var built := _reference_with_airside_facilities()
	var grid: BuildGrid = built["grid"]
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	# Direct pathing and step check across the divider door must be blocked.
	assert_bool(grid.can_passenger_route(DIVIDER_DOOR, DIVIDER_DOOR + Vector2i.UP)).is_false()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_empty()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(22, 5))).is_empty()

	var ids: Array[int] = []
	for i in 4:
		var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		var p := _world.passenger(id)
		p.toilet_need = ToiletSim.NEED_MAX
		p.toilet_cooldown = 0
		p.hunger = CafeSim.HUNGER_MAX
		p.cafe_cooldown = 0
		p.boredom = BoredomSim.BORED_AT
		p.shop_cooldown = 0
		ids.append(id)
		_world.run_to(_world.clock.tick + 10)

	while _world.clock.tick < PassengerTestWorld.doors_tick():
		_world.step()
		for id in ids:
			var p := _world.passenger(id)
			if p == null:
				continue
			if not p.cleared:
				(
					assert_bool(
						(
							p.stage
							in [
								Passenger.Stage.TOILET_WALK,
								Passenger.Stage.SHOP_WALK,
								Passenger.Stage.CAFE_WALK
							]
						)
					)
					. override_failure_message(
						(
							"unscreened passenger %d entered airside facility detour stage %s"
							% [id, Passenger.Stage.keys()[p.stage]]
						)
					)
					. is_false()
				)
			if p.stage in [Passenger.Stage.SECURITY, Passenger.Stage.APRON, Passenger.Stage.MADE]:
				continue
			if p.at.y <= ReferenceTerminal.AIRSIDE_MAX_Y:
				(
					assert_bool(p.cleared)
					. override_failure_message(
						"passenger %d crossed into airside at %s without clearance" % [id, p.at]
					)
					. is_true()
				)

	assert_int(_world.sim.made_count()).is_equal(4)


func test_divider_door_blocks_airside_cafe_detour_for_unscreened_passengers() -> void:
	var grid := BuildGrid.new()
	var ids := CafeTestLayout.build(grid)
	# Remove landside counter so ONLY the airside cafe is open.
	_apply(grid, BuildEdit.remove_object(ids["land_counter"]))
	_place_divider_door(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var air_counter_front := CafeTestLayout.AIR_COUNTER + Vector2i(0, 1)
	assert_array(grid.find_path(Vector2i(15, 12), air_counter_front)).is_empty()
	var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(pid)
	p.hunger = CafeSim.HUNGER_MAX
	p.cafe_cooldown = 0
	p.toilet_need = 0
	p.toilet_cooldown = 1000000
	p.boredom = 0
	p.shop_cooldown = 1000000
	while _world.clock.tick < PassengerTestWorld.doors_tick():
		_world.step()
		var live := _world.passenger(pid)
		if live == null:
			break
		if not live.cleared:
			assert_int(live.stage).is_not_equal(Passenger.Stage.CAFE_WALK)
		if live.stage in [Passenger.Stage.SECURITY, Passenger.Stage.APRON, Passenger.Stage.MADE]:
			continue
		if live.at.y <= ReferenceTerminal.AIRSIDE_MAX_Y:
			assert_bool(live.cleared).is_true()
	assert_int(_world.sim.made_count()).is_equal(1)


func test_staff_can_walk_through_divider_door() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	_place_divider_door(grid)
	assert_bool(grid.can_staff_route(DIVIDER_DOOR, DIVIDER_DOOR + Vector2i.UP)).is_true()
	var staff_path := grid.find_staff_path(Vector2i(15, 10), Vector2i(15, 7))
	assert_array(staff_path).is_not_empty()
	assert_bool(staff_path.has(DIVIDER_DOOR)).is_true()
	assert_bool(staff_path.has(DIVIDER_DOOR + Vector2i.UP)).is_true()
	var reach := StaffSpots.reach(grid)
	assert_int(reach.get(Vector2i(15, 10), -1)).is_equal(reach.get(Vector2i(15, 7), -2))


func test_landside_and_airside_same_side_doors_stay_passable() -> void:
	var grid := BuildGrid.new()
	var ids := ToiletTestLayout.build(grid)
	# Wall off the east annex rooms completely, leaving one door on landside and
	# one door on airside, plus a divider door between landside and airside.
	var edits: Array[BuildEdit] = []
	for y in [4, 6, 7, 11, 13, 14, 15]:
		edits.append(BuildEdit.place_wall(Vector2i(21, y), BuildGrid.Side.EAST))
	for y in [5, 12]:
		edits.append(
			BuildEdit.place_wall(Vector2i(21, y), BuildGrid.Side.EAST, BuildGrid.WallKind.DOOR)
		)
	for res in grid.apply_batch(edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	_place_divider_door(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))

	# Landside-to-landside door (21, 12) EAST and airside-to-airside door (21, 5)
	# EAST are passable; divider door (15, 9) NORTH is still blocked.
	_world.sim.toilets.refresh()
	var land_stall := _world.sim.toilets.layout.stall(ids["land_stalls"][0])
	var air_stall := _world.sim.toilets.layout.stall(ids["air_stalls"][0])
	assert_array(grid.find_path(Vector2i(15, 12), land_stall["approach"])).is_not_empty()
	assert_array(grid.find_path(Vector2i(17, 7), air_stall["approach"])).is_not_empty()
	assert_array(grid.find_path(Vector2i(15, 12), air_stall["approach"])).is_empty()

	# Unscreened passenger uses the walled landside toilet through the landside door.
	var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(pid)
	ToiletTestLayout.calm(p)
	p.toilet_need = ToiletSim.NEED_MAX
	p.toilet_cooldown = 0
	var used_land := false
	for _i in 400:
		_world.step()
		if p.stage == Passenger.Stage.TOILET_USE:
			used_land = true
			assert_bool(p.cleared).is_false()
			assert_int(p.at.y).is_greater(ReferenceTerminal.AIRSIDE_MAX_Y)
			break
	assert_bool(used_land).is_true()

	# Cleared passenger uses the walled airside toilet through the airside door.
	var air_pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var air_p := _world.passenger(air_pid)
	ToiletTestLayout.calm(air_p)
	air_p.cleared = true
	air_p.stage = Passenger.Stage.TO_GATE
	air_p.stage_tick = _world.clock.tick + 1
	air_p.at = Vector2i(17, 7)
	air_p.clear_path()
	air_p.toilet_need = ToiletSim.NEED_MAX
	air_p.toilet_cooldown = 0
	var used_air := false
	for _i in 300:
		_world.step()
		if air_p.stage == Passenger.Stage.TOILET_USE:
			used_air = true
			assert_int(air_p.at.y).is_less_equal(ReferenceTerminal.AIRSIDE_MAX_Y)
			break
	assert_bool(used_air).is_true()


func test_removing_scanners_with_only_divider_door_gives_no_security() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	for id in ReferenceTerminal.object_ids(grid)["scanners"]:
		_apply(grid, BuildEdit.remove_object(id))
	for x in ReferenceTerminal.SCANNER_XS:
		_apply(
			grid,
			BuildEdit.place_wall(Vector2i(x, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH)
		)
	_place_divider_door(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))

	var ids := [
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT),
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT),
	]
	_world.run_to(600)
	for id in ids:
		var p := _world.passenger(id)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_SECURITY)
		assert_int(p.stuck).is_equal(Passenger.Stuck.NO_SECURITY)
		assert_bool(p.cleared).is_false()
		assert_int(p.at.y).is_greater(ReferenceTerminal.AIRSIDE_MAX_Y)
	_world.run_to(PassengerTestWorld.doors_tick())
	for id in ids:
		assert_int(_world.passenger(id).stage).is_equal(Passenger.Stage.MISSED)
		assert_int(_world.passenger(id).seat_object).is_equal(0)


func test_open_plan_terminal_with_interior_door_keeps_working() -> void:
	var grid := BuildGrid.new()
	for result in grid.apply_batch(ReferenceTerminal.shell_edits()):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	_apply(grid, BuildEdit.place_object(&"checkin_desk", Vector2i(11, 11), 0))
	_apply(grid, BuildEdit.place_object(&"seat_row", Vector2i(11, 3), 0))
	# Build an internal walled room with a door in the open-plan hall.
	var room_edits: Array[BuildEdit] = [
		BuildEdit.place_wall(Vector2i(15, 11), BuildGrid.Side.NORTH),
		BuildEdit.place_wall(Vector2i(16, 11), BuildGrid.Side.NORTH),
		BuildEdit.place_wall(Vector2i(17, 11), BuildGrid.Side.NORTH),
		BuildEdit.place_wall(Vector2i(15, 11), BuildGrid.Side.WEST),
		BuildEdit.place_wall(Vector2i(17, 11), BuildGrid.Side.EAST),
		BuildEdit.place_wall(Vector2i(15, 11), BuildGrid.Side.SOUTH),
		BuildEdit.place_wall(Vector2i(17, 11), BuildGrid.Side.SOUTH),
		BuildEdit.place_wall(Vector2i(16, 11), BuildGrid.Side.SOUTH, BuildGrid.WallKind.DOOR),
	]
	for result in grid.apply_batch(room_edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	var entrance := ReferenceTerminal.ENTRANCE_CELL
	assert_array(grid.find_path(entrance, ReferenceTerminal.EXIT_CELL)).is_not_empty()
	assert_array(grid.find_path(entrance, Vector2i(16, 11))).is_not_empty()


func test_screened_passenger_stays_in_airside_and_cannot_cross_divider_door_to_landside() -> void:
	var grid := BuildGrid.new()
	var ids := ToiletTestLayout.build(grid)
	for stall in ids["air_stalls"]:
		_apply(grid, BuildEdit.remove_object(stall))
	_place_divider_door(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(pid)
	ToiletTestLayout.calm(p)
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick + 1
	p.at = Vector2i(17, 7)
	p.clear_path()
	p.toilet_need = ToiletSim.NEED_MAX
	p.toilet_cooldown = 0
	for _i in 60:
		_world.step()
		assert_object(_world.sim.toilets.visit_of(pid)).is_null()
		assert_int(p.at.y).is_less_equal(ReferenceTerminal.AIRSIDE_MAX_Y)


func test_closing_gap_flips_door_to_divider_and_updates_pathing() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var gap := Vector2i(12, ReferenceTerminal.DIVIDER_Y)
	_apply(grid, BuildEdit.remove_wall(gap, BuildGrid.Side.NORTH))
	_place_divider_door(grid)
	# While the gap is open, the whole floor is one component so the door is open.
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_not_empty()
	# Closing the gap turns the door into a divider door and disconnects it.
	_apply(grid, BuildEdit.place_wall(gap, BuildGrid.Side.NORTH))
	assert_bool(grid.can_passenger_route(DIVIDER_DOOR, DIVIDER_DOOR + Vector2i.UP)).is_false()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_empty()


func test_in_place_from_snapshot_replaces_divider_door_state() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	_place_divider_door(grid)
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_empty()
	var door_snap := grid.to_snapshot()

	var open_grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(open_grid)).is_true()
	_apply(
		open_grid,
		BuildEdit.remove_wall(Vector2i(12, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH)
	)
	_place_divider_door(open_grid)
	var open_snap := open_grid.to_snapshot()

	# In-place reload onto the already-used grid must clear stale divider doors.
	assert_bool(grid.from_snapshot(open_snap)).is_true()
	assert_bool(grid.can_passenger_route(DIVIDER_DOOR, DIVIDER_DOOR + Vector2i.UP)).is_true()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_not_empty()

	# Reloading the divider-door snapshot in-place restores the barrier.
	assert_bool(grid.from_snapshot(door_snap)).is_true()
	assert_bool(grid.can_passenger_route(DIVIDER_DOOR, DIVIDER_DOOR + Vector2i.UP)).is_false()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_empty()


func test_unrelated_indoor_object_on_large_grid_skips_divider_door_recompute() -> void:
	var grid := BuildGrid.new(Vector2i(256, 150))
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	_place_divider_door(grid)
	# With _pathing not yet created, edits stay lazy and do not recompute divider doors.
	assert_int(grid.divider_door_rebuilds).is_equal(0)
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_empty()
	assert_int(grid.divider_door_rebuilds).is_equal(1)

	var before := grid.divider_door_rebuilds
	var started := Time.get_ticks_usec()
	var placed := _apply(grid, BuildEdit.place_object(&"plant_pot_1a", Vector2i(12, 14), 0))
	_apply(grid, BuildEdit.remove_object(placed.object_id))
	var elapsed_usec := Time.get_ticks_usec() - started
	print(
		(
			"256x150 unrelated place+remove usec=%d rebuilds=%d"
			% [elapsed_usec, grid.divider_door_rebuilds - before]
		)
	)
	assert_int(grid.divider_door_rebuilds).is_equal(before)
	assert_int(elapsed_usec).is_less(25000)

	# Placing a gate-seat anchor still triggers a bounded divider-door recompute.
	_apply(grid, BuildEdit.place_object(&"seat_row", Vector2i(17, 3), 0))
	assert_int(grid.divider_door_rebuilds).is_equal(before + 1)


func _divided_box_without_anchors(skip_divider_xs: Array[int] = []) -> BuildGrid:
	var grid := BuildGrid.new()
	var edits: Array[BuildEdit] = []
	for y in range(ReferenceTerminal.FLOOR_MIN.y, ReferenceTerminal.FLOOR_MAX.y + 1):
		for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		edits.append(
			BuildEdit.place_wall(Vector2i(x, ReferenceTerminal.FLOOR_MIN.y), BuildGrid.Side.NORTH)
		)
		if x != ReferenceTerminal.ENTRANCE_CELL.x:
			edits.append(
				BuildEdit.place_wall(
					Vector2i(x, ReferenceTerminal.FLOOR_MAX.y), BuildGrid.Side.SOUTH
				)
			)
		if not skip_divider_xs.has(x):
			edits.append(
				BuildEdit.place_wall(Vector2i(x, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH)
			)
	for y in range(ReferenceTerminal.FLOOR_MIN.y, ReferenceTerminal.FLOOR_MAX.y + 1):
		edits.append(
			BuildEdit.place_wall(Vector2i(ReferenceTerminal.FLOOR_MIN.x, y), BuildGrid.Side.WEST)
		)
		edits.append(
			BuildEdit.place_wall(Vector2i(ReferenceTerminal.FLOOR_MAX.x, y), BuildGrid.Side.EAST)
		)
	for res in grid.apply_batch(edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	_apply(grid, BuildEdit.place_object(&"entrance_door", ReferenceTerminal.ENTRANCE_CELL, 2))
	_place_divider_door(grid)
	return grid


func test_removing_lane_blocker_completes_arch_and_blocks_divider_door() -> void:
	var grid := _divided_box_without_anchors([17, 18, 19])
	var arch_at := Vector2i(18, ReferenceTerminal.DIVIDER_Y)
	var wall_edits: Array[BuildEdit] = [
		BuildEdit.place_wall(Vector2i(17, 8), BuildGrid.Side.WEST),
		BuildEdit.place_wall(Vector2i(17, 7), BuildGrid.Side.WEST),
		BuildEdit.place_wall(Vector2i(17, 7), BuildGrid.Side.NORTH),
		BuildEdit.place_wall(Vector2i(17, 7), BuildGrid.Side.EAST),
		BuildEdit.place_wall(Vector2i(17, 9), BuildGrid.Side.EAST),
		BuildEdit.place_wall(Vector2i(17, 8), BuildGrid.Side.EAST, BuildGrid.WallKind.DOOR),
		BuildEdit.place_wall(Vector2i(20, 8), BuildGrid.Side.WEST),
	]
	for res in grid.apply_batch(wall_edits):
		assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	var lane := SecurityLanes.geometry(arch_at, 0, SecurityLanes.RIGHT)
	# Block the lane's exit cell before placing the lane so it starts incomplete.
	var blocker := _apply(grid, BuildEdit.place_object(&"plant_pot_1a", lane["exit"], 0)).object_id
	SecurityLaneBuilder.build(grid, arch_at, 0, SecurityLanes.RIGHT)
	assert_bool(grid.recognised_lanes().is_complete(grid.object_at(arch_at))).is_false()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_not_empty()

	# Removing the blocker completes the arch lane and turns the door into a barrier.
	_apply(grid, BuildEdit.remove_object(blocker))
	assert_bool(grid.recognised_lanes().is_complete(grid.object_at(arch_at))).is_true()
	assert_bool(grid.can_passenger_route(DIVIDER_DOOR, DIVIDER_DOOR + Vector2i.UP)).is_false()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_empty()

	# Blocking the lane exit with a desk whose interaction_cell lands on lane["exit"]
	# (footprint at y=6 outside the lane) also breaks the sole airside anchor.
	var desk := (
		_apply(grid, BuildEdit.place_object(&"checkin_desk", lane["exit"] + Vector2i.UP, 0))
		. object_id
	)
	assert_bool(grid.recognised_lanes().is_complete(grid.object_at(arch_at))).is_false()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_not_empty()
	_apply(grid, BuildEdit.remove_object(desk))
	assert_bool(grid.recognised_lanes().is_complete(grid.object_at(arch_at))).is_true()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_empty()


func test_blocking_sole_seat_front_flips_divider_door_state() -> void:
	var grid := _divided_box_without_anchors()
	_apply(grid, BuildEdit.place_object(&"bench_1a", Vector2i(14, 3), 0))
	# bench_1a at (14, 3) facing 0 opens to -X at (13, 3) and (13, 5).
	_apply(grid, BuildEdit.place_object(&"plant_pot_1a", Vector2i(13, 3), 0))
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_empty()

	# Blocking the sole remaining bench front cell removes the only airside anchor.
	var last_block := (
		_apply(grid, BuildEdit.place_object(&"plant_pot_1a", Vector2i(13, 5), 0)).object_id
	)
	assert_bool(grid.can_passenger_route(DIVIDER_DOOR, DIVIDER_DOOR + Vector2i.UP)).is_true()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_not_empty()

	# Unblocking the bench front cell restores the airside anchor and blocks the door.
	_apply(grid, BuildEdit.remove_object(last_block))
	assert_bool(grid.can_passenger_route(DIVIDER_DOOR, DIVIDER_DOOR + Vector2i.UP)).is_false()
	assert_array(grid.find_path(Vector2i(15, 12), Vector2i(15, 5))).is_empty()
