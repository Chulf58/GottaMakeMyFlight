class_name TestFlightSideStandSave
extends GdUnitTestSuite
## A flight at a west stand keeps the stand's side through a flight save
## (FlightSnapshot; slice S3 of design airside-all-around-technical-design-
## one-route-source-per-con), and the load checks its taxi pair against the
## routes of the side stand, not of a north stand with the same numbers.
##
## Gate D's stand has its sill at (-60, 300). Its west route runs the whole lane
## and down the west spur (board airside-all-around-s4), so it needs a longer
## TAXI_IN than the north reading of the same numbers. GroundPlanner books the
## spur routes, so a sim whose gate D is the west stand makes the save itself.
## A save made on the north reading's shorter pair and then given the west
## stand is refused: FlightSnapshot reads the side.

const SILL := Vector2(-60.0, 300.0)
const TEN := 600


static func _west() -> Dictionary:
	return StandPlacement.make(0, SILL.x, SILL.y, StandPlacement.WEST)


static func _north_reading() -> Dictionary:
	return StandPlacement.make(0, SILL.x, SILL.y)


## A flight save by a sim whose gate D stands on `stand`, its occurrence T-d0
## issued.
func _save(stand: Dictionary) -> Dictionary:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["D"] as Array[String]
	sim.stand_source = func() -> Dictionary:
		return {"D": {"stand": stand, "max_class": PlaneClasses.LARGE}}
	assert_bool(sim.open_airport()).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("T", TEN))).is_true()
	for t in range(1, FlightTimetable.issue_tick(sim.contract_of("T"), 0) + 1):
		sim.on_tick(t)
	assert_array(sim.flight_ids()).is_equal(["T-d0"])
	return JSON.parse_string(JSON.stringify(sim.to_snapshot()))


func test_the_west_route_needs_a_longer_taxi_in_than_the_north_reading() -> void:
	var west := TaxiTimes.for_stand(_west())
	var north := TaxiTimes.for_stand(_north_reading())
	print("west pair %s, north reading %s" % [west, north])
	assert_str(TaxiTimes.problem(west)).is_equal("")
	assert_int(west[0]).is_greater(north[0])


func test_a_flight_at_a_west_stand_loads_with_its_side_and_its_own_pair() -> void:
	var data := _save(_west())
	var flight: Dictionary = data["flights"][0]
	print("saved stand %s, starts %s" % [flight["stand"], flight["starts"]])
	assert_array(TaxiTimes.of_starts(flight["starts"])).is_equal(TaxiTimes.for_stand(_west()))
	var loaded := FlightSnapshot.load(data, ["D"] as Array[String])
	print("loaded: %s" % loaded.get("error", "no error"))
	assert_dict(loaded).not_contains_keys(["error"])
	var stand: Dictionary = loaded["flights"][0]["stand"]
	assert_dict(stand).is_equal(_west())
	assert_str(StandPlacement.side_of(stand)).is_equal(StandPlacement.WEST)


func test_a_north_reading_save_given_the_west_stand_is_refused() -> void:
	var data := _save(_north_reading())
	data["flights"][0]["stand"] = _west()
	var loaded := FlightSnapshot.load(
		JSON.parse_string(JSON.stringify(data)), ["D"] as Array[String]
	)
	print("north pair at the west stand: %s" % loaded.get("error", "no error"))
	assert_str(loaded.get("error", "")).contains("its stand needs")
