class_name TestRoomTemplates
extends GdUnitTestSuite
## Room templates (decision room-templates-store-rooms-with-their-pieces-kept-
## in-each-sa): a saved store room keeps its type, size and pieces; a paste
## places all of it at full price or nothing with its reason; R turns the room
## and every piece; one Ctrl+Z removes a paste and refunds it; the list
## survives a snapshot through JSON.
##
## The grid is 20x20 with floor on columns 2 to 17 and rows 2 to 15. The cafe
## that is saved covers columns 3 to 7 and rows 3 to 6, with a counter along
## its north side and a table along its south side.

const CAFE := Rect2i(3, 3, 5, 4)
const COUNTER_AT := Vector2i(4, 3)
const TABLE_AT := Vector2i(4, 5)
## The cell a paste is centred on: the pasted cafe covers columns 10 to 14 and
## rows 4 to 7 unturned.
const FREE_CENTRE := Vector2i(12, 5)

var _mode: BuildMode
var _finances: Finances
var _paste: TemplatePaste
var _room := 0


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	_paste = _mode.templates
	var edits: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(2, 18):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_room = _commit(BuildEdit.place_room(CAFE, &"cafe")).room_id
	_commit(BuildEdit.place_object(&"cafe_counter", COUNTER_AT, 0))
	_commit(BuildEdit.place_object(&"cafe_table", TABLE_AT, 0))
	_mode.clear_undo()


func after_test() -> void:
	_mode.free()
	_finances.free()


func _commit(edit: BuildEdit) -> BuildResult:
	var plan: Array[BuildEdit] = [edit]
	var result := BuildTransaction.commit_plan(_mode.grid, plan, _mode.wallet())
	var why := "setup edit refused: %s" % result.reason_text()
	assert_bool(result.ok).override_failure_message(why).is_true()
	return result


func _saved() -> RoomTemplate:
	return _paste.save_room(_room)


func _balance() -> int:
	return _mode.wallet().balance


## Every object's {def, cells sorted, facing} in grid order, for comparing whole layouts.
func _layout() -> Array:
	var out: Array = []
	for object_id in _mode.grid.object_ids():
		var record := _mode.grid.get_object(object_id)
		out.append([record["def"], record["anchor"], record["facing"]])
	return out


## The objects whose anchor lies in `rect`, as {def: [footprint cells sorted, facing]}.
func _pieces_in(rect: Rect2i) -> Dictionary:
	var out := {}
	for object_id in _mode.grid.object_ids():
		var record := _mode.grid.get_object(object_id)
		if rect.has_point(record["anchor"]):
			var cells := BuildCatalog.get_def(record["def"]).footprint(
				record["anchor"], record["facing"]
			)
			cells.sort()
			out[record["def"]] = [cells, record["facing"]]
	return out


func test_saving_a_room_keeps_its_type_size_and_pieces_from_its_corner() -> void:
	var template := _saved()
	assert_str(String(template.room_type)).is_equal("cafe")
	assert_that(template.size).is_equal(Vector2i(5, 4))
	assert_str(template.name).is_equal("Cafe 5x4")
	(
		assert_array(template.pieces)
		. is_equal(
			[
				{"def": &"cafe_counter", "anchor": COUNTER_AT - CAFE.position, "facing": 0},
				{"def": &"cafe_table", "anchor": TABLE_AT - CAFE.position, "facing": 0},
			]
		)
	)
	assert_int(_paste.library.size()).is_equal(1)
	assert_str(_paste.status_text()).is_equal("Saved template Cafe 5x4")


func test_a_piece_outside_the_room_and_desks_scanners_doors_are_not_kept() -> void:
	_commit(BuildEdit.place_object(&"plant_pot_1a", Vector2i(9, 4), 0))
	assert_int(_saved().pieces.size()).is_equal(2)
	for kept in [&"cafe_counter", &"cafe_table", &"plant_pot_1a", &"baggage_belt_end"]:
		assert_bool(RoomTemplate.keeps_piece(kept)).is_true()
	for left_out in [&"checkin_desk", &"security_scanner", &"tray_table", &"entrance_door"]:
		var kept := RoomTemplate.keeps_piece(left_out)
		assert_bool(kept).override_failure_message(String(left_out)).is_false()


func test_a_paste_places_the_room_and_every_piece_at_full_price() -> void:
	_saved()
	_paste.arm(0)
	var before := _balance()
	var price := (
		PriceTable.price_of_object(&"cafe_counter") + PriceTable.price_of_object(&"cafe_table")
	)
	assert_int(price).is_greater(0)
	var plan := _paste.library.get_template(0).plan(FREE_CENTRE, 0)
	assert_int(BuildTransaction.needed(_mode.grid, plan)).is_equal(price)
	var result := _paste.paste_at(FREE_CENTRE)
	assert_bool(result.ok).is_true()
	var pasted := _mode.grid.room_at(Vector2i(10, 4))
	assert_int(pasted).is_not_equal(_room)
	assert_that(_mode.grid.get_room(pasted)["rect"]).is_equal(Rect2i(10, 4, 5, 4))
	assert_str(String(_mode.grid.get_room(pasted)["type"])).is_equal("cafe")
	var shift := Vector2i(10, 4) - CAFE.position
	var original := _pieces_in(CAFE)
	var copy := _pieces_in(Rect2i(10, 4, 5, 4))
	for def_id in original:
		var cells: Array = []
		for cell in original[def_id][0]:
			cells.append(cell + shift)
		assert_array(copy[def_id][0]).is_equal(cells)
		assert_int(copy[def_id][1]).is_equal(original[def_id][1])
	assert_int(_balance()).is_equal(before - price)
	assert_bool(RoomRules.status(_mode.grid, pasted).ok).is_equal(
		RoomRules.status(_mode.grid, _room).ok
	)
	assert_str(_paste.status_text()).is_equal("Placed Cafe 5x4 for %d" % price)


func test_a_turned_paste_turns_the_room_and_every_piece_a_quarter() -> void:
	_saved()
	_paste.arm(0)
	_paste.rotate_turns()
	assert_bool(_paste.paste_at(FREE_CENTRE).ok).is_true()
	# Turned, the 5x4 cafe is 4x5, centred on the same cell: columns 11 to 14,
	# rows 3 to 7.
	var rect := Rect2i(11, 3, 4, 5)
	var pasted := _mode.grid.room_at(rect.position)
	assert_that(_mode.grid.get_room(pasted)["rect"]).is_equal(rect)
	# A quarter turn takes cell (x, y) of a W x H room to (H - 1 - y, x).
	var original := _pieces_in(CAFE)
	var turned := _pieces_in(rect)
	assert_int(turned.size()).is_equal(2)
	for def_id in original:
		var cells: Array[Vector2i] = []
		for cell in original[def_id][0]:
			var local: Vector2i = cell - CAFE.position
			cells.append(rect.position + Vector2i(CAFE.size.y - 1 - local.y, local.x))
		cells.sort()
		assert_array(turned[def_id][0]).override_failure_message(String(def_id)).is_equal(cells)
		assert_int(turned[def_id][1]).is_equal((original[def_id][1] + 1) % 4)


func test_r_turns_the_armed_paste_and_four_turns_come_back() -> void:
	_saved()
	_paste.arm(0)
	var press := InputEventAction.new()
	press.action = &"build_rotate"
	press.pressed = true
	# Through the viewport, so the paste (a child) must take R before BuildMode,
	# which would turn its own facing instead.
	var facing := _mode.facing
	get_viewport().push_input(press)
	assert_int(_paste.turns).is_equal(1)
	assert_int(_mode.facing).is_equal(facing)
	for i in 3:
		_paste.rotate_turns()
	assert_int(_paste.turns).is_equal(0)


func test_a_paste_over_another_room_is_refused_with_its_reason_and_changes_nothing() -> void:
	_saved()
	_paste.arm(0)
	var layout := _layout()
	var rooms := _mode.grid.room_ids()
	var before := _balance()
	var result := _paste.paste_at(Vector2i(8, 5))
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.ROOM_OVERLAP)
	assert_str(_paste.status_text()).is_equal("Cafe 5x4  " + result.reason_text())
	assert_str(result.reason_text()).is_not_empty()
	assert_array(_mode.grid.room_ids()).is_equal(rooms)
	assert_array(_layout()).is_equal(layout)
	assert_int(_balance()).is_equal(before)
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_a_paste_over_a_piece_is_refused_whole() -> void:
	_saved()
	_paste.arm(0)
	_commit(BuildEdit.place_object(&"plant_pot_1a", Vector2i(12, 4), 0))
	var layout := _layout()
	var result := _paste.paste_at(FREE_CENTRE)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.OVERLAP)
	assert_int(_mode.grid.room_at(Vector2i(10, 4))).is_equal(0)
	assert_array(_layout()).is_equal(layout)


func test_a_paste_the_wallet_cannot_pay_is_refused_and_changes_nothing() -> void:
	_saved()
	_paste.arm(0)
	# The cafe goes on floor already laid, so only its pieces are charged.
	var price := (
		PriceTable.price_of_object(&"cafe_counter") + PriceTable.price_of_object(&"cafe_table")
	)
	var wallet := _mode.wallet()
	assert_bool(wallet.spend(wallet.balance - (price - 1), Wallet.Category.BUILD)).is_true()
	var layout := _layout()
	var before := _balance()
	var result := _paste.paste_at(FREE_CENTRE)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_str(_paste.status_text()).is_equal("Cafe 5x4  " + result.reason_text())
	assert_int(_mode.grid.room_at(Vector2i(10, 4))).is_equal(0)
	assert_array(_layout()).is_equal(layout)
	assert_int(_balance()).is_equal(before)


func test_one_undo_removes_the_pasted_room_and_pieces_and_refunds_them() -> void:
	_saved()
	_paste.arm(0)
	var layout := _layout()
	var rooms := _mode.grid.room_ids()
	var before := _balance()
	assert_bool(_paste.paste_at(FREE_CENTRE).ok).is_true()
	assert_int(_layout().size()).is_equal(layout.size() + 2)
	assert_int(_mode.undo_history().size()).is_equal(1)
	assert_bool(_mode.undo().ok).is_true()
	assert_array(_mode.grid.room_ids()).is_equal(rooms)
	assert_array(_layout()).is_equal(layout)
	assert_int(_balance()).is_equal(before)
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_templates_survive_a_snapshot_through_json() -> void:
	_saved()
	_paste.rotate_turns()
	var data: Dictionary = JSON.parse_string(JSON.stringify(_paste.library.to_snapshot()))
	var loaded := RoomTemplates.new()
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_int(loaded.size()).is_equal(1)
	assert_dict(loaded.to_snapshot()).is_equal(_paste.library.to_snapshot())
	var a := _paste.library.get_template(0)
	var b := loaded.get_template(0)
	for turns in 4:
		var mine := a.plan(FREE_CENTRE, turns)
		var theirs := b.plan(FREE_CENTRE, turns)
		for i in mine.size():
			(
				assert_that([theirs[i].kind, theirs[i].cell, theirs[i].def_id, theirs[i].facing])
				. is_equal([mine[i].kind, mine[i].cell, mine[i].def_id, mine[i].facing])
			)


func test_a_bad_templates_snapshot_is_refused_and_keeps_the_list() -> void:
	_saved()
	var good := _paste.library.to_snapshot()
	var cases := {
		"unknown room type": func(d: Dictionary) -> void: d["templates"][0]["type"] = "spa",
		"a desk":
		func(d: Dictionary) -> void: d["templates"][0]["pieces"][0]["def"] = "checkin_desk",
		"piece outside":
		func(d: Dictionary) -> void: d["templates"][0]["pieces"][0]["anchor"] = [9, 0],
		"bad facing": func(d: Dictionary) -> void: d["templates"][0]["pieces"][0]["facing"] = 4,
		"zero size": func(d: Dictionary) -> void: d["templates"][0]["size"] = [0, 4],
		"version": func(d: Dictionary) -> void: d["save_version"] = 2,
		"short floor": func(d: Dictionary) -> void: d["templates"][0]["floor"].pop_back(),
		"bad floor type": func(d: Dictionary) -> void: d["templates"][0]["floor"][0] = [0, 1],
		"extra key": func(d: Dictionary) -> void: d["templates"][0]["colour"] = 1,
	}
	for label in cases:
		var bad: Dictionary = JSON.parse_string(JSON.stringify(good))
		cases[label].call(bad)
		assert_bool(_paste.library.from_snapshot(bad)).override_failure_message(label).is_false()
		assert_dict(_paste.library.to_snapshot()).override_failure_message(label).is_equal(good)


func test_a_tool_change_disarms_the_paste_and_saving() -> void:
	_saved()
	_paste.arm(0)
	assert_bool(_paste.is_active()).is_true()
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_int(_paste.armed).is_equal(-1)
	_paste.arm_capture()
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_bool(_paste.is_active()).is_false()


func test_a_click_while_saving_saves_the_room_under_it() -> void:
	_paste.arm_capture()
	assert_object(_paste.click(Vector2i(15, 12))).is_null()
	assert_int(_paste.library.size()).is_equal(0)
	assert_bool(_paste.capturing).is_true()
	_paste.click(Vector2i(5, 4))
	assert_int(_paste.library.size()).is_equal(1)
	assert_bool(_paste.capturing).is_false()
