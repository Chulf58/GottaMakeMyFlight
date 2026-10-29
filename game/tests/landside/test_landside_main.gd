class_name TestLandsideMain
extends GdUnitTestSuite
## The landside in the real main scene. A new game has only the free
## starter curb (decision landside-start-a-new-game-comes-with-a-small-free-
## drop-off-c): through the starter's first flight every passenger arrives
## by car or taxi and gets out within a small bound of the tick it was drawn
## for, which is the tick it would have appeared at the entrance before the
## landside existed. And a whole-world save taken with cars on the road and
## in a car park loads into a scene that plays on like the unsaved control,
## crediting the same parking fees and none on the load.

const SEED := 2_910_026
const OTHER_SEED := 77
## Passengers drawn for less notice than the drive can be late by up to the
## drive (LandsideSim.lead_ticks()); the rest by no more than one curb dwell.
const NOTICE_BOUND := LandsideSim.DWELL_TICKS
const COMPARE_TICKS := 400
const LIMIT := 12000

var _path := SaveTestKit.run_path("test_landside_main")
var _new: Node
var _control: Node
var _loaded: Node
var _run := {}


func before() -> void:
	_new = SaveTestKit.boot(self, SEED)
	SaveTestKit.start_airport(_new)
	_play_first_flight()
	_new.free()
	_new = null
	_control = SaveTestKit.boot(self, SEED)
	SaveTestKit.start_airport(_control)
	assert_bool(_landside(_control).build_lot(0)).is_true()
	_save_and_play_on()


func after() -> void:
	for main in [_new, _control, _loaded]:
		if main != null:
			main.free()
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + ".tmp")


static func _sim(main: Node) -> PassengerSim:
	return main.get_node("PassengerSim")


static func _landside(main: Node) -> LandsideSim:
	return main.get_node("LandsideSim")


func _play_first_flight() -> void:
	var sim := _sim(_new)
	var flights: FlightSim = _new.get_node("FlightSim")
	var unload := {}
	var notice := {}
	var released := {}
	sim.arrivals.released.connect(
		func(booking: int, _passenger: int) -> void: released[booking] = sim.tick
	)
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var start := sim.tick
	while sim.tick < start + LIMIT:
		for id in sim.arrivals.booking_ids():
			if not unload.has(id):
				var b := sim.arrivals.get_booking(id)
				unload[id] = b.unload_tick
				var lead := _landside(_new).lead_ticks(b.intent)
				notice[id] = b.unload_tick - lead >= sim.tick
		SaveTestKit.step(_new)
		if flights.flight_ids().has(first) and flights.is_doors_closed(first):
			break
	var late_notice := []
	var noticed := []
	for id in released:
		var delay: int = released[id] - unload[id]
		(noticed if notice[id] else late_notice).append(delay)
	_run["first_flight"] = first
	_run["booked"] = unload.size()
	_run["released"] = released.size()
	_run["noticed"] = noticed
	_run["late_notice"] = late_notice
	_run["missed"] = sim.missed_count()
	_run["pending"] = sim.pending_spawns()


func _save_and_play_on() -> void:
	var landside := _landside(_control)
	var limit := _sim(_control).tick + LIMIT
	while _sim(_control).tick < limit and not _busy(landside):
		SaveTestKit.step(_control)
	_run["saved_tick"] = _sim(_control).tick
	_run["busy"] = _busy(landside)
	_run["stages"] = _stages(landside)
	var credits := {}
	_watch(_control, credits)
	_run["saved"] = SaveTestKit.save_game(_control).save_to_file(_path)
	_loaded = SaveTestKit.boot(self, OTHER_SEED)
	_watch(_loaded, credits)
	_run["loaded"] = SaveTestKit.save_game(_loaded).load_from_file(_path)
	_run["credits_on_load"] = (credits[_loaded] as Array).duplicate()
	_run["same_after_load"] = SaveTestKit.checksum(_loaded) == SaveTestKit.checksum(_control)
	var first_bad := -1
	for i in COMPARE_TICKS:
		SaveTestKit.step(_control)
		SaveTestKit.step(_loaded)
		if first_bad < 0 and SaveTestKit.checksum(_loaded) != SaveTestKit.checksum(_control):
			first_bad = _sim(_control).tick
	_run["first_bad"] = first_bad
	_run["credits_control"] = credits[_control]
	_run["credits_loaded"] = credits[_loaded]


## Cars driving or queuing on the road and one parked.
static func _busy(landside: LandsideSim) -> bool:
	var stages := _stages(landside)
	var moving: int = stages[LandsideVehicle.Stage.DRIVE] + stages[LandsideVehicle.Stage.QUEUE]
	return moving > 0 and stages[LandsideVehicle.Stage.PARKED] > 0


static func _stages(landside: LandsideSim) -> Dictionary:
	var out := {}
	for stage in LandsideVehicle.Stage.values():
		out[stage] = 0
	for id in landside.vehicle_ids():
		out[landside.get_vehicle(id).stage] += 1
	return out


func _watch(main: Node, credits: Dictionary) -> void:
	credits[main] = []
	var wallet := (main.get_node("Finances") as Finances).wallet
	wallet.transaction.connect(
		func(amount: int, category: int, _claimed: Dictionary, tick: int) -> void:
			if category == Wallet.Category.PARKING:
				(credits[main] as Array).append([tick, amount])
	)


func test_a_new_game_starts_with_the_curb_and_no_car_park() -> void:
	print("first flight %s: %s" % [_run["first_flight"], _run])
	var fresh := SaveTestKit.boot(self, SEED)
	var landside := _landside(fresh)
	assert_object(landside.definition).is_not_null()
	assert_array(landside.lots_built).is_equal([false, false])
	assert_array(landside.curbs_built).is_equal([false, false])
	assert_int(landside.definition.curb.berths.size()).is_equal(4)
	assert_object(_sim(fresh).landside).is_same(landside)
	fresh.free()


func test_the_first_flight_arrives_by_road_within_a_small_bound_of_its_drawn_ticks() -> void:
	var noticed: Array = _run["noticed"]
	var late_notice: Array = _run["late_notice"]
	print(
		(
			"booked %d released %d: with notice max delay %s, short notice delays %s, missed %d"
			% [
				_run["booked"],
				_run["released"],
				noticed.max() if not noticed.is_empty() else "-",
				late_notice,
				_run["missed"]
			]
		)
	)
	assert_int(_run["booked"]).is_greater(0)
	assert_int(_run["released"]).is_equal(_run["booked"])
	assert_int(_run["pending"]).is_equal(0)
	assert_int(noticed.size()).is_greater(0)
	for delay in noticed:
		assert_int(delay).is_between(0, NOTICE_BOUND)
	var lead := _landside(_control).lead_ticks(LandsideVehicle.Intent.DROP)
	for delay in late_notice:
		assert_int(delay).is_between(0, lead + NOTICE_BOUND)


func test_a_save_with_cars_on_the_road_and_in_the_lot_plays_on_like_the_control() -> void:
	print(
		(
			"saved at %d stages %s; credits on load %s, control %s, loaded %s, first bad %d"
			% [
				_run["saved_tick"],
				_run["stages"],
				_run["credits_on_load"],
				_run["credits_control"],
				_run["credits_loaded"],
				_run["first_bad"]
			]
		)
	)
	assert_bool(_run["busy"]).is_true()
	assert_bool(_run["saved"]).is_true()
	assert_bool(_run["loaded"]).is_true()
	assert_bool(_run["same_after_load"]).is_true()
	assert_int(_run["first_bad"]).is_equal(-1)
	assert_array(_run["credits_on_load"]).is_empty()
	assert_array(_run["credits_loaded"]).is_equal(_run["credits_control"])
