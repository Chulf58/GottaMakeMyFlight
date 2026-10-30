class_name TestLandsideBuildState
extends GdUnitTestSuite
## What the landside build tools change in LandsideSim (Landside 3/4): a
## multi-storey holds 31 cars to a surface lot's 12, a closed car park
## takes no new arrivals and drains, it can be removed only once it is empty,
## curb bays add berths, and the built, closed and paid state survives a save
## (decision landside-technical-design-arrival-bookings-landsidesim-vehic,
## point 7).

const STARTER := preload("res://landside/starter_landside.tres")
const SURFACE := 0
const MULTI_STOREY := 1

var _sim: LandsideSim
var _rng := RandomNumberGenerator.new()
var _next_booking := 1


func before_test() -> void:
	_sim = auto_free(LandsideSim.new())
	assert_bool(_sim.use_definition(STARTER)).is_true()
	_sim.wallet = Wallet.new(0)
	_rng.seed = 7
	_next_booking = 1


## One car with a party aboard, handed to the sim now.
func _car(intent: LandsideVehicle.Intent) -> int:
	var bookings: Array[int] = [_next_booking]
	_next_booking += 1
	return _sim.add_vehicle(LandsideVehicle.Kind.CAR, intent, bookings)


## Steps the sim over ticks [from, to).
func _run(from: int, to: int, can_release := true) -> void:
	for t in range(from, to):
		_sim.step(t, can_release, _rng)


## The latest tick a parked car leaves on.
func _last_leave() -> int:
	var latest := 0
	for id in _sim.vehicle_ids():
		latest = maxi(latest, _sim.get_vehicle(id).leave_tick)
	return latest


func _in_lane(lane: LandsideVehicle.Lane) -> int:
	var count := 0
	for id in _sim.vehicle_ids():
		count += int(_sim.get_vehicle(id).lane == lane)
	return count


## The multi-storey holds 31 cars, one in each painted stall of its upper decks
## and 9 on the ground floor clear of the hatched zone (decision
## multi-storey-car-park-slots-fit-the-painted-stalls); the surface lot 12.
func test_a_multi_storey_fills_its_31_slots_then_diverts() -> void:
	assert_int(STARTER.lots[SURFACE].slots.size()).is_equal(12)
	assert_int(STARTER.lots[MULTI_STOREY].slots.size()).is_equal(31)
	assert_int(STARTER.lots[MULTI_STOREY].kind).is_equal(LandsideLotSpot.Kind.MULTI_STOREY)
	assert_bool(_sim.build_lot(MULTI_STOREY)).is_true()
	var parked: Array[int] = []
	var diverted: Array[int] = []
	_sim.parked.connect(func(_id: int, lot: int) -> void: parked.append(lot))
	_sim.diverted.connect(func(id: int) -> void: diverted.append(id))
	for i in 40:
		_car(LandsideVehicle.Intent.PARK)
	_run(1, 2500)
	var free := _sim.free_slots(MULTI_STOREY)
	print("parked %d diverted %d free %d" % [parked.size(), diverted.size(), free])
	assert_int(parked.size()).is_equal(31)
	assert_int(parked.count(MULTI_STOREY)).is_equal(31)
	assert_int(diverted.size()).is_equal(9)
	assert_int(_sim.free_slots(MULTI_STOREY)).is_equal(0)
	assert_int(_sim.wallet.balance).is_equal(31 * LandsideSim.SURFACE_LOT_FEE)


func test_a_surface_lot_holds_its_twelve() -> void:
	assert_bool(_sim.build_lot(SURFACE)).is_true()
	var parked: Array[int] = []
	_sim.parked.connect(func(_id: int, lot: int) -> void: parked.append(lot))
	for i in 14:
		_car(LandsideVehicle.Intent.PARK)
	_run(1, 2500)
	assert_int(parked.size()).is_equal(12)
	assert_int(_sim.free_slots(SURFACE)).is_equal(0)


func test_a_closed_car_park_takes_no_new_arrivals_and_drains_then_goes() -> void:
	assert_bool(_sim.build_lot(SURFACE, 1200)).is_true()
	for i in 3:
		_car(LandsideVehicle.Intent.PARK)
	_run(1, 1500)
	assert_int(_sim.lot_cars(SURFACE)).is_equal(3)
	assert_bool(_sim.set_lot_closed(SURFACE, true)).is_true()
	assert_bool(_sim.lot_open(SURFACE)).is_false()
	# A car arriving now means to drop at the curb: the closed lot is not offered.
	var late := _car(LandsideVehicle.Intent.PARK)
	assert_int(_sim.get_vehicle(late).intent).is_equal(LandsideVehicle.Intent.DROP)
	assert_int(_sim.lead_ticks(LandsideVehicle.Intent.PARK)).is_equal(
		_sim.lead_ticks(LandsideVehicle.Intent.DROP)
	)
	var balance := _sim.wallet.balance
	_run(1500, 2600)
	assert_int(_sim.lot_cars(SURFACE)).is_equal(3)
	assert_int(_sim.wallet.balance).is_equal(balance)
	# Removal is refused while its cars are in it, and changes nothing.
	assert_bool(_sim.remove_lot(SURFACE)).is_false()
	assert_bool(_sim.lots_built[SURFACE]).is_true()
	assert_bool(_sim.lots_closed[SURFACE]).is_true()
	assert_int(_sim.lots_paid[SURFACE]).is_equal(1200)
	# The cars leave on their own leave ticks; then the lot can go.
	var end := _last_leave()
	_run(end, end + 800)
	print("after the last leave tick %d: cars in the lot %d" % [end, _sim.lot_cars(SURFACE)])
	assert_int(_sim.lot_cars(SURFACE)).is_equal(0)
	assert_bool(_sim.remove_lot(SURFACE)).is_true()
	assert_bool(_sim.lots_built[SURFACE]).is_false()
	assert_bool(_sim.lots_closed[SURFACE]).is_false()
	assert_int(_sim.lots_paid[SURFACE]).is_equal(0)


func test_a_car_on_its_way_when_the_lot_closes_goes_to_the_curb_instead() -> void:
	assert_bool(_sim.build_lot(SURFACE)).is_true()
	var parked: Array[int] = []
	_sim.parked.connect(func(_id: int, lot: int) -> void: parked.append(lot))
	_car(LandsideVehicle.Intent.PARK)
	# The lot's turn is 15 m in (30 ticks); close it before the car gets there.
	_run(1, 10)
	assert_bool(_sim.set_lot_closed(SURFACE, true)).is_true()
	_run(10, 1500)
	assert_int(parked.size()).is_equal(0)
	assert_int(_sim.wallet.balance).is_equal(0)
	assert_int(_sim.lot_cars(SURFACE)).is_equal(0)


func test_a_reopened_car_park_takes_arrivals_again() -> void:
	assert_bool(_sim.build_lot(SURFACE)).is_true()
	assert_bool(_sim.set_lot_closed(SURFACE, true)).is_true()
	assert_bool(_sim.set_lot_closed(SURFACE, false)).is_true()
	var parked: Array[int] = []
	_sim.parked.connect(func(_id: int, lot: int) -> void: parked.append(lot))
	_car(LandsideVehicle.Intent.PARK)
	_run(1, 1500)
	assert_array(parked).is_equal([SURFACE])


func test_an_unbuilt_car_park_cannot_be_closed_or_removed() -> void:
	assert_bool(_sim.set_lot_closed(SURFACE, true)).is_false()
	assert_bool(_sim.remove_lot(SURFACE)).is_false()
	assert_bool(_sim.set_lot_closed(9, true)).is_false()
	assert_bool(_sim.remove_curb(0)).is_false()


## Cars that stay in their berths (nobody gets out), as many as are handed over.
func _berthed(cars: int) -> int:
	for i in cars:
		_car(LandsideVehicle.Intent.DROP)
	_run(1, 800, false)
	return _in_lane(LandsideVehicle.Lane.BERTH)


func test_curb_bays_add_berths_to_the_starter_curb() -> void:
	assert_int(STARTER.berth_count()).is_equal(8)
	assert_int(_berthed(9)).is_equal(4)
	before_test()
	assert_bool(_sim.build_curb(0, 300)).is_true()
	assert_int(_berthed(9)).is_equal(6)
	before_test()
	assert_bool(_sim.build_curb(0, 300)).is_true()
	assert_bool(_sim.build_curb(1, 300)).is_true()
	assert_int(_berthed(9)).is_equal(8)


func test_a_built_bay_moves_the_queue_stop_upstream_of_its_first_berth() -> void:
	assert_int(_sim.curb_stop_mm()).is_equal(STARTER.curb.stop_mm)
	# Bay 0's first berth is at x 7.25 (35750 mm in), bay 1's at x 23.25 (19750 mm).
	assert_int(STARTER.berth_mm(5)).is_equal(35750)
	assert_int(STARTER.berth_mm(7)).is_equal(19750)
	assert_bool(_sim.build_curb(0, 300)).is_true()
	assert_int(_sim.curb_stop_mm()).is_equal(35750 - LandsideSim.BERTH_APPROACH_MM)
	assert_bool(_sim.build_curb(1, 300)).is_true()
	assert_int(_sim.curb_stop_mm()).is_equal(19750 - LandsideSim.BERTH_APPROACH_MM)
	assert_bool(_sim.remove_curb(1)).is_true()
	assert_int(_sim.curb_stop_mm()).is_equal(35750 - LandsideSim.BERTH_APPROACH_MM)
	# The starter curb's stop is the same distance before its first berth.
	assert_int(STARTER.berth_mm(0) - LandsideSim.BERTH_APPROACH_MM).is_equal(STARTER.curb.stop_mm)


func test_cars_take_the_first_berth_they_reach_driving_on() -> void:
	assert_bool(_sim.build_curb(1, 300)).is_true()
	for i in 3:
		_car(LandsideVehicle.Intent.DROP)
	_run(1, 800, false)
	var standing: Array[Vector3] = []
	for id in _sim.vehicle_ids():
		var v := _sim.get_vehicle(id)
		assert_int(v.lane).is_equal(LandsideVehicle.Lane.BERTH)
		standing.append(_sim.world_position(v))
	# The east-most berth of the built bay first, then its other, then the
	# starter curb's nearest berth.
	(
		assert_array(standing)
		. contains_exactly_in_any_order(
			[
				STARTER.curb_spots[1].berths[1],
				STARTER.curb_spots[1].berths[0],
				STARTER.curb.berths[0],
			]
		)
	)


func test_a_car_never_reverses_into_a_berth_or_lands_on_the_queue() -> void:
	assert_bool(_sim.build_curb(0, 300)).is_true()
	assert_bool(_sim.build_curb(1, 300)).is_true()
	for i in 14:
		_car(LandsideVehicle.Intent.DROP)
	var entered := 0
	for t in range(1, 1500):
		var before := {}
		for id in _sim.vehicle_ids():
			var v := _sim.get_vehicle(id)
			if v.lane == LandsideVehicle.Lane.ROAD_IN:
				before[id] = v.pos_mm
		_sim.step(t, true, _rng)
		for id in before:
			var v := _sim.get_vehicle(id)
			if v == null or v.lane != LandsideVehicle.Lane.BERTH:
				continue
			entered += 1
			var at := STARTER.berth_mm(v.stop)
			assert_int(at).override_failure_message("car %d reversed" % id).is_greater_equal(
				before[id]
			)
			for other in _sim.vehicle_ids():
				var queued := _sim.get_vehicle(other)
				if queued.lane == LandsideVehicle.Lane.ROAD_IN:
					assert_int(queued.pos_mm).is_less(at)
	assert_int(entered).is_equal(14)


func test_a_car_past_a_bay_does_not_go_back_to_it() -> void:
	# A car that has driven on past bay 0 (a diverted car at the multi-storey's
	# turn, 39500 mm in) takes a starter berth, not the free bay behind it.
	assert_bool(_sim.build_curb(0, 300)).is_true()
	assert_bool(_sim.build_lot(MULTI_STOREY, 5000)).is_true()
	for i in 40:
		_car(LandsideVehicle.Intent.PARK)
	_run(1, 2500, false)
	var in_berths := 0
	for id in _sim.vehicle_ids():
		var v := _sim.get_vehicle(id)
		if v.lane == LandsideVehicle.Lane.BERTH:
			in_berths += 1
			# Starter berths only (0 to 3): bay 0's are behind the diverted cars.
			assert_int(v.stop).is_less(4)
	assert_int(in_berths).is_equal(4)


func test_lead_ticks_follow_the_lot_a_new_car_will_take() -> void:
	assert_bool(_sim.build_lot(SURFACE, 1200)).is_true()
	assert_bool(_sim.build_lot(MULTI_STOREY, 5000)).is_true()
	var surface_lead := _sim.lead_ticks(LandsideVehicle.Intent.PARK)
	var multi := STARTER.lots[MULTI_STOREY]
	var access_mm := LandsideDefinition.length_mm(multi.access)
	# The drive includes pulling in along slot 0's path, from the gate to the
	# stall: the passengers get out once the car stands there.
	var multi_lead := (
		ceili(float(multi.branch_mm) / LandsideSim.SPEED_MM)
		+ ceili(float(access_mm) / LandsideSim.SPEED_MM)
		+ ceili(float(_sim.paths.slot_stand[MULTI_STOREY][0] - access_mm) / LandsideSim.SPEED_MM)
	)
	assert_int(multi_lead).is_not_equal(surface_lead)
	# Fill the surface lot, which a car reaches first.
	for i in 12:
		_car(LandsideVehicle.Intent.PARK)
	_run(1, 1000)
	assert_int(_sim.free_slots(SURFACE)).is_equal(0)
	assert_int(_sim.lead_ticks(LandsideVehicle.Intent.PARK)).is_equal(multi_lead)
	# A car handed over that long before its unload tick gets out on it.
	var id := _car(LandsideVehicle.Intent.PARK)
	var released := -1
	for t in range(1000, 2000):
		for event in _sim.step(t, true, _rng):
			if event["vehicle"] == id:
				released = t
		if released >= 0:
			break
	assert_int(_sim.get_vehicle(id).lot).is_equal(MULTI_STOREY)
	assert_int(released - 999).is_equal(multi_lead)


func test_a_curb_bay_with_a_car_in_it_cannot_be_removed() -> void:
	assert_bool(_sim.build_curb(0, 300)).is_true()
	assert_int(_berthed(6)).is_equal(6)
	assert_int(_sim.curb_cars(0)).is_equal(2)
	assert_bool(_sim.remove_curb(0)).is_false()
	assert_bool(_sim.curbs_built[0]).is_true()
	assert_int(_sim.curbs_paid[0]).is_equal(300)
	# The passengers get out and the cars drive on; then the bay can go.
	_run(800, 1400)
	assert_int(_sim.curb_cars(0)).is_equal(0)
	assert_bool(_sim.remove_curb(0)).is_true()
	assert_bool(_sim.curbs_built[0]).is_false()
	assert_int(_sim.curbs_paid[0]).is_equal(0)


func test_built_closed_and_paid_state_survives_a_save() -> void:
	assert_bool(_sim.build_lot(SURFACE, 1200)).is_true()
	assert_bool(_sim.build_lot(MULTI_STOREY, 5000)).is_true()
	assert_bool(_sim.set_lot_closed(SURFACE, true)).is_true()
	assert_bool(_sim.build_curb(1, 300)).is_true()
	_car(LandsideVehicle.Intent.PARK)
	_car(LandsideVehicle.Intent.DROP)
	_run(1, 1500)
	var data := _sim.to_snapshot(ArrivalBookings.new(), 1500)
	var text := JSON.stringify(data)
	# Through JSON, so whole numbers come back as floats.
	var loaded: Dictionary = JSON.parse_string(text)
	var other: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(other.use_definition(STARTER)).is_true()
	assert_bool(other.from_snapshot(loaded, ArrivalBookings.new())).is_true()
	assert_array(other.lots_built).is_equal([true, true])
	assert_array(other.lots_closed).is_equal([true, false])
	assert_array(other.lots_paid).is_equal([1200, 5000])
	assert_array(other.curbs_built).is_equal([false, true])
	assert_array(other.curbs_paid).is_equal([0, 300])
	assert_str(JSON.stringify(other.to_snapshot(ArrivalBookings.new(), 1500))).is_equal(text)
	# The restored sim keeps the lot closed: a new car does not park.
	assert_bool(other.lot_open(SURFACE)).is_false()
	assert_bool(other.lot_open(MULTI_STOREY)).is_true()


func test_a_car_in_a_bay_berth_loads_with_the_bay_built() -> void:
	assert_bool(_sim.build_curb(0, 300)).is_true()
	assert_int(_berthed(6)).is_equal(6)
	# The passengers get out (no booking is left to save), the cars still dwell.
	_run(800, 830)
	assert_int(_sim.curb_cars(0)).is_equal(2)
	var data := _sim.to_snapshot(ArrivalBookings.new(), 830)
	assert_bool(LandsideSnapshot.load(data, STARTER).has("error")).is_false()
	var gone := data.duplicate(true)
	gone["curbs_built"] = [false, false]
	gone["curbs_paid"] = [0, 0]
	var refused := LandsideSnapshot.load(gone, STARTER)
	print("bay gone with a car in it: %s" % refused.get("error", "LOADED"))
	assert_str(str(refused.get("error", ""))).contains("curb")


func test_a_part_with_the_build_state_wrong_is_refused_whole() -> void:
	assert_bool(_sim.build_lot(SURFACE, 1200)).is_true()
	var data := _sim.to_snapshot(ArrivalBookings.new(), 0)
	var nothing := "a spot with nothing built is closed or has a price"
	var prices := "whole prices, 0 or more"
	# Each case: the keys it breaks and the error it must be refused with.
	var cases := {
		"closed with nothing built": [{"lots_closed": [false, true]}, nothing],
		"a price with nothing built": [{"lots_paid": [1200, 500]}, nothing],
		"a negative price": [{"lots_paid": [-1200, 0]}, prices],
		"a fractional price": [{"lots_paid": [1200.5, 0]}, prices],
		"too few lot entries": [{"lots_closed": [false]}, "lots_closed must be an array"],
		"too many curb entries": [{"curbs_built": [false, false, false]}, "curbs_built must be"],
		"a curb price with no bay": [{"curbs_paid": [300, 0]}, nothing],
		"a flag that is not true or false": [{"curbs_built": [0, 0]}, "must hold true or false"],
	}
	for name in cases:
		var bad := data.duplicate(true)
		for key in cases[name][0]:
			bad[key] = cases[name][0][key]
		var loaded := LandsideSnapshot.load(bad, STARTER)
		print("%s: %s" % [name, loaded.get("error", "LOADED")])
		assert_str(str(loaded.get("error", ""))).override_failure_message(name).contains(
			cases[name][1]
		)
	assert_bool(LandsideSnapshot.load(data, STARTER).has("error")).is_false()
