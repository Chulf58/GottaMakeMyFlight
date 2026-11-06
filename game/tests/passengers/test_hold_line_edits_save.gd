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
	# A hall three cells wide (x 1 to 3; x 3 is the staff's way round the desk):
	# the line runs straight down x = 1. Walls under (1, 11) and (2, 11) and east
	# of (2, 11) end it there after one step across: 6 + 5 cells.
	var grid := BuildGrid.new(Vector2i(5, 25))
	var edits: Array[BuildEdit] = []
	for y in 25:
		for x in [1, 2, 3]:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(3, 24), 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	_world.sim.set_meta(&"desk", desk)
	assert_int(_world.sim.layout.line_of(desk).size()).is_equal(18)
	var members: Array[Passenger] = []
	for i in 14:
		members.append(HoldLineKit.member(_world, desk))
	for wall in [
		[Vector2i(1, 11), Vector2i(0, 1)],
		[Vector2i(2, 11), Vector2i(0, 1)],
		[Vector2i(2, 11), Vector2i(1, 0)]
	]:
		var side := BuildGrid.SIDE_STEP.find(wall[1])
		assert_bool(grid.apply(BuildEdit.place_wall(wall[0], side)).ok).is_true()
	_world.step()
	var line: Array = _world.sim.layout.line_of(desk)
	assert_int(line.size()).is_equal(11)
	var queued := _world.sim.queue_of(desk) + _world.sim.holding_of(desk)
	assert_array(queued).is_equal(members.slice(0, 11).map(func(p: Passenger) -> int: return p.id))
	for p in members.slice(11):
		assert_int(p.station).is_equal(0)
		assert_int(p.stage).is_equal(Passenger.Stage.TO_CHECKIN)
	_check_placed(members)


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
