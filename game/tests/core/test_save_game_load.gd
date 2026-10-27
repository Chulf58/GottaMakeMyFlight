class_name TestSaveGameLoad
extends GdUnitTestSuite
## The whole-world save's shape and its staged load (Economy 8/8, decision
## flights-and-economy-design-tick-derived-calendar-timetable-o, point 8): one
## dictionary with one save_version and one key per part, and a load that
## checks every part before installing any, so a refused load leaves the world
## exactly as it was. One boot of main.tscn for the file, played until the
## airport is open and passengers are in the terminal.

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


## A save taken now, through JSON as a file holds it.
func _taken() -> Dictionary:
	var data := _save.snapshot()
	assert_bool(data.is_empty()).is_false()
	return JSON.parse_string(JSON.stringify(data, "", true, true))


## A save taken now and the world played on, so loading it would change the
## world: the positive control for every refusal below.
func _older() -> Dictionary:
	var old := _taken()
	for i in 30:
		SaveTestKit.step(_main)
	assert_int((_main.get_node("SimClock") as SimClock).tick).is_greater(
		str(old["clock"]["tick"]).to_int()
	)
	return old


func _assert_refused(bad: Dictionary, reason: String) -> void:
	var before := SaveTestKit.checksum(_main)
	var tick := (_main.get_node("SimClock") as SimClock).tick
	assert_bool(_save.load_world(bad)).override_failure_message(reason).is_false()
	assert_str(_save.message_text()).override_failure_message(reason).starts_with("Load failed")
	assert_int((_main.get_node("SimClock") as SimClock).tick).is_equal(tick)
	assert_str(SaveTestKit.checksum(_main)).override_failure_message(reason).is_equal(before)


func test_the_airport_is_open_with_passengers_in_the_terminal() -> void:
	var flights: FlightSim = _main.get_node("FlightSim")
	var sim: PassengerSim = _main.get_node("PassengerSim")
	assert_int(flights.opened_tick).is_greater(0)
	assert_int(sim.passenger_ids().size()).is_greater(0)


func test_a_save_holds_one_save_version_and_every_part() -> void:
	var data := _taken()
	var keys: Array = ["save_version"]
	for part in _save.parts():
		keys.append(part.key)
	assert_array(data.keys()).contains_exactly_in_any_order(keys)
	assert_int(int(data["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	assert_array(keys).contains(
		[
			"grid",
			"clock",
			"flights",
			"passengers",
			"staff",
			"wallet",
			"settlement",
			"rescue_grant",
			"offers",
			"rating"
		]
	)


func test_an_older_save_loads_back_into_the_same_world() -> void:
	var old := _taken()
	var old_sum := SaveTestKit.checksum(_main)
	for i in 30:
		SaveTestKit.step(_main)
	assert_str(SaveTestKit.checksum(_main)).is_not_equal(old_sum)
	assert_bool(_save.load_world(old)).is_true()
	assert_str(_save.message_text()).is_equal("Loaded")
	assert_str(SaveTestKit.checksum(_main)).is_equal(old_sum)


func test_a_refusal_in_the_last_part_installs_none_of_the_earlier_ones() -> void:
	var bad := _older()
	bad["rating"]["save_version"] = 999
	_assert_refused(bad, "rating save_version")
	assert_str(_save.message_text()).contains("rating")


func test_a_refusal_in_a_part_checked_against_the_staged_grid_changes_nothing() -> void:
	var bad := _older()
	bad["passengers"]["save_version"] = 999
	_assert_refused(bad, "passengers save_version")
	assert_str(_save.message_text()).contains("passengers")


func test_parts_saved_on_different_ticks_are_refused() -> void:
	var bad := _older()
	bad["rating"]["tick"] = int(bad["rating"]["tick"]) - 1
	_assert_refused(bad, "rating tick")
	assert_str(_save.message_text()).contains("saved on tick")


func test_a_bad_top_level_shape_is_refused() -> void:
	var old := _older()
	var unknown := old.duplicate(true)
	unknown["camera"] = {}
	var missing := old.duplicate(true)
	missing.erase("offers")
	var version := old.duplicate(true)
	version["save_version"] = SaveGame.SAVE_VERSION + 1
	var not_a_part := old.duplicate(true)
	not_a_part["wallet"] = [1]
	for case in [
		[unknown, "unknown key"],
		[missing, "missing key"],
		[version, "save_version"],
		[not_a_part, "is not a dictionary"],
	]:
		_assert_refused(case[0], case[1])
		assert_str(_save.message_text()).contains(case[1])
	_assert_refused({}, "empty")
	assert_bool(_save.load_world([])).is_false()


## A load into a Finances that has not been set up yet, as in a scene whose
## Finances has not entered the tree: only Finances.restore() marks it set up,
## so entering the tree afterwards credits no starting budget on top. Loading
## through wallet.from_snapshot() directly would leave it unset, and _ready()
## would add PriceTable.STARTING_BUDGET.
func test_a_wallet_part_goes_through_finances_restore_before_any_new_game() -> void:
	var data := _taken()
	data["wallet"]["balance"] = "1234"
	var live := _save.finances
	var fresh := FinancesDouble.new()
	_save.finances = fresh
	var loaded := _save.load_world(data)
	_save.finances = live
	assert_bool(loaded).is_true()
	assert_int(fresh.restores).is_equal(1)
	assert_int(fresh.wallet.balance).is_equal(1234)
	add_child(fresh)
	assert_int(fresh.wallet.balance).is_equal(1234)
	assert_bool(fresh.start_new_game()).is_false()
	assert_int(fresh.wallet.balance).is_equal(1234)
	fresh.free()


## Finances that counts its restore() calls.
class FinancesDouble:
	extends Finances
	var restores := 0

	func restore(data: Dictionary) -> bool:
		restores += 1
		return super(data)
