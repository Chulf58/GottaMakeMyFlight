class_name TestPrizeCarSpend
extends GdUnitTestSuite
## The prize car raises what shop and food visits pay near it (F4-4; decision
## furniture-set-modelled-on-copenhagen-airport-decor-calms-pas, point 2): a
## kiosk or cafe visit that settles with the passenger in reach of a podium pays
## PrizeCar.boosted() of the usual amount, the same visit with no podium, or
## with the podium out of reach, pays the usual amount.

## Extra airside floor east of the kiosk and cafe rooms (x 22-27), where the
## podium stands: 6x3, 3 to 4 cells from the kiosk slots and the cafe seats at
## NEAR_CELL, more than 10 at FAR_CELL.
const EXTENSION := Rect2i(28, 3, 14, 3)
const NEAR_CELL := Vector2i(28, 3)
const FAR_CELL := Vector2i(36, 3)
const NONE := Vector2i(-1, -1)
const START_MOOD := 60
## What the same visit pays at START_MOOD airside, before and after the boost:
## the kiosk 12 x 104% x 125% = 15.6, the cafe 15 x 104% x 125% = 19.5, each
## rounded half up; then x 120%, rounded half up.
const KIOSK_PLAIN := 16
const KIOSK_BOOSTED := 19
const CAFE_PLAIN := 20
const CAFE_BOOSTED := 24

var _world: PassengerTestWorld


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


## The kiosk layout or the cafe layout with the extension floor and a podium at
## `podium` unless it is NONE; the world made over it.
func _make(cafe: bool, podium: Vector2i) -> void:
	_free()
	var grid := BuildGrid.new()
	if cafe:
		CafeTestLayout.build(grid)
	else:
		ShopTestLayout.build(grid)
	var edits: Array[BuildEdit] = []
	for y in range(EXTENSION.position.y, EXTENSION.end.y):
		for x in range(EXTENSION.position.x, EXTENSION.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in grid.apply_batch(edits):
		assert_bool(result.ok).is_true()
	if podium != NONE:
		PassengerTestWorld.place(grid, PrizeCar.PODIUM_ID, podium, 0)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.run_to(10)


## What one bored guest pays for a kiosk browse in a world made by _make(); the
## prize car's distance from the slot goes to `reach`.
func _kiosk_payment(reach: Array[int]) -> int:
	var paid: Array[int] = []
	_world.sim.shops.paid.connect(
		func(_id: int, _room: int, amount: int) -> void: paid.append(amount)
	)
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	p.mood = START_MOOD
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var visit := _world.sim.shops.visit_of(p.id)
	assert_object(visit).is_not_null()
	reach.append(_world.sim.boredom.prize.distance_at(visit.slot["approach"]))
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	assert_int(paid.size()).is_equal(1)
	return paid[0]


## What one hungry guest pays for a cafe visit in a world made by _make(); the
## prize car's distance from the seat goes to `reach`.
func _cafe_payment(reach: Array[int]) -> int:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.cafe_cooldown = 1000000
	p.hunger = 30
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	var visit := _world.sim.cafes.visit_of(p.id)
	var seen := [PrizeCar.NO_REACH - 1]
	while not visit.settled and _world.clock.tick < 3000:
		if p.stage == Passenger.Stage.CAFE_SEATED:
			seen[0] = _world.sim.boredom.prize.distance_at(BoredomSim.watch_cell(p))
			p.mood = START_MOOD
		_world.step()
	assert_bool(visit.settled).is_true()
	reach.append(seen[0])
	return visit.amount


func test_a_kiosk_visit_in_reach_pays_the_boosted_amount() -> void:
	var reach: Array[int] = []
	_make(false, NEAR_CELL)
	var near := _kiosk_payment(reach)
	_make(false, NONE)
	var control := _kiosk_payment(reach)
	print("kiosk: car %d, no car %d, car distances %s" % [near, control, reach])
	assert_int(reach[0]).is_between(1, PrizeCar.SPEND_RADIUS)
	assert_int(reach[1]).is_equal(PrizeCar.NO_REACH)
	assert_int(control).is_equal(KIOSK_PLAIN)
	assert_int(near).is_equal(KIOSK_BOOSTED)
	assert_int(near).is_equal(PrizeCar.boosted(control))


func test_a_kiosk_visit_out_of_reach_pays_the_usual_amount() -> void:
	var reach: Array[int] = []
	_make(false, FAR_CELL)
	var far := _kiosk_payment(reach)
	print("kiosk, car far away: %d, car distances %s" % [far, reach])
	assert_int(reach[0]).is_equal(PrizeCar.NO_REACH)
	assert_int(far).is_equal(KIOSK_PLAIN)


func test_a_cafe_visit_in_reach_pays_the_boosted_amount() -> void:
	var reach: Array[int] = []
	_make(true, NEAR_CELL)
	var near := _cafe_payment(reach)
	_make(true, NONE)
	var control := _cafe_payment(reach)
	print("cafe: car %d, no car %d, car distances %s" % [near, control, reach])
	assert_int(reach[0]).is_between(1, PrizeCar.SPEND_RADIUS)
	assert_int(reach[1]).is_equal(PrizeCar.NO_REACH)
	assert_int(control).is_equal(CAFE_PLAIN)
	assert_int(near).is_equal(CAFE_BOOSTED)
	assert_int(near).is_equal(PrizeCar.boosted(control))


func test_a_cafe_visit_out_of_reach_pays_the_usual_amount() -> void:
	var reach: Array[int] = []
	_make(true, FAR_CELL)
	var far := _cafe_payment(reach)
	print("cafe, car far away: %d, car distances %s" % [far, reach])
	assert_int(reach[0]).is_equal(PrizeCar.NO_REACH)
	assert_int(far).is_equal(CAFE_PLAIN)
