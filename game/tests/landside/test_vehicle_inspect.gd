class_name TestVehicleInspect
extends GdUnitTestSuite
## What a selected car or taxi shows (VehicleInspect): its kind and id, what
## it is doing, how many passengers are aboard, their flight and the drop-off
## delay so far. With no entrance nobody gets out, so cars hold in the curb
## berths past their unload tick and the delay grows; empty vehicles say what
## they are doing without a flight or a delay.

const BOOKED := 8

var _land: LandsideTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _land != null:
		_land.free_all()
		_land = null


## The starter road and the reference terminal without its entrance door.
func _world_without_entrance() -> LandsideTestWorld:
	var shell := LandsideTestWorld.SHELL
	var grid := BuildGrid.new(shell.grid_size, shell.grid_origin)
	for edit in ReferenceTerminal.edits(shell):
		if edit.kind != BuildEdit.Kind.PLACE_OBJECT or edit.def_id != &"entrance_door":
			assert_bool(grid.apply(edit).ok).is_true()
	return LandsideTestWorld.make(null, [], 3, grid)


func test_a_car_held_at_the_curb_shows_its_passengers_flight_and_growing_delay() -> void:
	_land = _world_without_entrance()
	_land.schedule(BOOKED)
	var held := 0
	while _land.sim.tick < 6000 and held == 0:
		_land.step()
		for id in _land.landside.vehicle_ids():
			var v := _land.landside.get_vehicle(id)
			if v.stage == LandsideVehicle.Stage.DWELL and _land.sim.tick - _unload(v) > 25 * 20:
				held = id
	assert_int(held).is_greater(0)
	var v := _land.landside.get_vehicle(held)
	var text := VehicleInspect.text(_land.sim.arrivals, _land.world.flights, v, _land.sim.tick)
	@warning_ignore("integer_division")
	var minutes := (_land.sim.tick - _unload(v)) / GameCalendar.TICKS_PER_MINUTE
	print("tick %d: %s" % [_land.sim.tick, text])
	var kind := "Taxi" if v.kind == LandsideVehicle.Kind.TAXI else "Car"
	assert_str(text).starts_with("%s %d   At the curb   " % [kind, held])
	var aboard := "1 passenger" if v.bookings.size() == 1 else "%d passengers" % v.bookings.size()
	assert_str(text).contains(aboard)
	assert_str(text).contains("Flight %s" % PassengerTestWorld.FLIGHT)
	assert_int(minutes).is_greater_equal(25)
	assert_str(text).ends_with("Drop-off delay: %d min" % minutes)


func test_a_car_on_its_way_before_its_unload_tick_is_on_time() -> void:
	_land = LandsideTestWorld.make(null, [], 3)
	_land.schedule(BOOKED)
	var driving := 0
	while _land.sim.tick < 4000 and driving == 0:
		_land.step()
		for id in _land.landside.vehicle_ids():
			var v := _land.landside.get_vehicle(id)
			if (
				v.pos_mm >= 0
				and v.stage == LandsideVehicle.Stage.DRIVE
				and v.lane == LandsideVehicle.Lane.ROAD_IN
			):
				driving = id
	assert_int(driving).is_greater(0)
	var v := _land.landside.get_vehicle(driving)
	var text := VehicleInspect.text(_land.sim.arrivals, _land.world.flights, v, _land.sim.tick)
	print("tick %d unload %d: %s" % [_land.sim.tick, _unload(v), text])
	assert_int(_unload(v)).is_greater(_land.sim.tick)
	assert_str(text).contains("Driving to the")
	assert_str(text).ends_with("On time")


func test_empty_vehicles_say_what_they_do_without_a_flight() -> void:
	var v := LandsideVehicle.new()
	v.id = 7
	var cases := {
		LandsideVehicle.Stage.DWELL: "Car 7   Empty, at the curb",
		LandsideVehicle.Stage.PARKED: "Car 7   Parked, driver away",
		LandsideVehicle.Stage.LEAVE: "Car 7   Empty, leaving",
		LandsideVehicle.Stage.DRIVE: "Car 7   Empty, driving on",
	}
	for stage in cases:
		v.stage = stage
		assert_str(VehicleInspect.text(ArrivalBookings.new(), null, v, 100)).is_equal(cases[stage])


func test_the_delay_reads_in_whole_game_minutes_and_never_on_time_once_late() -> void:
	assert_str(VehicleInspect.delay_text(0)).is_equal("On time")
	assert_str(VehicleInspect.delay_text(-40)).is_equal("On time")
	assert_str(VehicleInspect.delay_text(1)).is_equal("Drop-off delay: under 1 min")
	assert_str(VehicleInspect.delay_text(GameCalendar.TICKS_PER_MINUTE * 12 + 5)).is_equal(
		"Drop-off delay: 12 min"
	)


func _unload(v: LandsideVehicle) -> int:
	return _land.sim.arrivals.get_booking(v.bookings[0]).unload_tick
