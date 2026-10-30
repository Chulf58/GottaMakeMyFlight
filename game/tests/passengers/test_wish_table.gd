class_name TestWishTable
extends GdUnitTestSuite
## Shopping wishes (WishTable; decision shopping-wish-technical-design-id-
## hash-wish-admissible-wished-slot-then-fallback, point 1): over many ids each
## arrival type gives each wish about its weight's share, and the wish is
## independent of the boredom a passenger starts with, which is derived from
## the same id (BoredomSim.start_of()).

const IDS := 20000
## How far, in tenths of a percent, a measured share may sit from its weight.
const SHARE_SLACK_PERMILLE := 15


func _wish_index(wish: StringName) -> int:
	return 0 if wish == WishTable.NONE else WishTable.CANDIDATES.find(wish) + 1


func test_each_arrival_type_draws_each_wish_near_its_weight() -> void:
	for type in ArrivalTypes.Type.values():
		var counts := [0, 0, 0, 0, 0]
		for id in range(1, IDS + 1):
			counts[_wish_index(WishTable.pick(type, id))] += 1
		var weights: Array = WishTable.WEIGHTS[type]
		print("%s: counts %s, weights %s" % [ArrivalTypes.NAMES[type], counts, weights])
		for i in counts.size():
			@warning_ignore("integer_division")
			var permille: int = counts[i] * 1000 / IDS
			@warning_ignore("integer_division")
			var want: int = int(weights[i]) * 1000 / WishTable.WEIGHT_TOTAL
			(
				assert_int(permille)
				. override_failure_message(
					(
						"%s wish %d: %d permille, want %d"
						% [ArrivalTypes.NAMES[type], i, permille, want]
					)
				)
				. is_between(want - SHARE_SLACK_PERMILLE, want + SHARE_SLACK_PERMILLE)
			)


func test_the_weights_lean_by_arrival_type_as_ruled() -> void:
	var rushed: Array = WishTable.WEIGHTS[ArrivalTypes.Type.RUSHED]
	var relaxed: Array = WishTable.WEIGHTS[ArrivalTypes.Type.RELAXED]
	var typical: Array = WishTable.WEIGHTS[ArrivalTypes.Type.TYPICAL]
	for weights: Array in [rushed, relaxed, typical]:
		var total := 0
		for w: int in weights:
			total += w
		assert_int(total).is_equal(WishTable.WEIGHT_TOTAL)
	# Rushed lean to the kiosk and the pharmacy, relaxed to duty free and
	# fashion; typical spread the same across all four; each has a no-wish share.
	assert_int(rushed[1] + rushed[2]).is_greater(rushed[3] + rushed[4])
	assert_int(relaxed[3] + relaxed[4]).is_greater(relaxed[1] + relaxed[2])
	assert_array(typical.slice(1)).is_equal([typical[1], typical[1], typical[1], typical[1]])
	for weights: Array in [rushed, relaxed, typical]:
		assert_int(weights[0]).is_greater(0)
	assert_array(WishTable.CANDIDATES).is_equal([&"kiosk", &"pharmacy", &"duty_free", &"fashion"])
	for kind in WishTable.CANDIDATES:
		assert_bool(RoomTypes.get_type(kind).relieves_boredom).is_true()


func test_the_wish_is_independent_of_the_starting_boredom() -> void:
	# Pearson correlation of the starting boredom with the wish roll, and the
	# mean starting boredom of each wish group against the mean of all.
	var n := float(IDS)
	var sum_b := 0.0
	var sum_r := 0.0
	var sum_bb := 0.0
	var sum_rr := 0.0
	var sum_br := 0.0
	var group_sum := [0.0, 0.0, 0.0, 0.0, 0.0]
	var group_n := [0, 0, 0, 0, 0]
	for id in range(1, IDS + 1):
		var b := float(BoredomSim.start_of(id))
		var r := float(WishTable.roll_of(id))
		sum_b += b
		sum_r += r
		sum_bb += b * b
		sum_rr += r * r
		sum_br += b * r
		var i := _wish_index(WishTable.pick(ArrivalTypes.Type.TYPICAL, id))
		group_sum[i] += b
		group_n[i] += 1
	var cov := sum_br / n - (sum_b / n) * (sum_r / n)
	var var_b := sum_bb / n - pow(sum_b / n, 2)
	var var_r := sum_rr / n - pow(sum_r / n, 2)
	var corr := cov / sqrt(var_b * var_r)
	var mean := sum_b / n
	var means: Array = []
	for i in group_sum.size():
		means.append(snappedf(group_sum[i] / maxi(group_n[i], 1), 0.01))
	print("correlation %.4f; mean start boredom %.2f, by typical wish %s" % [corr, mean, means])
	assert_float(absf(corr)).is_less(0.03)
	for m: float in means:
		assert_float(absf(m - mean)).is_less(0.6)
	# Control: the start boredom does spread over its range.
	assert_float(var_b).is_greater(50.0)
