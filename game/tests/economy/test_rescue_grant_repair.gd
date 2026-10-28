class_name TestRescueGrantRepair
extends GdUnitTestSuite
## The rescue grant judges the route, not the object count, and pays for the
## whole repair: missing pieces, the floor they stand on and the floor that
## joins them up (ruling going-broke-a-one-off-rescue-grant-when-the-airport-
## is-stuck). Each rebuild here is done with real paid build edits
## (BuildTransaction.commit_plan) from the granted money alone, and a passenger
## then makes the flight.

## A row of the reference terminal's landside hall between the entrance and
## the desks; nothing stands or is reserved on it.
const GAP_Y := 14

var _world: PassengerTestWorld
var _grant: RescueGrant
var _ids: Dictionary
var _granted: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_ids = ReferenceTerminal.object_ids(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	_grant.granted.connect(func(amount: int, text: String) -> void: _granted.append([amount, text]))


func after_test() -> void:
	_granted.clear()
	_world.free_all()
	_world = null


func _remove_all(kinds: Array[String]) -> void:
	for kind in kinds:
		for id in _ids[kind]:
			assert_bool(_world.grid.apply(BuildEdit.remove_object(id)).ok).is_true()


## Takes the floor off every free cell of row GAP_Y, cutting the entrance off
## from the desks. Returns how many cells lost their floor.
func _cut_the_hall() -> int:
	_old_save_rules()
	var cut := 0
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		if _world.grid.apply(BuildEdit.remove_floor(Vector2i(x, GAP_Y))).ok:
			cut += 1
	_today_s_rules()
	return cut


## The stuck terminals here cut the staff spots off from the entrance, which a
## player edit can no longer do (decision
## desk-belts-run-one-row-back-desk-then-the-agent-row-then-the, v3) but a
## save from before that rule can hold. Between these two calls the grid takes
## edits past the staff reach rule, as such a save was built.
func _old_save_rules() -> void:
	_world.grid.check_staff_reach = false


func _today_s_rules() -> void:
	_world.grid.check_staff_reach = true


## Commits each edit as its own paid player action, as clicks would.
func _rebuild(edits: Array[BuildEdit]) -> void:
	for edit in edits:
		var one: Array[BuildEdit] = [edit]
		var result := BuildTransaction.commit_plan(_world.grid, one, _world.sim.wallet)
		(
			assert_bool(result.ok)
			. override_failure_message(
				"rebuild edit %d at %s refused: %s" % [edit.kind, edit.cell, result.reason_text()]
			)
			. is_true()
		)


## Spawns a passenger and runs until it settles; true when it made the flight.
func _a_passenger_makes_the_flight() -> bool:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while not p.is_done() and _world.clock.tick < 6000:
		_world.step()
	print("passenger %d stage %d stuck %d tick %d" % [p.id, p.stage, p.stuck, _world.clock.tick])
	return p.stage == Passenger.Stage.MADE


func test_every_piece_standing_but_no_route_is_stuck() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	assert_int(_cut_the_hall()).is_greater(0)
	assert_bool(_grant.has_working_path()).is_false()
	print("passenger stage %d at %s" % [p.stage, p.at])
	assert_bool(_grant.evaluate()).is_true()
	print("grants %s" % [_granted])
	assert_int(_granted[0][0]).is_equal(PriceTable.price_of_floor())
	assert_str(_granted[0][1]).contains("floor")


func test_a_wall_across_the_route_is_not_stuck_because_removing_it_is_free() -> void:
	_old_save_rules()
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		var edit := BuildEdit.place_wall(Vector2i(x, GAP_Y), BuildGrid.Side.NORTH)
		assert_bool(_world.grid.apply(edit).ok).is_true()
	_today_s_rules()
	assert_bool(_grant.has_working_path()).is_false()
	var edits := _grant.repair_plan().edits
	assert_int(BuildTransaction.needed(_world.grid, edits)).is_equal(0)
	assert_bool(_grant.evaluate()).is_false()
	assert_array(_granted).is_empty()
	_rebuild(edits)
	assert_bool(_grant.has_working_path()).is_true()


## The rebuild here is the player's own, written out by hand (the floor gap
## and a desk where the old one stood), so it does not lean on the plan.
func test_the_grant_pays_for_the_floor_as_well_as_the_missing_desk() -> void:
	_cut_the_hall()
	_remove_all(["desks"])
	assert_bool(_grant.evaluate()).is_true()
	var expected := PriceTable.price_of_object(&"checkin_desk") + PriceTable.price_of_floor()
	print("grants %s expected %d" % [_granted, expected])
	assert_int(_world.sim.wallet.balance).is_equal(expected)
	var by_hand: Array[BuildEdit] = [
		BuildEdit.paint_floor(Vector2i(12, GAP_Y), BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE),
		BuildEdit.place_object(&"checkin_desk", Vector2i(11, 11), 0),
	]
	_rebuild(by_hand)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_bool(_grant.has_working_path()).is_true()
	assert_bool(_a_passenger_makes_the_flight()).is_true()


func test_a_terminal_missing_every_essential_is_rebuilt_from_the_grant_alone() -> void:
	_remove_all(["desks", "scanners", "entrances", "exits"])
	assert_bool(_grant.evaluate()).is_true()
	var plan := _grant.repair_plan()
	var cost := BuildTransaction.needed(_world.grid, plan.edits)
	var objects := 0
	for def in [&"entrance_door", &"checkin_desk", &"security_scanner", &"exit_door"]:
		objects += PriceTable.price_of_object(def)
	print("grant %s cost %d objects %d edits %d" % [_granted, cost, objects, plan.edits.size()])
	assert_int(cost).is_greater_equal(objects)
	assert_int(_world.sim.wallet.balance).is_equal(cost)
	_rebuild(plan.edits)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_bool(_grant.has_working_path()).is_true()
	assert_bool(_a_passenger_makes_the_flight()).is_true()


## No floor is left but the walk a passenger takes (entrance to scanner, and
## scanner to exit), so a new desk needs floor to stand on or to be walked to.
func test_a_missing_desk_with_no_floor_to_stand_on_is_granted_its_floor() -> void:
	var grid := _world.grid
	var layout := _world.sim.layout
	var walk := {}
	var door := layout.door_cell(grid, layout.entrances[0])
	for scanner in layout.scanners:
		var passage: Array = layout.passages[scanner]
		for cell in grid.find_path(door, layout.lanes[scanner][0]):
			walk[cell] = true
		for cell in grid.find_path(passage.back(), layout.door_cell(grid, layout.exits[0])):
			walk[cell] = true
	_remove_all(["desks"])
	for y in grid.size.y:
		for x in grid.size.x:
			if not walk.has(Vector2i(x, y)) and grid.floor_at(Vector2i(x, y)) != 0:
				grid.apply(BuildEdit.remove_floor(Vector2i(x, y)))
	assert_bool(_grant.evaluate()).is_true()
	var plan := _grant.repair_plan()
	var floors := 0
	for edit in plan.edits:
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			floors += 1
	print("grant %s floors %d" % [_granted, floors])
	assert_int(floors).is_greater(0)
	var desk := PriceTable.price_of_object(&"checkin_desk")
	assert_int(_granted[0][0]).is_equal(desk + floors * PriceTable.price_of_floor())
	_rebuild(plan.edits)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_bool(_grant.has_working_path()).is_true()
	assert_bool(_a_passenger_makes_the_flight()).is_true()


## The price of the last plan is kept as a bound while the wallet covers it,
## and each edit since raises the bound by the most it can add to a repair.
func test_no_new_plan_while_the_wallet_covers_the_bound_and_a_raised_one_is_caught() -> void:
	var wallet := _world.sim.wallet
	wallet.credit(5000, Wallet.Category.FEES)
	_remove_all(["scanners"])
	assert_bool(_grant.evaluate()).is_false()
	assert_object(_grant._plan).is_not_null()
	assert_int(_grant._bound).is_equal(PriceTable.price_of_object(&"security_scanner"))
	var cut := _cut_the_hall()
	assert_bool(_grant.evaluate()).is_false()
	print("cut %d bound %d plan %s" % [cut, _grant._bound, _grant._plan])
	assert_object(_grant._plan).is_null()
	assert_int(_grant._bound).is_equal(900 + cut * PriceTable.price_of_floor())
	assert_bool(wallet.spend(wallet.balance - 1000, Wallet.Category.BUILD)).is_true()
	assert_bool(_grant.evaluate()).is_false()
	assert_int(_grant._bound).is_equal(925)
	_remove_all(["exits"])
	assert_bool(_grant.evaluate()).is_true()
	print("grants %s" % [_granted])
	var price := RepairPlan.least_balance(_world.grid, _grant.repair_plan().edits)
	assert_int(price).is_greater_equal(925 + PriceTable.price_of_object(&"exit_door"))
	assert_int(_granted[0][0]).is_equal(price - 1000)


## Ruling rescue-grant-repair-price-never-removes-the-security-divider-other-
## walls-may-come-down-when-cheaper: no landside floor is left but a corridor
## at x = 18, and airside has free floor behind the divider. The new desk goes
## landside on paid floor, never airside through the divider.
func test_a_new_desk_never_goes_airside_through_the_security_divider() -> void:
	_remove_all(["desks"])
	_old_save_rules()
	for y in range(ReferenceTerminal.DIVIDER_Y, ReferenceTerminal.FLOOR_MAX.y):
		for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
			if x != ReferenceTerminal.ENTRANCE_CELL.x:
				_world.grid.apply(BuildEdit.remove_floor(Vector2i(x, y)))
	_today_s_rules()
	assert_bool(_grant.evaluate()).is_true()
	var floors := 0
	var desk_y := -1
	for edit in _grant.repair_plan().edits:
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			floors += 1
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT and edit.def_id == &"checkin_desk":
			desk_y = edit.cell.y
		if edit.kind == BuildEdit.Kind.REMOVE_WALL:
			assert_bool(edit.cell.y == ReferenceTerminal.DIVIDER_Y and edit.side == 0).is_false()
	print("grant %s floors %d desk row %d" % [_granted, floors, desk_y])
	assert_int(desk_y).is_greater_equal(ReferenceTerminal.DIVIDER_Y)
	assert_int(floors).is_greater(0)
	var desk := PriceTable.price_of_object(&"checkin_desk")
	assert_int(_granted[0][0]).is_equal(desk + floors * PriceTable.price_of_floor())
	_rebuild(_grant.repair_plan().edits)
	assert_bool(_a_passenger_makes_the_flight()).is_true()


## A paid wall across the route and a floor gap: taking the wall down refunds
## half its price before the floor is bought, so the grant is only the rest.
func test_a_refund_earned_early_in_the_repair_lowers_the_grant() -> void:
	var wallet := _world.sim.wallet
	var walls: Array[BuildEdit] = []
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		walls.append(BuildEdit.place_wall(Vector2i(x, 16), BuildGrid.Side.NORTH))
	wallet.credit(BuildTransaction.needed(_world.grid, walls), Wallet.Category.FEES)
	_old_save_rules()
	for result in BuildTransaction.commit_batch(_world.grid, walls, wallet):
		assert_bool(result.ok).is_true()
	_today_s_rules()
	assert_int(wallet.balance).is_equal(0)
	_cut_the_hall()
	var refund := PriceTable.refund_of(PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN))
	var expected := PriceTable.price_of_floor() - refund
	assert_bool(_grant.evaluate()).is_true()
	print("grants %s expected %d" % [_granted, expected])
	assert_int(_granted[0][0]).is_equal(expected)
	_rebuild(_grant.repair_plan().edits)
	assert_int(wallet.balance).is_equal(0)
	assert_bool(_grant.has_working_path()).is_true()
