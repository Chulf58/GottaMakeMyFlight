class_name TestShopWishSave
extends GdUnitTestSuite
## A shop visit's fallback flag in the passenger save (ShopSnapshot,
## PassengerSim save version 13; decision shopping-wish-technical-design-id-
## hash-wish-admissible-wished-slot-then-fallback, point 3): a fallback visit
## saved mid-walk loads as a fallback and settles for less; a visit without a
## true-or-false fallback is refused, and so is a version 12 save (no
## migration, decision old-saves-are-not-supported-until-after-a-release-no-
## save-mi).

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _ids: Dictionary
var _paid: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null
	_paid.clear()


func _fashion_wish(world: PassengerTestWorld) -> void:
	world.sim.shops.wishes = func(_p: Passenger) -> StringName: return &"fashion"


## World A: a kiosk only, a fashion wisher on a fallback walk to it; the
## save taken on the tick the visit starts.
func _saved() -> Dictionary:
	var grid := BuildGrid.new()
	_ids = WishTestLayout.build(grid, [&"kiosk"])
	_a = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_fashion_wish(_a)
	_a.run_to(10)
	var p := ShopTestLayout.airside_guest(_a, BoredomSim.MAX)
	p.mood = 70
	assert_int(NeedsPolicy.arbitrate(_a.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	assert_bool(_a.sim.shops.visit_of(p.id).fallback).is_true()
	var data: Dictionary = (
		JSON
		. parse_string(
			(
				JSON
				. stringify(
					{
						"clock": _a.clock.to_snapshot(),
						"flights": _a.flights.to_snapshot(),
						"grid": _a.grid.to_snapshot(),
						"passengers": _a.sim.to_snapshot(),
					}
				)
			)
		)
	)
	return {"data": data, "id": p.id}


func _load(data: Dictionary) -> bool:
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	_b = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(_b.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(_b.flights.from_snapshot(data["flights"])).is_true()
	return _b.sim.from_snapshot(data["passengers"])


func test_a_fallback_visit_saves_its_flag_and_settles_for_less_after_a_load() -> void:
	var saved := _saved()
	var data: Dictionary = saved["data"]
	var visits: Array = data["passengers"]["shop"]["visits"]
	print("saved visits %s, version %s" % [visits, data["passengers"]["save_version"]])
	assert_int(int(data["passengers"]["save_version"])).is_equal(13)
	assert_int(visits.size()).is_equal(1)
	assert_that(visits[0]["fallback"]).is_equal(true)
	assert_bool(_load(data)).is_true()
	_fashion_wish(_b)
	var id: int = saved["id"]
	var p := _b.passenger(id)
	assert_bool(_b.sim.shops.visit_of(id).fallback).is_true()
	assert_int(_b.sim.shops.visit_wish_state(id)).is_equal(WishTable.State.SUBSTITUTED)
	_b.sim.shops.paid.connect(
		func(pid: int, room: int, amount: int) -> void: _paid.append([pid, room, amount])
	)
	var full := ShopSim.spend(RoomTypes.get_type(&"kiosk").base_spend, p.mood, true)
	var until := _b.clock.tick + 3000
	while _b.sim.shops.visit_of(id) != null and _b.clock.tick < until:
		_b.step()
	print("after load paid %s of full %d, mood %d" % [_paid, full, p.mood])
	assert_array(_paid).is_equal([[id, _ids["rooms"][0], int(full * ShopSim.FALLBACK_SHARE)]])
	assert_int(p.mood).is_equal(70 - ShopSim.FALLBACK_MOOD)


func test_a_visit_without_a_true_or_false_fallback_is_refused() -> void:
	var data: Dictionary = _saved()["data"]
	for bad: Variant in ["missing", 1, "yes", null]:
		var copy: Dictionary = data.duplicate(true)
		var visit: Dictionary = copy["passengers"]["shop"]["visits"][0]
		if bad is String and bad == "missing":
			visit.erase("fallback")
		else:
			visit["fallback"] = bad
		assert_bool(_load(copy)).override_failure_message(str(bad)).is_false()
		assert_array(_b.sim.passenger_ids()).is_empty()
		_b.free_all()
		_b = null
	# Control: the unchanged save loads.
	assert_bool(_load(data)).is_true()


func test_a_version_12_save_is_refused() -> void:
	var data: Dictionary = _saved()["data"]
	data["passengers"]["save_version"] = 12
	assert_bool(_load(data)).is_false()
	assert_array(_b.sim.passenger_ids()).is_empty()
