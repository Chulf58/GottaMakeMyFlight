class_name TestPassengerMigrationKeepsFields
extends GdUnitTestSuite
## A migration step sets a field or block only when the save has none: an old
## save that already holds a value a later version added keeps it. Each case
## builds the shape of one old version (version 6 to 10) with one passenger
## record, or the block, holding such a value, loads it and checks the value
## survived while every other record got the migrated default.

const SAVE_TICK := 205

var _current: Dictionary
var _clock: Dictionary
var _flights: Dictionary
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self
	var a := PassengerTestWorld.reference_world(4242)
	# No bags anywhere, as a version 6 world had: security times then agree with
	# the traits the version 6 fixture loses.
	TestPassengerV6Migration._zero_traits_of(a)
	a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	for i in 10:
		a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	a.run_to(SAVE_TICK)
	_current = _json(a.sim.to_snapshot())
	_clock = _json(a.clock.to_snapshot())
	_flights = _json(a.flights.to_snapshot())
	a.free_all()


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _b != null:
		_b.free_all()
		_b = null


func _json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


## A world holding the clock and flights `_current` was saved with, with the
## passenger part not yet loaded.
func _fresh() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world(1)
	world.clock.from_snapshot(_clock)
	world.flights.from_snapshot(_flights)
	return world


## `_current` as version `version` saved it: every field and block added after
## it removed.
func _old(version: int) -> Dictionary:
	var data: Dictionary
	if version <= 7:
		data = SecurityTestWorld.as_v7(_current)
		if version == 6:
			_erase_fields(data, ["carry_on", "liquids", "alarm"])
	else:
		data = _current.duplicate(true)
		if version <= 9:
			data.erase("toilet")
			_erase_fields(data, ["toilet_need", "toilet_cooldown"])
		data.erase("shop")
		_erase_fields(data, ["boredom", "shop_cooldown"])
	data["save_version"] = version
	return data


func _erase_fields(data: Dictionary, fields: Array) -> void:
	for record: Dictionary in data["passengers"]:
		for field in fields:
			record.erase(field)


func _record(data: Dictionary, index := 0) -> Dictionary:
	return data["passengers"][index]


func _load(data: Dictionary) -> void:
	_b = _fresh()
	assert_bool(_b.sim.from_snapshot(data)).is_true()


func test_a_version_6_save_keeps_the_traits_it_holds() -> void:
	var data := _old(6)
	_record(data)["carry_on"] = 2
	_record(data)["liquids"] = true
	_load(data)
	var first := _b.passenger(int(_record(data)["id"]))
	assert_int(first.carry_on).is_equal(2)
	assert_bool(first.liquids).is_true()
	assert_bool(first.alarm).is_false()
	var other := _b.passenger(int(_record(data, 1)["id"]))
	assert_int(other.carry_on).is_equal(0)
	assert_bool(other.liquids).is_false()


func test_a_version_7_save_keeps_the_security_fields_it_holds() -> void:
	var data := _old(7)
	_record(data)["incident_resolved"] = true
	_load(data)
	assert_bool(_b.passenger(int(_record(data)["id"])).incident_resolved).is_true()
	assert_bool(_b.passenger(int(_record(data, 1)["id"])).incident_resolved).is_false()


func test_a_version_9_save_keeps_the_toilet_values_it_holds() -> void:
	var data := _old(9)
	_record(data)["toilet_need"] = 33
	_record(data)["toilet_cooldown"] = 9
	data["toilet"] = {"visits": [], "deadlines_stale": true}
	_load(data)
	var first := _b.passenger(int(_record(data)["id"]))
	assert_int(first.toilet_need).is_equal(33)
	assert_int(first.toilet_cooldown).is_equal(9)
	assert_bool(_b.sim.toilets.deadlines_stale).is_true()
	var other_id := int(_record(data, 1)["id"])
	assert_int(_b.passenger(other_id).toilet_need).is_equal(ToiletSim.migrated_need(other_id))
	assert_int(_b.passenger(other_id).toilet_cooldown).is_equal(0)


func test_a_version_10_save_keeps_the_boredom_and_kiosk_values_it_holds() -> void:
	var data := _old(10)
	_record(data)["boredom"] = 77
	_record(data)["shop_cooldown"] = 55
	data["shop"] = {"visits": [], "deadlines_stale": true}
	_load(data)
	var first := _b.passenger(int(_record(data)["id"]))
	assert_int(first.boredom).is_equal(77)
	assert_int(first.shop_cooldown).is_equal(55)
	assert_bool(_b.sim.shops.deadlines_stale).is_true()
	var other_id := int(_record(data, 1)["id"])
	assert_int(_b.passenger(other_id).boredom).is_equal(BoredomSim.start_of(other_id))
	assert_int(_b.passenger(other_id).shop_cooldown).is_equal(0)
