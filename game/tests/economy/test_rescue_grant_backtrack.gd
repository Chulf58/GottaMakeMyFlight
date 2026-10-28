class_name TestRescueGrantBacktrack
extends GdUnitTestSuite
## The repair plan backtracks across legs: in a narrow terminal the cheapest
## desk blocks the only corridor to the scanner, so the plan must take a
## dearer desk that leaves the corridor open (ruling going-broke-a-one-off-
## rescue-grant-when-the-airport-is-stuck: a broke airport that can be
## repaired is always helped).
##
## The grid is 4 x 11, y = 0 at the top. The exit is at (1, 0), the scanner
## stands at (1, 2)-(1, 3) with its service cell at (1, 4), and the corridor
## x = 1 runs down to a hall at y 7-10 (floored at x 1 and at (0, 7) and
## (0, 8), bare at x 2-3), with the entrance at (1, 10). Beside the
## corridor, gate seat rows fill x = 0 from y = 0 to 5 and x = 3 from y = 1
## to 6, a seat row fills x = 2 from y = 0 to 2 and two belt pieces fill
## (2, 5) and (2, 6). Staff spots stay free (decision
## staff-spot-design-a-derived-staff-spot-behind-each-desk-and): the officer's
## at (2, 3) with (2, 4) as its way to the corridor, and (0, 6), behind the
## hall's first desk cells. A desk at (0, 7)-(1, 7) costs no floor and blocks
## the corridor, and then no scanner fits in the hall; a desk on the bare cells
## at (2, 8)-(3, 8), its agent on (2, 7), keeps the corridor open.

var _world: PassengerTestWorld
var _grant: RescueGrant


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(Vector2i(4, 11))
	var floored: Array[Vector2i] = [Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 0), Vector2i(2, 0)]
	for y in range(0, 11):
		floored.append(Vector2i(1, y))
	for y in range(1, 7):
		floored.append(Vector2i(0, y))
		floored.append(Vector2i(2, y))
		floored.append(Vector2i(3, y))
	for cell in floored:
		assert_bool(grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)).ok).is_true()
	for anchor in [Vector2i(0, 0), Vector2i(0, 3), Vector2i(2, 0), Vector2i(3, 1), Vector2i(3, 4)]:
		PassengerTestWorld.place(grid, &"seat_row", anchor, 1)
	for cell in [Vector2i(2, 5), Vector2i(2, 6)]:
		PassengerTestWorld.place(grid, &"baggage_belt", cell, 1)
	PassengerTestWorld.place(grid, &"security_scanner", Vector2i(1, 2), 0)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(1, 0), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(1, 10), 2)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)


func after_test() -> void:
	_world.free_all()
	_world = null


func test_the_cheapest_desk_blocking_the_corridor_is_passed_over() -> void:
	var blocking := BuildEdit.place_object(&"checkin_desk", Vector2i(0, 7), 0)
	assert_bool(_world.grid.validate(blocking).ok).is_true()
	assert_bool(_grant.has_working_path()).is_false()
	var plan := _grant.repair_plan()
	print("plan ok %s edits %d" % [plan.ok, plan.edits.size()])
	assert_bool(plan.ok).is_true()
	assert_bool(_grant.evaluate()).is_true()
	print("balance %d" % _world.sim.wallet.balance)
	assert_int(_world.sim.wallet.balance).is_greater(PriceTable.price_of_object(&"checkin_desk"))
	for edit in plan.edits:
		var one: Array[BuildEdit] = [edit]
		assert_bool(BuildTransaction.commit_plan(_world.grid, one, _world.sim.wallet).ok).is_true()
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_bool(_grant.has_working_path()).is_true()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while not p.is_done() and _world.clock.tick < 6000:
		_world.step()
	print("passenger stage %d stuck %d tick %d" % [p.stage, p.stuck, _world.clock.tick])
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


## A desk where the old blocking desk would stand is the second choice here; the
## paid rebuild below is the player's own.
func _rebuild_by_hand() -> void:
	var by_hand: Array[BuildEdit] = [
		BuildEdit.paint_floor(Vector2i(2, 7), BuildGrid.FLOOR_TILE, 1),
		BuildEdit.paint_floor(Vector2i(2, 8), BuildGrid.FLOOR_TILE, 1),
		BuildEdit.paint_floor(Vector2i(3, 8), BuildGrid.FLOOR_TILE, 1),
		BuildEdit.paint_floor(Vector2i(2, 9), BuildGrid.FLOOR_TILE, 1),
		BuildEdit.place_object(&"checkin_desk", Vector2i(2, 8), 0),
	]
	for edit in by_hand:
		var one: Array[BuildEdit] = [edit]
		assert_bool(BuildTransaction.commit_plan(_world.grid, one, _world.sim.wallet).ok).is_true()
	assert_bool(_grant.has_working_path()).is_true()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while not p.is_done() and _world.clock.tick < 6000:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)


## With one choice per leg, the working desk (the second choice) is past the
## cap. Running out of choices is not "cannot be repaired": a grant is paid.
func test_a_working_choice_past_the_per_leg_cap_still_gets_a_grant() -> void:
	RepairPlan.max_tries = 1
	var plan := _grant.repair_plan()
	RepairPlan.max_tries = RepairPlan.MAX_TRIES
	print("plan ok %s fallback %d" % [plan.ok, plan.fallback_price])
	assert_bool(plan.ok).is_false()
	assert_bool(_grant.evaluate()).is_true()
	print("balance %d" % _world.sim.wallet.balance)
	assert_int(_world.sim.wallet.balance).is_greater_equal(475)
	_rebuild_by_hand()


## One attempt in all: the blocking desk is built, the scanner leg fails, and
## no attempt is left to back out of it.
func test_a_plan_that_runs_out_of_attempts_still_gets_a_grant() -> void:
	RepairPlan.max_attempts = 1
	var plan := _grant.repair_plan()
	RepairPlan.max_attempts = RepairPlan.MAX_ATTEMPTS
	print("plan ok %s fallback %d" % [plan.ok, plan.fallback_price])
	assert_bool(plan.ok).is_false()
	assert_bool(_grant.evaluate()).is_true()
	assert_int(_world.sim.wallet.balance).is_greater_equal(475)
	_rebuild_by_hand()
