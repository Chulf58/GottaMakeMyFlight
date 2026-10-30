class_name TestStandingSpotsOldSave
extends GdUnitTestSuite
## A save from before version 14 has no standing claims. A passenger it holds
## STANDING is sent back to TO_GATE on load with a cleared path, so on the
## next tick it plans a seat or a spot. The loaded game then saves as version
## 14 and that save loads again.

var _a: PassengerTestWorld
var _b: PassengerTestWorld
var _c: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b, _c]:
		if world != null:
			world.free_all()
	_a = null
	_b = null
	_c = null


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## The reference world with more cleared passengers at the gate than seats,
## run until three of them stand on spots.
func _standing_world() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(4242)
	for i in world.sim.layout.seats.size() + 3:
		TestStandingSpotClaims.cleared(world)
	for i in 400:
		world.step()
		if _standing(world).size() >= 3:
			break
	return world


func _standing(world: PassengerTestWorld) -> Array[int]:
	var out: Array[int] = []
	for id in world.sim.passenger_ids():
		if world.passenger(id).stage == Passenger.Stage.STANDING:
			out.append(id)
	return out


## `data` in the shape version 10 saved: no standing claims, info desk or
## kiosk block, and no boredom or kiosk cooldown on a passenger record.
func _as_v10(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out["save_version"] = 10
	for key in ["standing", "info_desk", "shop"]:
		out.erase(key)
	for record: Dictionary in out["passengers"]:
		record.erase("boredom")
		record.erase("shop_cooldown")
	return out


## A reference world holding `_a`'s clock and flights, passengers not loaded.
func _fresh() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(1)
	world.clock.from_snapshot(_json(_a.clock.to_snapshot()))
	world.flights.from_snapshot(_json(_a.flights.to_snapshot()))
	return world


func test_an_old_save_with_standing_passengers_saves_as_v14_and_loads_again() -> void:
	_a = _standing_world()
	var stood := _standing(_a)
	assert_int(stood.size()).is_greater_equal(3)
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(_as_v10(_json(_a.sim.to_snapshot())))).is_true()
	assert_int(_b.sim.standing.claim_count()).is_equal(0)
	for id in stood:
		var p := _b.passenger(id)
		print("passenger %d loads as %s" % [id, Passenger.Stage.keys()[p.stage]])
		assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
		assert_bool(p.is_moving()).is_false()
	# Saved straight away, before any tick, the current-version save loads.
	var again := _json(_b.sim.to_snapshot())
	assert_int(int(again["save_version"])).is_equal(PassengerSim.SAVE_VERSION)
	_c = _fresh()
	assert_bool(_c.sim.from_snapshot(again)).is_true()
	# On the next tick each plans again: a spot (or a seat).
	_b.step()
	for id in stood:
		var p := _b.passenger(id)
		var placed := _b.sim.standing.spot_of(id) != StandingSpots.NO_SPOT or p.seat_object != 0
		print(
			(
				"passenger %d after one tick: %s, spot %d"
				% [id, Passenger.Stage.keys()[p.stage], _b.sim.standing.spot_of(id)]
			)
		)
		assert_bool(placed).is_true()
