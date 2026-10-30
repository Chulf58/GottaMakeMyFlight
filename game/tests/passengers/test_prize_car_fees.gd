class_name TestPrizeCarFees
extends GdUnitTestSuite
## The prize car boosts purchases, not fees (F4-4): a nap pod's, a shower's
## and an exchange's fee are paid in full whether a podium stands in reach
## or not, where a pharmacy visit beside the same podium is boosted.

## A podium over the bottom half of the airside room (x 22-27, y 3-8), 2 cells
## from the first slot at (22, 4).
const PODIUM_CELL := Vector2i(22, 6)
const MOOD := 50

var _world: PassengerTestWorld
var _paid: Array[int] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null
	_paid.clear()


func _make(grid: BuildGrid) -> void:
	PassengerTestWorld.place(grid, PrizeCar.PODIUM_ID, PODIUM_CELL, 0)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.sim.shops.paid.connect(
		func(_id: int, _room: int, amount: int) -> void: _paid.append(amount)
	)
	_world.run_to(10)


## Runs a bored guest's visit to its end and returns what it paid; the guest's
## slot must be in the podium's reach.
func _bored_visit() -> int:
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	p.mood = MOOD
	NeedsPolicy.arbitrate(_world.sim, p)
	var visit := _world.sim.shops.visit_of(p.id)
	assert_object(visit).is_not_null()
	assert_int(_world.sim.boredom.prize.distance_at(visit.slot["approach"])).is_equal(2)
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	assert_int(_paid.size()).is_equal(1)
	return _paid[0]


func test_a_nap_pod_fee_is_not_boosted() -> void:
	var grid := BuildGrid.new()
	ActivityTestLayout.build(grid, &"nap_pod")
	_make(grid)
	var paid := _bored_visit()
	print("nap pod beside a podium paid %d, fee %d" % [paid, PriceTable.NAP_POD_FEE])
	assert_int(paid).is_equal(ShopSim.spend(PriceTable.NAP_POD_FEE, MOOD, true))


func test_a_shower_fee_is_not_boosted() -> void:
	var grid := BuildGrid.new()
	ActivityTestLayout.build(grid, &"shower")
	_make(grid)
	var paid := _bored_visit()
	print("shower beside a podium paid %d, fee %d" % [paid, PriceTable.SHOWER_FEE])
	assert_int(paid).is_equal(ShopSim.spend(PriceTable.SHOWER_FEE, MOOD, true))


func test_a_pharmacy_visit_beside_the_same_podium_is_boosted() -> void:
	var grid := BuildGrid.new()
	StoreTestLayout.build(grid, &"pharmacy", ["air"], 1)
	_make(grid)
	var paid := _bored_visit()
	var base := RoomTypes.get_type(&"pharmacy").base_spend
	print("pharmacy beside a podium paid %d, base %d" % [paid, base])
	assert_int(paid).is_equal(PrizeCar.boosted(ShopSim.spend(base, MOOD, true)))


func test_an_exchange_fee_is_not_boosted() -> void:
	var grid := BuildGrid.new()
	MoneyTestLayout.build(grid, &"exchange")
	_make(grid)
	# A spare-time browser walking east past the room, not bored.
	var p := ShopTestLayout.airside_guest(_world, 40, Vector2i(19, 5))
	p.mood = MOOD
	p.set_path(_world.grid.find_path(p.at, Vector2i(21, 5)))
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.SHOP_BROWSE)
	var visit := _world.sim.shops.visit_of(p.id)
	assert_object(visit).is_not_null()
	assert_int(_world.sim.boredom.prize.distance_at(visit.slot["approach"])).is_equal(2)
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	var fee := RoomTypes.get_type(&"exchange").base_spend
	print("exchange beside a podium paid %s, fee %d" % [_paid, fee])
	assert_array(_paid).is_equal([ShopSim.spend(fee, MOOD, true)])
