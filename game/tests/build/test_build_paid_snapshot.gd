class_name TestBuildPaidSnapshot
extends GdUnitTestSuite
## The purchase prices BuildGrid saves for refunds: kept per floor cell, wall
## edge and object, round-tripped through a snapshot, optional for older
## saves (which refund nothing), and refused when malformed.

const NORTH := BuildGrid.Side.NORTH


## A 6x6 grid with floor on x 1..4, y 1..4, a wall and a desk, every piece
## carrying its own purchase price.
func _priced_grid() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(6, 6))
	for y in range(1, 5):
		for x in range(1, 5):
			var paint := BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1)
			paint.paid = 20 + x
			grid.apply(paint)
	var wall := BuildEdit.place_wall(Vector2i(2, 1), NORTH)
	wall.paid = 33
	grid.apply(wall)
	var desk := BuildEdit.place_object(&"checkin_desk", Vector2i(1, 2), 0)
	desk.paid = 444
	grid.apply(desk)
	return grid


func _through_json(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


func test_the_grid_records_and_clears_purchase_prices() -> void:
	var grid := _priced_grid()
	assert_int(grid.floor_paid(Vector2i(3, 1))).is_equal(23)
	assert_int(grid.wall_paid(Vector2i(2, 1), NORTH)).is_equal(33)
	assert_int(grid.wall_paid(Vector2i(2, 0), BuildGrid.Side.SOUTH)).is_equal(33)
	assert_int(grid.get_object(1)["paid"]).is_equal(444)
	grid.apply(BuildEdit.remove_wall(Vector2i(2, 1), NORTH))
	grid.apply(BuildEdit.remove_floor(Vector2i(4, 4)))
	assert_int(grid.wall_paid(Vector2i(2, 1), NORTH)).is_equal(0)
	assert_int(grid.floor_paid(Vector2i(4, 4))).is_equal(0)


func test_purchase_prices_survive_a_json_round_trip() -> void:
	var snapshot := _priced_grid().to_snapshot()
	var other := BuildGrid.new(Vector2i(6, 6))
	assert_bool(other.from_snapshot(_through_json(snapshot))).is_true()
	assert_int(other.floor_paid(Vector2i(3, 1))).is_equal(23)
	assert_int(other.wall_paid(Vector2i(2, 1), NORTH)).is_equal(33)
	assert_int(other.get_object(1)["paid"]).is_equal(444)
	assert_str(JSON.stringify(other.to_snapshot())).is_equal(JSON.stringify(snapshot))


func test_a_snapshot_saved_before_prices_loads_with_nothing_paid() -> void:
	var old := _through_json(_priced_grid().to_snapshot())
	for key in BuildGrid.PAID_KEYS:
		old.erase(key)
	for entry in old["objects"]:
		entry.erase("paid")
	var other := BuildGrid.new(Vector2i(6, 6))
	assert_bool(other.from_snapshot(old)).is_true()
	assert_int(other.floor_paid(Vector2i(3, 1))).is_equal(0)
	assert_int(other.wall_paid(Vector2i(2, 1), NORTH)).is_equal(0)
	assert_int(other.get_object(1)["paid"]).is_equal(0)


func test_malformed_purchase_prices_are_refused_and_the_grid_kept() -> void:
	var good := _through_json(_priced_grid().to_snapshot())
	var other := BuildGrid.new(Vector2i(6, 6))
	var before := JSON.stringify(other.to_snapshot())
	var bad_cases: Array[Dictionary] = []
	# The three price arrays come together.
	var partial := good.duplicate(true)
	partial.erase("h_walls_paid")
	bad_cases.append(partial)
	var short := good.duplicate(true)
	(short["floor_paid"] as Array).pop_back()
	bad_cases.append(short)
	var negative := good.duplicate(true)
	negative["floor_paid"][8] = -5
	bad_cases.append(negative)
	var fraction := good.duplicate(true)
	fraction["v_walls_paid"][0] = 1.5
	bad_cases.append(fraction)
	# A price where no piece stands could never have been paid.
	var no_floor := good.duplicate(true)
	no_floor["floor_paid"][0] = 25
	bad_cases.append(no_floor)
	var no_wall := good.duplicate(true)
	no_wall["h_walls_paid"][0] = 40
	bad_cases.append(no_wall)
	var bad_object := good.duplicate(true)
	bad_object["objects"][0]["paid"] = "lots"
	bad_cases.append(bad_object)
	var refused := 0
	for data in bad_cases:
		if not other.from_snapshot(data):
			refused += 1
		assert_str(JSON.stringify(other.to_snapshot())).is_equal(before)
	print("refused %d of %d" % [refused, bad_cases.size()])
	assert_int(refused).is_equal(bad_cases.size())
