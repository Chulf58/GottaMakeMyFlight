extends GdUnitTestSuite
## A whole-world save whose passengers part holds a bad booking override
## ("booking_overrides", BookingOverrides.checked()) is refused while SaveGame
## stages it, before any part installs, so the world is left exactly as it was
## (board c6c13a5a). Checked only by PassengerSim.from_snapshot(), it would be
## refused partway through the install. One boot of main.tscn for the file.

const SEED := 8_812_027
const PLAY_TICKS := 300

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


## An override of no passengers, one with no occurrence id, and a missing list:
## each load is refused, says so, and leaves the tick and every part as they
## were. Control: the same save untouched loads and changes the world.
func test_a_bad_booking_override_is_refused_before_anything_installs() -> void:
	var old := _older()
	var entry := {"flight": "OVR-d0", "extra": 2}
	var no_extra := old.duplicate(true)
	no_extra["passengers"]["booking_overrides"] = [entry.merged({"extra": 0}, true)]
	var no_occurrence := old.duplicate(true)
	no_occurrence["passengers"]["booking_overrides"] = [entry.merged({"flight": "OVR"}, true)]
	var no_list := old.duplicate(true)
	no_list["passengers"].erase("booking_overrides")
	for bad: Dictionary in [no_extra, no_occurrence, no_list]:
		var clock := _main.get_node("SimClock") as SimClock
		var tick := clock.tick
		var before := SaveTestKit.checksum(_main)
		assert_bool(_save.load_world(bad)).is_false()
		print("refused: %s" % _save.message_text())
		assert_str(_save.message_text()).starts_with("Load failed")
		assert_str(_save.message_text()).contains("booking")
		assert_int(clock.tick).is_equal(tick)
		assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	var sum := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(old)).is_true()
	assert_str(SaveTestKit.checksum(_main)).is_not_equal(sum)
