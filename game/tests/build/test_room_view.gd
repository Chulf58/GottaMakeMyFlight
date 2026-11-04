class_name TestRoomView
extends GdUnitTestSuite
## RoomView inside BuildMode: each room gets a floor tint and a label with its
## type and what it needs, redrawn on the frame after any grid edit or load.

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(16, 12)
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in range(1, 11):
		for x in range(1, 15):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()


func _view() -> RoomView:
	return _mode.get_node("RoomView") as RoomView


func _tint(room_id: int) -> MeshInstance3D:
	return _view().get_node("RoomTint%d" % room_id) as MeshInstance3D


func test_a_new_room_is_labelled_with_what_it_needs() -> void:
	var room_id := _mode.grid.apply(BuildEdit.place_room(Rect2i(2, 2, 5, 4), &"cafe")).room_id
	assert_object(_view().label_of(room_id)).is_null()
	await _next_frame()
	var label := _view().label_of(room_id)
	assert_str(label.text).is_equal("Cafe\nNeeds a counter\nNeeds a table")
	assert_that(label.modulate).is_equal(RoomView.NEEDS_TEXT)
	var middle := _mode.grid.cell_to_world(Vector2i(2, 2)) + Vector3(2.0, 0.0, 1.5)
	assert_float(label.position.x).is_equal_approx(middle.x, 0.001)
	assert_float(label.position.z).is_equal_approx(middle.z, 0.001)
	var tint := _tint(room_id)
	assert_that((tint.mesh as PlaneMesh).size).is_equal(Vector2(4.9, 3.9))
	assert_that((tint.material_override as StandardMaterial3D).albedo_color).is_equal(
		RoomView.NEEDS_TINT
	)


func test_furnishing_turns_the_room_ready() -> void:
	var room_id := _mode.grid.apply(BuildEdit.place_room(Rect2i(2, 2, 5, 4), &"cafe")).room_id
	_mode.grid.apply(BuildEdit.place_object(&"cafe_counter", Vector2i(3, 2), 0))
	_mode.grid.apply(BuildEdit.place_object(&"cafe_table", Vector2i(3, 5), 0))
	await _next_frame()
	assert_str(_view().label_of(room_id).text).is_equal("Cafe\nReady")
	assert_that((_tint(room_id).material_override as StandardMaterial3D).albedo_color).is_equal(
		RoomView.READY_TINT
	)


func test_a_removed_room_loses_its_label_and_a_load_draws_the_saved_ones() -> void:
	var grid := _mode.grid
	var room_id := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 5, 4), &"cafe")).room_id
	var saved := grid.to_snapshot()
	grid.apply(BuildEdit.remove_room(room_id))
	await _next_frame()
	assert_object(_view().label_of(room_id)).is_null()
	assert_bool(_mode.load_snapshot(saved)).is_true()
	await _next_frame()
	assert_str(_view().label_of(room_id).text).starts_with("Cafe\n")


## Sol review of 0537708: the room labels lay out after PassengerViews has
## drawn this frame's need icons, so they slide clear of where the icons are
## now. PassengerViews keeps the default priority (its script and main.tscn
## never set one) and RoomView processes after it.
func test_room_labels_lay_out_after_the_passenger_views_draw() -> void:
	var views_script := load("res://passengers/passenger_views.gd") as GDScript
	assert_str(views_script.source_code).not_contains("process_priority")
	var main := FileAccess.get_file_as_string("res://main/main.tscn")
	var start := main.find('[node name="PassengerViews"')
	assert_int(start).is_greater(0)
	var section := main.substr(start, main.find("\n[", start + 1) - start)
	assert_str(section).not_contains("process_priority")
	assert_int(_view().process_priority).is_greater(0)


## SceneTree.process_frame fires before the nodes' _process, so the redraw
## lands one frame later.
func _next_frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
