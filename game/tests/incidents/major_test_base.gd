class_name MajorTestBase
extends GdUnitTestSuite
## The world the major incident suites share (TestIncidentMajors, TestIncidentMajorsVip;
## board 03e71ed7): a bare reference world with one small contract "AM" (booked
## 12 of at most 16, so 4 extra fit) departing 08:00 from day 0, an open
## airport and the clock never advanced, so the days after day 0 are not
## issued yet; a rating and a director bound to it. Each case drives the
## director's on_tick by hand.

const DEPARTS := 480
const BOOKED := 12
const HEADROOM := 4
const CONTRACT := "AM"
## The issued one-off flights: the VIP flies on the first, the second is another.
const VIP_FLIGHT := PassengerTestWorld.FLIGHT
const OTHER_FLIGHT := "GMF202"

var _world: PassengerTestWorld
var _director: IncidentDirector
var _rating: AirportRating
var _presented: Array[Dictionary] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_presented.clear()
	_world = PassengerTestWorld.reference_world(7311042)
	_world.flights.open_airport()
	var terms := TestFlightContracts.terms(CONTRACT, DEPARTS)
	terms["plane_size"] = "small"
	terms["booked_passengers"] = BOOKED
	assert_bool(_world.flights.accept_contract(terms)).is_true()
	assert_bool(_world.flights.add_flight(OTHER_FLIGHT, FlightSim.schedule_starts(0))).is_true()
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_director = auto_free(IncidentDirector.new()) as IncidentDirector
	_director.rating = _rating
	_director.bind(_world.clock, _world.flights, _world.sim)
	_director.major_presented.connect(func(i: Dictionary) -> void: _presented.append(i))


func after_test() -> void:
	_world.free_all()


## Rolls the forced `kind` on day 1 and fires it: the incident as presented.
func _presented_major(kind: String) -> Dictionary:
	_director.set_enabled(true)
	_director.forced_kind = kind
	_director.on_tick(GameCalendar.day_start(1))
	var rolled := _director.incidents()
	assert_int(rolled.size()).is_equal(1)
	assert_str(rolled[0]["state"]).is_equal(IncidentCatalogue.SCHEDULED)
	_director.on_tick(rolled[0]["fire_tick"])
	return _record(rolled[0]["id"])


func _record(id: int) -> Dictionary:
	for incident in _director.incidents():
		if incident["id"] == id:
			return incident
	return {}


## An accepted VIP waiting for its passenger, put in through the director's load.
## `plan_values` replace the tuning values the plan is made with.
func _accepted_vip(flight: String, plan_values := {}) -> int:
	var plan := {
		"flight": flight,
		"departs": 1,
		"bonus": IncidentTuning.VIP_BONUS_MONEY,
		"good_mood": IncidentTuning.VIP_GOOD_MOOD,
		"miss_half_stars": IncidentTuning.VIP_MISS_HALF_STARS,
		"target": 0,
	}
	plan.merge(plan_values, true)
	var data := _director.to_snapshot()
	var id: int = data["next_id"]
	data["next_id"] = id + 1
	data["enabled"] = true
	(
		(data["incidents"] as Array)
		. append(
			{
				"id": id,
				"kind": IncidentCatalogue.VIP,
				"roll_day": 1,
				"state": IncidentCatalogue.ACCEPTED,
				"fire_tick": 0,
				"cell": [-1, -1],
				"mess_id": 0,
				"place": "",
				"outcome": "",
				"shown": false,
				"plan": plan,
			}
		)
	)
	assert_bool(_director.from_snapshot(data)).is_true()
	return id


func _balance() -> int:
	return _world.sim.wallet.balance


## Three messes on the floor at distinct cells, found by scanning the grid.
func _add_messes(count: int) -> void:
	var grid := _world.grid
	var made := 0
	for y in grid.size.y:
		for x in grid.size.x:
			var cell := Vector2i(x, y)
			if made < count and grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
				if MessSim.approach_for(grid, cell) != MessSim.NO_CELL:
					if _world.sim.messes.add(MessSim.Kind.SPILL, cell) != 0:
						made += 1
	assert_int(_world.sim.messes.mess_count()).is_equal(count)
