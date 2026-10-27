class_name TestPriceTableBags
extends GdUnitTestSuite
## Baggage B4: a passenger whose bag missed the flight still pays, a reduced
## fee. The share is a tuning value, so the tests pin the shape, not the number.


func test_the_tuned_share_is_half_the_fee() -> void:
	assert_int(PriceTable.MISSED_BAG_FEE_PERCENT).is_equal(50)
	assert_int(PriceTable.fee_after_missed_bag(100)).is_equal(50)
	assert_int(PriceTable.fee_after_missed_bag(400)).is_equal(200)


func test_an_odd_fee_is_cut_and_rounded_down() -> void:
	assert_int(PriceTable.fee_after_missed_bag(37)).is_equal(18)
	assert_int(PriceTable.fee_after_missed_bag(1)).is_equal(0)


func test_a_missed_bag_cuts_the_fee_but_not_to_nothing() -> void:
	for fee in [2, 37, 100, 400]:
		var cut := PriceTable.fee_after_missed_bag(fee)
		assert_int(cut).is_less(fee)
		assert_int(cut).is_greater(0)


func test_the_cut_fee_is_rounded_down() -> void:
	var expected := 37 * PriceTable.MISSED_BAG_FEE_PERCENT / 100
	assert_int(PriceTable.fee_after_missed_bag(37)).is_equal(expected)


func test_cutting_a_fee_that_is_no_price_stays_an_error() -> void:
	assert_int(PriceTable.fee_after_missed_bag(PriceTable.NO_PRICE)).is_equal(PriceTable.NO_PRICE)
	assert_int(PriceTable.fee_after_missed_bag(0)).is_equal(0)
