class_name TestWishIconView
extends GdUnitTestSuite
## The shopping wish icon over a bored passenger (ruling store-variety-
## passengers-have-a-shopping-wish-weighted-by-arrival-type-unmet-settles-for-
## less: the wish shows as a small icon over the passenger; decision shopping-
## wish-technical-design-id-hash-wish-admissible-wished-slot-then-fallback,
## point 5): which icon and badge each state and kind maps to, the painted
## icons, hiding at NONE and at the home zoom, the views wiring, and that the
## view reads the planner's result and never plans.


## Counts every planning call; answers the two reads with fixed values.
class FakeShops:
	extends ShopSim
	var state := WishTable.State.NONE
	var kind := WishTable.NONE
	var reads := 0
	var wish_reads := 0
	var plans := 0

	func visit_wish_state(_passenger_id: int) -> WishTable.State:
		reads += 1
		return state

	func wish_of(_p: Passenger) -> StringName:
		wish_reads += 1
		return kind

	func plan_visit(_p: Passenger, _browsing := false) -> Dictionary:
		plans += 1
		return {}

	func commit_visit(_p: Passenger, _plan: Dictionary) -> void:
		plans += 1

	func refuse(_p: Passenger, _browsing := false) -> void:
		plans += 1

	func refresh() -> void:
		plans += 1

	func wants_relief(_p: Passenger) -> bool:
		plans += 1
		return false

	func wants_browse(_p: Passenger) -> bool:
		plans += 1
		return false


const STATES := [WishTable.State.WANTED, WishTable.State.FULFILLED, WishTable.State.SUBSTITUTED]

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


## A world of WishTestLayout `types` where every passenger wishes `wish`, and
## views over it.
func _wish_world(types: Array, wish: StringName) -> void:
	var grid := BuildGrid.new()
	WishTestLayout.build(grid, types)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return wish
	_world.run_to(10)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func _sprite(node: Node3D) -> Sprite3D:
	return node.get_node(WishIconView.SPRITE) as Sprite3D


func test_each_state_maps_to_its_badge() -> void:
	assert_int(WishIconView.badge_of(WishTable.State.NONE)).is_equal(WishIconView.Badge.NONE)
	assert_int(WishIconView.badge_of(WishTable.State.WANTED)).is_equal(WishIconView.Badge.NONE)
	assert_int(WishIconView.badge_of(WishTable.State.FULFILLED)).is_equal(WishIconView.Badge.TICK)
	assert_int(WishIconView.badge_of(WishTable.State.SUBSTITUTED)).is_equal(
		WishIconView.Badge.CROSS
	)


func test_every_kind_and_state_has_its_own_icon_and_none_has_none() -> void:
	var seen := {}
	for kind in WishTable.CANDIDATES:
		for state in STATES:
			var key := WishIconView.key_of(kind, state)
			assert_str(key).is_not_empty()
			var texture := WishIconView.texture(kind, state)
			assert_object(texture).is_not_null()
			# Painted once and kept.
			assert_object(WishIconView.texture(kind, state)).is_same(texture)
			seen[texture] = key
	print("icons: %d" % seen.size())
	assert_int(seen.size()).is_equal(WishTable.CANDIDATES.size() * STATES.size())
	for kind in WishTable.CANDIDATES:
		assert_str(WishIconView.key_of(kind, WishTable.State.NONE)).is_empty()
	for state in STATES:
		assert_str(WishIconView.key_of(WishTable.NONE, state)).is_empty()


func test_the_badge_is_a_green_tick_a_coral_cross_or_absent() -> void:
	var spot := WishIconView.BADGE_CENTRE + Vector2.ONE * WishIconView.SIZE / 2.0
	# The badge's fill, between its outline and its mark.
	var fill_at := Vector2i(spot + Vector2(0.0, WishIconView.BADGE_RADIUS - 9.0))
	var wanted := WishIconView.texture(&"kiosk", WishTable.State.WANTED).get_image()
	var fulfilled := WishIconView.texture(&"kiosk", WishTable.State.FULFILLED).get_image()
	var substituted := WishIconView.texture(&"kiosk", WishTable.State.SUBSTITUTED).get_image()
	var plain: Color = wanted.get_pixel(fill_at.x, fill_at.y)
	var good: Color = fulfilled.get_pixel(fill_at.x, fill_at.y)
	var problem: Color = substituted.get_pixel(fill_at.x, fill_at.y)
	print("badge fill: wanted %s fulfilled %s substituted %s" % [plain, good, problem])
	assert_float(plain.a).is_equal(0.0)
	assert_bool(_near(good, Color(WishIconView.GOOD, 1.0))).is_true()
	assert_bool(_near(problem, Color(WishIconView.PROBLEM, 1.0))).is_true()
	# The tick and the cross differ in shape, not only in colour: count the
	# white mark pixels inside the badge that are in one and not the other.
	var differ := 0
	var marks := 0
	var r := int(WishIconView.BADGE_RADIUS)
	for y in range(int(spot.y) - r, int(spot.y) + r):
		for x in range(int(spot.x) - r, mini(int(spot.x) + r, WishIconView.SIZE)):
			var tick := _near(fulfilled.get_pixel(x, y), Color(WishIconView.MARK, 1.0))
			var cross := _near(substituted.get_pixel(x, y), Color(WishIconView.MARK, 1.0))
			if tick:
				marks += 1
			if tick != cross:
				differ += 1
	print("tick mark pixels %d, tick and cross differ at %d" % [marks, differ])
	assert_int(marks).is_greater(80)
	assert_int(differ).is_greater(80)


func test_the_kinds_differ_by_glyph_on_one_cream_bubble() -> void:
	var images := []
	for kind in WishTable.CANDIDATES:
		images.append(WishIconView.texture(kind, WishTable.State.WANTED).get_image())
	var mid := Vector2i(WishIconView.BODY_CENTRE + Vector2.ONE * WishIconView.SIZE / 2.0)
	# Inside the body's outline, up and left of every glyph.
	var cream_at := mid + Vector2i(-34, -24)
	for img: Image in images:
		assert_float(img.get_pixel(0, 0).a).is_equal(0.0)
		var cream := img.get_pixel(cream_at.x, cream_at.y)
		assert_bool(_near(cream, Color(WishIconView.CARD, 1.0))).is_true()
		assert_float(img.get_pixel(mid.x, mid.y).a).is_equal(1.0)
	for i in images.size():
		for j in range(i + 1, images.size()):
			var differ := 0
			for y in range(8, WishIconView.SIZE - 8, 2):
				for x in range(8, WishIconView.SIZE - 8, 2):
					if not images[i].get_pixel(x, y).is_equal_approx(images[j].get_pixel(x, y)):
						differ += 1
			print(
				(
					"%s vs %s: %d pixels differ"
					% [WishTable.CANDIDATES[i], WishTable.CANDIDATES[j], differ]
				)
			)
			assert_int(differ).is_greater(100)


func test_the_icon_shows_each_state_and_hides_at_none() -> void:
	var node := Node3D.new()
	node.add_child(WishIconView.make_sprite())
	var sprite := _sprite(node)
	assert_bool(sprite.visible).is_false()
	for state in STATES:
		WishIconView.show_wish(node, [&"pharmacy", state])
		assert_bool(sprite.visible).is_true()
		assert_object(sprite.texture).is_same(WishIconView.texture(&"pharmacy", state))
	WishIconView.show_wish(node, [&"pharmacy", WishTable.State.NONE])
	assert_bool(sprite.visible).is_false()
	WishIconView.show_wish(node, [WishTable.NONE, WishTable.State.WANTED])
	assert_bool(sprite.visible).is_false()
	node.free()


func test_the_icon_changes_only_when_the_state_changes() -> void:
	var node := Node3D.new()
	node.add_child(WishIconView.make_sprite())
	var sprite := _sprite(node)
	WishIconView.show_wish(node, [&"fashion", WishTable.State.WANTED])
	# Cleared by hand: a repeat of the same wish must not set it again.
	sprite.texture = null
	WishIconView.show_wish(node, [&"fashion", WishTable.State.WANTED])
	assert_object(sprite.texture).is_null()
	# Control: a new state does set it.
	WishIconView.show_wish(node, [&"fashion", WishTable.State.FULFILLED])
	assert_object(sprite.texture).is_same(
		WishIconView.texture(&"fashion", WishTable.State.FULFILLED)
	)
	node.free()


func test_the_view_reads_the_planner_and_never_plans() -> void:
	var shops := FakeShops.new()
	var p := Passenger.new()
	p.id = 7
	p.stage = Passenger.Stage.TO_GATE
	p.boredom = BoredomSim.MAX
	shops.kind = &"duty_free"
	for state in STATES:
		shops.state = state
		assert_array(WishIconView.read(shops, p)).is_equal([&"duty_free", state])
	shops.state = WishTable.State.NONE
	assert_int(WishIconView.read(shops, p)[1]).is_equal(WishTable.State.NONE)
	print("reads %d, wish reads %d, plans %d" % [shops.reads, shops.wish_reads, shops.plans])
	# Positive control: the view did read the planner's state and the wish.
	assert_int(shops.reads).is_equal(4)
	assert_int(shops.wish_reads).is_greater(2)
	assert_int(shops.plans).is_equal(0)
	# A passenger who missed its flight shows nothing, whatever its state.
	shops.state = WishTable.State.WANTED
	p.stage = Passenger.Stage.MISSED
	assert_int(WishIconView.read(shops, p)[1]).is_equal(WishTable.State.NONE)
	assert_int(shops.plans).is_equal(0)


func test_the_views_show_wanted_then_fulfilled_over_a_bored_wisher() -> void:
	_wish_world([&"kiosk"], &"kiosk")
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	_views.sync()
	var node := _views.node_for(p.id)
	assert_object(node).is_not_null()
	assert_bool(_sprite(node).visible).is_true()
	assert_object(_sprite(node).texture).is_same(
		WishIconView.texture(&"kiosk", WishTable.State.WANTED)
	)
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	_views.sync()
	assert_object(_sprite(node).texture).is_same(
		WishIconView.texture(&"kiosk", WishTable.State.FULFILLED)
	)
	assert_bool(_sprite(node).visible).is_true()
	# Not bored: no icon.
	var calm := ShopTestLayout.airside_guest(_world, 0)
	_views.sync()
	assert_bool(_sprite(_views.node_for(calm.id)).visible).is_false()


func test_the_views_show_substituted_when_the_wished_kind_is_missing() -> void:
	_wish_world([&"kiosk"], &"pharmacy")
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	assert_bool(_world.sim.shops.visit_of(p.id).fallback).is_true()
	_views.sync()
	var sprite := _sprite(_views.node_for(p.id))
	assert_bool(sprite.visible).is_true()
	assert_object(sprite.texture).is_same(
		WishIconView.texture(&"pharmacy", WishTable.State.SUBSTITUTED)
	)


## User ruling shopping-wish-icon-replaces-the-boredom-hourglass-for-wishers:
## a bored passenger with a wish shows the bubble in the need row in place of
## the hourglass; one with no wish keeps the hourglass; hunger and toilet are
## unchanged.
func test_a_wish_takes_the_hourglass_place_and_other_needs_stay() -> void:
	var p := Passenger.new()
	p.stage = Passenger.Stage.TO_GATE
	p.boredom = BoredomSim.MAX
	assert_array(NeedIcons.shown(p)).is_equal([NeedIcons.Need.BOREDOM])
	assert_array(NeedIcons.shown(p, false)).is_equal([NeedIcons.Need.BOREDOM])
	assert_array(NeedIcons.shown(p, true)).is_empty()
	p.hunger = CafeSim.HUNGRY_AT
	p.toilet_need = ToiletSim.NEED_AT
	assert_array(NeedIcons.shown(p, true)).is_equal([NeedIcons.Need.HUNGER, NeedIcons.Need.TOILET])
	assert_array(NeedIcons.shown(p, false)).is_equal(
		[NeedIcons.Need.HUNGER, NeedIcons.Need.TOILET, NeedIcons.Need.BOREDOM]
	)


## A TycoonCamera closer than its home zoom over a world of `types` where
## every passenger wishes `wish`.
func _rig_over(types: Array, wish: StringName) -> TycoonCamera:
	_wish_world(types, wish)
	var rig := (
		(load("res://camera/tycoon_camera.tscn") as PackedScene).instantiate() as TycoonCamera
	)
	rig.home_distance = 40.0
	add_child(rig)
	rig.set_process(false)
	rig.distance = 12.0
	(rig.get_node("Camera3D") as Camera3D).make_current()
	return rig


func _need_sprite(node: Node3D, i: int) -> Sprite3D:
	return node.get_node(NeedIcons.SPRITES[i]) as Sprite3D


## A drawn sprite's centre along the row, in screen pixels.
static func _row_x_px(sprite: Sprite3D, size: float, px: float) -> float:
	return sprite.offset.x * px / size


func test_a_bored_wisher_shows_the_bubble_in_the_row_and_no_hourglass() -> void:
	var rig := _rig_over([&"kiosk"], &"kiosk")
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	_views.sync()
	var node := _views.node_for(p.id)
	(node.get_node("Bubble") as Label3D).text = ""
	_views.draw()
	var wish := _sprite(node)
	print(
		(
			"needs %d, wish visible %s offset %s"
			% [node.get_meta(&"needs", 0), wish.visible, wish.offset]
		)
	)
	assert_int(node.get_meta(&"needs", 0)).is_equal(0)
	for i in NeedIcons.SPRITES.size():
		assert_bool(_need_sprite(node, i).visible).is_false()
	assert_bool(wish.visible).is_true()
	assert_object(wish.texture).is_same(WishIconView.texture(&"kiosk", WishTable.State.WANTED))
	# In the row, alone: centred, its bottom on the row's anchor over the head.
	assert_vector(wish.position).is_equal(Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	assert_vector(wish.offset).is_equal_approx(WishIconView.offset_for(0.0), Vector2.ONE * 0.001)
	var unit := NeedIcons.unit_of(get_viewport(), rig.get_node("Camera3D") as Camera3D)
	assert_float(wish.pixel_size).is_equal_approx(
		WishIconView.WISH_PX * unit / WishIconView.SIZE, 1e-9
	)
	# At the home zoom it hides with the need icons.
	rig.distance = 40.0
	_views.draw()
	assert_bool(wish.visible).is_false()
	rig.free()


func test_a_bored_passenger_with_no_wish_keeps_the_hourglass() -> void:
	var rig := _rig_over([&"kiosk"], WishTable.NONE)
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	_views.sync()
	var node := _views.node_for(p.id)
	_views.draw()
	assert_int(node.get_meta(&"needs", 0)).is_equal(1)
	assert_bool(_need_sprite(node, 0).visible).is_true()
	assert_object(_need_sprite(node, 0).texture).is_same(NeedIcons.texture(NeedIcons.Need.BOREDOM))
	assert_bool(_sprite(node).visible).is_false()
	rig.free()


func test_a_hungry_wisher_shows_the_hunger_icon_then_the_bubble() -> void:
	var rig := _rig_over([&"kiosk"], &"pharmacy")
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	p.hunger = CafeSim.HUNGRY_AT
	p.cafe_cooldown = 1000000
	_views.sync()
	var node := _views.node_for(p.id)
	(node.get_node("Bubble") as Label3D).text = ""
	_views.draw()
	var hunger := _need_sprite(node, 0)
	var wish := _sprite(node)
	assert_int(node.get_meta(&"needs", 0)).is_equal(1)
	assert_object(hunger.texture).is_same(NeedIcons.texture(NeedIcons.Need.HUNGER))
	assert_bool(hunger.visible).is_true()
	assert_bool(_need_sprite(node, 1).visible).is_false()
	assert_bool(wish.visible).is_true()
	var left := _row_x_px(hunger, NeedIcons.SIZE, NeedIcons.ICON_PX)
	var right := _row_x_px(wish, WishIconView.SIZE, WishIconView.WISH_PX)
	print("hunger at %.1f px, wish at %.1f px" % [left, right])
	# Side by side, GAP_PX apart, the pair centred, both bottoms on the anchor.
	assert_float(right - left).is_equal_approx(
		(NeedIcons.ICON_PX + WishIconView.WISH_PX) / 2.0 + NeedIcons.GAP_PX, 0.001
	)
	var row_left := left - NeedIcons.ICON_PX / 2.0
	var row_right := right + WishIconView.WISH_PX / 2.0
	assert_float(row_left + row_right).is_equal_approx(0.0, 0.01)
	assert_float(hunger.offset.y).is_equal_approx(NeedIcons.SIZE / 2.0, 0.001)
	assert_float(wish.offset.y).is_equal_approx(WishIconView.offset_for(0.0).y, 0.001)
	assert_vector(hunger.position).is_equal(wish.position)
	rig.free()


## Equal to within the 8-bit image's rounding.
func _near(a: Color, b: Color) -> bool:
	const TOLERANCE := 2.0 / 255.0
	return (
		absf(a.r - b.r) <= TOLERANCE
		and absf(a.g - b.g) <= TOLERANCE
		and absf(a.b - b.b) <= TOLERANCE
		and absf(a.a - b.a) <= TOLERANCE
	)
