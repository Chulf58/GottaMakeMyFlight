class_name TestMoneyVisits
extends GdUnitTestSuite
## Visits to the currency exchange and the ATM (F4-5b; decision currency-
## exchange-and-atm-visits-front-cell-slot-small-fee-no-boredom): a passenger
## with spare time walking past drops in at the cell in front of the counter or
## ATM, pays the room type's small fee nudged by mood with the airside bonus, and
## keeps its boredom (relieves_boredom false), where a pharmacy visit resets it.
## A bored passenger never plans one: it does not cure boredom. An exchange with
## no server at its counter is closed; the ATM is self-service and works with no
## staff at all.

const MONEY_TYPES: Array[StringName] = [&"exchange", &"atm"]
## ShopSim.store_name() of a visit to each.
const STORE_NAMES := {&"exchange": "exchange", &"atm": "ATM"}
## Below BoredomSim.BORED_AT, so the walker is a spare-time browser, and above 0,
## so a reset shows.
const START_BOREDOM := 40
## Free airside floor west of the east wall's openings, and where the walker
## heads: east along the airside floor, past the room's door.
const WALK_FROM := Vector2i(19, 5)
const WALK_TO := Vector2i(21, 5)

var _world: PassengerTestWorld
var _ids: Dictionary
## [passenger id, room id, amount, boredom when paid] per paid signal.
var _paid: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_free()


func _free() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_paid.clear()


func _money_world(type: StringName, staffed := true) -> void:
	var grid := BuildGrid.new()
	_ids = MoneyTestLayout.build(grid, type)
	_make(grid, staffed)


func _pharmacy_world() -> void:
	var grid := BuildGrid.new()
	_ids = StoreTestLayout.build(grid, &"pharmacy")
	_make(grid, true)


func _make(grid: BuildGrid, staffed: bool) -> void:
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	if not staffed:
		_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	var world := _world
	var paid := _paid
	_world.sim.shops.paid.connect(
		func(id: int, room: int, amount: int) -> void:
			paid.append([id, room, amount, world.passenger(id).boredom])
	)
	# Staff come on duty on the first ticks.
	_world.run_to(10)


## A calm cleared passenger walking east past the room, `boredom` bored.
func _walker(boredom := START_BOREDOM) -> Passenger:
	var p := ShopTestLayout.airside_guest(_world, boredom, WALK_FROM)
	p.set_path(_world.grid.find_path(p.at, WALK_TO))
	assert_bool(p.is_moving()).is_true()
	return p


func _run_while_visiting(p: Passenger, limit := 3000) -> void:
	var until := _world.clock.tick + limit
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < until:
		_world.step()


func test_a_spare_time_visit_pays_the_fee_and_keeps_boredom_where_a_pharmacy_resets_it() -> void:
	for type in MONEY_TYPES:
		_money_world(type)
		var p := _walker()
		p.mood = 70
		assert_bool(_world.sim.shops.wants_relief(p)).is_false()
		assert_bool(_world.sim.shops.wants_browse(p)).override_failure_message(str(type)).is_true()
		var balance := _world.sim.wallet.balance
		assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.SHOP_BROWSE)
		var visit := _world.sim.shops.visit_of(p.id)
		assert_object(visit).override_failure_message(str(type)).is_not_null()
		assert_int(visit.room).is_equal(_ids["air_room"])
		assert_int(visit.display).is_equal(_ids["air_pieces"][0])
		# The follow line names it in running text, keeping ATM in capitals.
		assert_str(_world.sim.shops.store_name(p.id)).is_equal(STORE_NAMES[type])
		var base := RoomTypes.get_type(type).base_spend
		var expected := ShopSim.spend(base, p.mood, true)
		_run_while_visiting(p)
		print("%s: base %d, paid %s, boredom now %d" % [type, base, _paid, p.boredom])
		assert_int(_paid.size()).override_failure_message(str(type)).is_equal(1)
		assert_array(_paid[0].slice(0, 3)).is_equal([p.id, _ids["air_room"], expected])
		assert_int(_world.sim.wallet.balance - balance).is_equal(expected)
		# Not reset: boredom is where it was (or has risen), never 0.
		assert_int(_paid[0][3]).override_failure_message(str(type)).is_greater_equal(START_BOREDOM)
		assert_int(p.boredom).is_greater_equal(START_BOREDOM)
		_free()
	# Control: the same walk to a pharmacy resets boredom when it pays.
	_pharmacy_world()
	var shopper := _walker()
	assert_int(NeedsPolicy.arbitrate(_world.sim, shopper)).is_equal(NeedsPolicy.Need.SHOP_BROWSE)
	assert_str(_world.sim.shops.store_name(shopper.id)).is_equal("pharmacy")
	_run_while_visiting(shopper)
	print("pharmacy control: paid %s, boredom now %d" % [_paid, shopper.boredom])
	assert_int(_paid.size()).is_equal(1)
	assert_int(_paid[0][3]).is_equal(0)
	assert_int(shopper.boredom).is_equal(0)


func test_a_bored_passenger_never_plans_an_exchange_or_atm_visit() -> void:
	for type in MONEY_TYPES:
		_money_world(type)
		var bored := _walker(BoredomSim.MAX)
		assert_bool(_world.sim.shops.wants_relief(bored)).is_true()
		assert_bool(_world.sim.shops.wants_browse(bored)).is_false()
		var relief := _world.sim.shops.plan_visit(bored)
		# Control: the room is open and its slot free; only boredom keeps it out.
		var browse := _world.sim.shops.plan_visit(bored, true)
		print("%s bored: relief plan %s, browse plan room %s" % [type, relief, browse.get("slot")])
		assert_bool(relief.is_empty()).override_failure_message(str(type)).is_true()
		assert_bool(browse.is_empty()).override_failure_message(str(type)).is_false()
		NeedsPolicy.arbitrate(_world.sim, bored)
		assert_object(_world.sim.shops.visit_of(bored.id)).is_null()
		# The same walk with spare time and no boredom does plan one.
		var calm := _walker(0)
		(
			assert_bool(_world.sim.shops.wants_browse(calm))
			. override_failure_message(str(type))
			. is_true()
		)
		assert_int(NeedsPolicy.arbitrate(_world.sim, calm)).is_equal(NeedsPolicy.Need.SHOP_BROWSE)
		assert_int(_world.sim.shops.visit_of(calm.id).room).is_equal(_ids["air_room"])
		_free()


func test_an_unstaffed_exchange_is_closed_until_a_server_comes() -> void:
	_money_world(&"exchange", false)
	var counter: int = _ids["air_pieces"][0]
	var p := _walker()
	assert_bool(ShopCounters.room_open(_world.sim, _ids["air_room"])).is_false()
	assert_array(ShopCounters.closed(_world.sim)).contains([counter])
	assert_bool(_world.sim.shops.wants_browse(p)).is_false()
	assert_bool(_world.sim.shops.plan_visit(p, true).is_empty()).is_true()
	NeedsPolicy.arbitrate(_world.sim, p)
	assert_object(_world.sim.shops.visit_of(p.id)).is_null()
	StaffTestKit.seat_server(_world.staff, counter)
	assert_bool(ShopCounters.room_open(_world.sim, _ids["air_room"])).is_true()
	var plan := _world.sim.shops.plan_visit(p, true)
	assert_bool(plan.is_empty()).is_false()
	assert_int(plan["slot"]["room"]).is_equal(_ids["air_room"])


func test_the_atm_works_with_no_staff() -> void:
	_money_world(&"atm", false)
	var p := _walker()
	assert_array(ShopCounters.closed(_world.sim)).is_empty()
	assert_array(_world.staff.stations_of(StaffMember.Role.SHOP)).is_empty()
	assert_bool(ShopCounters.room_open(_world.sim, _ids["air_room"])).is_true()
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.SHOP_BROWSE)
	_run_while_visiting(p)
	print("unstaffed atm: paid %s" % [_paid])
	assert_int(_paid.size()).is_equal(1)
	assert_int(_paid[0][1]).is_equal(_ids["air_room"])
