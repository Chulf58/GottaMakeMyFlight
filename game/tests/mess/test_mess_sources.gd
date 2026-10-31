class_name TestMessSources
extends GdUnitTestSuite
## Real visits count their uses and make the messes (decision mess-sim-
## technical-design-messsim-under-passengersim-counters-refuse-at-cap, point
## 2): a settled cafe visit counts its seat, a paid kiosk browse its display
## slot, a toilet use its room once and a visit given up on the way nothing,
## and a shower its room by room type. Each source's counter is set one short
## of its Nth use first, so the one real visit here makes the mess.

var _world: PassengerTestWorld
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func _messes() -> MessSim:
	return _world.sim.messes


## The one mess there is, checked to be of `kind` at `cell`.
func _assert_one_mess(kind: MessSim.Kind, cell: Vector2i) -> void:
	var ids := _messes().mess_ids()
	assert_int(ids.size()).is_equal(1)
	if ids.size() != 1:
		return
	var mess := _messes().get_mess(ids[0])
	assert_int(mess["kind"]).is_equal(kind)
	assert_that(mess["cell"]).is_equal(cell)


func _shop_world(grid: BuildGrid) -> void:
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.run_to(10)


func _run_while_shopping(p: Passenger) -> void:
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()


func test_a_settled_cafe_visit_counts_its_seat_and_the_nth_leaves_litter_there() -> void:
	var grid := BuildGrid.new()
	_ids = CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	var cafes := _world.sim.cafes
	cafes.refresh()
	var seats: Array = []
	for cafe in cafes.layout.cafes:
		for seat: Dictionary in cafe["seats"]:
			seats.append(MessSim.seat_source(seat["key"]))
	assert_bool(MessTestKit.set_uses(_world, seats, MessSim.CAFE_EVERY - 1)).is_true()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.hunger = 0
	p.cafe_cooldown = 1000000
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	assert_bool(cafes.try_visit(p)).is_true()
	var visit := cafes.visit_of(p.id)
	var source := MessSim.seat_source(visit.seat_key)
	var before := _messes().mess_count()
	while cafes.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	print(
		(
			"seat %s: settled %s, uses %d, messes %d -> %d"
			% [
				visit.seat_key,
				visit.settled,
				_messes().uses_of(source),
				before,
				_messes().mess_count()
			]
		)
	)
	assert_bool(visit.settled).is_true()
	assert_int(before).is_equal(0)
	assert_int(_messes().uses_of(source)).is_equal(MessSim.CAFE_EVERY)
	_assert_one_mess(MessSim.Kind.LITTER, visit.seat["approach"])


func test_a_paid_kiosk_browse_counts_its_slot_and_the_nth_leaves_litter_there() -> void:
	var grid := BuildGrid.new()
	_ids = ShopTestLayout.build(grid)
	_shop_world(grid)
	_world.sim.shops.refresh()
	var slots: Array = []
	for shop in _world.sim.shops.layout.shops:
		for slot: Dictionary in shop["slots"]:
			slots.append(MessSim.slot_source(slot["key"]))
	assert_bool(MessTestKit.set_uses(_world, slots, MessSim.KIOSK_EVERY - 1)).is_true()
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	var visit := _world.sim.shops.visit_of(p.id)
	var source := MessSim.slot_source(visit.slot_key())
	_run_while_shopping(p)
	print(
		(
			"slot %s: boredom %d, uses %d, messes %d"
			% [visit.slot_key(), p.boredom, _messes().uses_of(source), _messes().mess_count()]
		)
	)
	assert_int(p.boredom).is_equal(0)
	assert_int(_messes().uses_of(source)).is_equal(MessSim.KIOSK_EVERY)
	_assert_one_mess(MessSim.Kind.LITTER, visit.slot["approach"])


## A toilet world with every room's counter one short; returns a landside
## passenger with a high need, its visit committed.
func _toilet_visit() -> Passenger:
	var grid := BuildGrid.new()
	_ids = ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	var rooms := [MessSim.toilet_source(_ids["air_room"]), MessSim.toilet_source(_ids["land_room"])]
	assert_bool(MessTestKit.set_uses(_world, rooms, MessSim.TOILET_EVERY - 1)).is_true()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.stage_tick = _world.clock.tick
	p.at = Vector2i(20, 14)
	p.clear_path()
	p.toilet_need = 90
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	return p


func test_a_toilet_use_counts_its_room_once_and_the_nth_leaves_a_toilet_mess() -> void:
	var p := _toilet_visit()
	var visit := _world.sim.toilets.visit_of(p.id)
	var source := MessSim.toilet_source(visit.room)
	var approach: Vector2i = visit.stall["approach"]
	var used := false
	while _world.sim.toilets.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
		used = used or p.stage == Passenger.Stage.TOILET_USE
	print(
		(
			"room %d: used %s, need %d, uses %d, messes %d"
			% [visit.room, used, p.toilet_need, _messes().uses_of(source), _messes().mess_count()]
		)
	)
	assert_bool(used).is_true()
	assert_int(p.toilet_need).is_less(ToiletSim.NEED_AT)
	assert_int(_messes().uses_of(source)).is_equal(MessSim.TOILET_EVERY)
	_assert_one_mess(MessSim.Kind.TOILET, approach)


func test_a_toilet_visit_given_up_on_the_way_counts_nothing() -> void:
	var p := _toilet_visit()
	var visit := _world.sim.toilets.visit_of(p.id)
	var source := MessSim.toilet_source(visit.room)
	_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TOILET_WALK)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(visit.stall_id)).ok).is_true()
	while _world.sim.toilets.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	print(
		(
			"visit ended at stage %s, need %d, uses %d, messes %d"
			% [
				Passenger.Stage.keys()[p.stage],
				p.toilet_need,
				_messes().uses_of(source),
				_messes().mess_count()
			]
		)
	)
	assert_int(p.toilet_need).is_greater(0)
	assert_int(_messes().uses_of(source)).is_equal(MessSim.TOILET_EVERY - 1)
	assert_int(_messes().mess_count()).is_equal(0)


func test_a_shower_counts_its_room_by_room_type_and_a_nap_pod_counts_nothing() -> void:
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, &"shower")
	_shop_world(grid)
	var room := MessSim.shower_source(_ids["room"])
	assert_bool(MessTestKit.set_uses(_world, [room], MessSim.SHOWER_EVERY - 1)).is_true()
	var p := ShopTestLayout.airside_guest(_world, 80)
	NeedsPolicy.arbitrate(_world.sim, p)
	var visit := _world.sim.shops.visit_of(p.id)
	assert_object(visit).is_not_null()
	_run_while_shopping(p)
	var sources := _messes().sources()
	print(
		(
			"shower: boredom %d, sources %s, uses %d, messes %d"
			% [p.boredom, sources, _messes().uses_of(room), _messes().mess_count()]
		)
	)
	assert_int(p.boredom).is_equal(0)
	assert_array(sources).is_equal([room])
	assert_int(_messes().uses_of(room)).is_equal(MessSim.SHOWER_EVERY)
	_assert_one_mess(MessSim.Kind.SPILL, visit.slot["approach"])
	_world.free_all()
	grid = BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, &"nap_pod")
	_shop_world(grid)
	p = ShopTestLayout.airside_guest(_world, 80)
	NeedsPolicy.arbitrate(_world.sim, p)
	assert_object(_world.sim.shops.visit_of(p.id)).is_not_null()
	_run_while_shopping(p)
	print(
		(
			"nap pod: boredom %d, sources %s, messes %d"
			% [p.boredom, _messes().sources(), _messes().mess_count()]
		)
	)
	assert_int(p.boredom).is_equal(0)
	assert_array(_messes().sources()).is_empty()
	assert_int(_messes().mess_count()).is_equal(0)
