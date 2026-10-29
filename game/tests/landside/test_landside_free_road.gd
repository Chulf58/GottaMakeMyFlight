class_name TestLandsideFreeRoad
extends GdUnitTestSuite
## On a free road a car or taxi lets its passengers out exactly when they
## meant to get out: it enters the road LandsideSim.lead_ticks() earlier. A
## passenger that got out at the curb walks from its berth's get-out point
## into door B, and only then is a Passenger record.

const STARTER := preload("res://landside/starter_landside.tres")

var _land: LandsideTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _land != null:
		_land.free_all()
	_land = null


func _bare_sim() -> LandsideSim:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(STARTER)).is_true()
	sim.wallet = Wallet.new()
	return sim


## The tick of the first release event when one vehicle of `intent` enters
## the road on tick `start` and the sim steps on from there.
func _release_tick(sim: LandsideSim, intent: LandsideVehicle.Intent, start: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bookings: Array[int] = [1]
	sim.step(start, true, rng)
	sim.add_vehicle(LandsideVehicle.Kind.CAR, intent, bookings)
	for t in range(start + 1, start + 2000):
		if not sim.step(t, true, rng).is_empty():
			return t
	return -1


func test_a_lone_drop_off_gets_out_exactly_its_lead_after_entering_the_road() -> void:
	var sim := _bare_sim()
	var lead := sim.lead_ticks(LandsideVehicle.Intent.DROP)
	var at := _release_tick(sim, LandsideVehicle.Intent.DROP, 100)
	print("DROP lead=%d released=%d" % [lead, at])
	# To the curb's stop, then pulling in along berth 0's path: the passengers
	# get out once the car stands in the berth, not at the stop.
	var pull_in := sim.paths.berth_stand[0] - STARTER.curb.stop_mm
	assert_int(pull_in).is_greater(0)
	assert_int(lead).is_equal(
		(
			ceili(STARTER.curb.stop_mm / float(LandsideSim.SPEED_MM))
			+ ceili(pull_in / float(LandsideSim.SPEED_MM))
		)
	)
	assert_int(at - 100).is_equal(lead)


func test_a_lone_parking_car_gets_out_in_the_lot_exactly_its_lead_after_entering() -> void:
	var sim := _bare_sim()
	assert_int(sim.lead_ticks(LandsideVehicle.Intent.PARK)).is_equal(
		sim.lead_ticks(LandsideVehicle.Intent.DROP)
	)
	assert_bool(sim.build_lot(0)).is_true()
	var lead := sim.lead_ticks(LandsideVehicle.Intent.PARK)
	var at := _release_tick(sim, LandsideVehicle.Intent.PARK, 100)
	var v := sim.get_vehicle(1)
	print("PARK lead=%d released=%d stage=%d slot=%d" % [lead, at, v.stage, v.stop])
	assert_int(at - 100).is_equal(lead)
	assert_int(v.stage).is_equal(LandsideVehicle.Stage.PARKED)
	assert_int(v.stop).is_equal(0)
	assert_int(sim.free_slots(0)).is_equal(STARTER.lots[0].slots.size() - 1)


func test_a_party_scheduled_with_notice_gets_out_on_its_unload_tick_and_walks_in() -> void:
	_land = LandsideTestWorld.make()
	_land.schedule(1)
	assert_int(_land.sim.passenger_ids().size()).is_equal(0)
	assert_int(_land.sim.pending_spawns()).is_equal(1)
	var unload: int = _land.unload.values()[0]
	_land.run_to(unload)
	print("unload=%d released=%s" % [unload, _land.released])
	assert_array(_land.delays()).is_equal([0])
	assert_int(_land.sim.pending_spawns()).is_equal(0)
	var p := _land.sim.get_passenger(_land.passenger_of.values()[0])
	assert_int(p.stage).is_equal(Passenger.Stage.SPAWNED)
	assert_vector(p.apron[0]).is_equal(STARTER.curb.get_out[0])
	# The walk joins door B's route after its road start: the porch, then in.
	assert_float(p.apron[1].z).is_less(-60.0)
	var ticks := 0
	while p.stage == Passenger.Stage.SPAWNED and ticks < 200:
		_land.step()
		ticks += 1
	print("walked in after %d ticks to %s" % [ticks, p.at])
	assert_int(p.stage).is_not_equal(Passenger.Stage.SPAWNED)
	assert_vector(p.at).is_equal(Vector2i(16, 29))
