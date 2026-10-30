class_name TestActivityRooms
extends GdUnitTestSuite
## The activity and rest room types of F4-7 (decisions furniture-set-modelled-
## on-copenhagen-airport-decor-calms-pas and food-and-drink-cafe-bar-sit-down-
## restaurant-and-grab-and-go-st, point 3): the play area, the lounge, the
## shower and the nap pod are shop-pipeline rooms (RoomType.shop) with
## RoomType.activity set, each needing its catalogued pieces, with a dwell
## above the kiosk's browse and a mood bonus. Only the shower and the nap pod
## charge, at PriceTable's fees. All four are self-service.

const TYPES: Array[StringName] = [&"play_area", &"lounge", &"shower", &"nap_pod"]
## Room type -> [use piece, its slots per piece, minimum size].
const SHAPE := {
	&"play_area": [&"play_slide", 2, Vector2i(3, 4)],
	&"lounge": [&"lounge_sofa", 2, Vector2i(2, 3)],
	&"shower": [&"shower_cubicle", 1, Vector2i(2, 2)],
	&"nap_pod": [&"nap_pod", 1, Vector2i(2, 2)],
}
## Room type -> the tool that draws it.
const TOOLS := {
	&"play_area": BuildMode.Tool.PLAY_AREA_ROOM,
	&"lounge": BuildMode.Tool.LOUNGE_ROOM,
	&"shower": BuildMode.Tool.SHOWER_ROOM,
	&"nap_pod": BuildMode.Tool.NAP_POD_ROOM,
}


func test_each_type_is_an_activity_room_on_the_shop_pipeline_needing_catalogued_pieces() -> void:
	for type in TYPES:
		var room := RoomTypes.get_type(type)
		print(
			(
				"%s: pieces %s, dwell %d, mood %d, fee %d"
				% [type, room.required, room.dwell_ticks, room.mood_bonus, room.base_spend]
			)
		)
		assert_bool(room.shop).is_true()
		assert_bool(room.activity).is_true()
		assert_bool(room.relieves_boredom).is_true()
		assert_bool(room.food).is_false()
		assert_str(str(room.seat_piece)).is_equal(str(SHAPE[type][0]))
		assert_int(room.seats_per_piece).is_equal(SHAPE[type][1])
		assert_that(room.min_size).is_equal(SHAPE[type][2])
		assert_int(room.dwell_ticks).is_greater(ShopSim.BROWSE_TICKS)
		assert_int(room.mood_bonus).is_greater(0)
		for need: Array in room.required:
			assert_object(BuildCatalog.get_def(need[0])).is_not_null()
		assert_array(ids_of(room)).contains([room.seat_piece])
		assert_int(ShopSim.browse_ticks(room)).is_equal(room.dwell_ticks)
	# Control: the kiosk and the money rooms set no dwell, so they keep the browse.
	for other: StringName in [&"kiosk", &"pharmacy", &"exchange", &"atm"]:
		var room := RoomTypes.get_type(other)
		assert_bool(room.activity).override_failure_message(str(other)).is_false()
		assert_int(ShopSim.browse_ticks(room)).is_equal(ShopSim.BROWSE_TICKS)
		assert_int(room.mood_bonus).is_equal(0)


func ids_of(room: RoomTypes.RoomType) -> Array:
	var out := []
	for need: Array in room.required:
		out.append(need[0])
	return out


func test_only_the_shower_and_the_nap_pod_charge_and_at_the_price_table_fees() -> void:
	assert_int(RoomTypes.get_type(&"shower").base_spend).is_equal(PriceTable.SHOWER_FEE)
	assert_int(RoomTypes.get_type(&"nap_pod").base_spend).is_equal(PriceTable.NAP_POD_FEE)
	assert_int(RoomTypes.get_type(&"play_area").base_spend).is_equal(0)
	assert_int(RoomTypes.get_type(&"lounge").base_spend).is_equal(0)
	assert_int(PriceTable.SHOWER_FEE).is_greater(0)
	assert_int(PriceTable.NAP_POD_FEE).is_greater(0)


func test_the_four_are_self_service_and_no_shopping_wish() -> void:
	for type in TYPES:
		assert_bool(ShopCounters.SELF_SERVICE_ROOMS.has(type)).is_true()
		assert_bool(WishTable.CANDIDATES.has(type)).is_false()
		for counter: StringName in ShopCounters.COUNTER_ROOMS:
			assert_str(str(ShopCounters.COUNTER_ROOMS[counter])).is_not_equal(str(type))


func test_each_room_tool_draws_its_type() -> void:
	for type in TYPES:
		assert_str(str(BuildMode.TOOL_ROOMS[TOOLS[type]])).is_equal(str(type))
		assert_bool(BuildMode.AREA_TOOLS.has(TOOLS[type])).is_true()
		assert_bool(BuildMode.ROOM_FOCUS_TOOLS.has(TOOLS[type])).is_true()


func test_a_room_with_its_pieces_is_ready_and_slots_are_the_cells_in_front() -> void:
	for type in TYPES:
		var grid := BuildGrid.new()
		var ids := ActivityTestLayout.build(grid, type)
		var status := RoomRules.status(grid, ids["room"])
		assert_bool(status.ok).override_failure_message("%s: %s" % [type, status.notes]).is_true()
		assert_int(status.seats).is_equal(SHAPE[type][1])
		var layout := ShopLayout.new()
		layout.rebuild(grid)
		assert_int(layout.shops.size()).is_equal(1)
		var slots: Array = layout.shops[0]["slots"]
		assert_int(slots.size()).is_equal(SHAPE[type][1])
		assert_that(slots[0]["approach"]).is_equal(Vector2i(22, 4))
