class_name TestNeedCluster
extends GdUnitTestSuite
## The count clusters of need icons, as pure logic (decision need-icon-count-
## clusters-technical-design-screen-space-clust): admission and retention radii,
## min 3 to form and 2 to survive, stable ids, splits and merges, members
## leaving at once, deterministic ties and badge placement. Points are screen
## pixels.

const TOILET := NeedIcons.Need.TOILET
const HUNGER := NeedIcons.Need.HUNGER

var _c: NeedCluster


func before_test() -> void:
	_c = NeedCluster.new()


## A kind's points: passenger id -> screen point.
func _pts(points: Dictionary, kind := TOILET) -> Dictionary:
	return {kind: points}


func _only() -> Dictionary:
	var all := _c.clusters()
	assert_int(all.size()).is_equal(1)
	return all[0] if not all.is_empty() else {}


func test_three_close_icons_form_one_cluster_and_two_do_not() -> void:
	_c.update(_pts({1: Vector2(100, 100), 2: Vector2(110, 100)}))
	assert_int(_c.clusters().size()).is_equal(0)
	_c.update(_pts({1: Vector2(100, 100), 2: Vector2(110, 100), 3: Vector2(100, 112)}))
	var cluster := _only()
	print("formed: ", cluster)
	assert_array(cluster["members"]).contains_exactly([1, 2, 3])
	assert_int(cluster["kind"]).is_equal(TOILET)


func test_a_free_icon_joins_inside_the_admission_radius_only() -> void:
	var base := {1: Vector2(0, 0), 2: Vector2(4, 0), 3: Vector2(0, 4)}
	_c.update(_pts(base))
	var rep: int = _only()["rep"]
	var near := base.duplicate()
	near[4] = (base[rep] as Vector2) + Vector2(NeedCluster.ADMIT_PX - 1.0, 0.0)
	near[5] = (base[rep] as Vector2) + Vector2(0.0, NeedCluster.ADMIT_PX + 2.0)
	_c.update(_pts(near))
	var members: Array = _only()["members"]
	print("rep %d members %s" % [rep, members])
	assert_array(members).contains_exactly([1, 2, 3, 4])


func test_a_member_stays_between_the_radii_and_leaves_past_retention() -> void:
	var pts := {1: Vector2(0, 0), 2: Vector2(3, 0), 3: Vector2(0, 3), 4: Vector2(10, 0)}
	_c.update(_pts(pts))
	var rep: int = _only()["rep"]
	assert_int(rep).is_not_equal(4)
	var at: Vector2 = pts[rep]
	var between := (NeedCluster.ADMIT_PX + NeedCluster.RETAIN_PX) / 2.0
	# Between ADMIT_PX and RETAIN_PX: a member stays (hysteresis)...
	pts[4] = at + Vector2(between, 0.0)
	_c.update(_pts(pts))
	assert_array(_only()["members"]).contains([4])
	# ...while a free icon at the same distance would not join.
	pts[5] = at + Vector2(0.0, between)
	_c.update(_pts(pts))
	assert_array(_only()["members"]).not_contains([5])
	# Past RETAIN_PX it leaves.
	pts[4] = at + Vector2(NeedCluster.RETAIN_PX + 1.0, 0.0)
	_c.update(_pts(pts))
	print("members after leaving: ", _only()["members"])
	assert_array(_only()["members"]).not_contains([4])


func test_a_cluster_survives_at_two_and_ends_at_one() -> void:
	var pts := {1: Vector2(0, 0), 2: Vector2(5, 0), 3: Vector2(0, 5)}
	_c.update(_pts(pts))
	var id: int = _only()["id"]
	pts.erase(3)
	_c.update(_pts(pts))
	assert_int(_only()["id"]).is_equal(id)
	assert_int((_only()["members"] as Array).size()).is_equal(2)
	pts.erase(2)
	_c.update(_pts(pts))
	assert_int(_c.clusters().size()).is_equal(0)


func test_the_id_holds_under_a_small_translation() -> void:
	var pts := {}
	for i in 6:
		pts[i + 1] = Vector2(200 + i * 6, 300 + (i % 2) * 6)
	_c.update(_pts(pts))
	var id: int = _only()["id"]
	var ids: Array[int] = []
	for frame in 20:
		for key: int in pts:
			pts[key] = (pts[key] as Vector2) + Vector2(4.0, -3.0)
		_c.update(_pts(pts))
		ids.append(_only()["id"])
	print("first id %d, ids over 20 frames %s" % [id, ids])
	for seen in ids:
		assert_int(seen).is_equal(id)
	assert_int((_only()["members"] as Array).size()).is_equal(6)


func test_a_split_keeps_the_id_on_the_group_with_the_representative() -> void:
	var pts := {}
	for i in 6:
		pts[i + 1] = Vector2(100 + i * 3, 100)
	_c.update(_pts(pts))
	var first := _only()
	var id: int = first["id"]
	var rep: int = first["rep"]
	var stay := [rep]
	for key: int in pts:
		if key != rep and stay.size() < 3:
			stay.append(key)
	# The other three walk off to the right in steps, still close together.
	for step in 10:
		for key: int in pts:
			if not stay.has(key):
				pts[key] = (pts[key] as Vector2) + Vector2(12.0, 0.0)
		_c.update(_pts(pts))
	var all := _c.clusters()
	print("after split: ", all)
	assert_int(all.size()).is_equal(2)
	for cluster in all:
		var members: Array = cluster["members"]
		if members.has(rep):
			assert_int(cluster["id"]).is_equal(id)
			assert_array(members).contains_exactly_in_any_order(stay)
		else:
			assert_int(cluster["id"]).is_not_equal(id)
			assert_int(members.size()).is_equal(3)


func test_the_radii_keep_a_hysteresis_gap() -> void:
	assert_float(NeedCluster.RETAIN_PX - NeedCluster.ADMIT_PX).is_greater_equal(12.0)


func test_a_merge_keeps_one_id() -> void:
	var pts := {}
	for i in 3:
		pts[i + 1] = Vector2(100 + i * 4, 100)
		pts[i + 11] = Vector2(200 + i * 4, 100)
	# Group b is bigger, so its id survives the merge.
	pts[14] = Vector2(204, 104)
	_c.update(_pts(pts))
	var before := _c.clusters()
	assert_int(before.size()).is_equal(2)
	var big_id := 0
	var ids := {}
	for cluster in before:
		ids[cluster["id"]] = true
		if (cluster["members"] as Array).size() == 4:
			big_id = cluster["id"]
	for step in 12:
		for key: int in [11, 12, 13, 14]:
			pts[key] = (pts[key] as Vector2) + Vector2(-8.0, 0.0)
		_c.update(_pts(pts))
	var merged := _only()
	print("before %s, merged %s" % [before, merged])
	assert_int(merged["id"]).is_equal(big_id)
	assert_int((merged["members"] as Array).size()).is_equal(7)


func test_a_member_leaves_at_once_when_its_need_stops() -> void:
	var pts := {1: Vector2(0, 0), 2: Vector2(5, 0), 3: Vector2(0, 5), 4: Vector2(5, 5)}
	_c.update(_pts(pts))
	assert_int(_c.mask().get(4, 0)).is_equal(1 << TOILET)
	pts.erase(4)
	_c.update(_pts(pts))
	assert_array(_only()["members"]).not_contains([4])
	assert_int(_c.mask().get(4, 0)).is_equal(0)


func test_ties_break_by_passenger_id_whatever_the_input_order() -> void:
	# Three points in a line, evenly spaced: 2 is the middle, densest point.
	# Four corners of a square: every point has the same neighbours, so the
	# lowest id is the representative.
	var square := {7: Vector2(0, 0), 5: Vector2(10, 0), 9: Vector2(0, 10), 6: Vector2(10, 10)}
	_c.update(_pts(square))
	var a := _only()
	var other := NeedCluster.new()
	var reversed := {}
	for key: int in [6, 9, 5, 7]:
		reversed[key] = square[key]
	other.update(_pts(reversed))
	var b: Dictionary = other.clusters()[0]
	print("a %s b %s" % [a, b])
	assert_int(a["rep"]).is_equal(5)
	assert_int(b["rep"]).is_equal(5)
	assert_array(a["members"]).is_equal(b["members"])
	assert_int(NeedCluster.anchor_member([7, 5, 9, 6], square)).is_equal(5)


func test_kinds_cluster_apart_and_mask_per_kind() -> void:
	var pts := {1: Vector2(0, 0), 2: Vector2(5, 0), 3: Vector2(0, 5)}
	_c.update({TOILET: pts, HUNGER: {1: Vector2(0, 0), 2: Vector2(5, 0)}})
	assert_int(_c.clusters().size()).is_equal(1)
	assert_int(_c.mask()[1]).is_equal(1 << TOILET)
	_c.update({TOILET: pts, HUNGER: pts})
	assert_int(_c.clusters().size()).is_equal(2)
	assert_int(_c.mask()[1]).is_equal((1 << TOILET) | (1 << HUNGER))


func test_forget_and_clear_drop_state() -> void:
	var pts := {1: Vector2(0, 0), 2: Vector2(5, 0), 3: Vector2(0, 5), 4: Vector2(5, 5)}
	_c.update(_pts(pts))
	_c.forget(4)
	assert_array(_only()["members"]).not_contains([4])
	_c.clear()
	assert_int(_c.clusters().size()).is_equal(0)
	assert_int(_c.mask().size()).is_equal(0)


func test_badges_are_placed_clear_of_each_other_and_of_obstacles() -> void:
	var size := Vector2(42, 42)
	var wanted: Array[Rect2] = [Rect2(Vector2(100, 100), size), Rect2(Vector2(110, 100), size)]
	var obstacles: Array[Rect2] = [Rect2(Vector2(100, 150), Vector2(40, 40))]
	var placed := _c.place(wanted, [1, 2], obstacles)
	print("placed ", placed)
	assert_int(placed.size()).is_equal(2)
	assert_bool(placed[0].intersects(placed[1])).is_false()
	for rect in placed:
		assert_bool(rect.intersects(obstacles[0])).is_false()
		var shift := rect.position - wanted[placed.find(rect)].position
		assert_float(shift.length()).is_less_equal(NeedCluster.MAX_SHIFT_PX * sqrt(2.0))


func test_a_badge_with_no_free_slot_stays_at_its_anchor() -> void:
	var wanted: Array[Rect2] = [Rect2(Vector2(100, 100), Vector2(42, 42))]
	var wall: Array[Rect2] = [Rect2(Vector2(-200, -200), Vector2(800, 800))]
	var placed := _c.place(wanted, [1], wall)
	assert_int(placed.size()).is_equal(1)
	assert_that(placed[0]).is_equal(wanted[0])


func test_a_shifted_badge_keeps_its_shift_while_it_still_fits() -> void:
	var size := Vector2(42, 42)
	var wanted: Array[Rect2] = [Rect2(Vector2(100, 100), size)]
	var block: Array[Rect2] = [Rect2(Vector2(100, 100), Vector2(20, 20))]
	var first := _c.place(wanted, [1], block)
	assert_that(first[0]).is_not_equal(wanted[0])
	# The obstacle moves away; the badge keeps its spot instead of jumping back.
	var none: Array[Rect2] = []
	var second := _c.place(wanted, [1], none)
	print("first %s second %s" % [first[0], second[0]])
	assert_that(second[0]).is_equal(first[0])


func test_badges_hemmed_in_by_obstacles_still_keep_off_each_other() -> void:
	var size := Vector2(42, 42)
	var wanted: Array[Rect2] = [Rect2(Vector2(100, 100), size), Rect2(Vector2(100, 100), size)]
	var wall: Array[Rect2] = [Rect2(Vector2(-200, -200), Vector2(800, 800))]
	var placed := _c.place(wanted, [1, 2], wall)
	print("hemmed in: ", placed)
	assert_that(placed[0]).is_equal(wanted[0])
	assert_bool(placed[0].intersects(placed[1])).is_false()


func test_a_badge_is_bigger_than_an_icon_and_its_pill_fits_the_count() -> void:
	assert_float(NeedCluster.BADGE_PX).is_greater_equal(NeedIcons.ICON_PX * 1.4)
	var short := NeedCluster.pill_width("5")
	var long := NeedCluster.pill_width("500")
	print("pill widths: '5' %.0f px, '500' %.0f px" % [short, long])
	assert_float(short).is_greater_equal(NeedCluster.PILL_H_PX)
	assert_float(long).is_greater(short)
	var rect := NeedCluster.badge_rect(Vector2.ZERO, 500)
	assert_float(rect.end.x).is_equal(NeedCluster.COUNT_AT.x + long / 2.0)


func test_a_representative_walking_off_its_group_leaves_the_id_with_the_group() -> void:
	var pts := {}
	for i in 10:
		pts[i + 1] = Vector2(300 + (i % 5) * 6, 300 + (i / 5) * 6)
	_c.update(_pts(pts))
	var first := _only()
	var rep: int = first["rep"]
	for step in 20:
		pts[rep] = (pts[rep] as Vector2) + Vector2(10.0, 0.0)
		_c.update(_pts(pts))
	var with_group := _c.clusters().filter(
		func(c: Dictionary) -> bool: return (c["members"] as Array).size() >= 9
	)
	print("after the walk: ", _c.clusters())
	assert_int(with_group.size()).is_equal(1)
	assert_int(with_group[0]["id"]).is_equal(first["id"])
	assert_array(with_group[0]["members"]).not_contains([rep])
