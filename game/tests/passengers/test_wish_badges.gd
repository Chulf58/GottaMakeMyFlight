class_name TestWishBadges
extends GdUnitTestSuite
## Wish bubbles merged into count badges in the Mood overlay's Boredom mode
## (board c8b16621; user ruling 'Merge wishes into badges', decision calm-
## cozy-default-view-quiet-world-detail-on-ask-soft-statio; the clustering is
## need-icon-count-clusters-technical-design-screen-space-clust): close wish
## bubbles of one shop kind become one bubble with a count, two kinds close
## together stay two badges, far apart groups stay apart, and the hovered,
## pinned or inspected passenger still shows its own wish.

## Airside cells one metre apart, close together on screen from the camera.
const BLOCK: Array[Vector2i] = [
	Vector2i(11, 4),
	Vector2i(12, 4),
	Vector2i(13, 4),
	Vector2i(11, 5),
	Vector2i(12, 5),
	Vector2i(13, 5),
	Vector2i(11, 6),
	Vector2i(12, 6),
	Vector2i(13, 6),
]
## A cell several metres from BLOCK, far past the cluster radius on screen.
const FAR := Vector2i(17, 7)

var _world: PassengerTestWorld
var _views: PassengerViews
var _rig: TycoonCamera
var _camera: Camera3D
var _screen: SubViewport
var _hover: HoverTarget
## Passenger id -> the wish kind the sim reports for it.
var _wish_of := {}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _screen != null:
		_screen.free()
		_screen = null
	if _world != null:
		_world.free_all()
		_world = null
	_views = null
	_rig = null
	_camera = null
	_hover = null
	_wish_of = {}


## The views drawn in a 1600 x 900 viewport closer than the home zoom with a
## HoverTarget the views resolve in draw(), and a Mood overlay that is off.
func _open() -> void:
	var grid := BuildGrid.new()
	WishTestLayout.build(grid, [&"kiosk"])
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_world.sim.shops.wishes = func(p: Passenger) -> StringName:
		return _wish_of.get(p.id, WishTable.NONE)
	_screen = SubViewport.new()
	_screen.size = Vector2i(1600, 900)
	add_child(_screen)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_hover = HoverTarget.new()
	_hover.views = _views
	_hover.pointer_override = Vector2(-1.0, -1.0)
	_views.hover_target = _hover
	_screen.add_child(_views)
	_screen.add_child(_hover)
	_hover.set_process(false)
	_rig = TycoonCamera.new()
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_rig.add_child(_camera)
	_screen.add_child(_rig)
	_rig.set_process(false)
	_rig.home_distance = 40.0
	_rig.distance = 12.0
	_camera.make_current()
	PassengerTestWorld.ensure_overlay(_views)


## A bored passenger on `cell` wishing for `kind`.
func _wisher(cell: Vector2i, kind: StringName) -> int:
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX, cell)
	_wish_of[p.id] = kind
	return p.id


## `kind` wishers on the first cells of BLOCK from `first`.
func _group(kind: StringName, count: int, first := 0) -> Array[int]:
	var ids: Array[int] = []
	for i in count:
		ids.append(_wisher(BLOCK[first + i], kind))
	return ids


## Syncs the views, frames the airside floor and opens the overlay in Boredom
## mode (or `shown` false: off), then draws.
func _draw(shown := true) -> void:
	_views.sync()
	var centre := _world.sim.grid.cell_to_world(Vector2i(14, 6))
	_camera.global_position = centre + Vector3(0.0, 12.0, 9.0)
	_camera.look_at(centre + Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	_views.mood_overlay.set_mode(MoodTint.Mode.BOREDOM)
	_views.mood_overlay.set_shown(shown)
	_views.draw()


func _wish(id: int) -> Sprite3D:
	return _views.node_for(id).get_node(WishIconView.SPRITE) as Sprite3D


## Of `ids`, those whose own wish bubble is drawn now.
func _own_wishes(ids: Array[int]) -> Array[int]:
	return ids.filter(func(id: int) -> bool: return _wish(id).visible)


## The wish badges drawn: need_badges() entries that carry a wish.
func _wish_badges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for badge in _views.need_badges():
		if badge.get("wish", "") != "":
			out.append(badge)
	return out


## The badge sprites shown whose icon is a wish bubble.
func _shown_badge_sprites() -> Array[Sprite3D]:
	var out: Array[Sprite3D] = []
	for child in _views.get_node(NeedCluster.ROOT).get_children():
		if (child as Sprite3D).visible:
			out.append(child)
	return out


func _over(id: int) -> Vector2:
	var node := _views.node_for(id)
	return _camera.unproject_position(node.global_position + Vector3(0.0, 1.0, 0.0))


func test_six_close_kiosk_wishes_merge_into_one_badge_of_six() -> void:
	_open()
	var ids := _group(&"kiosk", 6)
	_draw()
	var badges := _wish_badges()
	print("badges %s, own wishes %s" % [_views.need_badges(), _own_wishes(ids)])
	assert_int(badges.size()).is_equal(1)
	assert_int(badges[0]["count"]).is_equal(6)
	assert_str(badges[0]["wish"]).is_equal(WishIconView.key_of(&"kiosk", WishTable.State.WANTED))
	# Every member's own bubble is gone; the badge carries the kiosk bubble and
	# the count.
	assert_array(_own_wishes(ids)).is_empty()
	var shown := _shown_badge_sprites()
	assert_int(shown.size()).is_equal(1)
	assert_str((shown[0].get_node(NeedCluster.COUNT) as Label3D).text).is_equal("6")
	assert_object(shown[0].texture).is_same(WishIconView.texture(&"kiosk", WishTable.State.WANTED))


func test_two_kinds_close_together_stay_two_badges() -> void:
	_open()
	var kiosk := _group(&"kiosk", 4, 0)
	var pharmacy := _group(&"pharmacy", 5, 4)
	_draw()
	var badges := _wish_badges()
	var by_key := {}
	for badge in badges:
		by_key[badge["wish"]] = badge["count"]
	print("badges %s" % [badges])
	assert_int(badges.size()).is_equal(2)
	(
		assert_dict(by_key)
		. is_equal(
			{
				WishIconView.key_of(&"kiosk", WishTable.State.WANTED): 4,
				WishIconView.key_of(&"pharmacy", WishTable.State.WANTED): 5,
			}
		)
	)
	assert_array(_own_wishes(kiosk)).is_empty()
	assert_array(_own_wishes(pharmacy)).is_empty()
	# The two badges do not sit on each other.
	assert_bool((badges[0]["rect"] as Rect2).intersects(badges[1]["rect"])).is_false()


func test_one_kind_far_apart_stays_two_badges_and_two_close_stay_bubbles() -> void:
	_open()
	var near := _group(&"kiosk", 4)
	var far: Array[int] = []
	for i in 3:
		far.append(_wisher(FAR + Vector2i(-i, 0), &"kiosk"))
	var pair: Array[int] = [
		_wisher(Vector2i(17, 4), &"fashion"), _wisher(Vector2i(16, 4), &"fashion")
	]
	_draw()
	var badges := _wish_badges()
	var counts: Array[int] = []
	for badge in badges:
		counts.append(badge["count"])
	counts.sort()
	print(
		(
			"badges %s, own wishes near %s far %s pair %s"
			% [badges, _own_wishes(near), _own_wishes(far), _own_wishes(pair)]
		)
	)
	assert_array(counts).is_equal([3, 4])
	assert_array(_own_wishes(near)).is_empty()
	assert_array(_own_wishes(far)).is_empty()
	# Two fashion wishes are under the cluster minimum: each keeps its bubble.
	assert_array(_own_wishes(pair)).contains_exactly_in_any_order(pair)


func test_a_hovered_wisher_shows_its_own_wish_and_leaves_the_badge() -> void:
	_open()
	var ids := _group(&"kiosk", 6)
	_draw()
	assert_int(_wish_badges()[0]["count"]).is_equal(6)
	var focus := ids[4]
	_hover.pointer_override = _over(focus)
	_views.draw()
	print(
		(
			"hovered %d: own wishes %s, badges %s"
			% [_hover.hovered_passenger(), _own_wishes(ids), _wish_badges()]
		)
	)
	assert_int(_hover.hovered_passenger()).is_equal(focus)
	assert_array(_own_wishes(ids)).is_equal([focus])
	assert_int(_wish_badges().size()).is_equal(1)
	assert_int(_wish_badges()[0]["count"]).is_equal(5)
	# The pointer leaves: it rejoins the badge.
	_hover.pointer_override = Vector2(-1.0, -1.0)
	_views.draw()
	assert_array(_own_wishes(ids)).is_empty()
	assert_int(_wish_badges()[0]["count"]).is_equal(6)


func test_a_pinned_or_inspected_wisher_shows_its_own_wish_and_leaves_the_badge() -> void:
	_open()
	var ids := _group(&"kiosk", 6)
	_draw()
	# A click selects the passenger PassengerHud inspects, which a pin follows.
	var focus := ids[1]
	_views.selected_id = focus
	_views.draw()
	print("selected %d: own wishes %s, badges %s" % [focus, _own_wishes(ids), _wish_badges()])
	assert_array(_own_wishes(ids)).is_equal([focus])
	assert_int(_wish_badges()[0]["count"]).is_equal(5)
	_views.selected_id = 0
	_views.draw()
	assert_array(_own_wishes(ids)).is_empty()
	assert_int(_wish_badges()[0]["count"]).is_equal(6)


func test_a_focused_wisher_leaves_a_group_that_drops_under_the_minimum() -> void:
	_open()
	var ids := _group(&"kiosk", 3)
	_draw()
	assert_int(_wish_badges()[0]["count"]).is_equal(3)
	_views.selected_id = ids[0]
	_views.draw()
	print("two left: own wishes %s, badges %s" % [_own_wishes(ids), _wish_badges()])
	# Two members stay a cluster once formed (KEEP_MIN), the focused one is
	# drawn on its own.
	assert_array(_own_wishes(ids)).is_equal([ids[0]])
	assert_int(_wish_badges()[0]["count"]).is_equal(2)


func test_the_overlay_off_shows_no_badge_and_only_the_focused_wish() -> void:
	_open()
	var ids := _group(&"kiosk", 6)
	_draw(false)
	assert_array(_own_wishes(ids)).is_empty()
	assert_array(_wish_badges()).is_empty()
	_views.selected_id = ids[2]
	_views.draw()
	assert_array(_own_wishes(ids)).is_equal([ids[2]])
	assert_array(_wish_badges()).is_empty()


func test_wishes_of_one_kind_in_any_state_merge_into_one_wanted_badge() -> void:
	_open()
	var ids := _group(&"pharmacy", 6)
	_draw()
	# The first three stay wanted, then two fulfilled (tick) and one
	# substituted (cross), as the planner's visits would leave them.
	var states: Array[WishTable.State] = [
		WishTable.State.WANTED,
		WishTable.State.WANTED,
		WishTable.State.WANTED,
		WishTable.State.FULFILLED,
		WishTable.State.FULFILLED,
		WishTable.State.SUBSTITUTED,
	]
	for i in ids.size():
		WishIconView.show_wish(_views.node_for(ids[i]), [&"pharmacy", states[i]])
	_views.draw()
	var badges := _wish_badges()
	print("mixed states: badges %s, own wishes %s" % [badges, _own_wishes(ids)])
	assert_int(badges.size()).is_equal(1)
	assert_int(badges[0]["count"]).is_equal(6)
	# The aggregate is the plain wish bubble of the kind.
	assert_str(badges[0]["wish"]).is_equal(WishIconView.key_of(&"pharmacy", WishTable.State.WANTED))
	var shown := _shown_badge_sprites()
	assert_int(shown.size()).is_equal(1)
	assert_object(shown[0].texture).is_same(
		WishIconView.texture(&"pharmacy", WishTable.State.WANTED)
	)
	assert_array(_own_wishes(ids)).is_empty()
	# A focused passenger keeps its own bubble, tick and all.
	_views.selected_id = ids[3]
	_views.draw()
	assert_array(_own_wishes(ids)).is_equal([ids[3]])
	assert_object(_wish(ids[3]).texture).is_same(
		WishIconView.texture(&"pharmacy", WishTable.State.FULFILLED)
	)
	assert_int(_wish_badges()[0]["count"]).is_equal(5)


func test_wish_codes_are_one_per_shop_kind_and_round_trip() -> void:
	# One cluster identity per shop kind, whatever the wish's state (user
	# ruling: wishes merge per shop kind): the tick or cross is drawn only on a
	# passenger's own bubble.
	var seen := {}
	for kind: StringName in WishTable.CANDIDATES:
		var code := WishBadges.code_of(kind)
		assert_bool(seen.has(code)).override_failure_message(kind).is_false()
		seen[code] = true
		assert_str(WishBadges.key_of_code(code)).is_equal(
			WishIconView.key_of(kind, WishTable.State.WANTED)
		)
		assert_object(WishBadges.texture_of_code(code)).is_same(
			WishIconView.texture(kind, WishTable.State.WANTED)
		)
	assert_int(seen.size()).is_equal(WishTable.CANDIDATES.size())
	# A node's wish kind is cached when its wish changes: -1 with none.
	var node := Node3D.new()
	node.add_child(WishIconView.make_sprite())
	WishIconView.show_wish(node, [&"duty_free", WishTable.State.FULFILLED])
	assert_int(node.get_meta(WishIconView.KIND_META)).is_equal(WishBadges.code_of(&"duty_free"))
	WishIconView.show_wish(node, [WishTable.NONE, WishTable.State.NONE])
	assert_int(node.get_meta(WishIconView.KIND_META)).is_equal(-1)
	node.free()
