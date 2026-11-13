class_name TestNeedClusterViews
extends GdUnitTestSuite
## Need icon count clusters through the real PassengerViews (decision need-
## icon-count-clusters-technical-design-screen-space-clust): a close crowd's
## icons of one kind become one badge with the count, its members' icons of
## that kind hide while their other kinds still show, two passengers stay
## icons (the control), three needs give three badges that do not overlap, the
## state starts over on a load and on a release, and no badge shows while the
## icons are off.

const TOILET := NeedIcons.Need.TOILET
const HUNGER := NeedIcons.Need.HUNGER
const BOREDOM := NeedIcons.Need.BOREDOM

var _world: PassengerTestWorld
var _views: PassengerViews
var _camera: Camera3D
## The views draw into a 1600 x 900 viewport with no stretch, as a game window
## would; the headless root is 64 pixels high on output.
var _screen: SubViewport
var _path: String


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_path = SaveTestKit.run_path("need_cluster_views")
	var grid := BuildGrid.new()
	NeedFacilityKit.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_views.need_icons_toggle.settings_path = _path
	_screen = SubViewport.new()
	_screen.size = Vector2i(1600, 900)
	add_child(_screen)
	_screen.add_child(_views)
	_camera = Camera3D.new()
	_screen.add_child(_camera)
	_camera.make_current()


func after_test() -> void:
	DirAccess.remove_absolute(_path)
	_screen.free()
	_world.free_all()


## `count` calm passengers given `needs` (need -> true), ticked, drawn and
## framed by the camera from about 15 m, so they stand close on screen.
func _crowd(count: int, needs: Array) -> Array[int]:
	var ids: Array[int] = []
	for i in count:
		var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		ids.append(id)
		var p := _world.passenger(id)
		ToiletTestLayout.calm(p)
		if needs.has(TOILET):
			p.toilet_need = ToiletSim.NEED_MAX
		if needs.has(HUNGER):
			p.hunger = CafeSim.HUNGER_MAX
		if needs.has(BOREDOM):
			p.boredom = BoredomSim.MAX
	_world.step()
	_views.draw()
	var centre := Vector3.ZERO
	for id in ids:
		centre += _views.node_for(id).global_position
	centre /= ids.size()
	_camera.global_position = centre + Vector3(0.0, 12.0, 9.0)
	_camera.look_at(centre + Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	_views.draw()
	var screen: Array[Vector2] = []
	for id in ids:
		screen.append(
			_camera.unproject_position(_views.node_for(id).global_position) * _to_output()
		)
	print("output px per viewport px %.3f, crowd feet on screen %s" % [_to_output(), screen])
	return ids


func _to_output() -> float:
	return _views.get_viewport().get_stretch_transform().get_scale().y


## Whether the node's icon for `need` is drawn.
func _drawn(id: int, need: NeedIcons.Need) -> bool:
	var node := _views.node_for(id)
	var kinds: Array = node.get_meta(&"need_kinds", [])
	var at := kinds.find(need)
	return at >= 0 and (node.get_node(NeedIcons.SPRITES[at]) as Sprite3D).visible


func _visible_badges() -> Array[Sprite3D]:
	var out: Array[Sprite3D] = []
	for child in _views.get_node(NeedCluster.ROOT).get_children():
		if (child as Sprite3D).visible:
			out.append(child)
	return out


func test_ten_close_toilet_needs_show_one_badge_of_ten() -> void:
	var ids := _crowd(10, [TOILET])
	# Two of them are hungry too: two hunger icons stay icons.
	for id in ids.slice(0, 2):
		_world.passenger(id).hunger = CafeSim.HUNGER_MAX
	_world.step()
	_views.draw()
	var badges := _views.need_badges()
	print("badges ", badges)
	assert_int(badges.size()).is_equal(1)
	assert_int(badges[0]["kind"]).is_equal(TOILET)
	assert_int(badges[0]["count"]).is_equal(10)
	var shown := _visible_badges()
	assert_int(shown.size()).is_equal(1)
	assert_str((shown[0].get_node(NeedCluster.COUNT) as Label3D).text).is_equal("10")
	assert_object(shown[0].texture).is_same(NeedIcons.texture(TOILET))
	var toilets_drawn := ids.filter(func(id: int) -> bool: return _drawn(id, TOILET)).size()
	var hunger_drawn := ids.filter(func(id: int) -> bool: return _drawn(id, HUNGER)).size()
	print("toilet icons drawn %d, hunger icons drawn %d" % [toilets_drawn, hunger_drawn])
	assert_int(toilets_drawn).is_equal(0)
	assert_int(hunger_drawn).is_equal(2)


func test_two_close_passengers_keep_their_own_icons() -> void:
	var ids := _crowd(2, [TOILET])
	print("badges ", _views.need_badges())
	assert_int(_views.need_badges().size()).is_equal(0)
	assert_int(_visible_badges().size()).is_equal(0)
	for id in ids:
		assert_bool(_drawn(id, TOILET)).is_true()


func test_three_needs_give_three_badges_that_do_not_overlap() -> void:
	var ids := _crowd(10, [TOILET, HUNGER, BOREDOM])
	var badges := _views.need_badges()
	print("badges ", badges)
	assert_int(badges.size()).is_equal(3)
	var kinds := {}
	for badge in badges:
		kinds[badge["kind"]] = badge["count"]
	assert_dict(kinds).is_equal({TOILET: 10, HUNGER: 10, BOREDOM: 10})
	for i in badges.size():
		for j in range(i + 1, badges.size()):
			var a: Rect2 = badges[i]["rect"]
			var b: Rect2 = badges[j]["rect"]
			(
				assert_bool(a.intersects(b))
				. override_failure_message("%s overlaps %s" % [a, b])
				. is_false()
			)
	for id in ids:
		assert_bool(_drawn(id, TOILET) or _drawn(id, HUNGER) or _drawn(id, BOREDOM)).is_false()
	# The drawn sprites stand where the badges were placed, and the room labels
	# see them (RoomLabelLayout.icon_rects(), decision 77c15d41).
	var seen := RoomLabelLayout.icon_rects(_views, _camera, _to_output())
	print("room label blockers ", seen)
	assert_int(seen.size()).is_equal(3)
	for badge in badges:
		var placed: Rect2 = badge["rect"]
		var near := seen.filter(
			func(r: Rect2) -> bool: return r.get_center().distance_to(placed.get_center()) < 1.0
		)
		var missing := "no drawn badge at %s" % placed
		assert_int(near.size()).override_failure_message(missing).is_equal(1)


func test_the_clusters_start_over_on_a_load_and_a_release() -> void:
	var ids := _crowd(4, [TOILET])
	var before: Dictionary = _views.need_clusters.clusters()[0]
	var first_id: int = before["id"]
	_views.snap()
	var after: Array[Dictionary] = _views.need_clusters.clusters()
	print("before %s after snap %s" % [before, after])
	assert_int(after.size()).is_equal(1)
	assert_int(after[0]["id"]).is_not_equal(first_id)
	# A passenger whose view is released leaves its cluster at the sync.
	var gone := ids[0]
	_world.passenger(gone).stage = Passenger.Stage.MADE
	_world.step()
	assert_object(_views.node_for(gone)).is_null()
	var members: Array = _views.need_clusters.clusters()[0]["members"]
	print("members after release ", members)
	assert_array(members).not_contains([gone])
	assert_int(members.size()).is_equal(3)


func test_no_badge_shows_while_the_icons_are_off() -> void:
	_crowd(10, [TOILET])
	assert_int(_visible_badges().size()).is_equal(1)
	_views.need_icons_toggle.set_shown(false)
	_views.draw()
	print(
		(
			"off: badges %d clusters %d"
			% [_visible_badges().size(), _views.need_clusters.clusters().size()]
		)
	)
	assert_int(_visible_badges().size()).is_equal(0)
	assert_int(_views.need_badges().size()).is_equal(0)
	assert_int(_views.need_clusters.clusters().size()).is_equal(0)


## A VIP whose own icon sits in a count badge has no row (its icon is masked),
## so the crown stands over the badge it anchors, not on the badge's line
## (board b679fd1d review): the crown rect clears the badge rect and its
## bottom is no lower than the badge's top, with and without a speech bubble.
func test_a_vip_that_anchors_a_badge_wears_the_crown_over_it() -> void:
	_check_crown_over_badge(false)


func test_a_vip_that_anchors_a_badge_over_a_speech_bubble_wears_the_crown_over_it() -> void:
	_check_crown_over_badge(true)


func _check_crown_over_badge(with_bubble: bool) -> void:
	var ids := _crowd(10, [TOILET])
	if with_bubble:
		# Every passenger speaks, so the badge keeps its anchor member.
		_views.declutter_bubbles = false
		for id in ids:
			(_views.node_for(id).get_node("Bubble") as Label3D).text = "I'm late!"
		_views.draw()
	var badge := _visible_badges()[0]
	# The badge hangs off its anchor member's head: that passenger is the VIP.
	var holder: Node3D = null
	var best := INF
	for id in _world.sim.passenger_ids():
		var node := _views.node_for(id)
		var anchor := NeedIcons.head_centre(node)
		if with_bubble:
			anchor = (node.get_node("Bubble") as Label3D).position
		var d := (node.global_transform * anchor).distance_to(badge.global_position)
		if d < best:
			best = d
			holder = node
	assert_float(best).is_less(0.01)
	VipMarker.mark(holder, true)
	_views.draw()
	var bubble := holder.get_node("Bubble") as Label3D
	assert_bool(bubble.text != "" and bubble.visible).is_equal(with_bubble)
	var crown := holder.get_node(VipMarker.SPRITE) as Sprite3D
	assert_bool(crown.visible).is_true()
	var placed: Rect2 = _views.need_badges()[0]["rect"]
	var lift := (crown.offset.y - VipMarker.SIZE / 2.0) * VipMarker.CROWN_PX / VipMarker.SIZE
	var at := _camera.unproject_position(crown.global_position) * _to_output()
	var bottom := at.y - lift
	var rect := Rect2(
		Vector2(at.x - VipMarker.CROWN_PX / 2.0, bottom - VipMarker.CROWN_PX),
		Vector2.ONE * VipMarker.CROWN_PX
	)
	print("bubble %s: badge %s, crown %s (bottom %.1f)" % [with_bubble, placed, rect, bottom])
	assert_bool(rect.intersects(placed)).override_failure_message("crown over badge").is_false()
	assert_float(bottom).is_less_equal(placed.position.y + 0.5)


func test_cluster_needs_off_draws_every_icon() -> void:
	var ids := _crowd(10, [TOILET])
	_views.cluster_needs = false
	_views.draw()
	assert_int(_visible_badges().size()).is_equal(0)
	for id in ids:
		assert_bool(_drawn(id, TOILET)).is_true()
