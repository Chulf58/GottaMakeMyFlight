class_name TestRescueGrantNewGame
extends GdUnitTestSuite
## A new game starts on the empty terminal shell with the starting budget
## (smoke playtest 5). The budget buys a working path, so the airport is not
## stuck and no grant is paid (ruling going-broke-a-one-off-rescue-grant-when-
## the-airport-is-stuck). The control: the same empty shell with almost no
## money is stuck and is paid the repair's shortfall. The repair plan for the
## empty shell is made once in before().

const SHELL := "res://build/toon_terminal_shell.tres"

var _shell: ShellDefinition
var _plan: RepairPlan
## What the plan's repair needs in the wallet (least_balance), or -1.
var _price := -1
var _world: PassengerTestWorld
var _grant: RescueGrant
## [amount, message] per `granted`.
var _granted: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self
	_shell = load(SHELL)
	var grid := BuildGrid.new(_shell.grid_size, _shell.grid_origin)
	_plan = RepairPlan.make(grid, _shell)
	if _plan.ok:
		_price = RepairPlan.least_balance(grid, _plan.edits)


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(_shell.grid_size, _shell.grid_origin)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.sim.shell = _shell
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	_grant.granted.connect(_on_granted)


func after_test() -> void:
	_granted.clear()
	_world.free_all()
	_world = null


func _on_granted(amount: int, text: String) -> void:
	_granted.append([amount, text])


## The plan finds a real repair on bare ground, within its caps, and the
## starting budget pays for it.
func test_the_empty_shell_has_a_repair_the_starting_budget_pays_for() -> void:
	prints("plan ok", _plan.ok, "price", _price, "fallback", _plan.fallback_price)
	assert_bool(_plan.ok).is_true()
	assert_int(_plan.edits.size()).is_greater(0)
	assert_int(_price).is_between(1, PriceTable.STARTING_BUDGET)


func test_a_new_game_with_the_starting_budget_gets_no_grant() -> void:
	var wallet := _world.sim.wallet
	assert_bool(wallet.credit(PriceTable.STARTING_BUDGET, Wallet.Category.OPENING)).is_true()
	assert_bool(_grant.has_working_path()).is_false()
	_world.run_to(3)
	prints("balance", _world.sim.wallet.balance, "granted", _granted)
	assert_array(_granted).is_empty()
	assert_int(_world.sim.wallet.balance).is_equal(PriceTable.STARTING_BUDGET)


## Control: an empty shell the wallet cannot build is stuck and gets the
## shortfall once, the message naming the pieces to build. The money is just
## enough: buying the repair edit by edit through paid build transactions
## goes through, spends the wallet to exactly 0 and leaves a working path.
func test_an_empty_shell_with_no_money_gets_the_shortfall() -> void:
	var wallet := _world.sim.wallet
	assert_bool(wallet.credit(100, Wallet.Category.OPENING)).is_true()
	_world.run_to(3)
	prints("granted", _granted, "balance", wallet.balance)
	assert_int(_granted.size()).is_equal(1)
	assert_int(_granted[0][0]).is_greater(0)
	assert_str(_granted[0][1]).contains("entrance, check-in desk, security scanner, exit")
	var grid := _world.grid
	var edits := _grant.repair_plan().edits.duplicate()
	for edit: BuildEdit in edits:
		var result := BuildTransaction.commit_plan(grid, [edit] as Array[BuildEdit], wallet)
		var why := "buying %s at %s refused: %d" % [edit.kind, edit.cell, result.reason]
		assert_bool(result.ok).override_failure_message(why).is_true()
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	prints("left", wallet.balance)
	assert_int(wallet.balance).is_equal(0)
	assert_bool(RepairPlan.has_working_path(grid, layout)).is_true()
