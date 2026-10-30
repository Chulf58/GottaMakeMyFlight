class_name TestStandingSpots
extends GdUnitTestSuite
## Standing spots near the gate (StandingSpots): derivation and exclusions,
## stable ids and spacing, nearest-free order with id tie-breaks, and one
## passenger walking to its spot and standing on it. The claims in the running
## sim are in test_standing_spot_claims.gd. Each case builds its own small
## world, because claims and edits change it.

## A basic scanner's exit cell in the reference terminal (the passage end).
const SCANNER_EXIT := Vector2i(17, 7)
## The airside partition test's wall runs along the north edge of this row.
const PARTITION_Y := 5

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
	_world = null


## The reference terminal with its four seat rows taken out: every cleared
## passenger stands, and the gate area grows from the exit door.
func _seatless_world() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world()
	for id in ReferenceTerminal.object_ids(world.grid)["seats"]:
		assert_bool(world.grid.apply(BuildEdit.remove_object(id)).ok).is_true()
	world.sim.standing.rebuild(world.sim)
	return world


## A calm, cleared passenger on its way to the gate at `cell`, trying for a
## seat or spot on the next tick.
func _cleared(cell := SCANNER_EXIT) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick + 1
	p.at = cell
	p.clear_path()
	p.apron = []
	p.apron_mm = 0
	return p


## Steps until `done` holds, at most `limit` ticks; returns whether it did.
func _run_until(done: Callable, limit := 600) -> bool:
	for i in limit:
		if done.call():
			return true
		_world.step()
	return done.call()


func _excluded(world: PassengerTestWorld) -> Dictionary:
	var sim := world.sim
	var out := {}
	for cells: Array in sim.layout.lanes.values():
		for cell: Vector2i in cells:
			out[cell] = "lane"
	for cells: Array in sim.layout.passages.values():
		for cell: Vector2i in cells:
			out[cell] = "passage"
	for scanner in sim.layout.scanners:
		out[sim.security.exit_cell(scanner)] = "scanner exit"
	for seat in sim.layout.seats:
		out[seat["front"]] = "seat access"
	for id in world.grid.object_ids():
		out[StaffSpots.spot_of(world.grid, id)] = "staff spot"
		out[world.grid.interaction_cell(id)] = "interaction"
	return out


func test_spots_are_airside_near_the_seats_and_skip_reserved_cells() -> void:
	_world = PassengerTestWorld.reference_world()
	var spots := _world.sim.standing
	spots.rebuild(_world.sim)
	var excluded := _excluded(_world)
	var tiers := [0, 0]
	for id: int in spots.spots:
		var cell := spots.cell_of(id)
		(
			assert_bool(excluded.has(cell))
			. override_failure_message("spot %d on a %s cell %s" % [id, excluded.get(cell), cell])
			. is_false()
		)
		assert_int(cell.y).is_less_equal(ReferenceTerminal.AIRSIDE_MAX_Y)
		assert_bool(_world.grid.is_walkable(cell)).is_true()
		assert_that(_world.grid.world_to_cell(spots.world_of(_world.grid, id))).is_equal(cell)
		tiers[spots.tier_of(id)] += 1
	print("spots near=%d overflow=%d" % tiers)
	assert_int(tiers[StandingSpots.NEAR]).is_greater(20)
	assert_int(tiers[StandingSpots.OVERFLOW]).is_greater(0)
	# The cell beside the left seat rows is gate area; the far corner is not.
	assert_int(spots.tier_of(spots.free_nearest(Vector2i(10, 4))[0])).is_equal(StandingSpots.NEAR)
	assert_that(spots.cell_of(spots.free_nearest(Vector2i(10, 4))[0])).is_equal(Vector2i(10, 4))
	var corner := spots.free_nearest(Vector2i(21, 8))[0]
	assert_that(spots.cell_of(corner)).is_not_equal(Vector2i(21, 8))


func test_spots_are_at_least_a_pitch_apart_and_ids_survive_an_edit() -> void:
	_world = PassengerTestWorld.reference_world()
	var spots := _world.sim.standing
	spots.rebuild(_world.sim)
	var ids: Array = spots.spots.keys()
	var closest := 1.0e9
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			var pa := spots.world_of(_world.grid, ids[a])
			var pb := spots.world_of(_world.grid, ids[b])
			closest = minf(closest, Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z)))
	print("spots=%d closest=%.3f m" % [ids.size(), closest])
	assert_float(closest).is_equal_approx(0.6, 0.001)
	var before := {}
	for id: int in spots.spots:
		before[id] = spots.world_of(_world.grid, id)
	# A landside edit leaves every airside spot with its id and place.
	var desk: int = ReferenceTerminal.object_ids(_world.grid)["desks"][0]
	assert_bool(_world.grid.apply(BuildEdit.remove_object(desk)).ok).is_true()
	assert_bool(spots.stale).is_true()
	spots.rebuild(_world.sim)
	assert_int(spots.spots.size()).is_equal(before.size())
	for id: int in before:
		assert_bool(spots.spots.has(id)).is_true()
		assert_that(spots.world_of(_world.grid, id)).is_equal(before[id])


func test_the_nearest_free_spot_wins_and_ties_go_to_the_lower_id() -> void:
	_world = PassengerTestWorld.reference_world()
	var spots := _world.sim.standing
	spots.rebuild(_world.sim)
	var per_row := StandingSpots.columns(_world.grid.size)
	# Cell (10, 4)'s one lattice point (17, 7) sits on its centre. With it
	# taken, (17, 6) in cell (10, 3) and (17, 8) in cell (10, 5) are both
	# 0.6 m away; the lower id, the row above, comes first.
	var centre := 7 * per_row + 17
	assert_int(spots.free_nearest(Vector2i(10, 4))[0]).is_equal(centre)
	spots.claim(9001, centre)
	var order := spots.free_nearest(Vector2i(10, 4))
	assert_int(order[0]).is_equal(6 * per_row + 17)
	assert_int(order[1]).is_equal(8 * per_row + 17)
	spots.release(9001)
	assert_int(spots.free_nearest(Vector2i(10, 4))[0]).is_equal(centre)


func test_a_seatless_passenger_walks_to_its_spot_and_stands_on_it() -> void:
	_world = _seatless_world()
	var p := _cleared()
	var nearest := _world.sim.standing.free_nearest(SCANNER_EXIT)[0]
	_world.step()
	var spot := _world.sim.standing.spot_of(p.id)
	assert_int(spot).is_equal(nearest)
	assert_bool(p.is_moving()).is_true()
	assert_bool(_run_until(func() -> bool: return p.stage == Passenger.Stage.STANDING)).is_true()
	assert_that(p.at).is_equal(_world.sim.standing.cell_of(spot))
	_world.run_to(_world.clock.tick + PassengerSim.SHUFFLE_TICKS)
	var drawn := _world.sim.world_position(p)
	var point := _world.sim.standing.world_of(_world.grid, spot)
	print("spot %d cell %s drawn %s spot %s" % [spot, p.at, drawn, point])
	assert_float(drawn.distance_to(point)).is_less(0.001)
	assert_int(_world.sim.standing.shortage(_world.sim)).is_equal(0)


func test_a_door_in_the_security_divider_keeps_spots_airside() -> void:
	_world = PassengerTestWorld.reference_world()
	# The divider runs along the north edge of row 9; a door at (15, 9) puts
	# landside (15, 9) two steps from the seat access cell (15, 7).
	var door := BuildEdit.place_wall(
		Vector2i(15, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR
	)
	var placed := _world.grid.apply(door)
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	var spots := _world.sim.standing
	spots.rebuild(_world.sim)
	var landside := 0
	for id: int in spots.spots:
		landside += int(spots.cell_of(id).y > ReferenceTerminal.AIRSIDE_MAX_Y)
	print("spots=%d landside=%d" % [spots.spots.size(), landside])
	assert_int(spots.spots.size()).is_greater(100)
	assert_int(landside).is_equal(0)


## A partition across the airside lounge: this wall row is the north edge of
## row 5, so the gate (and its exit door) is north of it and the concourse
## south of it.
func _partition_with_door(door_x: int) -> void:
	# A door needs a plain wall on each side, so it goes in last.
	var xs := range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1)
	xs.erase(door_x)
	xs.append(door_x)
	for x: int in xs:
		var kind := BuildGrid.WallKind.DOOR if x == door_x else BuildGrid.WallKind.PLAIN
		var placed := _world.grid.apply(
			BuildEdit.place_wall(Vector2i(x, PARTITION_Y), BuildGrid.Side.NORTH, kind)
		)
		assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()


func test_an_internal_airside_door_keeps_spots_on_both_sides() -> void:
	_world = _seatless_world()
	_partition_with_door(15)
	var spots := _world.sim.standing
	spots.rebuild(_world.sim)
	var north := 0
	var south := 0
	var landside := 0
	for id: int in spots.spots:
		var y := spots.cell_of(id).y
		if y > ReferenceTerminal.AIRSIDE_MAX_Y:
			landside += 1
		elif y >= PARTITION_Y:
			south += 1
		else:
			north += 1
	print("north=%d south=%d landside=%d" % [north, south, landside])
	assert_int(north).is_greater(0)
	assert_int(south).is_greater(0)
	assert_int(landside).is_equal(0)


func _landside_spots(spots: StandingSpots) -> int:
	var landside := 0
	for id: int in spots.spots:
		landside += int(spots.cell_of(id).y > ReferenceTerminal.AIRSIDE_MAX_Y)
	return landside


func _place(edit: BuildEdit) -> void:
	var placed := _world.grid.apply(edit)
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()


func _divider_door() -> void:
	_place(
		BuildEdit.place_wall(
			Vector2i(15, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR
		)
	)


func test_a_landside_lobby_behind_an_internal_door_gets_no_spots() -> void:
	_world = PassengerTestWorld.reference_world()
	# A wall across the hall at the north edge of row 14 with a door at x = 12:
	# the lobby north of it (rows 9-13) holds no entrance, and the divider door
	# opens from it onto the airside.
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		if x != 12:
			_place(BuildEdit.place_wall(Vector2i(x, 14), BuildGrid.Side.NORTH))
	_place(BuildEdit.place_wall(Vector2i(12, 14), BuildGrid.Side.NORTH, BuildGrid.WallKind.DOOR))
	_divider_door()
	var spots := _world.sim.standing
	spots.rebuild(_world.sim)
	print("spots=%d landside=%d" % [spots.spots.size(), _landside_spots(spots)])
	assert_int(spots.spots.size()).is_greater(100)
	assert_int(_landside_spots(spots)).is_equal(0)


func test_removing_the_scanners_does_not_open_the_divider_door() -> void:
	_world = PassengerTestWorld.reference_world()
	for id in ReferenceTerminal.object_ids(_world.grid)["scanners"]:
		_place(BuildEdit.remove_object(id))
	# The scanners leave gaps in the divider; wall them so only the door joins.
	for x in ReferenceTerminal.SCANNER_XS:
		_place(BuildEdit.place_wall(Vector2i(x, ReferenceTerminal.DIVIDER_Y), BuildGrid.Side.NORTH))
	_divider_door()
	var spots := _world.sim.standing
	spots.rebuild(_world.sim)
	print("spots=%d landside=%d" % [spots.spots.size(), _landside_spots(spots)])
	assert_int(spots.spots.size()).is_greater(100)
	assert_int(_landside_spots(spots)).is_equal(0)


func test_a_scanner_in_the_open_hall_does_not_open_the_divider_door() -> void:
	_world = PassengerTestWorld.reference_world()
	# A scanner with nothing walled around it: its exit cell is in the same
	# doorless component as the entrance.
	var scanners_before: int = _world.sim.layout.scanners.size()
	_place(BuildEdit.place_object(&"security_scanner", Vector2i(12, 15), 0))
	_divider_door()
	var spots := _world.sim.standing
	spots.rebuild(_world.sim)
	print(
		(
			"scanners=%d spots=%d landside=%d"
			% [_world.sim.layout.scanners.size(), spots.spots.size(), _landside_spots(spots)]
		)
	)
	assert_int(_world.sim.layout.scanners.size()).is_equal(scanners_before + 1)
	assert_int(spots.spots.size()).is_greater(100)
	assert_int(_landside_spots(spots)).is_equal(0)
