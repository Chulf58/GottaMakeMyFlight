class_name TestPassengerEditsRecovery
extends GdUnitTestSuite
## Regression tests for PassengerEdits recovery when BuildUndo or unpaused
## building restores an object, places a wall, or removes floor onto a live
## passenger's cell (board 81d616ee).

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


func _apply(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var result := grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	return result


func _calm(p: Passenger) -> void:
	p.hunger = 0
	p.cafe_cooldown = 1000000
	p.toilet_need = 0
	p.toilet_cooldown = 1000000
	p.boredom = 0
	p.shop_cooldown = 1000000


func _walk_passenger_onto_cell(p: Passenger, target: Vector2i, need_seg_mm := false) -> bool:
	var limit := _world.clock.tick + 600
	while _world.clock.tick < limit:
		_world.step()
		if p.at == target and p.is_moving() and (not need_seg_mm or p.seg_mm > 0):
			return true
		if p.is_done():
			return false
	return false


func test_undo_restoring_object_onto_walking_passenger_mid_step_recovers_onto_next() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.step()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	_calm(p)
	for i in 4:
		_world.step()
	assert_bool(p.is_moving()).is_true()
	assert_int(p.path.size()).is_greater_equal(p.path_index + 4)
	var obstacle_cell := p.path[p.path_index + 2]
	var placed := _apply(_world.grid, BuildEdit.place_object(&"statue_indoor", obstacle_cell, 0))
	var receipt := BuildReceipt.new()
	_world.grid.recorder = receipt
	_apply(_world.grid, BuildEdit.remove_object(placed.object_id))
	_world.grid.recorder = null
	assert_bool(_walk_passenger_onto_cell(p, obstacle_cell, true)).is_true()
	var next_cell := p.path[p.path_index + 1]
	assert_bool(_world.grid.is_passenger_cell(next_cell)).is_true()

	var undone := BuildUndo.commit(_world.grid, receipt, null)
	assert_bool(undone.ok).override_failure_message(undone.reason_text()).is_true()
	assert_bool(_world.grid.is_passenger_cell(obstacle_cell)).is_false()
	assert_bool(p.needs_replan).is_true()

	_world.step()
	assert_vector(p.at).is_equal(next_cell)
	assert_bool(_world.grid.is_passenger_cell(p.at)).is_true()
	assert_int(p.stuck).is_not_equal(Passenger.Stuck.NO_ROUTE)

	_world.run_to(PassengerTestWorld.doors_tick() - 1)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_place_object_onto_stationary_passenger_relocates_and_continues() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.step()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	_calm(p)
	while p.at.y > 14 and _world.clock.tick < 200:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	assert_int(p.at.y).is_less_equal(14)
	# Clear path to simulate a stationary passenger on open floor (e.g. waiting
	# for a desk or stuck with NO_ROUTE).
	p.clear_path()
	p.stuck = Passenger.Stuck.NO_ROUTE
	var blocked_cell := p.at
	_apply(_world.grid, BuildEdit.place_object(&"statue_indoor", blocked_cell, 0))
	assert_bool(_world.grid.is_passenger_cell(blocked_cell)).is_false()

	_world.step()
	assert_that(p.at).is_not_equal(blocked_cell)
	assert_bool(_world.grid.is_passenger_cell(p.at)).is_true()
	assert_int(p.stuck).is_not_equal(Passenger.Stuck.NO_ROUTE)

	_world.run_to(PassengerTestWorld.doors_tick() - 1)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_undo_removing_painted_floor_under_passenger_recovers_to_walkable_cell() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.step()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	_calm(p)
	for i in 4:
		_world.step()
	assert_bool(p.is_moving()).is_true()
	assert_int(p.path.size()).is_greater_equal(p.path_index + 4)
	var floor_cell := p.path[p.path_index + 2]
	_apply(_world.grid, BuildEdit.remove_floor(floor_cell))
	var receipt := BuildReceipt.new()
	_world.grid.recorder = receipt
	_apply(_world.grid, BuildEdit.paint_floor(floor_cell, BuildGrid.FLOOR_TILE, 0))
	_world.grid.recorder = null
	assert_bool(_walk_passenger_onto_cell(p, floor_cell, true)).is_true()

	var undone := BuildUndo.commit(_world.grid, receipt, null)
	assert_bool(undone.ok).override_failure_message(undone.reason_text()).is_true()
	assert_bool(_world.grid.is_passenger_cell(floor_cell)).is_false()

	_world.step()
	assert_that(p.at).is_not_equal(floor_cell)
	assert_bool(_world.grid.is_passenger_cell(p.at)).is_true()
	assert_int(p.stuck).is_not_equal(Passenger.Stuck.NO_ROUTE)

	_world.run_to(PassengerTestWorld.doors_tick() - 1)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_place_wall_across_mid_step_keeps_passenger_off_blocked_cells_and_side() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.step()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	_calm(p)
	while p.at.y > 14 and _world.clock.tick < 200:
		_world.step()
	assert_bool(p.is_moving()).is_true()
	assert_int(p.at.y).is_less_equal(14)
	var here := p.at
	var next := p.path[p.path_index + 1]
	# Force a straight step so a single wall edge separates here and next.
	if next.x != here.x and next.y != here.y:
		next = Vector2i(here.x + signi(next.x - here.x), here.y)
		var path: Array[Vector2i] = [here]
		path.append_array(_world.grid.find_path(next, p.path_end()))
		p.set_path(path)
	p.seg_mm = 200
	var side := BuildGrid.SIDE_STEP.find(next - here)
	assert_int(side).is_greater_equal(0)
	_apply(_world.grid, BuildEdit.place_wall(here, side))
	# Also block `here` so recovery must NOT jump across the wall onto `next`.
	_apply(_world.grid, BuildEdit.place_object(&"statue_indoor", here, 0))
	assert_bool(_world.grid.is_passenger_cell(here)).is_false()
	assert_bool(_world.grid.is_passenger_cell(next)).is_true()

	_world.step()
	assert_that(p.at).is_not_equal(here)
	assert_that(p.at).is_not_equal(next)
	assert_bool(_world.grid.is_passenger_cell(p.at)).is_true()


func test_recovery_never_teleports_unscreened_passenger_across_divider_door() -> void:
	_world = PassengerTestWorld.reference_world()
	var door_cell := Vector2i(15, ReferenceTerminal.DIVIDER_Y)
	_apply(
		_world.grid, BuildEdit.place_wall(door_cell, BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR)
	)
	# Narrow the landside approach to `door_cell` with east/west walls while
	# keeping south open so `door_cell` stays on landside and the north door
	# remains a security divider door.
	_apply(_world.grid, BuildEdit.place_wall(door_cell, BuildGrid.Side.EAST))
	_apply(_world.grid, BuildEdit.place_wall(door_cell, BuildGrid.Side.WEST))
	assert_bool(_world.grid.can_passenger_route(door_cell, door_cell + Vector2i.UP)).is_false()

	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	_calm(p)
	p.stage = Passenger.Stage.TO_SECURITY
	p.cleared = false
	p.at = door_cell
	var step_path: Array[Vector2i] = [door_cell, door_cell + Vector2i.UP]
	p.set_path(step_path)
	p.seg_mm = 200
	_apply(_world.grid, BuildEdit.place_object(&"statue_indoor", door_cell, 0))
	_world.step()
	assert_bool(_world.grid.is_passenger_cell(p.at)).is_true()
	assert_int(p.at.y).is_greater_equal(ReferenceTerminal.DIVIDER_Y)
	assert_that(p.at).is_not_equal(door_cell + Vector2i.UP)


func test_recovery_never_teleports_through_security_scanner_in_walled_alcove() -> void:
	_world = PassengerTestWorld.reference_world()
	# Place a security_arch in a gap at (15, 9) and enclose its landside entry
	# cell (15, 10) on east, west, and south with an obstacle on (15, 10), so
	# the only WallKind.NONE edge from (15, 10) goes north into the arch.
	var arch_cell := Vector2i(15, ReferenceTerminal.DIVIDER_Y)
	var entry_cell := arch_cell + Vector2i.DOWN
	_apply(_world.grid, BuildEdit.remove_wall(arch_cell, BuildGrid.Side.NORTH))
	_apply(_world.grid, BuildEdit.place_object(&"security_arch", arch_cell, 2))
	_apply(_world.grid, BuildEdit.place_wall(entry_cell, BuildGrid.Side.EAST))
	_apply(_world.grid, BuildEdit.place_wall(entry_cell, BuildGrid.Side.WEST))
	_apply(_world.grid, BuildEdit.place_wall(entry_cell, BuildGrid.Side.SOUTH))
	_apply(_world.grid, BuildEdit.place_object(&"statue_indoor", entry_cell, 0))

	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	_calm(p)
	p.stage = Passenger.Stage.TO_SECURITY
	p.cleared = false
	p.at = entry_cell
	p.clear_path()

	_world.step()
	assert_vector(p.at).is_equal(entry_cell)
	assert_bool(p.cleared).is_false()
	assert_int(p.at.y).is_greater_equal(ReferenceTerminal.DIVIDER_Y)


func test_undo_restoring_security_scanner_onto_walking_passenger_recovers_to_landside() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.step()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	_calm(p)
	for i in 4:
		_world.step()
	assert_bool(p.is_moving()).is_true()
	assert_int(p.path.size()).is_greater_equal(p.path_index + 4)
	var scan_cell := p.path[p.path_index + 2]
	var placed := _apply(
		_world.grid, BuildEdit.place_object(&"security_scanner", scan_cell + Vector2i.UP, 0)
	)
	var receipt := BuildReceipt.new()
	_world.grid.recorder = receipt
	_apply(_world.grid, BuildEdit.remove_object(placed.object_id))
	_world.grid.recorder = null
	assert_bool(_walk_passenger_onto_cell(p, scan_cell, true)).is_true()

	var undone := BuildUndo.commit(_world.grid, receipt, null)
	assert_bool(undone.ok).override_failure_message(undone.reason_text()).is_true()
	# Security scanners are walk_through so raw is_passenger_cell() is still true.
	assert_bool(_world.grid.is_passenger_cell(scan_cell)).is_true()

	_world.step()
	assert_that(p.at).is_not_equal(scan_cell)
	assert_bool(_world.grid.is_passenger_cell(p.at)).is_true()
	assert_int(_world.grid.object_at(p.at)).is_equal(0)
	assert_int(p.stuck).is_not_equal(Passenger.Stuck.NO_ROUTE)

	_world.run_to(PassengerTestWorld.doors_tick() - 1)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


func test_undo_security_scanner_in_divider_gap_ejects_unscreened_passenger_to_landside() -> void:
	_world = PassengerTestWorld.reference_world()
	var scanner_id: int = ReferenceTerminal.object_ids(_world.grid)["scanners"][0]
	var receipt := BuildReceipt.new()
	_world.grid.recorder = receipt
	_apply(_world.grid, BuildEdit.remove_object(scanner_id))
	_world.grid.recorder = null
	_world.step()

	# Stationary unscreened passenger at (17, 8) and mid-step unscreened
	# passenger at (17, 8) stepping north toward airside (17, 7).
	var p_still := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_calm(p_still)
	p_still.stage = Passenger.Stage.TO_SECURITY
	p_still.cleared = false
	p_still.at = Vector2i(17, 8)
	p_still.clear_path()

	var p_step := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_calm(p_step)
	p_step.stage = Passenger.Stage.TO_SECURITY
	p_step.cleared = false
	p_step.at = Vector2i(17, 8)
	var north_step: Array[Vector2i] = [Vector2i(17, 8), Vector2i(17, 7)]
	p_step.set_path(north_step)
	p_step.seg_mm = 200

	var undone := BuildUndo.commit(_world.grid, receipt, null)
	assert_bool(undone.ok).override_failure_message(undone.reason_text()).is_true()

	_world.step()
	for p in [p_still, p_step]:
		assert_int(p.at.y).is_greater(ReferenceTerminal.DIVIDER_Y)
		assert_bool(_world.grid.is_passenger_cell(p.at)).is_true()
		assert_int(_world.grid.object_at(p.at)).is_equal(0)
		assert_bool(p.cleared).is_false()
		assert_int(p.stuck).is_not_equal(Passenger.Stuck.NO_ROUTE)

	_world.run_to(PassengerTestWorld.doors_tick() - 1)
	assert_int(p_still.stage).is_equal(Passenger.Stage.MADE)
	assert_int(p_step.stage).is_equal(Passenger.Stage.MADE)


func test_security_arch_in_divider_gap_splits_unscreened_and_cleared() -> void:
	_world = PassengerTestWorld.reference_world()
	var arch_cell := Vector2i(15, ReferenceTerminal.DIVIDER_Y)
	_apply(_world.grid, BuildEdit.remove_wall(arch_cell, BuildGrid.Side.NORTH))
	_world.step()

	var p_unscreened := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_calm(p_unscreened)
	p_unscreened.stage = Passenger.Stage.TO_SECURITY
	p_unscreened.cleared = false
	p_unscreened.at = arch_cell
	var arch_north: Array[Vector2i] = [arch_cell, arch_cell + Vector2i.UP]
	p_unscreened.set_path(arch_north)
	p_unscreened.seg_mm = 200

	var p_cleared := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_calm(p_cleared)
	p_cleared.stage = Passenger.Stage.TO_GATE
	p_cleared.cleared = true
	p_cleared.at = arch_cell
	p_cleared.clear_path()

	_apply(_world.grid, BuildEdit.place_object(&"security_arch", arch_cell, 0))
	_world.step()
	assert_vector(p_unscreened.at).is_equal(arch_cell + Vector2i.DOWN)
	assert_bool(p_unscreened.cleared).is_false()
	assert_vector(p_cleared.at).is_equal(arch_cell + Vector2i.UP)
	assert_bool(p_cleared.cleared).is_true()


func test_non_recoverable_stages_are_not_relocated_when_cell_is_not_passenger_cell() -> void:
	_world = PassengerTestWorld.reference_world()
	var blocked_cell := Vector2i(12, 14)
	_apply(_world.grid, BuildEdit.place_object(&"statue_indoor", blocked_cell, 0))
	assert_bool(_world.grid.is_passenger_cell(blocked_cell)).is_false()
	for stage in [
		Passenger.Stage.SPAWNED,
		Passenger.Stage.SECURITY,
		Passenger.Stage.SITTING_DOWN,
		Passenger.Stage.SEATED,
		Passenger.Stage.STANDING_UP,
		Passenger.Stage.APRON,
		Passenger.Stage.CAFE_SEATED,
		Passenger.Stage.TOILET_USE,
		Passenger.Stage.SHOP_BROWSE,
	]:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.stage = stage
		p.at = blocked_cell
		p.clear_path()
		PassengerEdits.replan(_world.sim, p)
		assert_vector(p.at).override_failure_message("stage %d moved" % stage).is_equal(
			blocked_cell
		)


func test_passenger_views_survives_undo_recovery_without_errors_or_orphans() -> void:
	_world = PassengerTestWorld.reference_world()
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_world.step()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var p := _world.passenger(id)
	_calm(p)
	for i in 4:
		_world.step()
	var obstacle_cell := p.path[p.path_index + 2]
	var placed := _apply(_world.grid, BuildEdit.place_object(&"statue_indoor", obstacle_cell, 0))
	var receipt := BuildReceipt.new()
	_world.grid.recorder = receipt
	_apply(_world.grid, BuildEdit.remove_object(placed.object_id))
	_world.grid.recorder = null
	assert_bool(_walk_passenger_onto_cell(p, obstacle_cell, true)).is_true()

	assert_bool(BuildUndo.commit(_world.grid, receipt, null).ok).is_true()
	_world.step()
	assert_bool(_world.grid.is_passenger_cell(p.at)).is_true()

	_world.run_to(PassengerTestWorld.doors_tick() + PassengerSim.SETTLED_KEEP_TICKS + 2)
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_int(_views.active_count()).is_equal(0)
