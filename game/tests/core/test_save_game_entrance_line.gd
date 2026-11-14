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


## A line naming a passenger the save does not hold, and one whose held
## bookings are not a list: each load is refused, says so, and leaves the tick
## and every part as they were. Control: the same save untouched loads and
## changes the world.
func test_a_bad_entrance_line_is_refused_before_anything_installs() -> void:
	var old := _older()
	assert_dict(old["passengers"]["entrance_line"]).contains_keys(["order", "claims", "held"])
	var stranger := old.duplicate(true)
	stranger["passengers"]["entrance_line"]["order"] = [987654]
	var bad_held := old.duplicate(true)
	bad_held["passengers"]["entrance_line"]["held"] = "none"
	for bad: Dictionary in [stranger, bad_held]:
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
