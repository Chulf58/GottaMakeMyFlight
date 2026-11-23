class_name TestMoneyRooms
extends GdUnitTestSuite
## The currency exchange and ATM standalone corridor services (Slice B1a;
## decisions c221025a and 593876df): each is a ServiceTypes standalone service
## on the shop visit pipeline whose piece (the exchange counter or the ATM) is
## placed directly on walkable terminal floor with zero room zone required and
## provides one slot in front of it. A visit pays a small fee and does not lower
## boredom (relieves_boredom false). The exchange counter needs a SHOP server;
## the ATM is self-service.

## Service id -> [piece tool, base spend, where its piece goes].
const MONEY := {
	&"exchange": [BuildMode.Tool.EXCHANGE, 8, Vector2i(3, 4)],
	&"atm": [BuildMode.Tool.ATM, 3, Vector2i(3, 3)],
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
	EnclosureKit.close_floor(_mode.grid)


func after_test() -> void:
	_mode.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func test_each_money_type_is_a_standalone_service_not_in_room_types() -> void:
	for type: StringName in MONEY:
		assert_object(RoomTypes.get_type(type)).is_null()
		var spec: Array = MONEY[type]
		var svc := ServiceTypes.get_service(type)
		assert_object(svc).override_failure_message(str(type)).is_not_null()
		var piece := BuildMode.tool_object(spec[0])
		print("%s: piece %s, spend %d" % [type, piece, svc.base_spend])
		assert_bool(svc.shop).is_true()
		assert_bool(svc.relieves_boredom).override_failure_message(str(type)).is_false()
		assert_int(svc.base_spend).is_equal(spec[1])
		assert_str(str(svc.seat_piece)).is_equal(str(piece))
		assert_int(svc.seats_per_piece).is_equal(1)
		assert_bool(BuildMode.ROOM_FOCUS_TOOLS.has(spec[0])).is_false()
	# A fee is smaller than any store's spend; the exchange earns more than the ATM.
	assert_int(ServiceTypes.get_service(&"exchange").base_spend).is_greater(
		ServiceTypes.get_service(&"atm").base_spend
	)
	assert_int(ServiceTypes.get_service(&"exchange").base_spend).is_less(
		RoomTypes.get_type(&"pharmacy").base_spend
	)
	# Every other shop lowers boredom.
	for other in [&"kiosk", &"pharmacy", &"duty_free", &"fashion"]:
		assert_bool(RoomTypes.get_type(other).relieves_boredom).is_true()


func test_the_exchange_counter_needs_a_server_and_the_atm_needs_none() -> void:
	assert_str(str(ShopCounters.COUNTER_ROOMS[&"currency_exchange"])).is_equal("")
	assert_bool(ShopCounters.ROOMLESS.has(&"currency_exchange")).is_true()
	assert_bool(ShopCounters.COUNTER_ROOMS.has(&"atm")).is_false()
	assert_bool(ShopCounters.SELF_SERVICE_ROOMS.has(&"atm")).is_false()
	assert_bool(ShopCounters.SELF_SERVICE_ROOMS.has(&"exchange")).is_false()
	assert_bool(ServiceTypes.get_service(&"exchange").needs_staff).is_true()
	assert_bool(ServiceTypes.get_service(&"atm").needs_staff).is_false()


func test_each_money_piece_places_on_corridor_floor_with_no_room_and_provides_a_slot() -> void:
	for type: StringName in MONEY:
		var spec: Array = MONEY[type]
		var cell: Vector2i = spec[2]
		assert_int(_mode.grid.room_at(cell)).is_equal(0)
		_mode.set_tool(spec[0])
		var placed := _mode.apply_at(_at(cell))
		assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
		assert_int(_mode.grid.room_at(cell)).is_equal(0)
		var layout := ShopLayout.new()
		layout.rebuild(_mode.grid)
		assert_int(layout.shops.size()).is_equal(1)
		assert_int(layout.shops[0]["room"]).is_equal(0)
		assert_str(str(layout.shops[0]["type"])).is_equal(str(type))
		assert_int(layout.shops[0]["slots"].size()).is_equal(1)
		_mode.set_tool(BuildMode.Tool.REMOVE)
		_mode.apply_at(_at(cell))
		layout.rebuild(_mode.grid)
		assert_int(layout.shops.size()).is_equal(0)
