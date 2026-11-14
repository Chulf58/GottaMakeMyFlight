extends GdUnitTestSuite
## A whole-world save whose passengers part holds a bad line outside the
## entrance ("entrance_line", PassengerSimSave.checked_entrance()) is refused
## while SaveGame stages it, before any part installs, so the world is left
## exactly as it was (board 66be00a0). One boot of main.tscn for the file,
## played until passengers are in the terminal.

const SEED := 8_812_026
const PLAY_TICKS := 2700

var _main: Node
var _save: SaveGame


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	SaveTestKit.start_airport(_main)
	for i in PLAY_TICKS:
		SaveTestKit.step(_main)


func after() -> void:
	_main.free()


## A save taken now and the world played on, so loading it would change the
## world (the positive control below), through JSON as a file holds it.
func _older() -> Dictionary:
	var old: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot(), "", true, true))
	for i in 30:
		SaveTestKit.step(_main)
	return old


## A line naming a passenger the save does not hold, one whose held
## bookings are not a list, and one listing a booking held on the last step
## that is not among its held bookings: each load is refused, says so, and leaves the tick
## and every part as they were. Control: the same save untouched loads and
## changes the world.
func test_a_bad_entrance_line_is_refused_before_anything_installs() -> void:
	var old := _older()
	assert_dict(old["passengers"]["entrance_line"]).contains_keys(["order", "claims", "held"])
	var stranger := old.duplicate(true)
	stranger["passengers"]["entrance_line"]["order"] = [987654]
	var bad_held := old.duplicate(true)
	bad_held["passengers"]["entrance_line"]["held"] = "none"
	var bad_now := old.duplicate(true)
	bad_now["passengers"]["entrance_line"]["held"] = []
	bad_now["passengers"]["entrance_line"]["held_now"] = [987654]
	for bad: Dictionary in [stranger, bad_held, bad_now]:
		var clock := _main.get_node("SimClock") as SimClock
		var tick := clock.tick
		var before := SaveTestKit.checksum(_main)
		assert_bool(_save.load_world(bad)).is_false()
		print("refused: %s" % _save.message_text())
		assert_str(_save.message_text()).starts_with("Load failed")
		assert_str(_save.message_text()).contains("entrance line")
		assert_int(clock.tick).is_equal(tick)
		assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	var sum := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(old)).is_true()
	assert_str(SaveTestKit.checksum(_main)).is_not_equal(sum)


## The line's held bookings and held misses checked against the staged
## landside (SaveGame._entrance_links_problem()): a held id that is no booking,
## a held booking still awaiting its vehicle, held misses of a flight with no
## transport misses, and more held misses than the flight's transport misses
## are each refused whole, leaving the world as it was. Control: a booking really in its vehicle,
## held, loads. The save is taken once a car or taxi has passengers aboard.
func test_held_bookings_and_misses_must_match_the_staged_landside() -> void:
	var aboard := 0
	for i in 150:
		for vehicle: Dictionary in _save.snapshot()["landside"]["vehicles"]:
			if not (vehicle["bookings"] as Array).is_empty():
				aboard = int(vehicle["bookings"][0])
		if aboard != 0:
			break
		for step in 20:
			SaveTestKit.step(_main)
	var old := _older()
	var awaiting := 0
	for booking: Dictionary in old["landside"]["bookings"]:
		if int(booking["state"]) == ArrivalBooking.State.AWAITING:
			awaiting = int(booking["id"])
	var flight := str(old["passengers"]["scheduled"][0])
	var road := 0
	for entry: Dictionary in old["landside"]["missed"]:
		if entry["flight"] == flight:
			road = int(entry["count"])
	prints("in a vehicle", aboard, "awaiting", awaiting, "flight", flight, "transport misses", road)
	assert_int(aboard).is_greater(0)
	assert_int(awaiting).is_greater(0)
	var stray := old.duplicate(true)
	stray["passengers"]["entrance_line"]["held"] = [987654]
	var not_aboard := old.duplicate(true)
	not_aboard["passengers"]["entrance_line"]["held"] = [awaiting]
	var no_flight := old.duplicate(true)
	no_flight["passengers"]["entrance_line"]["held_missed"] = {"NO-SUCH-FLIGHT": 1}
	var too_many := old.duplicate(true)
	too_many["passengers"]["entrance_line"]["held_missed"] = {flight: road + 1}
	for bad: Dictionary in [stray, not_aboard, no_flight, too_many]:
		var clock := _main.get_node("SimClock") as SimClock
		var tick := clock.tick
		var before := SaveTestKit.checksum(_main)
		assert_bool(_save.load_world(bad)).is_false()
		print("refused: %s" % _save.message_text())
		assert_str(_save.message_text()).contains("entrance line held")
		assert_int(clock.tick).is_equal(tick)
		assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	var good := old.duplicate(true)
	good["passengers"]["entrance_line"]["held"] = [aboard]
	var sum := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(good)).is_true()
	assert_str(SaveTestKit.checksum(_main)).is_not_equal(sum)
