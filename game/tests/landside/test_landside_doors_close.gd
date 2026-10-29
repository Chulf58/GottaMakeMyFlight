class_name TestLandsideDoorsClose
extends GdUnitTestSuite
## A booking still in its car or taxi when its flight's doors close is a
## missed flight, counted once, with the cause 'waiting for drop-off': in
## PassengerSim.missed_count(), in the flight's result and in the airport
## rating (unlike a no-show, it is in "missed"). With no entrance it is a
## 'never arrived' no-show, as before. The flight here closes its doors at
## tick 60, before the first car (on the road from tick 1) reaches the curb,
## 94 ticks along the 47 m of road that is baked into the shell.

const BOARDING := 30
const DOORS := 60
const BOOKED := 6

var _land: LandsideTestWorld
var _rating: AirportRating


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_land = LandsideTestWorld.make(null, PassengerTestWorld.starts_with(BOARDING, DOORS), 3)
	_rating = auto_free(AirportRating.new())
	_rating.bind(_land.world.clock, _land.world.flights, _land.sim)


func after_test() -> void:
	_land.free_all()
	_land = null


func test_bookings_still_on_the_road_at_doors_close_are_missed_once_with_the_new_cause() -> void:
	var announced := []
	_land.sim.arrivals.missed.connect(func(flight: String) -> void: announced.append(flight))
	_land.schedule(BOOKED)
	_land.run_to(DOORS - 1)
	var aboard := 0
	for id in _land.landside.vehicle_ids():
		aboard += _land.landside.get_vehicle(id).bookings.size()
	assert_int(aboard).is_equal(BOOKED)
	assert_int(_land.sim.missed_count()).is_equal(0)
	_land.step()
	var summary := FlightResult.summarize(_land.sim, PassengerTestWorld.FLIGHT)
	var day := GameCalendar.day_of(DOORS)
	print("at doors close: %s rating day %s" % [summary, _rating.day_totals(day)])
	assert_int(_land.sim.arrivals.missed_total).is_equal(BOOKED)
	assert_int(_land.sim.missed_count()).is_equal(BOOKED)
	assert_int(_land.sim.made_count()).is_equal(0)
	assert_int(summary["missed"]).is_equal(BOOKED)
	assert_array(summary["reasons"]).is_equal(
		[{"text": FlightResult.WAITING_FOR_DROP_OFF, "count": BOOKED}]
	)
	assert_bool(_land.sim.no_shows.has(PassengerTestWorld.FLIGHT)).is_false()
	assert_int(announced.size()).is_equal(BOOKED)
	assert_int(_rating.day_totals(day)["missed"]).is_equal(BOOKED)
	assert_int(_land.sim.pending_spawns()).is_equal(0)
	# The cars drive on empty: nobody gets out and nothing is counted again.
	_land.run_to(DOORS + 600)
	assert_int(_land.sim.passenger_ids().size()).is_equal(0)
	assert_int(_land.released.size()).is_equal(0)
	assert_int(_land.sim.missed_count()).is_equal(BOOKED)
	assert_int(announced.size()).is_equal(BOOKED)
	assert_int(_rating.day_totals(day)["missed"]).is_equal(BOOKED)
	assert_array(_land.landside.vehicle_ids()).is_empty()


func test_with_no_entrance_they_are_no_shows_not_traffic_misses() -> void:
	_land.free_all()
	var grid := BuildGrid.new(
		LandsideTestWorld.SHELL.grid_size, LandsideTestWorld.SHELL.grid_origin
	)
	for edit in ReferenceTerminal.edits(LandsideTestWorld.SHELL):
		if edit.kind != BuildEdit.Kind.PLACE_OBJECT or edit.def_id != &"entrance_door":
			assert_bool(grid.apply(edit).ok).is_true()
	_land = LandsideTestWorld.make(null, PassengerTestWorld.starts_with(BOARDING, DOORS), 3, grid)
	assert_array(_land.sim.layout.entrances).is_empty()
	_land.schedule(BOOKED)
	_land.run_to(DOORS + 5)
	var counts: Dictionary = _land.sim.no_shows[PassengerTestWorld.FLIGHT]
	print("no entrance: no-shows %s missed %d" % [counts, _land.sim.missed_count()])
	assert_int(counts["no_entrance"]).is_equal(BOOKED)
	assert_int(_land.sim.arrivals.missed_total).is_equal(0)
	assert_int(_land.sim.missed_count()).is_equal(0)
	var reasons: Array = FlightResult.summarize(_land.sim, PassengerTestWorld.FLIGHT)["reasons"]
	assert_array(reasons).is_equal([{"text": FlightResult.NEVER_ARRIVED, "count": BOOKED}])
