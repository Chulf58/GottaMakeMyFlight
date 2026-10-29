class_name TestLandsideCongestion
extends GdUnitTestSuite
## A jammed curb or a full car park delays passengers (decision
## landside-congestion-a-jammed-curb-or-full-car-park-delays-pa). Each case
## measures release ticks against an uncongested control: cars that find
## every berth taken wait in the queue, and a car that means to park but
## finds the lot full drives on to the curb.

const STARTER := preload("res://landside/starter_landside.tres")
## Ticks between two cars that entered the road on the same tick (a gap).
const SPACING := LandsideSim.GAP_MM / LandsideSim.SPEED_MM
const CARS := 5

var _land: LandsideTestWorld
var _rng := RandomNumberGenerator.new()


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_rng.seed = 11


func after_test() -> void:
	if _land != null:
		_land.free_all()
	_land = null


func _bare_sim(definition: LandsideDefinition = STARTER) -> LandsideSim:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(definition)).is_true()
	sim.wallet = Wallet.new()
	return sim


## Vehicle id -> release tick, stepping from `from` to `to`.
func _run(sim: LandsideSim, from: int, to: int, out: Dictionary) -> void:
	for t in range(from, to):
		for event in sim.step(t, true, _rng):
			out[event["vehicle"]] = t


## Per car, release tick less the tick it would get out on a free road
## behind the cars that entered with it (the lead plus a gap per car ahead).
func _delays(released: Dictionary, entered: Dictionary, lead: int) -> Array[int]:
	var out: Array[int] = []
	var ids: Array = released.keys()
	ids.sort()
	for id in ids:
		out.append(released[id] - entered[id][0] - lead - entered[id][1] * SPACING)
	return out


func test_a_jammed_curb_delays_release_by_measured_ticks_against_a_control() -> void:
	# Three berths, as the curb was before it became two bays.
	var three := LandsideTestWorld.with_berths(3)
	var control := _bare_sim(three)
	var jammed := _bare_sim(three)
	var lead := control.lead_ticks(LandsideVehicle.Intent.DROP)
	var entered_control := {}
	var entered_jammed := {}
	var released_control := {}
	var released_jammed := {}
	for i in CARS:
		var booking: Array[int] = [i + 1]
		# Jammed: all five on tick 0, one behind the other.
		var id := jammed.add_vehicle(
			LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP, booking
		)
		entered_jammed[id] = [0, i]
	for t in range(0, 2000):
		_run(control, t, t + 1, released_control)
		# Control: one car every 100 ticks, so each finds a free berth.
		if t % 100 == 0 and t < CARS * 100:
			var booking: Array[int] = [t / 100 + 1]
			var id := control.add_vehicle(
				LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, booking
			)
			entered_control[id] = [t, 0]
	_run(jammed, 1, 2000, released_jammed)
	var control_delays := _delays(released_control, entered_control, lead)
	var jammed_delays := _delays(released_jammed, entered_jammed, lead)
	print("control %s jammed %s" % [control_delays, jammed_delays])
	assert_array(control_delays).is_equal([0, 0, 0, 0, 0])
	# Three berths: the fourth car waits for the first car's dwell to end, the
	# fifth for the second's; each wait is the dwell less the gaps between.
	var berths := three.curb.berths.size()
	var wait := LandsideSim.DWELL_TICKS - berths * SPACING
	assert_int(berths).is_equal(3)
	assert_array(jammed_delays).is_equal([0, 0, 0, wait, wait])
	assert_int(wait).is_greater(0)


func test_a_jammed_curb_delays_passengers_against_an_uncongested_control() -> void:
	var control := LandsideTestWorld.make(null, [], 5)
	var jammed := LandsideTestWorld.make(LandsideTestWorld.with_berths(1), [], 5)
	for world in [control, jammed]:
		world.schedule(40)
		var doors: int = world.world.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
		while world.released.size() < 40 and world.sim.tick < doors:
			world.step()
	# The same seed books the same parties at the same ticks in both.
	assert_dict(jammed.unload).is_equal(control.unload)
	var control_total := 0
	var jammed_total := 0
	for delay in control.delays():
		control_total += delay
	for delay in jammed.delays():
		jammed_total += delay
	print(
		(
			"bookings %d control released %d delay %d max %d; one berth released %d delay %d max %d"
			% [
				control.unload.size(),
				control.released.size(),
				control_total,
				control.delays().max(),
				jammed.released.size(),
				jammed_total,
				jammed.delays().max()
			]
		)
	)
	assert_int(control.released.size()).is_equal(40)
	assert_int(jammed.released.size()).is_equal(40)
	assert_int(jammed_total).is_greater(control_total)
	assert_int(jammed.delays().max()).is_greater(control.delays().max())
	control.free_all()
	jammed.free_all()


func test_a_full_lot_diverts_the_car_to_the_curb() -> void:
	var sim := _bare_sim()
	assert_bool(sim.build_lot(0)).is_true()
	var slots := STARTER.lots[0].slots.size()
	var parked := []
	var diverted := []
	sim.parked.connect(func(id: int, _lot: int) -> void: parked.append(id))
	sim.diverted.connect(func(id: int) -> void: diverted.append(id))
	for i in slots:
		var booking: Array[int] = [i + 1]
		sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, booking)
	_run(sim, 1, 1000, {})
	assert_int(parked.size()).is_equal(slots)
	assert_int(sim.free_slots(0)).is_equal(0)
	assert_array(diverted).is_empty()
	var last: Array[int] = [slots + 1]
	var id := sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, last)
	var events := {}
	var walks := {}
	for t in range(1000, 2000):
		for event in sim.step(t, true, _rng):
			events[event["vehicle"]] = t
			walks[event["vehicle"]] = event["walk"]
		if events.has(id):
			break
	var v := sim.get_vehicle(id)
	print(
		(
			"parked %d diverted %s released at %d (park lead %d, curb lead %d) walk %s"
			% [
				parked.size(),
				diverted,
				events.get(id, -1) - 999,
				sim.lead_ticks(LandsideVehicle.Intent.PARK),
				sim.lead_ticks(LandsideVehicle.Intent.DROP),
				walks.get(id)
			]
		)
	)
	assert_array(diverted).is_equal([id])
	assert_int(parked.size()).is_equal(slots)
	assert_int(v.intent).is_equal(LandsideVehicle.Intent.DROP)
	assert_int(v.lot).is_equal(-1)
	assert_int(v.lane).is_equal(LandsideVehicle.Lane.BERTH)
	assert_array(walks[id]).is_equal([STARTER.curb.get_out[v.stop]])
	# It gets out at the curb, the drive past the lot's turn later than a
	# free slot would have let it out.
	assert_int(events[id] - 999).is_equal(sim.lead_ticks(LandsideVehicle.Intent.DROP))
	assert_int(sim.wallet.balance).is_equal(slots * LandsideSim.SURFACE_LOT_FEE)
