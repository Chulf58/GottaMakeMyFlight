class_name TestFlightSideStandSave
extends GdUnitTestSuite
## A flight at a west stand keeps the stand's side through a flight save
## (FlightSnapshot; slice S3 of design airside-all-around-technical-design-
## one-route-source-per-con), and the load checks its taxi pair against the
## routes of the side stand, not of a north stand with the same numbers.
##
## Gate D's stand has its sill at (-60, 300). Read as a north stand its route
## needs a longer TAXI_IN than its west route does. GroundPlanner books only
## axis-aligned routes until side spurs exist (board airside-all-around-s4), so
## the save is made by a sim whose gate D is the north reading, then given the
## west stand and the west route's pair: FlightSnapshot alone reads it.

const SILL := Vector2(-60.0, 300.0)
const TEN := 600


static func _west() -> Dictionary:
	return StandPlacement.make(0, SILL.x, SILL.y, StandPlacement.WEST)


static func _north_reading() -> Dictionary:
	return StandPlacement.make(0, SILL.x, SILL.y)


## A flight save at the west stand, its occurrence T-d0 issued and flown with
## the west route's pair.
func _west_save() -> Dictionary:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["D"] as Array[String]
	sim.stand_source = func() -> Dictionary:
		return {"D": {"stand": _north_reading(), "max_class": PlaneClasses.LARGE}}
	assert_bool(sim.open_airport()).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("T", TEN))).is_true()
	for t in range(1, FlightTimetable.issue_tick(sim.contract_of("T"), 0) + 1):
		sim.on_tick(t)
	assert_array(sim.flight_ids()).is_equal(["T-d0"])
	var contract := sim.contract_of("T").duplicate()
	contract["taxi"] = TaxiTimes.for_stand(_west())
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
	data["contracts"][0]["taxi"] = contract["taxi"]
	var flight: Dictionary = data["flights"][0]
	flight["starts"] = FlightTimetable.starts_for(contract, 0)
	flight["stand"] = _west()
	return JSON.parse_string(JSON.stringify(data))


func test_the_north_reading_of_the_stand_needs_a_longer_taxi_in() -> void:
	var west := TaxiTimes.for_stand(_west())
	var north := TaxiTimes.for_stand(_north_reading())
	print("west pair %s, north reading %s" % [west, north])
	assert_str(TaxiTimes.problem(west)).is_equal("")
	assert_int(north[0]).is_greater(west[0])


func test_a_flight_at_a_west_stand_loads_with_its_side_and_its_own_pair() -> void:
	var data := _west_save()
	print("saved stand %s, starts %s" % [data["flights"][0]["stand"], data["flights"][0]["starts"]])
	var loaded := FlightSnapshot.load(data, ["D"] as Array[String])
	print("loaded: %s" % loaded.get("error", "no error"))
	assert_dict(loaded).not_contains_keys(["error"])
	var stand: Dictionary = loaded["flights"][0]["stand"]
	assert_dict(stand).is_equal(_west())
	assert_str(StandPlacement.side_of(stand)).is_equal(StandPlacement.WEST)


func test_the_same_save_without_the_side_is_refused_for_the_north_route() -> void:
	var data := _west_save()
	data["flights"][0]["stand"].erase("side")
	var loaded := FlightSnapshot.load(data, ["D"] as Array[String])
	print("without side: %s" % loaded.get("error", "no error"))
	assert_str(loaded.get("error", "")).contains("its stand needs")
