class_name TestArrivalShares
extends GdUnitTestSuite
## Shoppers and Rush crowd change a contract flight's arrival shares
## (ArrivalTypes.shares_for), resolved once in PassengerSim.schedule_flight and
## used by both ways of arriving: straight into the terminal, and by car or taxi
## through the landside. Each passenger or party makes the same draws whatever
## the shares, so with one seed a traited flight's rushed (or relaxed) arrivals
## are a superset of the plain flight's.

## 10:20: the occurrence is issued at tick 140 and scheduled then.
const CONTRACT := "ARR"
const OCCURRENCE := "ARR-d0"
const MINUTE := 620
const ISSUED := 140
const BOOKED := 48
const RUSH := {"up": "top_fare", "down": "rush_crowd", "level": 2}
const SHOP := {"up": "shoppers", "down": "heavy_bags", "level": 1}

var _worlds: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func test_shares_follow_the_traits_and_always_sum_to_100() -> void:
	assert_array(ArrivalTypes.shares_for({})).is_equal(ArrivalTypes.SHARES)
	assert_array(ArrivalTypes.shares_for(RUSH)).is_equal([45, 25, 30])
	assert_array(ArrivalTypes.shares_for(SHOP)).is_equal([15, 40, 45])
	var big_shop := {"up": "shoppers", "down": "heavy_bags", "level": 2}
	assert_array(ArrivalTypes.shares_for(big_shop)).is_equal([15, 30, 55])
	var rush_1 := {"up": "full_flight", "down": "rush_crowd", "level": 1}
	assert_array(ArrivalTypes.shares_for(rush_1)).is_equal([30, 40, 30])


## Arrival type counts [rushed, typical, relaxed] of the occurrence's
## passengers, scheduled straight into the terminal.
func _terminal_counts(traits: Dictionary) -> Array[int]:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(100000), 9)
	_worlds.append(world)
	_accept(world.flights, traits)
	world.run_to(ISSUED + 1)
	var counts: Array[int] = [0, 0, 0]
	for entry in world.sim._schedule:
		if entry["flight"] == OCCURRENCE:
			counts[entry["arrival"]] += 1
	assert_int(counts[0] + counts[1] + counts[2]).is_equal(BOOKED)
	return counts


## The same, booked by car or taxi through the landside.
func _landside_counts(traits: Dictionary) -> Array[int]:
	var land := LandsideTestWorld.make(null, FlightSim.schedule_starts(100000), 9)
	_worlds.append(land.world)
	_accept(land.world.flights, traits)
	land.run_to(ISSUED + 1)
	var counts: Array[int] = [0, 0, 0]
	for id in land.sim.arrivals.booking_ids():
		var booking := land.sim.arrivals.get_booking(id)
		if booking.flight_id == OCCURRENCE:
			counts[booking.arrival] += 1
	assert_int(counts[0] + counts[1] + counts[2]).is_equal(BOOKED)
	return counts


func _accept(flights: FlightSim, traits: Dictionary) -> void:
	flights.open_airport()
	var terms := TestFlightContracts.terms(CONTRACT, MINUTE)
	terms["booked_passengers"] = BOOKED
	terms["traits"] = traits
	assert_bool(flights.accept_contract(terms)).is_true()


func test_rush_crowd_brings_more_rushed_passengers_into_the_terminal() -> void:
	var plain := _terminal_counts({})
	var rush := _terminal_counts(RUSH)
	assert_int(rush[0]).is_greater(plain[0])
	assert_int(rush[2]).is_equal(plain[2])


func test_shoppers_bring_more_relaxed_passengers_into_the_terminal() -> void:
	var plain := _terminal_counts({})
	var shop := _terminal_counts(SHOP)
	assert_int(shop[2]).is_greater(plain[2])
	assert_int(shop[0]).is_equal(plain[0])


func test_rush_crowd_and_shoppers_change_the_landside_parties_too() -> void:
	var plain := _landside_counts({})
	var rush := _landside_counts(RUSH)
	var shop := _landside_counts(SHOP)
	assert_int(rush[0]).is_greater(plain[0])
	assert_int(shop[2]).is_greater(plain[2])
