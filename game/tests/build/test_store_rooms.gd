class_name TestStoreRooms
extends GdUnitTestSuite
## The pharmacy, duty free and fashion room types and their tools (F4-5;
## decisions store-mechanics-draw-a-room-then-furnish-it-required-pieces and
## duty-free-and-fashion-shops-get-their-own-blender-retail-kit): each is a
## per-visit shop like the kiosk, dragged out with its room tool and furnished
## with its counter or till and its browse pieces. The room says what it is
## missing until it has both, and is Ready once it has. The four retail pieces
## are catalogued, priced and drawn with their own kit models.

const ROOM := Rect2i(3, 3, 4, 4)
const COUNTER_AT := Vector2i(3, 3)
const PIECE_AT := Vector2i(5, 5)
## Store type -> [room tool, counter tool, piece tool, notes in order].
const STORES := {
	&"pharmacy":
	[
		BuildMode.Tool.PHARMACY_ROOM,
		BuildMode.Tool.PHARMACY_COUNTER,
		BuildMode.Tool.PHARMACY_SHELF,
		["Needs a pharmacy counter", "Needs a shelf"],
	],
	&"duty_free":
	[
		BuildMode.Tool.DUTY_FREE_ROOM,
		BuildMode.Tool.DUTY_FREE_TILL,
		BuildMode.Tool.DUTY_FREE_SHELF,
		["Needs a till", "Needs a shelf"],
	],
	&"fashion":
	[
		BuildMode.Tool.FASHION_ROOM,
		BuildMode.Tool.FASHION_TILL,
		BuildMode.Tool.FASHION_RAIL,
		["Needs a till", "Needs a clothes rail"],
	],
}
const RETAIL_IDS: Array[StringName] = [
	&"duty_free_shelf", &"duty_free_till", &"fashion_rail", &"fashion_till"
]
## The mounts that name where a passenger stands to use a piece; the first
## one a piece has is its interaction cell.
const USE_MOUNTS: Array[String] = ["Mount_Order", "Mount_Browse_0"]
const HEIGHT_SLACK := 0.02

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


func _click(tool: BuildMode.Tool, cell: Vector2i) -> BuildResult:
	_mode.set_tool(tool)
	return _mode.apply_at(_at(cell))


func _notes(room_id: int) -> Array:
	return Array(RoomRules.status(_mode.grid, room_id).notes)


## Where a piece's mount sits in the piece's frame, or null when it has none.
func _mount(piece: String, mount_name: String) -> Variant:
	var root := InteriorKit.instantiate(piece)
	var node := root.find_child(mount_name, true, false) as Node3D
	var found: Variant = null
	if node != null:
		var xf := node.transform
		var parent := node.get_parent()
		while parent != root:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		found = xf
	root.free()
	return found


func test_each_store_type_is_a_shop_with_its_pieces_size_and_spend() -> void:
	var spends := {&"pharmacy": 10, &"duty_free": 25, &"fashion": 30}
	for type: StringName in STORES:
		var room := RoomTypes.get_type(type)
		assert_object(room).override_failure_message(str(type)).is_not_null()
		assert_bool(room.shop).is_true()
		assert_int(room.base_spend).is_equal(spends[type])
		var counter := BuildMode.tool_object(STORES[type][1])
		var piece := BuildMode.tool_object(STORES[type][2])
		assert_array(room.required).is_equal(
			[[counter, STORES[type][3][0]], [piece, STORES[type][3][1]]]
		)
		assert_str(str(room.seat_piece)).is_equal(str(piece))
		assert_int(room.seats_per_piece).is_equal(StoreTestLayout.STORES[type][2])
		assert_bool(room.fits(ROOM.size)).is_true()
		assert_bool(room.fits(Vector2i(2, 2))).is_false()
		assert_str(str(BuildMode.TOOL_ROOMS[STORES[type][0]])).is_equal(str(type))
		for tool in STORES[type]:
			if tool is int:
				assert_bool(BuildMode.ROOM_FOCUS_TOOLS.has(tool)).is_true()
		assert_str(str(ShopCounters.COUNTER_ROOMS[counter])).is_equal(str(type))
	# The kiosk is the first shop; cafes, toilets and bag rooms are none.
	assert_bool(RoomTypes.get_type(&"kiosk").shop).is_true()
	for other in [&"cafe", &"toilet", &"bag_room"]:
		assert_bool(RoomTypes.get_type(other).shop).is_false()


func test_each_store_says_what_it_misses_until_furnished_then_is_ready() -> void:
	for type: StringName in STORES:
		var tools: Array = STORES[type]
		var room_id := _mark(tools[0], ROOM)
		assert_int(room_id).override_failure_message(str(type)).is_greater(0)
		var empty := _notes(room_id)
		print("empty %s: %s" % [type, empty])
		assert_array(empty).is_equal(tools[3])
		assert_bool(_click(tools[1], COUNTER_AT).ok).is_true()
		assert_array(_notes(room_id)).is_equal([tools[3][1]])
		assert_bool(_click(tools[2], PIECE_AT).ok).is_true()
		var status := RoomRules.status(_mode.grid, room_id)
		print("furnished %s: %s" % [type, status.headline()])
		assert_bool(status.ok).is_true()
		assert_str(status.headline()).is_equal(RoomRules.READY)
		assert_int(status.base_spend).is_equal(RoomTypes.get_type(type).base_spend)
		# The counter alone is not enough: without the browse piece it is not ready.
		_mode.set_tool(BuildMode.Tool.REMOVE)
		_mode.apply_at(_at(PIECE_AT))
		assert_array(_notes(room_id)).is_equal([tools[3][1]])
		_mode.apply_at(_at(COUNTER_AT))
		_mode.grid.apply(BuildEdit.remove_room(room_id))


func test_the_retail_pieces_are_catalogued_priced_and_drawn_with_their_own_models() -> void:
	for id in RETAIL_IDS:
		var def := BuildCatalog.get_def(id)
		assert_object(def).override_failure_message(str(id)).is_not_null()
		assert_that(def.size).is_equal(Vector2i(2, 1))
		assert_str(def.display_name).is_not_empty()
		assert_int(PriceTable.price_of_object(id)).is_greater(0)
		assert_str(InteriorKit.object_piece(id)).is_equal(str(id))
		var parts := InteriorKit.meshes(str(id))
		assert_int(parts.size()).is_greater(0)
		var box := AABB()
		for i in parts.size():
			var part_box: AABB = (parts[i][1] as Transform3D) * (parts[i][0] as Mesh).get_aabb()
			box = part_box if i == 0 else box.merge(part_box)
		print(
			(
				"%s: top %.3f, height %.3f, price %d"
				% [id, box.end.y, def.height, PriceTable.price_of_object(id)]
			)
		)
		assert_float(def.height).is_between(box.end.y - 0.001, box.end.y + HEIGHT_SLACK)
		# The interaction cell is the model's order or first browse mount.
		var xf: Variant = null
		for mount_name in USE_MOUNTS:
			if xf == null:
				xf = _mount(str(id), mount_name)
		assert_object(xf).override_failure_message(str(id)).is_not_null()
		var at: Vector3 = (xf as Transform3D).origin
		var cell := Vector2i(floori(at.x + def.size.x / 2.0), floori(at.z + def.size.y / 2.0))
		assert_bool(def.has_interaction).is_true()
		assert_that(def.interaction_offset).is_equal(cell)
	# A till costs about the pharmacy counter; a shelf or rail about its shelf.
	for till in [&"duty_free_till", &"fashion_till"]:
		assert_int(PriceTable.price_of_object(till)).is_greater(
			PriceTable.price_of_object(&"duty_free_shelf")
		)
