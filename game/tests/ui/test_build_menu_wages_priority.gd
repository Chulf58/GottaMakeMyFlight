class_name TestBuildMenuWagesPriority
extends GdUnitTestSuite
## A rescue grant's message and a wages-paid message share the status line's one
## hold. The rescue message always wins: a wage message never cuts it short, and
## one it cuts short shows once the rescue hold ends. Driven by a real
## Settlement, RescueGrant and stuck terminal, in both signal orders.

var _world: PassengerTestWorld
var _grant: RescueGrant
var _settlement: Settlement
var _port: SubViewport
var _menu: BuildMenu


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000))
	_world.auto_staff = false
	_settlement = auto_free(Settlement.new())
	_settlement.staff = _world.staff
	_settlement.bind(_world.sim, _world.sim.wallet)
	_grant = auto_free(RescueGrant.new())
	_grant.bind(_world.clock, _world.sim, _world.sim.wallet)
	_grant.settlement = _settlement
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_menu = BuildMenu.new()
	_menu.settlement = _settlement
	_menu.rescue_grant = _grant
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()
	_world.free_all()
	_world = null


func _text() -> String:
	return _menu.status_label().text


func _set_tick(tick: int) -> void:
	var data := _world.clock.to_snapshot()
	data["tick"] = str(tick)
	assert_bool(_world.clock.from_snapshot(data)).is_true()


## Two hired agents whose day-0 wages are owed (the wallet is empty at the charge).
func _owe_wages() -> void:
	for i in 2:
		_world.staff.hire(StaffMember.Role.CHECKIN)
	_world.step()
	_set_tick(GameCalendar.day_start(1) - 2)
	_world.step()
	_world.step()
	assert_int(_settlement.wages_owed()).is_equal(120)


func _remove_scanners() -> void:
	var ids := ReferenceTerminal.object_ids(_world.grid)
	for id in ids["scanners"]:
		assert_bool(_world.grid.apply(BuildEdit.remove_object(id)).ok).is_true()


## The rescue credit pays the debt first (wages_paid) and the grant's message
## follows in the same tick: the rescue message shows, the wage one waits.
func test_a_rescue_that_clears_owed_wages_shows_rescue_first_then_wages() -> void:
	_owe_wages()
	_remove_scanners()
	_world.step()
	assert_int(_settlement.wages_owed()).is_equal(0)
	assert_str(_text()).contains("120")
	assert_str(_text()).not_contains("Wages paid")
	_menu.end_grant_hold()
	assert_str(_text()).is_equal("Wages paid: 120")
	_menu.end_grant_hold()
	assert_str(_text()).is_empty()


## A midnight wage payment during the rescue hold leaves the rescue message up.
func test_a_wage_payment_during_a_rescue_hold_waits_for_it() -> void:
	_remove_scanners()
	_world.step()
	var rescue := _text()
	assert_str(rescue).is_not_empty()
	assert_bool(_world.sim.wallet.credit(500, Wallet.Category.OPENING)).is_true()
	_world.staff.hire(StaffMember.Role.CHECKIN)
	_set_tick(GameCalendar.day_start(1) - 2)
	_world.step()
	assert_int(_settlement.wages_paid_today()).is_greater(0)
	assert_str(_text()).is_equal(rescue)
	_menu.end_grant_hold()
	assert_str(_text()).starts_with("Wages paid: ")
	_menu.end_grant_hold()
	assert_str(_text()).is_empty()


## A wage message already up gives way to a rescue message, and is not lost.
func test_a_rescue_cuts_a_wage_message_short_and_the_wage_one_follows() -> void:
	assert_bool(_world.sim.wallet.credit(500, Wallet.Category.OPENING)).is_true()
	_world.staff.hire(StaffMember.Role.CHECKIN)
	_world.step()
	_set_tick(GameCalendar.day_start(1) - 2)
	_world.step()
	var wage := _text()
	assert_str(wage).starts_with("Wages paid: ")
	_menu._on_granted(50, "Rescue grant")
	assert_str(_text()).is_equal("Rescue grant")
	_menu.end_grant_hold()
	assert_str(_text()).is_equal(wage)
	_menu.end_grant_hold()
	assert_str(_text()).is_empty()


## While a rescue message holds, only the latest waiting wage message is kept.
func test_only_the_latest_waiting_wage_message_is_kept() -> void:
	_menu._on_granted(50, "Rescue grant")
	_menu._on_wages_paid(60, 0)
	_menu._on_wages_paid(10, 5)
	assert_str(_text()).is_equal("Rescue grant")
	_menu.end_grant_hold()
	assert_str(_text()).is_equal("Wages paid: 10 (5 owed)")
	_menu.end_grant_hold()
	assert_str(_text()).is_empty()
