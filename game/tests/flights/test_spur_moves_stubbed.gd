class_name TestSpurMovesStubbed
extends GdUnitTestSuite
## Review fixes in FlightSim's spur checks (decision side-spur-move-design-s7-
## stands-carry-lane-x-the-wanted-spur), on a sim whose gates come from test
## sources: gate A (and B) on west stands whose spur waits to move from x -124
## to -150, gate C and D on fallback north stands. The plans are stubs that
## refuse what real planning cannot be made to refuse on demand, as
## test_flight_planner_wiring.gd's NonMonotonePlans does:
## - ending a contract whose world must keep reserving it is checked whole,
##   reservations across the earlier release included;
## - an occurrence a change moves across the release that then loses its plan
##   is named as stranded by the spur (SPUR_STRANDS_TEXT), not TAXI_BUSY_TEXT.

const CURRENT_X := -124.0
const WANTED_X := -150.0

var _sim: FlightSim
## Gate letter -> its ground, as the sim's stand_source returns it.
var _grounds: Dictionary


## Contract C's occurrences get no plan while B runs and A does not (A ending
## frees ground C needs), or while ended A still reserves a day on the wanted
## spur (a reservation across the earlier release lands on C's ground).
class ReservationPlans:
	extends FlightPlans

	func plan_day(world: Dictionary, day: int) -> Dictionary:
		var out := {}
		var ids := {}
		var a_moved := false
		for req: Dictionary in FlightPlans.requests(world, day):
			var contract: String = FlightTimetable.parse_occurrence(req["id"])["contract"]
			ids[contract] = true
			if contract == "A" and world["ended"].has("A"):
				a_moved = (
					a_moved or is_equal_approx(StandPlacement.lane_x_of(req["stand"]), WANTED_X)
				)
		for req: Dictionary in FlightPlans.requests(world, day):
			var contract: String = FlightTimetable.parse_occurrence(req["id"])["contract"]
			var stranded: bool = (
				contract == "C" and ((ids.has("B") and not ids.has("A")) or a_moved)
			)
			out[req["id"]] = {
				"ok": not stranded,
				"reason": GroundPlanner.TAXI_BUSY if stranded else "",
				"pauses": {},
				"bookings": [],
			}
		return out


## Contract C1's occurrences get no plan from a stand on spur x -124.
class OldSpurPlans:
	extends FlightPlans

	func plan_day(world: Dictionary, day: int) -> Dictionary:
		var out := {}
		for req: Dictionary in FlightPlans.requests(world, day):
			var contract: String = FlightTimetable.parse_occurrence(req["id"])["contract"]
			var stranded: bool = (
				contract == "C1"
				and is_equal_approx(StandPlacement.lane_x_of(req["stand"]), CURRENT_X)
			)
			out[req["id"]] = {
				"ok": not stranded,
				"reason": GroundPlanner.TAXI_BUSY if stranded else "",
				"pauses": {},
				"bookings": [],
			}
		return out


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_grounds = {
		"A": {"stand": _west(-93.5), "max_class": PlaneClasses.LARGE},
		"B": {"stand": _west(-40.0), "max_class": PlaneClasses.LARGE},
		"C": FlightGround.fallback("C"),
		"D": FlightGround.fallback("D"),
	}
	_sim.gate_source = func() -> Array[String]: return ["A", "B", "C", "D"] as Array[String]
	_sim.stand_source = func() -> Dictionary: return _grounds
	var spurs := SideSpurs.spurs_at({}, {StandPlacement.WEST: WANTED_X})
	spurs[StandPlacement.WEST]["x"] = CURRENT_X
	_sim.spur_source = func() -> Dictionary: return spurs
	_sim.spur_release = func(_side: String) -> void: pass
	_sim.open_airport()


static func _west(wall_z: float) -> Dictionary:
	return StandPlacement.make(1, -33.0, wall_z, StandPlacement.WEST, CURRENT_X)


func _accept(id: String, minute: int, gate: String) -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms(id, minute))).is_true()
	if _sim.contract_of(id)["gate"] != gate:
		assert_bool(_sim.reassign_gate(id, gate)).is_true()


## A one-off at west gate A keeps the side busy until its TAKEOFF (3700), and
## A's first day, issued at 07:47 before that, holds R to A's TAKEOFF. Ending
## A would strand C (the stub's B rule), so A must keep reserving; but reserving
## does not delay R, so A's next day lands on the wanted spur, where (the stub
## says) its reservation strands C. The end is refused and A keeps running.
func test_an_end_that_must_reserve_is_checked_with_its_reservations() -> void:
	_sim._plans = ReservationPlans.new()
	_sim._trial_plans = ReservationPlans.new()
	assert_bool(_sim.add_flight("X1", FlightSim.schedule_starts(0), "A")).is_true()
	_accept("A", 12 * 60, "A")
	_accept("B", 14 * 60, "C")
	_accept("C", 17 * 60, "D")
	_sim.on_tick(1000)
	var running := _sim.spur_release_tick("W")
	var non_reserving := _sim.end_refusal("A")
	print("R %d; ending A alone strands %s" % [running, non_reserving])
	assert_int(running).is_greater(_sim.state_start("X1", FlightSim.State.TAKEOFF))
	assert_str(non_reserving.get("id", "")).starts_with("C-d")
	assert_bool(_sim.end_contract("A")).is_false()
	assert_array(_sim.active_contract_ids()).contains(["A"])
	assert_bool(_sim.is_reserving("A")).is_false()


## A one-off at gate B keeps the side busy until 3700; C1 at gate A is first
## issued after that, so its days fly the wanted spur. C2 at gate B is issued
## before 3700 and takes off after C1's issue, so accepting it moves R past
## C1's first day, which then flies from x -124, where (the stub says) it gets
## no plan. The north gates take only small planes, so no other gate answers:
## the accept is refused naming C1's day as stranded by the spur.
func test_an_occurrence_moved_across_the_release_that_loses_its_plan_is_typed() -> void:
	for gate in ["C", "D"]:
		_grounds[gate]["max_class"] = PlaneClasses.SMALL
	assert_bool(_sim.add_flight("X1", FlightSim.schedule_starts(0), "B")).is_true()
	_sim._plans = OldSpurPlans.new()
	_sim._trial_plans = OldSpurPlans.new()
	_accept("C1", 14 * 60, "A")
	var before := _sim.spur_release_tick("W")
	var terms := TestFlightContracts.terms("C2", 12 * 60)
	var problem := _sim.accept_problem(terms)
	print("R %d; accepting C2: '%s'" % [before, problem])
	assert_int(before).is_equal(_sim.state_start("X1", FlightSim.State.TAKEOFF))
	assert_str(problem).is_equal(FlightSim.SPUR_STRANDS_TEXT % "C1-d0")
