class_name TestRescueGrantDivider
extends GdUnitTestSuite
## The repair plan keeps the security divider whatever the walk across it
## looks like today (ruling rescue-grant-repair-price-never-removes-the-
## security-divider-other-walls-may-come-down-when-cheaper): a door wall in the
## divider (decision a-door-wall-in-the-security-divider-is-allowed-security-
## is-e), the open gap a removed scanner leaves, and an exit on the landside
## edge. In each case the landside floor is cut back to row 9 (along the
## divider) and a corridor at x = 18, so a desk airside would cost no floor
## and a landside one does.

var _world: PassengerTestWorld
var _grant: RescueGrant
var _granted: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	_grant.granted.connect(func(amount: int, text: String) -> void: _granted.append([amount, text]))


func after_test() -> void:
	RepairPlan.max_candidates = RepairPlan.MAX_CANDIDATES
	_granted.clear()
	_world.free_all()
	_world = null


func _remove_all(def_id: StringName, only_x := -1) -> void:
	for id in _world.grid.object_ids():
		var record := _world.grid.get_object(id)
		if record["def"] == def_id and (only_x < 0 or record["anchor"].x == only_x):
			assert_bool(_world.grid.apply(BuildEdit.remove_object(id)).ok).is_true()


## Removes the desks and every free landside floor cell below row 9 off the
## x = 18 corridor.
func _cut_landside() -> void:
	_remove_all(&"checkin_desk")
	for y in range(ReferenceTerminal.DIVIDER_Y + 1, ReferenceTerminal.FLOOR_MAX.y):
		for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
			if x != ReferenceTerminal.ENTRANCE_CELL.x:
				_world.grid.apply(BuildEdit.remove_floor(Vector2i(x, y)))


## The grant is paid, the new desk stands landside on bought floor, no
## divider wall comes down, and a passenger flies after the paid rebuild.
func _assert_landside_repair() -> void:
	assert_bool(_grant.evaluate()).is_true()
	var plan := _grant.repair_plan()
	var floors := 0
	var desk_y := -1
	for edit in plan.edits:
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			floors += 1
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT and edit.def_id == &"checkin_desk":
			desk_y = edit.cell.y
		var divider := edit.cell.y == ReferenceTerminal.DIVIDER_Y and edit.side == 0
		assert_bool(edit.kind == BuildEdit.Kind.REMOVE_WALL and divider).is_false()
	print("grant %s floors %d desk row %d" % [_granted, floors, desk_y])
	assert_int(desk_y).is_greater_equal(ReferenceTerminal.DIVIDER_Y)
	assert_int(floors).is_greater(0)
	for edit in plan.edits:
		var one: Array[BuildEdit] = [edit]
		assert_bool(BuildTransaction.commit_plan(_world.grid, one, _world.sim.wallet).ok).is_true()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while not p.is_done() and _world.clock.tick < 6000:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


## With the candidate cap lifted, so the search surely reaches the door.
func test_a_door_in_the_divider_does_not_open_airside_to_a_desk() -> void:
	RepairPlan.max_candidates = 100000
	var door := BuildEdit.place_wall(Vector2i(15, ReferenceTerminal.DIVIDER_Y), 0, 3)
	assert_bool(_world.grid.apply(door).ok).is_true()
	_cut_landside()
	_assert_landside_repair()


func test_the_gap_of_a_removed_scanner_does_not_open_airside_to_a_desk() -> void:
	_remove_all(&"security_scanner", ReferenceTerminal.SCANNER_XS[0])
	_cut_landside()
	_assert_landside_repair()


func test_an_exit_on_the_landside_edge_does_not_open_airside_to_a_desk() -> void:
	var exit := BuildEdit.place_object(&"exit_door", Vector2i(10, 17), 3)
	assert_bool(DoorPlacement.check(_world.grid, exit).ok).is_true()
	for step in DoorPlacement.edits_for(_world.grid, exit):
		assert_bool(_world.grid.apply(step).ok).is_true()
	_cut_landside()
	_assert_landside_repair()
