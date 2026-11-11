class_name TestBuildUnlocksSave
extends GdUnitTestSuite
## The real scene wires the build unlocks (decision build-unlocks-need-stars-
## and-passengers-served-hunger-cafe-a): a new game is on the start tier with
## hunger off, a locked tool is refused, and the tier and made-flight count
## survive a save and a load. One boot of main.tscn.

const SEED := 4_011_104

var _main: Node
var _save: SaveGame
var _unlocks: BuildUnlocks
var _mode: BuildMode
var _pax: PassengerSim
var _path := SaveTestKit.run_path("test_build_unlocks_save")


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_unlocks = _main.get_node("BuildUnlocks")
	_mode = _main.get_node("BuildMode")
	_pax = _main.get_node("PassengerSim")
	_save.quick_save_path = _path
	SaveTestKit.step(_main)


func after() -> void:
	for file in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	_main.free()


func test_a_new_game_is_on_the_start_tier_with_hunger_off_and_the_gate_wired() -> void:
	assert_int(_unlocks.tier()).is_equal(1)
	assert_bool(_pax.cafes.hunger_enabled).is_false()
	assert_object(_mode.unlocks).is_same(_unlocks)
	assert_bool(_mode.require_unlocks).is_true()
	assert_object(_save.unlocks).is_same(_unlocks)
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	assert_int(_mode.tool).is_not_equal(BuildMode.Tool.CAFE_ROOM)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	_mode.set_tool(BuildMode.Tool.NONE)


func test_the_tier_and_the_count_survive_a_save_and_a_load() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 3, "made": 260, "shown": [], "seen": []})).is_true()
	SaveTestKit.step(_main)
	assert_bool(_save.snapshot().has("unlocks")).is_true()
	assert_bool(_save.save_to_file(_path)).is_true()
	# The game moves on, then the save comes back.
	assert_bool(_unlocks.from_snapshot({"tier": 1, "made": 0, "shown": [], "seen": []})).is_true()
	assert_bool(_pax.cafes.hunger_enabled).is_false()
	assert_bool(_save.load_from_file(_path)).is_true()
	print("after load: tier %d, made %d" % [_unlocks.tier(), _unlocks.made_total()])
	assert_int(_unlocks.tier()).is_equal(3)
	assert_int(_unlocks.made_total()).is_equal(260)
	assert_bool(_pax.cafes.hunger_enabled).is_true()
	_mode.set_tool(BuildMode.Tool.TREE)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.TREE)
	_mode.set_tool(BuildMode.Tool.NONE)


## A save whose unlocks part is malformed (a tier above what its made-flight
## count opens) is refused whole while it is staged: the world after the
## refusal is the world before it, the earlier parts included.
func test_a_malformed_unlocks_part_refuses_the_whole_load_and_changes_nothing() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 70, "shown": [], "seen": []})).is_true()
	SaveTestKit.step(_main)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot(), "", true, true))
	data["unlocks"] = {"tier": 4, "made": 0, "shown": [], "seen": []}
	# Moved on from the save, so a part installed from it would show.
	for i in 5:
		SaveTestKit.step(_main)
	var before := SaveTestKit.checksum(_main)
	var clock: SimClock = _main.get_node("SimClock")
	var tick := clock.tick
	var done := [true]
	await (
		assert_error(func() -> void: done[0] = _save.load_world(data))
		. is_push_error("BuildUnlocks.from_snapshot: tier 4 needs 600 passengers made, not 0")
	)
	print("refused: %s" % _save.message_text())
	assert_bool(done[0]).is_false()
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	assert_int(clock.tick).is_equal(tick)
	assert_int(_unlocks.tier()).is_equal(2)
	assert_int(_unlocks.made_total()).is_equal(70)
