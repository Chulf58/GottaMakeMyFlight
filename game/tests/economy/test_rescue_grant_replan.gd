class_name TestRescueGrantReplan
extends GdUnitTestSuite
## A repair plan takes about a second on the airport site, so the rescue
## grant keeps them out of the sim ticks (RescueGrant.prepare(), REPLAN_TICKS):
## a new game (RescueGrant._ready()) works the plan out before the first tick,
## in the real scene too, and a burst
## of paid build edits while the wallet is below the kept bound costs one plan
## per REPLAN_TICKS, not one per edit.

const SITE := preload("res://build/terminal_site.tres")
## Paid edits in the burst, one tick apart.
const BURST := 10

var _world: PassengerTestWorld
var _grant: RescueGrant
var _granted: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.sim.site = SITE
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	# As RescueGrant._ready() does for a new game, outside any tick.
	_grant.prepare()
	_grant.granted.connect(func(amount: int, _text: String) -> void: _granted.append(amount))


func after_test() -> void:
	_granted.clear()
	_world.free_all()
	_world = null


func test_preparing_a_new_game_plans_before_the_first_tick_and_no_tick_plans() -> void:
	var at_bind := _grant.plans_made
	(
		assert_bool(_world.sim.wallet.credit(PriceTable.STARTING_BUDGET, Wallet.Category.OPENING))
		. is_true()
	)
	_world.run_to(50)
	print(
		"plans at prepare %d, after %d ticks %d" % [at_bind, _world.clock.tick, _grant.plans_made]
	)
	assert_int(at_bind).is_equal(1)
	assert_int(_grant.plans_made).is_equal(at_bind)
	assert_array(_granted).is_empty()


## The real scene: the empty plot's plan is made while main.tscn enters the
## tree, and the new game's first ticks make none.
func test_the_main_scene_plans_before_its_first_tick() -> void:
	var main := SaveTestKit.boot(self, 5)
	var grant: RescueGrant = main.get_node("RescueGrant")
	var at_boot := grant.plans_made
	for i in 20:
		SaveTestKit.step(main)
	print("main scene: plans at boot %d, after 20 ticks %d" % [at_boot, grant.plans_made])
	assert_int(at_boot).is_equal(1)
	assert_int(grant.plans_made).is_equal(at_boot)
	main.free()


func test_a_burst_of_paid_edits_below_the_bound_plans_once_per_window() -> void:
	var plan := _grant.repair_plan()
	assert_bool(plan.ok).is_true()
	var price := RepairPlan.least_balance(_world.grid, plan.edits)
	var wallet := _world.sim.wallet
	assert_bool(wallet.credit(price, Wallet.Category.OPENING)).is_true()
	var before_burst := _grant.plans_made
	for i in BURST:
		var edit: BuildEdit = plan.edits[i]
		var bought := BuildTransaction.commit_plan(_world.grid, [edit] as Array[BuildEdit], wallet)
		assert_bool(bought.ok).override_failure_message("edit %d" % i).is_true()
		_world.step()
	var in_burst := _grant.plans_made - before_burst
	print(
		(
			"burst of %d paid edits over %d ticks: %d plans, balance %d of %d"
			% [BURST, BURST, in_burst, wallet.balance, price]
		)
	)
	# The first tick below the bound plans; the rest of the window waits.
	assert_int(in_burst).is_equal(1)
	assert_array(_granted).is_empty()
	# Control: once the window has passed, one more edit is planned for again.
	var edit: BuildEdit = plan.edits[BURST]
	var more := BuildTransaction.commit_plan(_world.grid, [edit] as Array[BuildEdit], wallet)
	assert_bool(more.ok).is_true()
	_world.run_to(_world.clock.tick + RescueGrant.REPLAN_TICKS)
	print("after the window: %d plans" % (_grant.plans_made - before_burst))
	assert_int(_grant.plans_made - before_burst).is_equal(2)
