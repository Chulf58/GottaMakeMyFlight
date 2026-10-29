class_name TestMoneyRooms
extends GdUnitTestSuite
## The currency exchange and ATM room types (F4-5b; decisions currency-
## exchange-and-atm-visits-front-cell-slot-small-fee-no-boredom and shop-room-
## types-share-the-shop-visit-pipeline-shop-flag-seat-piece-browse-slots): each
## is a shop on the kiosk's visit pipeline whose one required piece (the
## exchange counter or the ATM) is also its browse piece, with one slot in front
## of it. A visit pays a small fee and does not lower boredom
## (relieves_boredom false). The exchange counter needs a SHOP server; the ATM
## is self-service. Each room says what it misses until furnished, then is Ready.

## Room type -> [room tool, piece tool, the note while it has no piece, base
## spend, minimum size, its room rect, where its piece goes].
const MONEY := {
	&"exchange":
	[
		BuildMode.Tool.EXCHANGE_ROOM,
		BuildMode.Tool.EXCHANGE,
		"Needs an exchange counter",
		8,
		Vector2i(2, 3),
		Rect2i(3, 3, 2, 3),
		Vector2i(3, 4),
	],
	&"atm":
	[
		BuildMode.Tool.ATM_ROOM,
		BuildMode.Tool.ATM,
		"Needs an ATM",
		3,
		Vector2i(1, 2),
		Rect2i(3, 3, 1, 2),
		Vector2i(3, 3),
	],
}

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _mark(tool: BuildMode.Tool, rect: Rect2i) -> int:
	_mode.set_tool(tool)
	_mode.begin_area(_at(rect.position))
	_mode.move_area(_at(rect.end - Vector2i.ONE))
	_mode.finish_area()
	return _mode.grid.room_at(rect.position)


func test_each_money_type_is_a_shop_whose_one_piece_is_its_single_slot_browse_piece() -> void:
	for type: StringName in MONEY:
		var spec: Array = MONEY[type]
		var room := RoomTypes.get_type(type)
		assert_object(room).override_failure_message(str(type)).is_not_null()
		var piece := BuildMode.tool_object(spec[1])
		print("%s: piece %s, spend %d, min %s" % [type, piece, room.base_spend, room.min_size])
		assert_bool(room.shop).is_true()
		assert_bool(room.relieves_boredom).override_failure_message(str(type)).is_false()
		assert_int(room.base_spend).is_equal(spec[3])
		assert_array(room.required).is_equal([[piece, spec[2]]])
		assert_str(str(room.seat_piece)).is_equal(str(piece))
		assert_int(room.seats_per_piece).is_equal(1)
		assert_that(room.min_size).is_equal(spec[4])
		var size: Vector2i = spec[4]
		assert_bool(room.fits(size)).is_true()
		assert_bool(room.fits(Vector2i(size.y, size.x))).is_true()
		assert_bool(room.fits(size - Vector2i(0, 1))).is_false()
		assert_str(str(BuildMode.TOOL_ROOMS[spec[0]])).is_equal(str(type))
		assert_bool(BuildMode.ROOM_FOCUS_TOOLS.has(spec[0])).is_true()
		assert_bool(BuildMode.ROOM_FOCUS_TOOLS.has(spec[1])).is_true()
		assert_bool(BuildMode.AREA_TOOLS.has(spec[0])).is_true()
	# A fee is smaller than any store's spend; the exchange earns more than the ATM.
	assert_int(RoomTypes.get_type(&"exchange").base_spend).is_greater(
		RoomTypes.get_type(&"atm").base_spend
	)
	assert_int(RoomTypes.get_type(&"exchange").base_spend).is_less(
		RoomTypes.get_type(&"pharmacy").base_spend
	)
	# Every other shop lowers boredom.
	for other in [&"kiosk", &"pharmacy", &"duty_free", &"fashion"]:
		assert_bool(RoomTypes.get_type(other).relieves_boredom).is_true()


func test_the_exchange_counter_needs_a_server_and_the_atm_needs_none() -> void:
	assert_str(str(ShopCounters.COUNTER_ROOMS[&"currency_exchange"])).is_equal("exchange")
	assert_bool(ShopCounters.COUNTER_ROOMS.has(&"atm")).is_false()
	assert_bool(ShopCounters.SELF_SERVICE_ROOMS.has(&"atm")).is_true()
	assert_bool(ShopCounters.SELF_SERVICE_ROOMS.has(&"exchange")).is_false()


func test_each_money_room_says_what_it_misses_until_furnished_then_is_ready() -> void:
	for type: StringName in MONEY:
		var spec: Array = MONEY[type]
		var rect: Rect2i = spec[5]
		var room_id := _mark(spec[0], rect)
		assert_int(room_id).override_failure_message(str(type)).is_greater(0)
		var empty := Array(RoomRules.status(_mode.grid, room_id).notes)
		print("empty %s: %s" % [type, empty])
		assert_array(empty).is_equal([spec[2]])
		_mode.set_tool(spec[1])
		var placed := _mode.apply_at(_at(spec[6]))
		assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
		var status := RoomRules.status(_mode.grid, room_id)
		print("furnished %s: %s" % [type, status.headline()])
		assert_bool(status.ok).is_true()
		assert_str(status.headline()).is_equal(RoomRules.READY)
		assert_int(status.base_spend).is_equal(spec[3])
		_mode.set_tool(BuildMode.Tool.REMOVE)
		_mode.apply_at(_at(spec[6]))
		assert_array(Array(RoomRules.status(_mode.grid, room_id).notes)).is_equal([spec[2]])
		_mode.grid.apply(BuildEdit.remove_room(room_id))
