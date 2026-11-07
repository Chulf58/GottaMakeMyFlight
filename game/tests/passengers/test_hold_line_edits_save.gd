class_name TestHoldLineEditsSave
extends GdUnitTestSuite
## A build edit that reroutes or shortens a hold line re-places the queue on
## the new line with no two members on one cell, and sends back the members
## the shorter line has no place for; a save taken with holders on the line
## plays on exactly.

var _world: PassengerTestWorld
var _other: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_world, _other]:
		if world != null:
			world.free_all()
	_world = null
	_other = null


## The desk hall with `count` members standing on their places.
func _queued(count: int) -> Array[Passenger]:
	_world = HoldLineKit.desk_hall()
	var desk: int = _world.sim.get_meta(&"desk")
	var members: Array[Passenger] = []
	for i in count:
		members.append(HoldLineKit.member(_world, desk))
	return members


## Walls on `sides` of hold cell (4, 11), each a BuildGrid.SIDE_STEP step.
func _wall(sides: Array[Vector2i]) -> void:
	for step in sides:
		var side := BuildGrid.SIDE_STEP.find(step)
		var result := _world.grid.apply(BuildEdit.place_wall(Vector2i(4, 11), side))
		assert_bool(result.ok).is_true()


## Every member of the desk on line[index], and no two standing passengers
## of `members` on one cell.
func _check_placed(members: Array[Passenger]) -> void:
	var desk: int = _world.sim.get_meta(&"desk")
	assert_bool(HoldLineKit.run_until_settled(_world, desk)).is_true()
	var ids: Array = members.map(func(p: Passenger) -> int: return p.id)
	var got: Array = HoldLineKit.standing_cells(_world, ids)
	print("line %s, standing cells %s" % [_world.sim.layout.line_of(desk), got[0]])
	assert_int(got[1]).is_equal(0)


func test_an_edit_that_reroutes_the_hold_line_re_places_its_holders() -> void:
	var members := _queued(14)
	var desk: int = _world.sim.get_meta(&"desk")
	var before: Array = _world.sim.layout.line_of(desk).duplicate()
	_wall([Vector2i(0, 1)])
	_world.step()
	var line: Array = _world.sim.layout.line_of(desk)
	assert_that(line[11]).is_not_equal(before[11])
	assert_int(line.size()).is_equal(before.size())
	_check_placed(members)
	assert_int((_world.sim.queue_of(desk) + _world.sim.holding_of(desk)).size()).is_equal(14)
	assert_that(members[13].at).is_equal(line[13])


func test_an_edit_that_shortens_the_hold_line_sends_back_the_members_past_its_end() -> void:
	var grid := _narrow_hall()
	var desk := _desk_of(grid)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	_world.sim.set_meta(&"desk", desk)
	assert_int(_world.sim.layout.line_of(desk).size()).is_equal(18)
	var members: Array[Passenger] = []
	for i in 14:
		members.append(HoldLineKit.member(_world, desk))
	_shorten(grid)
	_world.step()
	var line: Array = _world.sim.layout.line_of(desk)
	assert_int(line.size()).is_equal(11)
	var queued := _world.sim.queue_of(desk) + _world.sim.holding_of(desk)
	assert_array(queued).is_equal(members.slice(0, 11).map(func(p: Passenger) -> int: return p.id))
	for p in members.slice(11):
		assert_int(p.station).is_equal(0)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	_check_placed(members)


## A hall three cells wide (x 1 to 3; x 3 is the staff's way round the desk)
## whose desk (_desk_of()) has its line straight down x = 1, 18 cells.
## _shorten() ends it at (2, 11): 6 + 5 cells.
static func _narrow_hall() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(5, 25))
	var edits: Array[BuildEdit] = []
	for y in 25:
		for x in [1, 2, 3]:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(3, 24), 2)
	return grid


static func _desk_of(grid: BuildGrid) -> int:
	for id in grid.object_ids():
		if StringName(grid.get_object(id)["def"]) == &"checkin_desk":
			return id
	return 0


## Walls under (1, 11) and (2, 11) and east of (2, 11).
static func _shorten(grid: BuildGrid) -> void:
	var walls := [
		[Vector2i(1, 11), Vector2i(0, 1)],
		[Vector2i(2, 11), Vector2i(0, 1)],
		[Vector2i(2, 11), Vector2i(1, 0)],
	]
	for wall: Array in walls:
		var side := BuildGrid.SIDE_STEP.find(wall[1])
		assert(grid.apply(BuildEdit.place_wall(wall[0], side)).ok)


func test_a_walker_heading_for_a_cell_an_edit_takes_off_the_line_heads_on() -> void:
	_queued(10)
	var desk: int = _world.sim.get_meta(&"desk")
	var w := HoldLineKit.passenger(_world, Vector2i(8, 14), Passenger.Stage.TO_CHECKIN)
	_world.step()
	var old_cell: Vector2i = _world.sim.layout.line_of(desk)[10]
	assert_that(w.path_end()).is_equal(old_cell)
	_wall([Vector2i(0, 1)])
	var on_old := 0
	for i in 200:
		_world.step()
		on_old += int(w.at == old_cell)
		if HoldLineKit.settled(_world, desk) and w.stage == Passenger.Stage.CHECKIN_QUEUE:
			break
	var line: Array = _world.sim.layout.line_of(desk)
	var seen := [old_cell, line[10], w.at, on_old]
	print("old cell %s, new line[10] %s, walker at %s, on the old cell %d ticks" % seen)
	assert_bool(line.has(old_cell)).is_false()
	assert_int(on_old).is_equal(0)
	assert_int(w.stage).is_equal(Passenger.Stage.CHECKIN_QUEUE)
	assert_that(w.at).is_equal(line[10])


func test_a_save_loaded_on_a_shorter_line_fits_the_queue_to_it() -> void:
	_world = PassengerTestWorld.make(_narrow_hall(), PassengerTestWorld.starts_with(4000, 5000))
	var desk := _desk_of(_world.grid)
	var members: Array[Passenger] = []
	for i in 14:
		members.append(HoldLineKit.member(_world, desk))
	_world.step()
	var data := _world.sim.to_snapshot()
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(_world.grid.to_snapshot())).is_true()
	_shorten(grid)
	_other = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	assert_bool(_other.clock.from_snapshot(_world.clock.to_snapshot())).is_true()
	assert_bool(_other.sim.from_snapshot(data)).is_true()
	var line: Array = _other.sim.layout.line_of(desk)
	var queued := _other.sim.queue_of(desk) + _other.sim.holding_of(desk)
	assert_int(line.size()).is_equal(11)
	assert_array(queued).is_equal(members.slice(0, 11).map(func(p: Passenger) -> int: return p.id))
	for p in members.slice(11):
		var loaded := _other.passenger(p.id)
		assert_int(loaded.station).is_equal(0)
		assert_int(loaded.stage).is_equal(Passenger.Stage.TO_CHECKIN)


func test_a_save_with_holders_on_the_line_plays_on_exactly() -> void:
	var members := _queued(10)
	members[0].service_end = _world.sim.tick + 40
	for i in 3:
		HoldLineKit.passenger(_world, Vector2i(8, 18), Passenger.Stage.TO_CHECKIN, 1)
	_world.run_to(_world.clock.tick + 25)
	var desk: int = _world.sim.get_meta(&"desk")
	assert_int(_world.sim.holding_of(desk).size()).is_greater(3)
	var data := {
		"clock": _world.clock.to_snapshot(),
		"flights": _world.flights.to_snapshot(),
		"grid": _world.grid.to_snapshot(),
		"passengers": _world.sim.to_snapshot(),
	}
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	_other = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(_other.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(_other.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(_other.sim.from_snapshot(data["passengers"])).is_true()
	var moves := 0
	for i in 300:
		_world.step()
		_other.step()
		assert_str(_other.signature()).is_equal(_world.signature())
		for id in _world.sim.holding_of(desk):
			moves += int(_world.passenger(id).is_moving())
	print("holder moving frames %d" % moves)
	assert_int(moves).is_greater(0)


## A save taken on the tick before several waiting passengers are given places
## at once (decision hold-line-rebuild-the-security-line-follows-where-people-
## sta: free places by waiting age, the line's order by where people stand)
## plays on exactly: the loaded sim gives the same places in the same order.
func test_a_save_before_a_simultaneous_release_plays_on_exactly() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(3000))
	var sim := _world.sim
	var ids: Array[int] = []
	for i in 32:
		var p := _world.passenger(sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.hunger = 0
		p.cafe_cooldown = 1000000
		p.stage = Passenger.Stage.TO_SECURITY
		p.at = Vector2i(16, 12)
		p.clear_path()
		ids.append(p.id)
	var data := {}
	var released := 0
	for i in 2000:
		var waiting: Array[int] = []
		for id in ids:
			var p := sim.get_passenger(id)
			if p != null and p.station == 0 and p.stage == Passenger.Stage.TO_SECURITY:
				waiting.append(id)
		var open := sim.layout.scanners.all(sim._is_open)
		data = {
			"clock": _world.clock.to_snapshot(),
			"flights": _world.flights.to_snapshot(),
			"grid": _world.grid.to_snapshot(),
			"passengers": sim.to_snapshot(),
		}
		_world.step()
		released = 0
		for id in waiting:
			released += int(sim.get_passenger(id).station != 0)
		if open and released >= 2:
			break
	print("released %d at once on tick %d" % [released, sim.tick])
	assert_int(released).is_greater_equal(2)
	var loaded := BuildGrid.new()
	assert_bool(loaded.from_snapshot(data["grid"])).is_true()
	_other = PassengerTestWorld.make(loaded, FlightSim.schedule_starts(3000), 99)
	assert_bool(_other.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(_other.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(_other.sim.from_snapshot(data["passengers"])).is_true()
	_other.step()
	assert_str(_other.signature()).is_equal(_world.signature())
	for i in 300:
		_world.step()
		_other.step()
		assert_str(_other.signature()).is_equal(_world.signature())


## A save whose tail claims are not valid (a list for the station -> id map) is
## refused before anything is installed: the populated sim, its standing
## spots, gate places, boarding files, queues and claims included, is left
## exactly as it was.
func test_a_save_with_bad_claims_is_refused_and_changes_nothing() -> void:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(3000))
	var sim := _world.sim
	for i in 32:
		var p := _world.passenger(sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.hunger = 0
		p.cafe_cooldown = 1000000
		p.stage = Passenger.Stage.TO_SECURITY
		p.at = Vector2i(16, 12)
		p.clear_path()
	_world.run_to(_world.clock.tick + 150)
	assert_bool(sim._claims.is_empty()).is_false()
	var data := sim.to_snapshot()
	# A save from another moment, so a partial install would show.
	_world.run_to(_world.clock.tick + 40)
	var before := JSON.stringify(sim.to_snapshot())
	data["claims"] = []
	assert_bool(sim.from_snapshot(data)).is_false()
	assert_str(JSON.stringify(sim.to_snapshot())).is_equal(before)
