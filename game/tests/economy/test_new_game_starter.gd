class_name TestNewGameStarter
extends GdUnitTestSuite
## A new game on the real main scene starts with the player-owned starter
## shell (decision terminal-growth-and-starter-building-move-the-airside-
## north): the shell stands once, the wallet still holds the starting budget
## and no rescue grant is paid at boot, a save and load never places it again,
## and the Debug panel's Starter terminal button fills it with the reference
## interior. One boot for the file; before() records what each case reads.

const SEED := 4_117_209
const BOOT_TICKS := 250

var _main: Node
var _other: Node
var _boot := {}
var _round_trip := {}
var _filled := {}
var _grants := 0


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	var rescue: RescueGrant = _main.get_node("RescueGrant")
	rescue.granted.connect(func(_amount: int, _message: String) -> void: _grants += 1)
	_boot = _read(_main)
	for i in BOOT_TICKS:
		SaveTestKit.step(_main)
	_boot["balance_after"] = _wallet(_main).balance
	_boot["grants"] = _grants
	_boot["opened_tick"] = (_main.get_node("FlightSim") as FlightSim).opened_tick
	_boot["has_path"] = rescue.has_working_path()
	var plan := rescue.repair_plan()
	_boot["repair_ok"] = plan.ok
	_boot["repair_cost"] = RepairPlan.least_balance(_grid(_main), plan.edits)
	_boot["after"] = _read(_main)
	_press_the_button()
	_play_a_round_trip()


func after() -> void:
	_main.free()
	if _other != null:
		_other.free()


static func _grid(main: Node) -> BuildGrid:
	return (main.get_node("BuildMode") as BuildMode).grid


static func _wallet(main: Node) -> Wallet:
	return (main.get_node("Finances") as Finances).wallet


## The starter's footprint read off a main scene's grid.
static func _read(main: Node) -> Dictionary:
	var grid := _grid(main)
	var floors := 0
	for y in grid.size.y:
		for x in grid.size.x:
			if grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE:
				floors += 1
	var kinds := ReferenceTerminal.object_ids(grid)
	# The site moves the starter terminal by its starter_offset.
	var shift := ReferenceTerminal.offset_on(grid)
	var divider := 0
	for x in range(ReferenceTerminal.FLOOR_MIN.x, ReferenceTerminal.FLOOR_MAX.x + 1):
		if grid.has_wall(Vector2i(x, ReferenceTerminal.DIVIDER_Y) + shift, BuildGrid.Side.NORTH):
			divider += 1
	return {
		"floors": floors,
		"desks": (kinds["desks"] as Array).size(),
		"scanners": (kinds["scanners"] as Array).size(),
		"seats": (kinds["seats"] as Array).size(),
		"entrances": (kinds["entrances"] as Array).size(),
		"exits": (kinds["exits"] as Array).size(),
		"divider": divider,
		"snapshot": JSON.stringify(grid.to_snapshot()),
	}


## Presses the Debug panel's button on the main scene, the shell standing.
func _press_the_button() -> void:
	var hud: PassengerHud = _main.get_node("PassengerHud")
	_filled["before"] = _read(_main)
	hud.press_starter_terminal()
	_filled["status"] = hud.status_text()
	_filled["after"] = _read(_main)
	hud.press_starter_terminal()
	_filled["again_status"] = hud.status_text()
	_filled["again"] = _read(_main)


## Saves the filled world and loads it into a fresh boot, which has the shell of
## a new game to be told apart from the loaded grid. Then a third boot takes its
## entrance down (the shell has no staff spot to keep it), is saved, and that is
## loaded into the same fresh boot: a load that placed the shell again would
## bring the entrance back.
func _play_a_round_trip() -> void:
	SaveTestKit.step(_main)
	var first := _taken(SaveTestKit.save_game(_main))
	_other = SaveTestKit.boot(self, SEED + 1)
	_round_trip["fresh_entrances"] = _read(_other)["entrances"]
	_round_trip["loaded_ok"] = SaveTestKit.save_game(_other).load_world(first)
	_round_trip["loaded"] = _read(_other)
	_round_trip["saved"] = _read(_main)
	var third := SaveTestKit.boot(self, SEED + 2)
	var entrance: int = (ReferenceTerminal.object_ids(_grid(third))["entrances"] as Array)[0]
	var removed := _grid(third).apply(BuildEdit.remove_object(entrance))
	_round_trip["removed_ok"] = removed.ok
	_round_trip["removed_why"] = removed.reason_text()
	SaveTestKit.step(third)
	var second := _taken(SaveTestKit.save_game(third))
	_round_trip["demolished"] = _read(third)
	third.free()
	_round_trip["second_ok"] = SaveTestKit.save_game(_other).load_world(second)
	_round_trip["reloaded"] = _read(_other)


func _taken(save: SaveGame) -> Dictionary:
	var data := save.snapshot()
	assert_bool(data.is_empty()).is_false()
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func test_a_new_game_starts_with_the_shell_once() -> void:
	assert_int(_boot["floors"]).is_equal(12 * 16)
	assert_int(_boot["entrances"]).is_equal(1)
	assert_int(_boot["exits"]).is_equal(1)


func test_the_shell_has_no_desks_scanners_seats_or_divider() -> void:
	for key in ["desks", "scanners", "seats", "divider"]:
		assert_int(_boot[key]).override_failure_message("%s at boot" % key).is_equal(0)


func test_the_shell_stays_a_single_one_after_the_first_ticks() -> void:
	assert_int(_boot["after"]["floors"]).is_equal(12 * 16)
	assert_int(_boot["after"]["entrances"]).is_equal(1)
	assert_int(_boot["after"]["exits"]).is_equal(1)
	assert_str(_boot["after"]["snapshot"]).is_equal(_boot["snapshot"])


func test_no_rescue_grant_is_paid_at_boot_and_the_wallet_is_untouched() -> void:
	assert_int(_boot["grants"]).is_equal(0)
	assert_int(_boot["balance_after"]).is_equal(PriceTable.STARTING_BUDGET)


## Not stuck: the airport is closed and has no path yet, but the starting
## budget pays for the repair, so the grant has nothing to give.
func test_the_new_game_is_closed_but_not_stuck() -> void:
	assert_int(_boot["opened_tick"]).is_equal(-1)
	assert_bool(_boot["has_path"]).is_false()
	assert_bool(_boot["repair_ok"]).is_true()
	assert_int(_boot["repair_cost"]).is_greater(0)
	assert_int(_boot["repair_cost"]).is_less(_boot["balance_after"])


func test_the_debug_button_fills_the_shell_with_the_interior() -> void:
	for key in ["desks", "scanners", "seats", "divider"]:
		assert_int(_filled["before"][key]).override_failure_message("%s before" % key).is_equal(0)
		assert_int(_filled["after"][key]).override_failure_message("%s after" % key).is_greater(0)
	assert_str(_filled["status"]).is_equal("Starter terminal filled")
	assert_int(_filled["after"]["entrances"]).is_equal(1)
	assert_int(_filled["after"]["exits"]).is_equal(1)
	assert_int(_filled["after"]["floors"]).is_equal(12 * 16)


func test_a_second_press_changes_nothing_and_says_why() -> void:
	assert_str(_filled["again"]["snapshot"]).is_equal(_filled["after"]["snapshot"])
	assert_str(_filled["again_status"]).starts_with("Starter terminal not filled")


func test_a_fresh_boot_has_a_shell_but_the_loaded_world_replaces_it() -> void:
	assert_int(_round_trip["fresh_entrances"]).is_equal(1)
	assert_bool(_round_trip["loaded_ok"]).is_true()
	assert_str(_round_trip["loaded"]["snapshot"]).is_equal(_round_trip["saved"]["snapshot"])
	assert_int(_round_trip["loaded"]["entrances"]).is_equal(1)
	assert_int(_round_trip["loaded"]["exits"]).is_equal(1)
	assert_int(_round_trip["loaded"]["floors"]).is_equal(12 * 16)


func test_a_load_does_not_place_the_shell_again_over_a_demolished_entrance() -> void:
	(
		assert_bool(_round_trip["removed_ok"])
		. override_failure_message(_round_trip["removed_why"])
		. is_true()
	)
	assert_bool(_round_trip["second_ok"]).is_true()
	assert_int(_round_trip["reloaded"]["entrances"]).is_equal(0)
	assert_int(_round_trip["reloaded"]["exits"]).is_equal(1)
	assert_str(_round_trip["reloaded"]["snapshot"]).is_equal(_round_trip["demolished"]["snapshot"])
