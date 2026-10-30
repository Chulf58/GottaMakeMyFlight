class_name TestShopWishSave
extends GdUnitTestSuite
## A shop visit's fallback flag in the passenger save (ShopSnapshot,
## PassengerSim save version 13; decision shopping-wish-technical-design-id-
## hash-wish-admissible-wished-slot-then-fallback, point 3): a fallback visit
## saved mid-walk loads as a fallback and settles for less; a visit without a
## true-or-false fallback is refused, and so is a version 12 save (no
## migration, decision old-saves-are-not-supported-until-after-a-release-no-
## save-mi). The flag must also fit the visit: a bored passenger's relief
## visit is a fallback exactly when it wishes for a kind and the room is of
## another, and a no-wish visit or a spare-time browse never is.
##
## The wish here is WishTable's, derived from the passenger as the loader
## derives it: each test picks a guest whose arrival type gives the wish the
## scenario needs. (Before the loader checked the flag, these tests pinned a
## fashion wish through ShopSim.wishes; a save of a pinned wish that the
## table would not give is now, rightly, an inconsistent save.)

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _ids: Dictionary
var _paid: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_free_worlds()
	_paid.clear()


func _free_worlds() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


## A wish for some kind other than the kiosk.
static func _other_than_kiosk(wish: StringName) -> bool:
	return wish != WishTable.NONE and wish != &"kiosk"


static func _kiosk(wish: StringName) -> bool:
	return wish == &"kiosk"


static func _none(wish: StringName) -> bool:
	return wish == WishTable.NONE


## An airside guest in `world`, `boredom` bored, whose wish (WishTable.pick()
## of its arrival type and id) passes `accept`: its arrival type is set to the
## first that gives such a wish. A passenger spawned on the way whose id gives
## none stays where it spawned.
func _guest(world: PassengerTestWorld, boredom: int, accept: Callable) -> Passenger:
	for attempt in 60:
		var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		for type: ArrivalTypes.Type in ArrivalTypes.Type.values():
			if accept.call(WishTable.pick(type, p.id)):
				p.arrival_type = type
				ShopTestLayout.to_airside(world, p, boredom)
				return p
	assert_bool(false).override_failure_message("no passenger id gives the wish").is_true()
	return null


## World A: a kiosk only, and a guest (`boredom`, wish passing `accept`) who
## starts a visit to it: a relief visit, or a spare-time browse when
## `browse`. The save is taken on the tick the visit starts.
func _saved(boredom: int, accept: Callable, browse := false) -> Dictionary:
	if _a != null:
		_free_worlds()
	var grid := BuildGrid.new()
	_ids = WishTestLayout.build(grid, [&"kiosk"])
	_a = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_a.run_to(10)
	var p := _guest(_a, boredom, accept)
	p.mood = 70
	if browse:
		var plan := _a.sim.shops.plan_visit(p, true)
		assert_bool(plan.is_empty()).is_false()
		_a.sim.shops.commit_visit(p, plan)
	else:
		assert_int(NeedsPolicy.arbitrate(_a.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	assert_object(_a.sim.shops.visit_of(p.id)).is_not_null()
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
	return {"data": data, "id": p.id, "wish": WishTable.of(p)}


func _load(data: Dictionary) -> bool:
	if _b != null:
		_b.free_all()
		_b = null
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	_b = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(_b.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(_b.flights.from_snapshot(data["flights"])).is_true()
	return _b.sim.from_snapshot(data["passengers"])


## The one visit of a save's passengers.
static func _visit(data: Dictionary) -> Dictionary:
	return data["passengers"]["shop"]["visits"][0]


func test_a_fallback_visit_saves_its_flag_and_settles_for_less_after_a_load() -> void:
	var saved := _saved(BoredomSim.MAX, _other_than_kiosk)
	var data: Dictionary = saved["data"]
	var visits: Array = data["passengers"]["shop"]["visits"]
	print(
		(
			"wish %s, saved visits %s, version %s"
			% [saved["wish"], visits, data["passengers"]["save_version"]]
		)
	)
	assert_int(int(data["passengers"]["save_version"])).is_equal(PassengerSim.SAVE_VERSION)
	assert_int(visits.size()).is_equal(1)
	assert_that(visits[0]["fallback"]).is_equal(true)
	assert_bool(_load(data)).is_true()
	var id: int = saved["id"]
	var p := _b.passenger(id)
	assert_bool(_b.sim.shops.visit_of(id).fallback).is_true()
	assert_int(_b.sim.shops.visit_wish_state(id)).is_equal(WishTable.State.SUBSTITUTED)
	_b.sim.shops.paid.connect(
		func(pid: int, room: int, amount: int) -> void: _paid.append([pid, room, amount])
	)
	var kiosk := RoomTypes.get_type(&"kiosk").base_spend
	var wished := RoomTypes.get_type(saved["wish"]).base_spend
	var full := ShopSim.spend(mini(kiosk, wished), p.mood, true)
	var until := _b.clock.tick + 3000
	while _b.sim.shops.visit_of(id) != null and _b.clock.tick < until:
		_b.step()
	print("after load paid %s of full %d, mood %d" % [_paid, full, p.mood])
	assert_array(_paid).is_equal([[id, _ids["rooms"][0], int(full * ShopSim.FALLBACK_SHARE)]])
	assert_int(p.mood).is_equal(70 - ShopSim.FALLBACK_MOOD)


func test_a_visit_without_a_true_or_false_fallback_is_refused() -> void:
	var data: Dictionary = _saved(BoredomSim.MAX, _other_than_kiosk)["data"]
	for bad: Variant in ["missing", 1, "yes", null]:
		var copy: Dictionary = data.duplicate(true)
		var visit := _visit(copy)
		if bad is String and bad == "missing":
			visit.erase("fallback")
		else:
			visit["fallback"] = bad
		assert_bool(_load(copy)).override_failure_message(str(bad)).is_false()
		assert_array(_b.sim.passenger_ids()).is_empty()
	# Control: the unchanged save loads.
	assert_bool(_load(data)).is_true()


## Review finding (Sol, MEDIUM): a flag that does not fit the visit loaded,
## and a no-wish fallback then crashed at settle on RoomTypes.get_type(NONE).
## [scenario, boredom, wish filter, browse, the flag play saves].
func test_a_fallback_flag_that_does_not_fit_the_visit_is_refused_whole() -> void:
	var cases := [
		["no wish", BoredomSim.MAX, _none, false, false],
		["wished kind", BoredomSim.MAX, _kiosk, false, false],
		["another kind", BoredomSim.MAX, _other_than_kiosk, false, true],
		["spare-time browse", 0, _other_than_kiosk, true, false],
	]
	for case: Array in cases:
		var saved := _saved(case[1], case[2], case[3])
		var data: Dictionary = saved["data"]
		print("%s: wish %s, saved fallback %s" % [case[0], saved["wish"], _visit(data)["fallback"]])
		assert_that(_visit(data)["fallback"]).override_failure_message(case[0]).is_equal(case[4])
		var flipped: Dictionary = data.duplicate(true)
		_visit(flipped)["fallback"] = not case[4]
		assert_bool(_load(flipped)).override_failure_message(case[0]).is_false()
		assert_array(_b.sim.passenger_ids()).override_failure_message(case[0]).is_empty()
		assert_int(_b.sim.shops.visit_ids().size()).is_equal(0)
		# Control: the save as play left it loads.
		assert_bool(_load(data)).override_failure_message(case[0]).is_true()
		assert_bool(_b.sim.shops.visit_of(saved["id"]).fallback).is_equal(case[4])


func test_a_version_12_save_is_refused() -> void:
	var data: Dictionary = _saved(BoredomSim.MAX, _other_than_kiosk)["data"]
	data["passengers"]["save_version"] = 12
	assert_bool(_load(data)).is_false()
	assert_array(_b.sim.passenger_ids()).is_empty()
