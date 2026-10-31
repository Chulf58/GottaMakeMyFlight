class_name TestRoomTemplatesBeltsFloor
extends GdUnitTestSuite
## Room templates with belts and floor (decision room-templates-store-rooms-
## with-their-pieces-kept-in-each-sa, user rulings "Inside belts only" and "Lay
## floor too"): a bag room keeps the belt cells inside it and not the run
## leading out; a paste reshapes its belts and, once the player draws the link,
## bags have a route into it; a paste on bare ground lays the floor and charges
## for it, a paste over floor does not; a refused paste lays nothing.
##
## The grid is 24x20 with floor on columns 2 to 21 and rows 2 to 9; rows 10 to
## 19 are bare ground. The bag room covers columns 10 to 12 and rows 3 to 5; a
## belt runs along row 4 from column 8, outside the room, to its end at column 11.

const BAG_ROOM := Rect2i(10, 3, 3, 3)
## Paste centres: on the floor east of the bag room, and on bare ground.
const ON_FLOOR := Vector2i(17, 4)
const ON_GROUND := Vector2i(17, 14)

var _mode: BuildMode
var _finances: Finances
var _paste: TemplatePaste
var _room := 0


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(24, 20)
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	_paste = _mode.templates
	var edits: Array[BuildEdit] = []
	for y in range(2, 10):
		for x in range(2, 22):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	var plan: Array[BuildEdit] = [BuildEdit.place_room(BAG_ROOM, &"bag_room")]
	_room = BuildTransaction.commit_plan(_mode.grid, plan, _mode.wallet()).room_id
	assert_bool(_mode.lay_belt(Vector2i(8, 4), Vector2i(11, 4)).ok).is_true()
	assert_str(String(_def_at(Vector2i(11, 4)))).is_equal("baggage_belt_end")
	_mode.clear_undo()


func after_test() -> void:
	_mode.free()
	_finances.free()


func _def_at(cell: Vector2i) -> StringName:
	var object_id := _mode.grid.object_at(cell)
	return _mode.grid.get_object(object_id).get("def", &"") if object_id != 0 else &""


func _balance() -> int:
	return _mode.wallet().balance


func _saved_and_armed() -> RoomTemplate:
	var template := _paste.save_room(_room)
	_paste.arm(0)
	return template


func _belt_price() -> int:
	return PriceTable.price_of_object(&"baggage_belt")


## Every cell's floor and every object, for proving nothing changed.
func _state() -> Array:
	var objects: Array = []
	for object_id in _mode.grid.object_ids():
		var record := _mode.grid.get_object(object_id)
		objects.append([record["def"], record["anchor"], record["facing"]])
	var floors: Array = []
	for y in _mode.grid.size.y:
		for x in _mode.grid.size.x:
			floors.append(_mode.grid.floor_at(Vector2i(x, y)))
	return [objects, floors, _mode.grid.room_ids(), _balance()]


func test_a_belt_leaving_the_room_keeps_only_its_cells_inside() -> void:
	var template := _paste.save_room(_room)
	# Kept as plain belts (the shape comes back from the links after a paste).
	var kept: Array = []
	for piece in template.pieces:
		kept.append([piece["def"], piece["anchor"]])
	assert_array(kept).is_equal(
		[[&"baggage_belt", Vector2i(0, 1)], [&"baggage_belt", Vector2i(1, 1)]]
	)
	assert_int(template.floors.size()).is_equal(9)
	assert_that(template.floors[0]).is_equal(Vector2i(BuildGrid.FLOOR_TILE, 1))


func test_a_pasted_bag_room_reshapes_its_belt_and_takes_bags_once_linked() -> void:
	_saved_and_armed()
	var before := _balance()
	assert_bool(_paste.paste_at(ON_FLOOR).ok).is_true()
	var pasted := _mode.grid.room_at(Vector2i(16, 3))
	assert_that(_mode.grid.get_room(pasted)["rect"]).is_equal(Rect2i(16, 3, 3, 3))
	# Both cells were laid as plain belts; the inner one is now the end bags rest on.
	assert_str(String(_def_at(Vector2i(17, 4)))).is_equal("baggage_belt_end")
	assert_bool(RoomRules.status(_mode.grid, pasted).ok).is_true()
	assert_int(_balance()).is_equal(before - 2 * _belt_price())
	# The player draws the link from outside; the bags' route reaches the end.
	assert_bool(_mode.lay_belt(Vector2i(14, 4), Vector2i(15, 4)).ok).is_true()
	assert_str(String(_def_at(Vector2i(16, 4)))).is_equal("baggage_belt")
	assert_str(String(_def_at(Vector2i(17, 4)))).is_equal("baggage_belt_end")
	var routes := BagRoutes.build(_mode.grid)
	assert_bool(routes.is_root(Vector2i(17, 4))).is_true()
	assert_bool(routes.has_route(Vector2i(14, 4))).is_true()
	assert_int(routes.dist[Vector2i(14, 4)]).is_equal(3)


func test_a_paste_on_bare_ground_lays_the_floor_and_charges_for_it() -> void:
	var template := _saved_and_armed()
	var rect := template.rect_at(ON_GROUND, 0)
	var price := 9 * PriceTable.price_of_floor() + 2 * _belt_price()
	assert_int(PriceTable.price_of_floor()).is_greater(0)
	var plan := template.plan(ON_GROUND, 0, _mode.grid)
	assert_int(BuildTransaction.needed(_mode.grid, plan)).is_equal(price)
	var before := _balance()
	assert_bool(_paste.paste_at(ON_GROUND).ok).is_true()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			assert_int(_mode.grid.floor_at(Vector2i(x, y))).is_equal(BuildGrid.FLOOR_TILE)
			assert_int(_mode.grid.zone_at(Vector2i(x, y))).is_equal(1)
	assert_int(_mode.grid.room_at(rect.position)).is_not_equal(0)
	assert_int(_balance()).is_equal(before - price)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.floor_at(rect.position)).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_balance()).is_equal(before)


func test_a_paste_over_floor_does_not_charge_for_floor() -> void:
	var template := _saved_and_armed()
	var plan := template.plan(ON_FLOOR, 0, _mode.grid)
	for edit in plan:
		assert_int(edit.kind).is_not_equal(BuildEdit.Kind.PAINT_FLOOR)
	var before := _balance()
	assert_bool(_paste.paste_at(ON_FLOOR).ok).is_true()
	assert_int(_balance()).is_equal(before - 2 * _belt_price())


func test_a_paste_partly_off_the_grid_is_refused_and_lays_no_floor() -> void:
	_saved_and_armed()
	var state := _state()
	# Centred on row 19, the room would cover rows 18 to 20; row 20 is off the grid.
	var result := _paste.paste_at(Vector2i(17, 19))
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.OUT_OF_BOUNDS)
	assert_array(_state()).is_equal(state)
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_a_paste_on_bare_ground_the_wallet_cannot_pay_lays_nothing() -> void:
	_saved_and_armed()
	var price := 9 * PriceTable.price_of_floor() + 2 * _belt_price()
	var wallet := _mode.wallet()
	assert_bool(wallet.spend(wallet.balance - (price - 1), Wallet.Category.BUILD)).is_true()
	var state := _state()
	var result := _paste.paste_at(ON_GROUND)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_array(_state()).is_equal(state)
	assert_int(_mode.undo_history().size()).is_equal(0)
