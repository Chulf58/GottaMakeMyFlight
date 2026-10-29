class_name TestLandsideSlotSaves
extends GdUnitTestSuite
## Saves and views of cars on a parking slot's path (LandsidePaths). A save
## breaking the car park rule LandsideSim keeps (one car pulls out at a time,
## none pulls in meanwhile) is refused; a save taken on the very tick a parked
## car was let go loads and drives on as the unsaved world does; a car on its
## slot's path faces the way it drives, not into the stall, at the gate and
## after a paused load. Bare LandsideSims on the starter road with the surface
## lot built, stepped by hand.

const STARTER := preload("res://landside/starter_landside.tres")
const SURFACE := 0

var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_rng.seed = 9


func _sim() -> LandsideSim:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(STARTER)).is_true()
	sim.wallet = Wallet.new()
	assert_bool(sim.build_lot(SURFACE)).is_true()
	return sim


func _car(sim: LandsideSim, booking: int) -> int:
	var bookings: Array[int] = [booking]
	return sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings)


## Steps from `from` until `done` holds or `limit` ticks; the next tick.
func _until(sim: LandsideSim, from: int, limit: int, done: Callable) -> int:
	var t := from
	while t < from + limit and not done.call():
		sim.step(t, true, _rng)
		t += 1
	return t


func _parked(sim: LandsideSim) -> int:
	var count := 0
	for id in sim.vehicle_ids():
		count += int(sim.get_vehicle(id).stage == LandsideVehicle.Stage.PARKED)
	return count


## The JSON text of `sim`'s save part, as a save file holds it.
func _save(sim: LandsideSim, at_tick: int) -> Dictionary:
	return JSON.parse_string(JSON.stringify(sim.to_snapshot(ArrivalBookings.new(), at_tick)))


func _record(data: Dictionary, id: int) -> Dictionary:
	for entry in data["vehicles"]:
		if int(entry["id"]) == id:
			return entry
	return {}


func test_a_save_with_two_cars_moving_the_wrong_way_in_one_lot_is_refused() -> void:
	var sim := _sim()
	for i in 3:
		_car(sim, i + 1)
	var t := _until(sim, 1, 3000, func() -> bool: return _parked(sim) == 3)
	assert_int(_parked(sim)).is_equal(3)
	var good := _save(sim, t)
	var stands: Array = sim.paths.slot_stand[SURFACE]
	print("loads as saved: %s" % LandsideSnapshot.load(good, STARTER).get("error", "LOADED"))
	assert_bool(LandsideSnapshot.load(good, STARTER).has("error")).is_false()
	var leave := func(data: Dictionary, id: int) -> void:
		var entry := _record(data, id)
		entry["stage"] = LandsideVehicle.Stage.LEAVE
		entry["leave_tick"] = 0
		entry["pos_mm"] = int(stands[int(entry["stop"])]) + 500
	var arrive := func(data: Dictionary, id: int, slot: int) -> void:
		var entry := _record(data, id)
		entry["stage"] = LandsideVehicle.Stage.DRIVE
		entry["leave_tick"] = 0
		entry["stop"] = slot
		entry["pos_mm"] = int(stands[slot]) - 500
	# One car pulling out alone is what the sim does: it loads.
	var one: Dictionary = good.duplicate(true)
	leave.call(one, 1)
	print("one pulling out: %s" % LandsideSnapshot.load(one, STARTER).get("error", "LOADED"))
	assert_bool(LandsideSnapshot.load(one, STARTER).has("error")).is_false()
	var cases := {}
	var two: Dictionary = good.duplicate(true)
	leave.call(two, 1)
	leave.call(two, 2)
	cases["two pulling out"] = [two, "more than one car pulling out"]
	var beside: Dictionary = good.duplicate(true)
	leave.call(beside, 1)
	arrive.call(beside, 2, 1)
	cases["one pulling in beside one pulling out"] = [beside, "pulling in while one pulls out"]
	var same: Dictionary = good.duplicate(true)
	leave.call(same, 1)
	arrive.call(same, 2, int(_record(same, 1)["stop"]))
	cases["one pulling into the slot one pulls out of"] = [same, "pulling in while one pulls out"]
	for case_name in cases:
		var loaded := LandsideSnapshot.load(cases[case_name][0], STARTER)
		print("%s: %s" % [case_name, loaded.get("error", "LOADED")])
		assert_str(str(loaded.get("error", ""))).override_failure_message(case_name).contains(
			cases[case_name][1]
		)


func test_a_save_on_the_tick_a_parked_car_is_let_go_loads_and_drives_on_alike() -> void:
	var sim := _sim()
	var id := _car(sim, 1)
	var t := _until(sim, 1, 3000, func() -> bool: return _parked(sim) == 1)
	var v := sim.get_vehicle(id)
	v.leave_tick = t + 5
	t = _until(sim, t, 100, func() -> bool: return v.stage == LandsideVehicle.Stage.LEAVE)
	var stand: int = sim.paths.slot_stand[SURFACE][v.stop]
	print("let go at tick %d at %d mm, stand %d" % [t - 1, v.pos_mm, stand])
	assert_int(v.stage).is_equal(LandsideVehicle.Stage.LEAVE)
	assert_int(v.pos_mm).is_equal(stand)
	var other: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(other.use_definition(STARTER)).is_true()
	other.wallet = Wallet.new()
	assert_bool(other.from_snapshot(_save(sim, t - 1), ArrivalBookings.new())).is_true()
	var ticks := 0
	while sim.get_vehicle(id) != null and ticks < 400:
		sim.step(t + ticks, true, _rng)
		other.step(t + ticks, true, _rng)
		var a := sim.get_vehicle(id)
		var b := other.get_vehicle(id)
		assert_bool(a == null).is_equal(b == null)
		if a != null and b != null:
			assert_vector(other.world_position(b)).is_equal(sim.world_position(a))
		ticks += 1
	print("both drove out after %d ticks" % ticks)
	assert_object(sim.get_vehicle(id)).is_null()
	assert_int(ticks).is_greater(10)


func test_a_car_let_in_at_the_gate_faces_the_way_it_drives_not_the_stall() -> void:
	var sim := _sim()
	var views := LandsideViews.new()
	views.landside = sim
	add_child(views)
	var first := _car(sim, 1)
	var t := _until(sim, 1, 3000, func() -> bool: return _parked(sim) == 1)
	var second := _car(sim, 2)
	var b := sim.get_vehicle(second)
	var gate_mm := LandsideDefinition.length_mm(STARTER.lots[SURFACE].access)
	t = _until(
		sim,
		t,
		3000,
		func() -> bool: return b.lane == LandsideVehicle.Lane.ACCESS and b.pos_mm >= gate_mm - 3000
	)
	# The parked car's stay ends now, just before the second car reaches the
	# gate: it pulls out first and the second waits at the gate until it is out.
	sim.get_vehicle(first).leave_tick = t
	var waited := 0
	while b.lane == LandsideVehicle.Lane.ACCESS and t < 5000:
		sim.step(t, true, _rng)
		views.sync()
		t += 1
		if b.stage == LandsideVehicle.Stage.QUEUE and b.lane == LandsideVehicle.Lane.ACCESS:
			waited += 1
	var drives := sim.heading(b)
	var stall := LandsidePlaces.parked_heading(
		STARTER.lots[SURFACE], STARTER.lots[SURFACE].slots[b.stop]
	)
	var nose := views.pose_at(second, 0.5).basis.z
	print(
		(
			"waited %d ticks at the gate; drives %s, stall %s, drawn nose %s"
			% [waited, drives, stall, nose]
		)
	)
	assert_int(b.lane).is_equal(LandsideVehicle.Lane.SLOT)
	assert_int(waited).is_greater(1)
	assert_float(drives.dot(stall)).is_less(0.5)
	assert_float(nose.dot(drives)).is_greater(0.99)
	views.free()


func test_a_paused_load_draws_a_car_on_its_slot_path_facing_the_way_it_drives() -> void:
	var sim := _sim()
	var id := _car(sim, 1)
	var v := sim.get_vehicle(id)
	var gate_mm := LandsideDefinition.length_mm(STARTER.lots[SURFACE].access)
	var t := _until(
		sim,
		1,
		3000,
		func() -> bool: return v.lane == LandsideVehicle.Lane.SLOT and v.pos_mm >= gate_mm + 1000
	)
	assert_int(v.stage).is_equal(LandsideVehicle.Stage.DRIVE)
	# Its passenger's flight closed on the way in, so the save lists no booking.
	sim.drop_booking(id, 1)
	var other: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(other.use_definition(STARTER)).is_true()
	assert_bool(other.from_snapshot(_save(sim, t - 1), ArrivalBookings.new())).is_true()
	var views := LandsideViews.new()
	views.landside = other
	add_child(views)
	views.snap()
	var loaded := other.get_vehicle(id)
	var drives := other.heading(loaded)
	var stall := LandsidePlaces.parked_heading(
		STARTER.lots[SURFACE], STARTER.lots[SURFACE].slots[loaded.stop]
	)
	var nose := views.pose_at(id, 0.0).basis.z
	print(
		"loaded at %d mm: drives %s, stall %s, drawn nose %s" % [loaded.pos_mm, drives, stall, nose]
	)
	assert_float(drives.dot(stall)).is_less(0.5)
	assert_float(nose.dot(drives)).is_greater(0.99)
	assert_vector(views.pose_at(id, 1.0).origin).is_equal_approx(
		other.world_position(loaded), Vector3.ONE * 0.001
	)
	views.free()
