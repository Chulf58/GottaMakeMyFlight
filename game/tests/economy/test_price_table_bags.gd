class_name TestPriceTableBags
extends GdUnitTestSuite
## Baggage B4: a passenger whose bag missed the flight still pays, a reduced
## fee. The share is a tuning value, so the tests pin the shape, not the number.


func test_a_missed_bag_cuts_the_fee_but_not_to_nothing() -> void:
	assert_int(PriceTable.MISSED_BAG_FEE_PERCENT).is_between(1, 99)
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
