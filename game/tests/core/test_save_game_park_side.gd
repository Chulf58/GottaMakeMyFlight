extends GdUnitTestSuite
## A whole-world save whose passengers part holds a bad ParkSide stamp list
## ("park_side", PassengerSimSave.checked_park_side()) is refused while
## SaveGame stages it, before any part installs, so the world is left exactly
## as it was (board 4da2e8ff, Sol HIGH): checked only by
## PassengerSim.from_snapshot(), it passed staging and was refused partway
## through the install, after the grid, the clock and the flights. One boot of
## main.tscn for the file, played until passengers are in the terminal.

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


## The id of the first passenger saved in `data`.
static func _first_id(data: Dictionary) -> int:
	return int(data["passengers"]["passengers"][0]["id"])


## A stamp list with a hand of 2, and one naming a passenger twice: each load
## is refused, says so, and leaves the tick and every part as they were.
## Control: the same save untouched loads and changes the world.
func test_a_bad_park_side_is_refused_before_anything_installs() -> void:
	var old := _older()
	assert_bool((old["passengers"]["passengers"] as Array).is_empty()).is_false()
	var id := _first_id(old)
	var stamp := {"passenger": id, "seat": "gate (1, 1)", "hand": 0}
	var bad_hand := old.duplicate(true)
	bad_hand["passengers"]["park_side"] = [stamp.merged({"hand": 2}, true)]
	var twice := old.duplicate(true)
	twice["passengers"]["park_side"] = [stamp, stamp.duplicate()]
	for bad: Dictionary in [bad_hand, twice]:
		var clock := _main.get_node("SimClock") as SimClock
		var tick := clock.tick
		var before := SaveTestKit.checksum(_main)
		assert_bool(_save.load_world(bad)).is_false()
		print("refused: %s" % _save.message_text())
		assert_str(_save.message_text()).starts_with("Load failed")
		assert_str(_save.message_text()).contains("park side")
		assert_int(clock.tick).is_equal(tick)
		assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	var sum := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(old)).is_true()
	assert_str(SaveTestKit.checksum(_main)).is_not_equal(sum)
