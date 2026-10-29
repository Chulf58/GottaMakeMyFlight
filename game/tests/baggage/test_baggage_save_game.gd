class_name TestBaggageSaveGame
extends GdUnitTestSuite
## The bags in the whole-world save (SaveGame part "baggage", SaveLinks): a
## save waits while the bags' routes are stale and keeps saying so while it
## waits; a load checks the bags against the saved grid and flights but not
## against passengers or desks, whose ids on a bag are historical.

const SEED := 4_242
const LIMIT := 8000

var _path := SaveTestKit.run_path("test_baggage_save_game")
var _main: Node
var _save: SaveGame
var _bags: BaggageSim
## A save taken with at least one unsettled bag.
var _data := {}


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	var clock: SimClock = _main.get_node("SimClock")
	var start := GameCalendar.tick_at(0, 20 * 60 + 5)
	var data := clock.to_snapshot()
	data["tick"] = str(start)
	assert_bool(clock.from_snapshot(data)).is_true()
	SaveTestKit.start_airport(_main)
	# Passengers check no bag until a ready bag room exists.
	BagRoomKit.add((_main.get_node("BuildMode") as BuildMode).grid)
	_save = SaveTestKit.save_game(_main)
	_bags = _main.get_node("BaggageSim")
	while _unsettled() == null and clock.tick < start + LIMIT:
		SaveTestKit.step(_main)
	SaveTestKit.step(_main)
	_data = JSON.parse_string(JSON.stringify(_save.snapshot()))


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_path)


func _unsettled() -> Bag:
	for bag in _bags.bags():
		if not bag.is_settled():
			return bag
	return null


func _first_bag(data: Dictionary) -> Dictionary:
	return data["baggage"]["bags"][0]


func test_the_save_holds_the_bags_of_checked_in_passengers() -> void:
	assert_object(_unsettled()).is_not_null()
	assert_int(int(_data["save_version"])).is_equal(3)
	assert_int((_data["baggage"]["bags"] as Array).size()).is_greater(0)
	var bag := _first_bag(_data)
	assert_int(int(bag["state"])).is_equal(Bag.State.AT_DESK)
	assert_bool(_save.load_world(_data)).is_true()


func test_a_save_waits_while_the_routes_are_stale_and_says_so() -> void:
	_save.quick_save_path = _path
	_bags.routes_stale = true
	assert_str(_save.save_problem()).is_equal("the last build change settles on the next tick")
	assert_bool(_save.request_save(_path)).is_false()
	assert_str(_save.pending_path).is_equal(_path)
	# Paused, no tick comes: the message stays up however long it waits.
	for i in 3:
		_save._process(SaveGame.MESSAGE_SECONDS)
	var label: Label = _save.get_node("SaveMessage/Message")
	assert_bool(label.visible).is_true()
	assert_str(label.text).contains("Saving after the next tick")
	assert_bool(FileAccess.file_exists(_path)).is_false()
	SaveTestKit.step(_main)
	assert_bool(_bags.routes_stale).is_false()
	_save._process(0.0)
	assert_str(_save.pending_path).is_equal("")
	assert_bool(FileAccess.file_exists(_path)).is_true()


func test_a_bag_names_its_passenger_and_desk_without_needing_them() -> void:
	var data: Dictionary = _data.duplicate(true)
	_first_bag(data)["passenger"] = 987_654
	_first_bag(data)["desk"] = 4_242
	assert_bool(_save.load_world(data)).is_true()
	assert_int(_bags.bags()[0].desk).is_equal(4_242)


func test_an_unsettled_bag_for_a_flight_not_live_is_refused() -> void:
	var data: Dictionary = _data.duplicate(true)
	_first_bag(data)["flight"] = "GMF999-d9"
	assert_bool(_save.load_world(data)).is_false()
	assert_str(_save.message_text()).contains("baggage: bag")
	assert_str(_save.message_text()).contains("not live")


func test_a_bag_that_does_not_fit_the_saved_grid_is_refused() -> void:
	var data: Dictionary = _data.duplicate(true)
	var bag := _first_bag(data)
	bag["state"] = Bag.State.RIDING
	bag["cell"] = [0, 0]
	bag["from"] = [1, 0]
	assert_bool(_save.load_world(data)).is_false()
	assert_str(_save.message_text()).contains("baggage: bag")


## The saved settlement holds a fee for `passenger` while the bag is on its way.
func _await_bag(data: Dictionary, passenger: int) -> void:
	data["settlement"]["bags_awaited"].append({"passenger": str(passenger), "fee": "50"})


## The passenger of the first bag in `data` that is not settled (no outcome yet).
func _unsettled_passenger(data: Dictionary) -> int:
	for bag in data["baggage"]["bags"]:
		if int(bag["outcome_tick"]) < 0:
			return int(bag["passenger"])
	return -1


func test_a_fee_awaiting_the_bag_of_a_passenger_with_an_unsettled_bag_loads() -> void:
	var data: Dictionary = _data.duplicate(true)
	_await_bag(data, _unsettled_passenger(data))
	assert_bool(_save.load_world(data)).is_true()


func test_a_fee_awaiting_a_bag_that_is_not_there_is_refused() -> void:
	var data: Dictionary = _data.duplicate(true)
	_await_bag(data, 987_654)
	assert_bool(_save.load_world(data)).is_false()
	assert_str(_save.message_text()).contains("baggage: passenger 987654 awaits a bag")


func test_a_fee_awaiting_a_bag_that_is_settled_is_refused() -> void:
	var data: Dictionary = _data.duplicate(true)
	var bag := _first_bag(data)
	bag["state"] = Bag.State.LOADED
	bag["outcome_tick"] = int(bag["created_tick"]) + 1
	# The settled bag is counted in its flight's results and the totals.
	var result: Dictionary = data["baggage"]["results"].get(
		bag["flight"], {"loaded": 0, "missed": 0, "causes": {}}
	)
	result["loaded"] = int(result["loaded"]) + 1
	data["baggage"]["results"][bag["flight"]] = result
	data["baggage"]["loaded_total"] = int(data["baggage"]["loaded_total"]) + 1
	_await_bag(data, int(bag["passenger"]))
	assert_bool(_save.load_world(data)).is_false()
	assert_str(_save.message_text()).contains("awaits a bag")
