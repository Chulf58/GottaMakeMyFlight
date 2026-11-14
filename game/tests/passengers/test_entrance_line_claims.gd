extends GdUnitTestSuite
## The claims of the line outside the entrance (EntranceLine, board 66be00a0
## fix round 2): only check-in places a walk from the door reaches admit
## anyone, each claim holds a place on one desk, the line's own NO_ROUTE marks
## come off and go back on as the entrance moves, admitted walkers bound for a
## door that went are sent back, and a save in the middle of an admission
## plays on the same.

## The split hall's second entrance, on the walled desk's side.
const FAR_DOOR := Vector2i(14, 0)

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


## A hall split by a wall: desk "reach" on the entrance's side with
## `free_on_reach` places left on its line, and desk "walled" behind the wall
## with its whole line free, open and usable but out of reach of the entrance
## (its staff come in by a second entrance on its side, which the line, kept
## at the first entrance, does not use).
static func _split_hall(free_on_reach: int) -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(16, 22))
	for y in 22:
		grid.apply(BuildEdit.place_wall(Vector2i(8, y), BuildGrid.Side.WEST))
	var reach := PassengerTestWorld.place(grid, &"checkin_desk", HoldLineKit.DESK_AT, 0)
	var walled := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(12, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", HoldLineKit.HALL_DOOR, 2)
	PassengerTestWorld.place(grid, &"entrance_door", FAR_DOOR, 0)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	world.sim.set_meta(&"reach", reach)
	world.sim.set_meta(&"walled", walled)
	for i in world.sim.layout.line_of(reach).size() - free_on_reach:
		HoldLineKit.member(world, reach)
	world.step()
	return world


## Moves the world's entrance to (6, 21), as TestEntranceLine does; the
## desks' staff reach rule is off for the edit.
## In the split hall (`far`) the second entrance is taken down and put back
## after it, so the moved one stays the first (the line's).
static func _move_entrance(world: PassengerTestWorld, far := false) -> void:
	var doors := world.sim.layout.passenger_entrances.duplicate()
	if not far:
		doors.resize(1)
	world.grid.check_staff_reach = false
	for door in doors:
		for edit in DoorPlacement.edits_for(world.grid, BuildEdit.remove_object(door)):
			assert(world.grid.apply(edit).ok, "removing an entrance was refused")
	world.grid.check_staff_reach = true
	PassengerTestWorld.place(world.grid, &"entrance_door", Vector2i(6, 21), 2)
	if far:
		PassengerTestWorld.place(world.grid, &"entrance_door", FAR_DOOR, 0)


static func _inside_looking(world: PassengerTestWorld) -> int:
	var count := 0
	for id in world.sim.passenger_ids():
		if world.passenger(id).stage == Passenger.Stage.TO_CHECKIN:
			count += 1
	return count


func test_one_reachable_place_admits_one_however_many_places_are_out_of_reach() -> void:
	_world = _split_hall(1)
	var sim := _world.sim
	var reach: int = sim.get_meta(&"reach")
	var walled: int = sim.get_meta(&"walled")
	var walled_free := sim.layout.line_of(walled).size() - PassengerStations.slot(sim, walled)
	var ids := TestEntranceLine._arrive(_world, 5)
	prints(
		"admitted",
		sim.entrance.claims,
		sim.entrance.stations,
		"waiting",
		sim.entrance.order,
		"walled free",
		walled_free
	)
	# Control: the walled desk is open and usable, with room for every arrival.
	assert_bool(sim._is_open(walled) and sim.layout.is_usable(walled)).is_true()
	assert_int(walled_free).is_greater(ids.size())
	assert_array(sim.entrance.claims).is_equal([ids[0]])
	assert_int(int(sim.entrance.stations[ids[0]])).is_equal(reach)
	assert_array(sim.entrance.order).is_equal(ids.slice(1))
	var head := _world.passenger(ids[0])
	for i in 400:
		if head.stage == Passenger.Stage.CHECKIN_QUEUE:
			break
		_world.step()
	var door := TestEntranceLine._door(_world)
	var on_door := 0
	for id in sim.passenger_ids():
		var p := _world.passenger(id)
		if p.stage != Passenger.Stage.SPAWNED and p.at == door:
			on_door += 1
	prints(
		"after",
		sim.tick,
		"head",
		head.stage,
		head.station,
		"waiting",
		sim.entrance.order,
		"inside looking",
		_inside_looking(_world),
		"on the door cell",
		on_door
	)
	assert_int(head.stage).is_equal(Passenger.Stage.CHECKIN_QUEUE)
	assert_int(head.station).is_equal(reach)
	assert_int(_inside_looking(_world)).is_equal(0)
	assert_int(on_door).is_equal(0)
	assert_array(sim.entrance.claims).is_empty()
	assert_array(sim.entrance.order).is_equal(ids.slice(1))
	for id in ids.slice(1):
		assert_int(_world.passenger(id).stage).is_equal(Passenger.Stage.SPAWNED)


func test_a_seeker_inside_never_takes_the_place_a_claim_holds_on_its_desk() -> void:
	_world = _split_hall(1)
	var sim := _world.sim
	var reach: int = sim.get_meta(&"reach")
	var claimant := TestEntranceLine._arrive(_world, 1)[0]
	assert_int(int(sim.entrance.stations[claimant])).is_equal(reach)
	# A passenger inside turns to check-in: the one reachable place is held.
	var seeker := HoldLineKit.passenger(_world, Vector2i(4, 12), Passenger.Stage.TO_CHECKIN)
	sim.entrance.forget(seeker.id)
	PassengerStations.choose(sim, seeker)
	prints(
		"seeker",
		seeker.station,
		seeker.stuck,
		"claims on reach",
		sim.entrance.claims_on(sim, reach)
	)
	assert_int(sim.entrance.claims_on(sim, reach)).is_equal(1)
	assert_int(seeker.station).is_equal(0)
	assert_int(seeker.stuck).is_equal(Passenger.Stuck.QUEUE_FULL)


func test_moving_the_entrance_while_the_line_is_no_route_walks_each_to_its_new_place() -> void:
	_world = _split_hall(0)
	var sim := _world.sim
	var ids := TestEntranceLine._arrive(_world, 4)
	for i in 30:
		_world.step()
	var walled: int = sim.get_meta(&"walled")
	assert_bool(sim._is_open(walled)).is_true()
	for id in ids:
		assert_int(_world.passenger(id).stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_array(sim.entrance.marked.keys()).contains_exactly_in_any_order(ids)
	var before := sim.entrance.places.duplicate()
	_move_entrance(_world, true)
	for i in 60:
		_world.step()
	assert_bool(sim._is_open(walled)).is_true()
	prints("places", before[0], "->", sim.entrance.places[0], "order", sim.entrance.order)
	assert_bool(sim.entrance.places[0].is_equal_approx(before[0])).is_false()
	assert_array(sim.entrance.order).is_equal(ids)
	for index in ids.size():
		var p := _world.passenger(ids[index])
		prints("member", p.id, "ends at", p.apron.back(), "place", sim.entrance.places[index])
		assert_bool(p.apron.back().is_equal_approx(sim.entrance.places[index])).is_true()
		assert_int(p.apron_mm).is_equal(p.apron_total_mm())
		# Still out of reach from the new door: marked again on its new place.
		assert_int(p.stuck).is_equal(Passenger.Stuck.NO_ROUTE)
	assert_array(sim.entrance.marked.keys()).contains_exactly_in_any_order(ids)


func test_moving_the_entrance_mid_admission_sends_no_walker_to_the_old_door() -> void:
	_world = TestEntranceLine._full_hall()
	var sim := _world.sim
	var ids := TestEntranceLine._arrive(_world, 3)
	for i in 5:
		_world.step()
	var added := PassengerTestWorld.place(_world.grid, &"checkin_desk", Vector2i(7, 1), 0)
	_world.step()
	_world.step()
	assert_array(sim.entrance.claims).is_equal(ids)
	var old_door := TestEntranceLine._door(_world)
	_move_entrance(_world)
	_world.step()
	var new_door := TestEntranceLine._door(_world)
	prints(
		"door", old_door, "->", new_door, "claims", sim.entrance.claims, "line", sim.entrance.order
	)
	assert_bool(new_door == old_door).is_false()
	for id in ids:
		var p := _world.passenger(id)
		assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
		(
			assert_bool(p.at == new_door)
			. override_failure_message("%d bound for %s" % [id, p.at])
			. is_true()
		)
	for i in 1500:
		if sim.queue_of(added).has(ids[2]):
			break
		_world.step()
	var entered: Array[int] = []
	for id in ids:
		assert_int(_world.passenger(id).station).is_equal(added)
		entered.append(sim.queue_of(added).find(id))
	prints("places in the new desk's lane", entered)
	assert_array(entered).is_equal([0, 1, 2])


func test_a_save_in_the_middle_of_an_admission_plays_on_the_same() -> void:
	_world = TestEntranceLine._full_hall()
	var sim := _world.sim
	var ids := TestEntranceLine._arrive(_world, 4)
	for i in 5:
		_world.step()
	var added := PassengerTestWorld.place(_world.grid, &"checkin_desk", Vector2i(7, 1), 0)
	_world.step()
	_world.step()
	assert_int(sim.entrance.claims.size()).is_greater(1)
	var data := sim.to_snapshot()
	prints("saved line", data["entrance_line"])
	assert_array(data["entrance_line"]["stations"]).is_not_empty()
	_other = HoldLineKit.desk_hall()
	var again := PassengerTestWorld.place(_other.grid, &"checkin_desk", Vector2i(7, 1), 0)
	assert_int(again).is_equal(added)
	_other.clock.tick = _world.clock.tick
	assert_bool(_other.sim.from_snapshot(data)).is_true()
	assert_array(_other.sim.entrance.claims).is_equal(sim.entrance.claims)
	assert_dict(_other.sim.entrance.stations).is_equal(sim.entrance.stations)
	var moved := 0
	for i in 600:
		_world.step()
		_other.step()
		assert_str(_other.signature()).is_equal(_world.signature())
		moved = 0
		for id in ids:
			moved += int(_world.passenger(id).station == added)
		if moved == ids.size():
			break
	prints("at the new desk after", sim.tick, moved)
	assert_int(moved).is_equal(ids.size())
	var bad := data.duplicate(true)
	bad["entrance_line"]["stations"] = []
	assert_bool(HoldLineKit.desk_hall().sim.from_snapshot(bad)).is_false()
