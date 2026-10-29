class_name TestLandsideSnapshot
extends GdUnitTestSuite
## The landside save part is checked whole before anything changes: a
## malformed part, a booking that is aboard a vehicle not listing it, two
## cars in one berth or slot, a stage on the wrong lane and a lot that does
## not fit the definition are each refused, and the sim and bookings keep
## what they had. Across parts, a booking must be for a flight the
## passengers part has scheduled (SaveLinks).

const BAD_CASES := [
	"unknown key",
	"old version",
	"lots size",
	"no lot built",
	"aboard unlisted",
	"listed not aboard",
	"stage off its lane",
	"berth twice",
	"released state saved",
	"missed above total",
]

var _land: LandsideTestWorld
## A JSON round trip of a part taken with cars on the road, in a berth and
## in the lot, and bookings both waiting and aboard.
var _data: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self
	_land = LandsideTestWorld.make(LandsideTestWorld.with_berths(1), [], 8)
	assert_bool(_land.landside.build_lot(0)).is_true()
	_land.schedule(40)
	while _land.sim.tick < 9000 and not _varied():
		_land.step()
	_data = JSON.parse_string(JSON.stringify(_part()))


func after() -> void:
	_land.free_all()
	PassengerTestWorld.tracker = null


func _part() -> Dictionary:
	return _land.landside.to_snapshot(_land.sim.arrivals, _land.sim.tick)


func _varied() -> bool:
	var lanes := {}
	for id in _land.landside.vehicle_ids():
		lanes[_land.landside.get_vehicle(id).lane] = true
	var lane := LandsideVehicle.Lane
	return lanes.has(lane.ROAD_IN) and lanes.has(lane.BERTH) and lanes.has(lane.SLOT)


func _first(key: String, field: String, value: Variant) -> Dictionary:
	for entry in _data[key]:
		if entry[field] == value:
			return entry
	return {}


func test_the_part_loads_back_as_it_was() -> void:
	var states := {}
	for entry in _data["bookings"]:
		states[int(entry["state"])] = true
	print(
		(
			"tick %s vehicles %d bookings %d states %s"
			% [_data["tick"], _data["vehicles"].size(), _data["bookings"].size(), states.keys()]
		)
	)
	assert_bool(_varied()).is_true()
	assert_bool(states.has(ArrivalBooking.State.AWAITING)).is_true()
	assert_bool(states.has(ArrivalBooking.State.IN_VEHICLE)).is_true()
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(LandsideTestWorld.with_berths(1))).is_true()
	var bookings := ArrivalBookings.new()
	assert_bool(sim.from_snapshot(_data, bookings)).is_true()
	assert_str(JSON.stringify(sim.to_snapshot(bookings, _land.sim.tick))).is_equal(
		JSON.stringify(_part())
	)


## Breaks `d` (a copy of the saved part) the way `case_name` says.
func _break(d: Dictionary, case_name: String) -> void:
	match case_name:
		"unknown key":
			d["extra"] = 1
		"old version":
			d["save_version"] = 0
		"lots size":
			d["lots_built"] = [true, true, true]
		"no lot built":
			d["lots_built"] = [false, false]
		"aboard unlisted":
			for v in d["vehicles"]:
				(v["bookings"] as Array).clear()
		"listed not aboard":
			var b: Dictionary = _first("bookings", "state", ArrivalBooking.State.AWAITING)
			var entry: Dictionary = d["bookings"][(_data["bookings"] as Array).find(b)]
			(d["vehicles"][0]["bookings"] as Array).append(entry["id"])
		"stage off its lane":
			var driving: Dictionary = _first("vehicles", "lane", LandsideVehicle.Lane.ROAD_IN)
			d["vehicles"][(_data["vehicles"] as Array).find(driving)]["stage"] = (
				LandsideVehicle.Stage.DWELL
			)
		"berth twice":
			var copy: Dictionary = _first("vehicles", "lane", LandsideVehicle.Lane.BERTH)
			copy = copy.duplicate(true)
			copy["id"] = d["next_vehicle_id"]
			copy["bookings"] = []
			d["next_vehicle_id"] += 1
			d["vehicles"].append(copy)
		"released state saved":
			d["bookings"][0]["state"] = ArrivalBooking.State.RELEASED
		"missed above total":
			var count: int = d["missed_total"] + 1
			d["missed"] = [{"flight": PassengerTestWorld.FLIGHT, "count": count}]


func test_bad_parts_are_refused_whole() -> void:
	for case_name in BAD_CASES:
		var bad: Dictionary = _data.duplicate(true)
		_break(bad, case_name)
		var loaded := LandsideSnapshot.load(bad, LandsideTestWorld.with_berths(1))
		print("%s: %s" % [case_name, loaded.get("error", "LOADED")])
		assert_bool(loaded.has("error")).override_failure_message(case_name).is_true()
	var sim := _land.landside
	var before := JSON.stringify(_part())
	var bad: Dictionary = _data.duplicate(true)
	bad["lots_built"] = []
	assert_bool(sim.from_snapshot(bad, _land.sim.arrivals)).is_false()
	assert_str(JSON.stringify(_part())).is_equal(before)


func test_a_booking_for_a_flight_not_scheduled_breaks_the_link() -> void:
	var loaded := LandsideSnapshot.load(_data, LandsideTestWorld.with_berths(1))
	var flights := {"flights": [{"id": PassengerTestWorld.FLIGHT}], "start_day": {}, "next_day": {}}
	var scheduled := {"scheduled": {PassengerTestWorld.FLIGHT: true}}
	assert_str(SaveLinks._landside_problem(loaded, scheduled, flights)).is_equal("")
	var problem := SaveLinks._landside_problem(loaded, {"scheduled": {}}, flights)
	print(problem)
	assert_str(problem).contains("which is not scheduled")
	loaded["bookings"] = []
	loaded["missed"] = {"GONE": 2}
	problem = SaveLinks._landside_problem(loaded, {"scheduled": {}}, flights)
	print(problem)
	assert_str(problem).contains("neither live nor issued")
