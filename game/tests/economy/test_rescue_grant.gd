class_name TestRescueGrant
extends GdUnitTestSuite
## The rescue grant (ruling going-broke-a-one-off-rescue-grant-when-the-airport-
## is-stuck): when a new passenger has no working path (entrance, check-in
## desk, scanner, exit), money cannot pay for the repair and no passenger can
## still make a flight, the airport authority pays just the shortfall, once per
## stuck event, and says so. It is checked on the sim tick, never from a
## BuildGrid signal. Route, floor and rebuild cases are in
## test_rescue_grant_repair.gd, real journeys in test_rescue_grant_passengers.gd.

var _world: PassengerTestWorld
var _grant: RescueGrant
var _ids: Dictionary
## [amount, message] per `granted`.
var _granted: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_ids = ReferenceTerminal.object_ids(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	_grant.granted.connect(_on_granted)


func after_test() -> void:
	_granted.clear()
	_world.free_all()
	_world = null


func _on_granted(amount: int, text: String) -> void:
	_granted.append([amount, text])


func _remove_all(kinds: Array[String]) -> void:
	for kind in kinds:
		for id in _ids[kind]:
			assert_bool(_world.grid.apply(BuildEdit.remove_object(id)).ok).is_true()


func _cost(defs: Array[StringName]) -> int:
	var total := 0
	for def in defs:
		total += PriceTable.price_of_object(def)
	return total


## Puts one scanner back, from the reference terminal's own edits.
func _rebuild_a_scanner() -> void:
	for edit in ReferenceTerminal.edits():
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT and edit.def_id == &"security_scanner":
			assert_bool(_world.grid.apply(edit).ok).is_true()
			return


func test_nothing_is_paid_while_every_essential_stands() -> void:
	assert_bool(_grant.has_working_path()).is_true()
	assert_bool(_grant.evaluate()).is_false()
	_world.run_to(40)
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_array(_granted).is_empty()


func test_no_grant_while_money_can_rebuild_the_missing_piece() -> void:
	_remove_all(["scanners"])
	var price := PriceTable.price_of_object(&"security_scanner")
	_world.sim.wallet.credit(price)
	assert_bool(_grant.has_working_path()).is_false()
	assert_bool(_grant.evaluate()).is_false()
	assert_int(_world.sim.wallet.balance).is_equal(price)
	assert_array(_granted).is_empty()


func test_stuck_airport_gets_exactly_the_shortfall() -> void:
	_remove_all(["scanners", "exits"])
	var cost := _cost([&"security_scanner", &"exit_door"])
	_world.sim.wallet.credit(100)
	assert_bool(_grant.evaluate()).is_true()
	print("balance %d cost %d grants %s" % [_world.sim.wallet.balance, cost, _granted])
	assert_int(_world.sim.wallet.balance).is_equal(cost)
	assert_int(BuildTransaction.needed(_world.grid, _grant.repair_plan().edits)).is_equal(cost)
	assert_int(_granted.size()).is_equal(1)
	assert_int(_granted[0][0]).is_equal(cost - 100)
	assert_str(_granted[0][1]).contains(str(cost - 100))
	assert_str(_granted[0][1]).contains("scanner")
	assert_str(_granted[0][1]).contains("exit")


func test_one_grant_per_stuck_event() -> void:
	_remove_all(["scanners"])
	assert_bool(_grant.evaluate()).is_true()
	assert_bool(_world.sim.wallet.spend(_world.sim.wallet.balance)).is_true()
	assert_bool(_grant.evaluate()).is_false()
	_world.run_to(40)
	assert_int(_granted.size()).is_equal(1)
	assert_int(_world.sim.wallet.balance).is_equal(0)


func test_rebuilding_the_essentials_ends_the_event_so_a_new_one_is_granted() -> void:
	_remove_all(["scanners"])
	assert_bool(_grant.evaluate()).is_true()
	_world.sim.wallet.spend(_world.sim.wallet.balance)
	_rebuild_a_scanner()
	assert_bool(_grant.has_working_path()).is_true()
	assert_bool(_grant.evaluate()).is_false()
	_remove_all(["desks"])
	assert_bool(_grant.evaluate()).is_true()
	assert_int(_granted.size()).is_equal(2)


func test_a_finished_passenger_does_not_count_as_able_to_make_a_flight() -> void:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.stage = Passenger.Stage.MISSED
	_remove_all(["scanners"])
	assert_bool(_grant.evaluate()).is_true()


func test_a_grid_edit_pays_nothing_until_the_next_tick() -> void:
	_remove_all(["scanners"])
	assert_int(_world.sim.wallet.balance).is_equal(0)
	assert_array(_granted).is_empty()
	_world.step()
	assert_array(_granted).has_size(1)
	assert_int(_world.sim.wallet.balance).is_equal(PriceTable.price_of_object(&"security_scanner"))


func test_binding_again_does_not_double_the_tick_check() -> void:
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	_remove_all(["scanners"])
	_world.step()
	assert_array(_granted).has_size(1)


func test_the_event_latch_survives_a_save_round_trip() -> void:
	_remove_all(["scanners"])
	assert_bool(_grant.evaluate()).is_true()
	_world.sim.wallet.spend(_world.sim.wallet.balance)
	var data := JSON.parse_string(JSON.stringify(_grant.to_snapshot())) as Dictionary
	var loaded: RescueGrant = auto_free(RescueGrant.new())
	loaded.bind(_world.clock, _world.sim, _world.sim.wallet)
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_bool(loaded.evaluate()).is_false()
	assert_int(_world.sim.wallet.balance).is_equal(0)


func test_a_malformed_snapshot_is_refused_and_changes_nothing() -> void:
	assert_bool(_grant.from_snapshot({})).is_false()
	assert_bool(_grant.from_snapshot({"granted": "yes"})).is_false()
	assert_bool(_grant.from_snapshot({"granted": true, "extra": 1})).is_false()
	_remove_all(["scanners"])
	assert_bool(_grant.evaluate()).is_true()
