class_name TestFlightLaneX
extends GdUnitTestSuite
## A flight's taxi times and save follow its side stand's own lane_x (decision
## side-spur-move-design-s7-stands-carry-lane-x-the-wanted-spur, slice S7a).
## TaxiTimes.for_stand reads the stand alone: a stand on a spur at x -174 /
## +174 needs a longer pair than the same sill on the spur at -124 / +124, and
## stays inside TaxiTimes' bounds. The flight save keeps lane_x, refuses a side
## stand without it, and refuses a version 9 save, with no migration.

const WIDE := 174.0
const TEN := 600
## West and east sills: one 62 m inside its spur, one just inside the site's
## grid near x 0, and one far south.
const SILLS := [
	["W", Vector2(-62.0, -150.0)],
	["W", Vector2(0.0, -149.5)],
	["W", Vector2(0.0, -60.5)],
	["E", Vector2(62.0, -150.0)],
	["E", Vector2(0.0, -129.5)],
	["E", Vector2(0.0, -60.5)],
]


static func _stand(entry: Array, lane: float) -> Dictionary:
	var side: String = entry[0]
	var sill: Vector2 = entry[1]
	var lane_x := -lane if side == StandPlacement.WEST else lane
	return StandPlacement.make(0, sill.x, sill.y, side, lane_x)


## Each side stand's pair at x -174 / +174 is longer than at -124 / +124 and
## passes TaxiTimes.problem(), so it is inside MAX_IN and MAX_OUT. A phase over
## BASE at -124 / +124 grows by the 100 m more each way, within a STEP_TICKS of
## rounding; one held at BASE (the short way between a spur and its own stub)
## never shrinks.
func test_a_wider_spur_needs_a_longer_pair_inside_the_bounds() -> void:
	var extra := 2.0 * (WIDE - StandPlacement.SIDE_LANE_X) * TaxiTimes.TICKS_PER_M
	var grown := 0
	for entry: Array in SILLS:
		var near := TaxiTimes.for_stand(_stand(entry, StandPlacement.SIDE_LANE_X))
		var far := TaxiTimes.for_stand(_stand(entry, WIDE))
		print("%s near %s far %s" % [entry, near, far])
		assert_str(TaxiTimes.problem(far)).is_equal("")
		assert_int(far[0] + far[1]).is_greater(near[0] + near[1])
		for i in 2:
			assert_int(far[i]).is_greater_equal(near[i])
			if near[i] > TaxiTimes.BASE[i]:
				var gain := float(far[i] - near[i])
				assert_float(gain).is_between(
					extra - TaxiTimes.STEP_TICKS, extra + TaxiTimes.STEP_TICKS
				)
				grown += 1
		assert_int(far[0]).is_less_equal(TaxiTimes.MAX_IN)
		assert_int(far[1]).is_less_equal(TaxiTimes.MAX_OUT)
	assert_int(grown).is_equal(SILLS.size())


## A flight save by a sim whose gate D stands on `stand`, its occurrence T-d0
## issued.
func _save(stand: Dictionary) -> Dictionary:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["D"] as Array[String]
	sim.stand_source = func() -> Dictionary:
		return {"D": {"stand": stand, "max_class": PlaneClasses.LARGE}}
	assert_bool(sim.open_airport()).is_true()
	assert_bool(sim.accept_contract(TestFlightContracts.terms("T", TEN))).is_true()
	for t in range(1, FlightTimetable.issue_tick(sim.contract_of("T"), 0, 0) + 1):
		sim.on_tick(t)
	assert_array(sim.flight_ids()).is_equal(["T-d0"])
	return JSON.parse_string(JSON.stringify(sim.to_snapshot()))


## A flight at a west stand on the floor spur saves its lane_x and loads with
## it; the same save with the stand's lane_x taken out is refused, and so is it
## at save version 9.
func test_the_flight_save_keeps_lane_x_and_refuses_older_saves() -> void:
	assert_int(FlightSim.SAVE_VERSION).is_equal(10)
	var stand := _stand(SILLS[0], StandPlacement.SIDE_LANE_X)
	var data := _save(stand)
	assert_int(int(data["save_version"])).is_equal(10)
	var saved: Dictionary = data["flights"][0]["stand"]
	print("saved stand %s" % saved)
	assert_float(float(saved["lane_x"])).is_equal(-StandPlacement.SIDE_LANE_X)
	var loaded := FlightSnapshot.load(data, ["D"] as Array[String], 0)
	assert_dict(loaded).not_contains_keys(["error"])
	assert_dict(loaded["flights"][0]["stand"]).is_equal(stand)
	var bare: Dictionary = data.duplicate(true)
	bare["flights"][0]["stand"].erase("lane_x")
	var refused := FlightSnapshot.load(bare, ["D"] as Array[String], 0)
	print("no lane_x: %s" % refused.get("error", "no error"))
	assert_str(refused.get("error", "")).contains("stand must be a stand")
	var old: Dictionary = data.duplicate(true)
	old["save_version"] = 9
	var sim: FlightSim = auto_free(FlightSim.new())
	assert_bool(sim.from_snapshot(old)).is_false()
	# Control: the current save loads into a sim.
	var control: FlightSim = auto_free(FlightSim.new())
	control.gate_source = func() -> Array[String]: return ["D"] as Array[String]
	control.stand_source = func() -> Dictionary:
		return {"D": {"stand": stand, "max_class": PlaneClasses.LARGE}}
	assert_bool(control.from_snapshot(data)).is_true()
