class_name TestNeedClusterPlacement
extends GdUnitTestSuite
## NeedCluster.place()'s shift order: one shared array, tried in the same order
## for every badge (the per-frame view path must not rebuild it per badge).

var _c: NeedCluster


func before_test() -> void:
	_c = NeedCluster.new()


func test_the_shift_order_is_built_once_and_starts_none_then_up() -> void:
	var first := NeedCluster._offsets()
	var again := NeedCluster._offsets()
	print("offsets %d, first %s, ring one starts %s" % [first.size(), first[0], first[1]])
	assert_bool(is_same(first, again)).is_true()
	assert_int(first.size()).is_equal(49)
	assert_that(first[0]).is_equal(Vector2.ZERO)
	assert_that(first[1]).is_equal(Vector2(0, -NeedCluster.SHIFT_STEP_PX))
	assert_that(first[8]).is_equal(Vector2(-1, 1) * NeedCluster.SHIFT_STEP_PX)
	assert_that(first[48]).is_equal(Vector2(-1, 1) * NeedCluster.MAX_SHIFT_PX)


func test_many_badges_on_one_spot_spread_in_the_shift_order() -> void:
	var wanted: Array[Rect2] = []
	var ids := []
	for i in 9:
		wanted.append(Rect2(Vector2(100, 100), Vector2(10, 10)))
		ids.append(i)
	var none: Array[Rect2] = []
	var placed := _c.place(wanted, ids, none)
	var offsets := NeedCluster._offsets()
	print("placed ", placed)
	for i in 9:
		assert_that(placed[i].position).is_equal(wanted[i].position + offsets[i])
