class_name TestPriceTable
extends GdUnitTestSuite

## A starter terminal: about 200 floor tiles, a mixed wall ring, one desk, one
## scanner, the two doors and four seat rows.
const STARTER_FLOOR_TILES := 200
const STARTER_PLAIN_WALLS := 40
const STARTER_GLASS_WALLS := 10
const STARTER_SEAT_ROWS := 4


func _starter_cost() -> int:
	return (
		STARTER_FLOOR_TILES * PriceTable.price_of_floor()
		+ STARTER_PLAIN_WALLS * PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
		+ STARTER_GLASS_WALLS * PriceTable.price_of_wall(BuildGrid.WallKind.GLASS)
		+ PriceTable.price_of_object(&"checkin_desk")
		+ PriceTable.price_of_object(&"security_scanner")
		+ PriceTable.price_of_object(&"entrance_door")
		+ PriceTable.price_of_object(&"exit_door")
		+ STARTER_SEAT_ROWS * PriceTable.price_of_object(&"seat_row")
	)


func test_floor_and_every_placeable_wall_kind_has_a_positive_price() -> void:
	assert_int(PriceTable.price_of_floor()).is_greater(0)
	for kind in [BuildGrid.WallKind.PLAIN, BuildGrid.WallKind.GLASS, BuildGrid.WallKind.DOOR]:
		assert_int(PriceTable.price_of_wall(kind)).is_greater(0)


func test_every_catalog_object_has_a_positive_price() -> void:
	var ids := BuildCatalog.ids()
	assert_int(ids.size()).is_equal(7)
	for id in ids:
		assert_int(PriceTable.price_of_object(id)).is_greater(0)


func test_price_table_covers_exactly_the_catalog() -> void:
	var priced: Array = PriceTable.OBJECT_PRICES.keys()
	priced.sort()
	var catalog: Array = BuildCatalog.ids()
	catalog.sort()
	assert_array(priced).is_equal(catalog)


func test_unknown_object_id_is_an_error_not_zero() -> void:
	assert_int(PriceTable.price_of_object(&"no_such_thing")).is_equal(PriceTable.NO_PRICE)
	assert_int(PriceTable.NO_PRICE).is_less(0)


func test_wall_kind_none_and_out_of_range_are_errors() -> void:
	for kind in [BuildGrid.WallKind.NONE, -1, 4, 99]:
		assert_int(PriceTable.price_of_wall(kind)).is_equal(PriceTable.NO_PRICE)


func test_glass_and_door_walls_cost_more_than_plain() -> void:
	var plain := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	assert_int(PriceTable.price_of_wall(BuildGrid.WallKind.GLASS)).is_greater(plain)
	assert_int(PriceTable.price_of_wall(BuildGrid.WallKind.DOOR)).is_greater(plain)


func test_refund_is_a_fixed_share_rounded_down() -> void:
	assert_int(PriceTable.refund_of(100)).is_equal(100 * PriceTable.REFUND_SHARE_PERCENT / 100)
	assert_int(PriceTable.refund_of(0)).is_equal(0)
	assert_int(PriceTable.refund_of(1)).is_equal(0)
	assert_int(PriceTable.refund_of(7)).is_equal(7 * PriceTable.REFUND_SHARE_PERCENT / 100)


func test_refund_is_strictly_less_than_the_price() -> void:
	for price in [1, 25, 40, 400, 900]:
		assert_int(PriceTable.refund_of(price)).is_less(price)
	assert_int(PriceTable.REFUND_SHARE_PERCENT).is_between(1, 99)


func test_refund_of_no_price_stays_an_error() -> void:
	assert_int(PriceTable.refund_of(PriceTable.NO_PRICE)).is_equal(PriceTable.NO_PRICE)
	assert_int(PriceTable.refund_of(-5)).is_equal(PriceTable.NO_PRICE)


func test_refund_of_an_unknown_object_is_not_laundered_to_zero() -> void:
	var refund := PriceTable.refund_of(PriceTable.price_of_object(&"no_such_thing"))
	assert_int(refund).is_equal(PriceTable.NO_PRICE)
	var wall_refund := PriceTable.refund_of(PriceTable.price_of_wall(BuildGrid.WallKind.NONE))
	assert_int(wall_refund).is_equal(PriceTable.NO_PRICE)


func test_starting_budget_covers_a_starter_terminal_at_roughly_half() -> void:
	var cost := _starter_cost()
	var share := float(cost) / PriceTable.STARTING_BUDGET
	assert_float(share).is_between(0.4, 0.6)
