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
	SaveTestKit.start_airport(_main)
	# Connect the starter desk at (14, 11) + offset via its outlet (15, 10) to a
	# bag room on owned starter floor so checked bags activate (17e414be).
	var mode := _main.get_node("BuildMode") as BuildMode
	var offset := ReferenceTerminal.offset_on(mode.grid)
	var room := Rect2i(Vector2i(16, 13) + offset, Vector2i(3, 3))
	assert_bool(mode.grid.apply(BuildEdit.place_room(room, &"bag_room")).ok).is_true()
	for seg in [[Vector2i(15, 10), Vector2i(16, 10)], [Vector2i(16, 10), Vector2i(16, 13)]]:
		var plan := BeltShaper.plan_line(mode.grid, seg[0] + offset, seg[1] + offset, 0)
		assert_bool(plan.result.ok).is_true()
		for r in mode.grid.apply_batch(plan.edits):
			assert_bool(r.ok).is_true()
	_save = SaveTestKit.save_game(_main)
	_bags = _main.get_node("BaggageSim")
	while _unsettled() == null and clock.tick < LIMIT:
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
	assert_int(int(_data["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	assert_int((_data["baggage"]["bags"] as Array).size()).is_greater(0)
	var bag := _first_bag(_data)
	assert_bool([Bag.State.AT_DESK, Bag.State.RIDING].has(int(bag["state"]))).is_true()
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
	data["settlement"]["bags_awaited"].append(
		{"passenger": str(passenger), "fee": "50", "missed_fee": "25"}
	)


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
	bag["remain_mm"] = 0
	bag["from"] = [0, 0]
	bag["from_desk"] = false
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


func test_active_shuttle_round_trips_through_whole_world_save() -> void:
	assert_bool(_save.load_world(_data)).is_true()
	var mode := _main.get_node("BuildMode") as BuildMode
	var offset := ReferenceTerminal.offset_on(mode.grid)
	var cart := mode.grid.apply(
		BuildEdit.place_object(&"baggage_cart", Vector2i(17, 14) + offset, 0)
	)
	assert_bool(cart.ok).is_true()
	var ramp_id := (_main.get_node("Staff") as StaffSim).hire(StaffMember.Role.RAMP)
	var clock := _main.get_node("SimClock") as SimClock
	while _bags.shuttles().is_empty() and clock.tick < LIMIT:
		SaveTestKit.step(_main)
	assert_int(_bags.shuttles().size()).is_equal(1)
	var orig := _bags.shuttles()[0]
	var orig_cart_id := orig.cart_id
	var orig_bag_ids := orig.bag_ids.duplicate()
	var orig_waypoints_size := orig.waypoints.size()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot()))
	assert_bool(_save.load_world(snap)).is_true()
	assert_int(_bags.shuttles().size()).is_equal(1)
	var s := _bags.shuttles()[0]
	assert_int(s.cart_id).is_equal(orig_cart_id)
	assert_array(s.bag_ids).is_equal(orig_bag_ids)
	assert_int(s.waypoints.size()).is_equal(orig_waypoints_size)
	assert_int(s.driver_staff_id).is_equal(ramp_id)
	var loaded_staff := _main.get_node("Staff") as StaffSim
	var driver := loaded_staff.get_member(s.driver_staff_id)
	assert_object(driver).is_not_null()
	assert_int(driver.role).is_equal(StaffMember.Role.RAMP)
	assert_int(driver.ramp_job).is_equal(StaffMember.RampJob.SHUTTLE)
	assert_int(driver.ramp_shuttle_id).is_equal(s.id)
	while not _bags.shuttles().is_empty() and clock.tick < LIMIT:
		SaveTestKit.step(_main)
	assert_int(_bags.loaded_total).is_greater(0)
	assert_bool(_save.load_world(_data)).is_true()


func test_malformed_shuttle_in_world_save_is_refused() -> void:
	var mode := _main.get_node("BuildMode") as BuildMode
	var cart_id := 0
	for id in mode.grid.object_ids():
		if StringName(mode.grid.get_object(id)["def"]) == BaggageSim.CART_DEF:
			cart_id = id
			break
	if cart_id == 0:
		var offset := ReferenceTerminal.offset_on(mode.grid)
		var placed := mode.grid.apply(
			BuildEdit.place_object(&"baggage_cart", Vector2i(17, 14) + offset, 0)
		)
		assert_bool(placed.ok).is_true()
		cart_id = placed.object_id
		SaveTestKit.step(_main)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot()))
	var tick := int(snap["baggage"]["tick"])
	var base_shuttle := {
		"id": 1,
		"cart_id": cart_id,
		"flight": "GMF101-d0",
		"phase": BaggageShuttle.Phase.OUTBOUND,
		"start_tick": tick,
		"arrive_tick": tick + 40,
		"unload_tick": tick + 60,
		"return_tick": tick + 100,
		"origin_world": [0.0, 0.2, 0.0],
		"origin_yaw": 0.0,
		"target_world": [1.0, 0.2, -10.0],
		"target_yaw": 0.0,
		"waypoints": [[0.0, 0.2, 0.0], [1.0, 0.2, -10.0]],
		"bag_ids": [999_999],
		"driver_staff_id": 0,
	}
	# 1. Ghost bag_id in shuttle.bag_ids
	var bad_ghost: Dictionary = snap.duplicate(true)
	bad_ghost["baggage"]["next_shuttle_id"] = 2
	bad_ghost["baggage"]["shuttles"] = [base_shuttle.duplicate(true)]
	assert_bool(_save.load_world(bad_ghost)).is_false()
	assert_str(_save.message_text()).contains("baggage:")
	# 2. Settled bag_id in shuttle.bag_ids
	var bad_settled: Dictionary = snap.duplicate(true)
	var b0: Dictionary = bad_settled["baggage"]["bags"][0]
	b0["state"] = Bag.State.LOADED
	b0["remain_mm"] = 0
	b0["from"] = [0, 0]
	b0["from_desk"] = false
	b0["outcome_tick"] = tick
	var res: Dictionary = bad_settled["baggage"]["results"].get(
		b0["flight"], {"loaded": 0, "missed": 0, "causes": {}}
	)
	res["loaded"] = int(res["loaded"]) + 1
	bad_settled["baggage"]["results"][b0["flight"]] = res
	bad_settled["baggage"]["loaded_total"] = int(bad_settled["baggage"]["loaded_total"]) + 1
	var s_settled := base_shuttle.duplicate(true)
	s_settled["bag_ids"] = [int(b0["id"])]
	bad_settled["baggage"]["next_shuttle_id"] = 2
	bad_settled["baggage"]["shuttles"] = [s_settled]
	assert_bool(_save.load_world(bad_settled)).is_false()
	assert_str(_save.message_text()).contains("baggage:")
	# 3. Bad waypoints (fewer than 2 points)
	var bad_wp: Dictionary = snap.duplicate(true)
	var s_wp := base_shuttle.duplicate(true)
	s_wp["waypoints"] = [[0.0, 0.2, 0.0]]
	bad_wp["baggage"]["next_shuttle_id"] = 2
	bad_wp["baggage"]["shuttles"] = [s_wp]
	assert_bool(_save.load_world(bad_wp)).is_false()
	assert_str(_save.message_text()).contains("baggage:")
