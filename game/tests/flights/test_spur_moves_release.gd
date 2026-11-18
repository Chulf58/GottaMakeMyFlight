class_name TestSpurMovesRelease
extends GdUnitTestSuite
## A pending side spur's release tick R and the one resolver (SpurMoves;
## decision side-spur-move-design-s7-stands-carry-lane-x-the-wanted-spur), on
## planning worlds built by hand: R is the first tick no real occurrence at the
## side's gates is between issue and TAKEOFF, chained through the days not yet
## issued; a reserving contract never delays it; the nightly gap bounds it; the
## resolver gives a day issued before R the stand and pair it has, and a later
## day the stand on the wanted spur with its own pair; refusal() names a
## contract the new stand cannot take and a re-timed occurrence that meets
## another at its gate.

const WEST_X := -124.0
const WANTED_X := -150.0
## A west stand on the starter shell's west wall (test_gate_desks_side.gd's).
const SILL := Vector2(-33.0, -93.5)
## The largest pair TaxiTimes allows.
const MAX_PAIR: Array[int] = [TaxiTimes.MAX_IN, TaxiTimes.MAX_OUT]

var _stand: Dictionary
var _next: Dictionary


func before() -> void:
	_stand = StandPlacement.make(1, SILL.x, SILL.y, StandPlacement.WEST, WEST_X)
	_next = StandPlacement.with_lane_x(_stand, WANTED_X)


func _contract(id: String, minute: int, taxi: Array = []) -> Dictionary:
	return (
		FlightContract
		. make(
			{
				"id": id,
				"airline": "Gotta Air",
				"destination": "Oslo",
				"departure_minute": minute,
				"gate": "A",
				"plane_size": "small",
				"booked_passengers": 12,
				"fee_per_passenger": 25,
				"first_day": 0,
				"taxi": taxi if not taxi.is_empty() else TaxiTimes.for_stand(_stand),
			}
		)
	)


func _world(at: int, contracts: Array, flights: Array = [], next: Dictionary = {}) -> Dictionary:
	var next_day := {}
	for contract: Dictionary in contracts:
		next_day[contract["id"]] = 0
	var ground := {"stand": _stand, "max_class": PlaneClasses.LARGE}
	if not next.is_empty():
		ground["next"] = next
	return {
		"spurs":
		{
			StandPlacement.WEST: {"x": WEST_X, "wanted": WANTED_X},
			StandPlacement.EAST: {"x": 124.0, "wanted": 124.0},
		},
		"tick": at,
		"open": true,
		"epoch": 0,
		"contracts": contracts,
		"start_day": next_day.duplicate(),
		"next_day": next_day,
		"ended": {},
		"reserving": {},
		"flights": flights,
		"landed": [],
		"grounds": {"A": ground},
		"works": [],
	}


func _flight(id: String, starts: Array[int], stand: Dictionary) -> Dictionary:
	return {"id": id, "starts": starts, "state": 0, "gate": "A", "contract": "", "stand": stand}


## Not pending: no release. Pending and quiet: R is the tick itself.
func test_a_quiet_side_releases_at_once() -> void:
	var world := _world(1000, [])
	world["spurs"][StandPlacement.WEST]["wanted"] = WEST_X
	assert_int(SpurMoves.release(world, StandPlacement.WEST)).is_equal(-1)
	var pending := _world(1000, [])
	print("quiet pending side: R %d" % SpurMoves.release(pending, StandPlacement.WEST))
	assert_int(SpurMoves.release(pending, StandPlacement.WEST)).is_equal(1000)
	assert_int(SpurMoves.release(pending, StandPlacement.EAST)).is_equal(-1)


## A live flight at a west stand holds R until its TAKEOFF; a north one does
## not; and a day not yet issued whose issue comes before that TAKEOFF holds it
## on to its own TAKEOFF.
func test_live_flights_and_unissued_days_chain_the_release() -> void:
	var starts := FlightSim.schedule_starts(2000)
	var west := _flight("W1", starts, _stand)
	var north := _flight("N1", FlightSim.schedule_starts(9000), StandPlacement.make(2, 0.0, -210.0))
	var takeoff := starts[FlightSim.State.TAKEOFF]
	var alone := SpurMoves.release(_world(1500, [], [west, north]), StandPlacement.WEST)
	print("live west takeoff %d, north takeoff %d: R %d" % [takeoff, 9000, alone])
	assert_int(alone).is_equal(takeoff)
	# A contract issued 30 to 49 ticks before that TAKEOFF (whole minutes).
	var departure := takeoff - 30 + FlightTimetable.issue_lead()
	var later := _contract("C2", GameCalendar.minute_of_day(departure, 0))
	var day := GameCalendar.day_of(departure, 0)
	var issue := FlightTimetable.issue_tick(later, day, 0)
	var chained := SpurMoves.release(_world(1500, [later], [west]), StandPlacement.WEST)
	var later_takeoff := FlightTimetable.starts_for(later, day, 0)[FlightSim.State.TAKEOFF]
	print(
		(
			"C2 day %d issue %d (before %d): R %d, its takeoff %d"
			% [day, issue, takeoff, chained, later_takeoff]
		)
	)
	assert_int(issue).is_less(takeoff)
	assert_int(chained).is_equal(later_takeoff)


## An ended contract that still reserves its ground plans, but never delays R.
func test_a_reserving_contract_never_delays_the_release() -> void:
	var contract := _contract("C1", 600)
	var issue := FlightTimetable.issue_tick(contract, 0, 0)
	var running := _world(issue, [contract])
	var ran := SpurMoves.release(running, StandPlacement.WEST)
	var ended := _world(issue, [contract])
	ended["ended"] = {"C1": 0}
	ended["reserving"] = {"C1": true}
	var reserved := SpurMoves.release(ended, StandPlacement.WEST)
	print("running R %d, reserving R %d" % [ran, reserved])
	assert_int(ran).is_equal(FlightTimetable.starts_for(contract, 0, 0)[FlightSim.State.TAKEOFF])
	assert_int(reserved).is_equal(issue)


## The nightly gap: a 22:00 departure on the longest TAXI_OUT takes off at
## 23:50, before a 06:00 departure on the longest TAXI_IN is issued at 01:47
## next day, so R from the evening is that night's 23:50 and a tick inside the
## gap is quiet at once.
func test_the_nightly_gap_bounds_the_release() -> void:
	var late := _contract("LATE", 22 * 60, MAX_PAIR)
	var early := _contract("EARLY", 6 * 60, MAX_PAIR)
	var day := 1
	var late_takeoff := FlightTimetable.starts_for(late, day, 0)[FlightSim.State.TAKEOFF]
	var early_issue := FlightTimetable.issue_tick(early, day + 1, 0)
	print(
		(
			"late takeoff %s day %d, next early issue %s"
			% [
				GameCalendar.clock_text(late_takeoff, 0),
				GameCalendar.day_of(late_takeoff, 0),
				GameCalendar.clock_text(early_issue, 0)
			]
		)
	)
	assert_int(late_takeoff).is_equal(GameCalendar.tick_at(day, 23 * 60 + 50, 0))
	assert_int(early_issue).is_equal(GameCalendar.tick_at(day + 1, 60 + 47, 0))
	var evening := FlightTimetable.issue_tick(late, day, 0)
	var world := _world(evening, [late, early])
	var released := SpurMoves.release(world, StandPlacement.WEST)
	print(
		(
			"from %s: R %s"
			% [GameCalendar.clock_text(evening, 0), GameCalendar.clock_text(released, 0)]
		)
	)
	assert_int(released).is_equal(late_takeoff)
	assert_int(GameCalendar.day_of(released, 0)).is_equal(day)
	(
		assert_int(SpurMoves.release(_world(early_issue - 1, [late, early]), StandPlacement.WEST))
		. is_equal(early_issue - 1)
	)
	var early_takeoff := FlightTimetable.starts_for(early, day + 1, 0)[FlightSim.State.TAKEOFF]
	assert_int(SpurMoves.release(_world(early_issue, [late, early]), StandPlacement.WEST)).is_equal(
		early_takeoff
	)


## A day issued before R keeps the stand and pair it has; a day issued at or
## after R gets the stand on the wanted spur and that stand's own pair.
func test_the_resolver_splits_the_days_at_the_release() -> void:
	var contract := _contract("C1", 600)
	var issue := FlightTimetable.issue_tick(contract, 0, 0)
	var world := _world(
		issue - 1, [contract], [], {"stand": _next, "max_class": PlaneClasses.LARGE}
	)
	var held := _flight("HOLD", FlightSim.schedule_starts(issue - 10), _stand)
	world["flights"] = [held]
	var released := SpurMoves.release(world, StandPlacement.WEST)
	var before := SpurMoves.resolve(world, contract, 0)
	var after := SpurMoves.resolve(world, contract, 1)
	print(
		(
			"R %d; day 0 issue %d: stand x %s pair %s; day 1: stand x %s pair %s"
			% [
				released,
				issue,
				before["stand"]["lane_x"],
				before["contract"]["taxi"],
				after["stand"]["lane_x"],
				after["contract"]["taxi"]
			]
		)
	)
	assert_int(issue).is_less(released)
	assert_dict(before["stand"]).is_equal(_stand)
	assert_array(before["contract"]["taxi"]).is_equal(contract["taxi"])
	assert_dict(after["stand"]).is_equal(_next)
	assert_array(after["contract"]["taxi"]).is_equal(TaxiTimes.for_stand(_next))
	assert_array(after["contract"]["taxi"]).is_not_equal(contract["taxi"])


## refusal() names a running contract whose gate's new stand cannot take its
## plane, by its first day issued from R: with the side quiet a tick before day
## 0 is issued, day 0; from inside day 0's turnaround, day 1.
func test_a_contract_the_new_stand_cannot_take_is_named() -> void:
	var contract := _contract("C1", 600)
	var next := {"stand": _next, "max_class": ""}
	var issue := FlightTimetable.issue_tick(contract, 0, 0)
	var refusal := SpurMoves.refusal(_world(issue - 1, [contract], [], next))
	var later := SpurMoves.refusal(_world(issue, [contract], [], next))
	print("refusal from %d: %s; from %d: %s" % [issue - 1, refusal, issue, later])
	assert_dict(refusal).is_equal({"id": "C1-d0", "reason": SpurMoves.NO_STAND})
	assert_dict(later).is_equal({"id": "C1-d1", "reason": SpurMoves.NO_STAND})
	var fits := _world(issue - 1, [contract], [], {"stand": _next, "max_class": PlaneClasses.SMALL})
	assert_dict(SpurMoves.refusal(fits)).is_empty()


## Two contracts at one gate that clear each other on today's pair but meet
## once both fly the farther spur's longer pair: refusal() names the later one.
func test_a_re_timed_occurrence_that_meets_another_at_its_gate_is_named() -> void:
	var far := StandPlacement.with_lane_x(_stand, -300.0)
	var pair := TaxiTimes.for_stand(_stand)
	var far_pair := TaxiTimes.for_stand(far)
	var first := _contract("C1", 10 * 60)
	# C2 departs as early as clears C1 at the gate on today's pair, plus a minute.
	var held := FlightTimetable.reserved_ticks(pair)
	var gap := ceili(float(held + 20) / 20.0)
	var second := _contract("C2", 10 * 60 + gap)
	assert_bool(FlightTimetable.contracts_share_gate(first, second)).is_false()
	var moved_a := FlightContract.assigned(first, "A", far)
	var moved_b := FlightContract.assigned(second, "A", far)
	print("pairs %s -> %s; C2 departs %d min after C1" % [pair, far_pair, gap])
	assert_bool(FlightTimetable.contracts_share_gate(moved_a, moved_b)).is_true()
	var world := _world(0, [first, second], [], {"stand": far, "max_class": PlaneClasses.LARGE})
	var refusal := SpurMoves.refusal(world)
	print("refusal %s" % [refusal])
	assert_str(refusal.get("reason", "")).is_equal(SpurMoves.GATE_MEETS)
	assert_str(refusal["id"]).starts_with("C2-d")
