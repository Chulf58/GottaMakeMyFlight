class_name TestApronWalkPlaneDoor
extends GdUnitTestSuite
## A passenger's walk out to the plane ends beside its own plane's drawn door
## (decision plane-04-stops-further-out-with-the-passenger-walk-ending-at):
## model 04 parks further out than door alignment puts it, so a passenger of a
## flight drawn with it walks on past the stand's door to the 04's, and the
## lateness forecast prices that same walk. A flight drawn with another model
## keeps the stand's door (StandPlacement.door_point()).

const SITE := preload("res://build/terminal_site.tres")
const MODEL_04 := "tp_plane_04a"
## An airline whose medium flights draw model 04 (test_plane_classes.gd).
const AIRLINE_04 := "Meridian Air"
const ONE_OFF_LATER_MIN := 240
## How far along the plane a walk end may lie from its plane's drawn door: the
## stand's door is 0.18 m from model 05's (StandPlacement.DOOR_AFT_M).
const MAX_ALONG_M := 0.2
## The terminal below stands where the starter does, moved by the site's
## starter_offset, so the plane stand is just north of its exit.
var _entrance := Vector2i(16, 29) + SITE.starter_offset
var _exit_cell := Vector2i(16, 0) + SITE.starter_offset

var _world: PassengerTestWorld
var _exit := 0
var _flight_04 := ""


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var off := SITE.starter_offset
	for y in range(0, 30):
		for x in range(12, 21):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y) + off, BuildGrid.FLOOR_TILE, 1))
	PassengerTestWorld.place(grid, &"entrance_door", _entrance, 2)
	_exit = PassengerTestWorld.place(grid, &"exit_door", _exit_cell, 0)
	EnclosureKit.close_floor(grid)
	# The one-off flight leaves four hours after the 04's, so the two do not
	# clash at the gate.
	_world = PassengerTestWorld.make(
		grid, FlightSim.schedule_starts(ONE_OFF_LATER_MIN * GameCalendar.TICKS_PER_MINUTE)
	)
	_world.sim.site = SITE
	_world.flights.open_airport()
	var terms := {
		"id": "C04",
		"airline": AIRLINE_04,
		"destination": "Oslo",
		"departure_minute": TestFlightContracts.bootstrap_minute(),
		"plane_size": PlaneClasses.MEDIUM,
		"booked_passengers": 40,
		"fee_per_passenger": 25,
	}
	var problem := _world.flights.accept_problem(terms)
	assert_str(problem).is_empty()
	assert_bool(_world.flights.accept_contract(terms)).is_true()
	_flight_04 = ""
	for id in _world.flights.flight_ids():
		if _world.flights.flight_contract_id(id) == "C04":
			_flight_04 = id


func after_test() -> void:
	_world.free_all()
	_world = null


func test_a_plane_04_passenger_walks_out_to_the_04s_drawn_door() -> void:
	assert_str(_flight_04).is_not_empty()
	assert_str(PlaneClasses.flight_model(_world.flights, _flight_04)).is_equal(MODEL_04)
	var stand := _world.sim.layout.live_stand(_world.grid)
	var p := _stepped_out(_flight_04)
	var end: Vector3 = p.apron.back()
	var door := _drawn_door(stand, MODEL_04)
	# The stand's walk end stands beside model 05's drawn door (0.18 m along it,
	# 2.13 m out on the apron); the 04's walk end stands the same way beside the
	# 04's drawn door.
	var reference := _drawn_door(stand, PlaneClasses.REFERENCE_MODEL)
	var stand_end := StandPlacement.door_point(stand)
	print(
		(
			(
				"04 walk end %s, 04 drawn door %s: %.3f m along the plane, %.3f m across;"
				+ " stand walk end %s, 05 drawn door %s: %.3f m along, %.3f m across; 04 end"
				+ " past the stand's %.3f m"
			)
			% [
				end,
				door,
				absf(end.z - door.z),
				absf(end.x - door.x),
				stand_end,
				reference,
				absf(stand_end.z - reference.z),
				absf(stand_end.x - reference.x),
				stand_end.z - end.z,
			]
		)
	)
	assert_float(absf(end.z - door.z)).is_less(MAX_ALONG_M)
	assert_float(absf(end.z - door.z)).is_equal_approx(absf(stand_end.z - reference.z), 0.01)
	assert_float(absf(end.x - door.x)).is_equal_approx(absf(stand_end.x - reference.x), 0.01)
	# The 04 really parks further out than the stand's door (the control).
	assert_float(stand_end.z - end.z).is_greater(1.0)


func test_a_one_off_flights_passenger_keeps_the_stands_door() -> void:
	var stand := _world.sim.layout.live_stand(_world.grid)
	var p := _stepped_out(PassengerTestWorld.FLIGHT)
	var end: Vector3 = p.apron.back()
	print("one-off walk end %s, stand door %s" % [end, StandPlacement.door_point(stand)])
	assert_float(Vector2(end.x, end.z).distance_to(_xz(StandPlacement.door_point(stand)))).is_less(
		0.01
	)


## The forecast prices the walk the passenger will take: its plane key and its
## time to the plane are those of the 04's own walk, not the stand door's.
func test_the_forecast_prices_the_walk_to_the_04s_door() -> void:
	var p := _world.passenger(_world.sim.spawn_now(_flight_04))
	p.stage = Passenger.Stage.TO_EXIT
	p.exit_object = _exit
	p.at = _world.sim.layout.door_cell(_world.grid, _exit)
	var own := JourneyForecast.own_times(_world.sim, p, 0, true)
	var walk := Passenger.new()
	walk.apron.assign(OutsideWalks.departure(_world.sim, _exit, MODEL_04))
	var stand_walk := Passenger.new()
	stand_walk.apron.assign(OutsideWalks.departure(_world.sim, _exit))
	print(
		(
			"forecast plane %s at tick %d; 04 walk %d mm ends %s, stand walk %d mm"
			% [
				own["plane"],
				own["plane_tick"],
				walk.apron_total_mm(),
				walk.apron.back(),
				stand_walk.apron_total_mm()
			]
		)
	)
	assert_that(own["plane"]).is_equal(BoardingFiles.plane_key(walk.apron.back()))
	assert_int(own["plane_tick"]).is_equal(JourneyForecast.walk_ticks(walk.apron_total_mm()))
	assert_int(walk.apron_total_mm()).is_greater(stand_walk.apron_total_mm() + 1000)


## A passenger of `flight` standing in the exit's cell, stepped out onto its
## walk to the plane (PassengerGates.step_out()).
func _stepped_out(flight: String) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(flight))
	p.stage = Passenger.Stage.TO_EXIT
	p.exit_object = _exit
	p.at = _world.sim.layout.door_cell(_world.grid, _exit)
	PassengerGates.step_out(_world.sim, p)
	assert_int(p.stage).is_equal(Passenger.Stage.APRON)
	assert_bool(p.apron.is_empty()).is_false()
	return p


## Where `model`'s front port door is drawn when it is parked at `stand`, on
## the ground.
func _drawn_door(stand: Dictionary, model: String) -> Vector3:
	var door: Vector3 = (
		StandPlacement.stand_point(stand)
		+ PlaneClasses.stand_offset(model)
		+ PlaneModels.PLANES[model]["doors"][0]
	)
	return Vector3(door.x, 0.0, door.z)


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
