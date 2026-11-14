class_name TestNeedIconsOverlayOnly
extends GdUnitTestSuite
## Need icons show only while the Mood overlay is open in its Hunger, Toilet or
## Boredom mode, and then only that need's, with the count badges (decision
## need-icons-show-only-in-the-mood-overlay-need-modes-n-key-removed). The
## default view and plain Mood mode show none, the zoom-out hide still applies
## inside a need mode, wish bubbles show only in Boredom mode (decision calm-
## cozy-default-view-quiet-world-detail-on-ask-soft-statio, part 3, which
## replaced "wish bubbles stay in the default view"), and the N key's action is
## gone.

const NEEDS := [NeedIcons.Need.HUNGER, NeedIcons.Need.TOILET, NeedIcons.Need.BOREDOM]
const MODE_OF := {
	NeedIcons.Need.HUNGER: MoodTint.Mode.HUNGER,
	NeedIcons.Need.TOILET: MoodTint.Mode.TOILET,
	NeedIcons.Need.BOREDOM: MoodTint.Mode.BOREDOM,
}
const CROWD := 10

var _world: PassengerTestWorld
var _views: PassengerViews
var _rig: TycoonCamera
var _camera: Camera3D
var _screen: SubViewport


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


## Views over `grid` in a 1600 x 900 viewport under a TycoonCamera rig that is
## closer than its home zoom (40 m), the camera 15 m from the crowd at `centre`.
func _open(grid: BuildGrid, wish: StringName) -> void:
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return wish
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_screen = SubViewport.new()
	_screen.size = Vector2i(1600, 900)
	add_child(_screen)
	_screen.add_child(_views)
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


## A crowd of CROWD close passengers, each with every need at its maximum,
## framed from about 15 m.
func _crowd_with_all_needs() -> Array[int]:
	var grid := BuildGrid.new()
	NeedFacilityKit.build(grid)
	_open(grid, WishTable.NONE)
	var ids: Array[int] = []
	for i in CROWD:
		var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		ids.append(id)
		var p := _world.passenger(id)
		ToiletTestLayout.calm(p)
		p.hunger = CafeSim.HUNGER_MAX
		p.toilet_need = ToiletSim.NEED_MAX
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
	return ids


func _mode(mode: MoodTint.Mode, shown := true) -> void:
	var overlay := PassengerTestWorld.ensure_overlay(_views)
	overlay.set_mode(mode)
	overlay.set_shown(shown)
	_views.draw()


## How many need icon sprites show, per need (NeedIcons.Need -> count).
func _drawn_by_need(ids: Array[int]) -> Dictionary:
	var out := {}
	for need: int in NEEDS:
		out[need] = 0
	for id in ids:
		var node := _views.node_for(id)
		var kinds: Array = node.get_meta(&"need_kinds", [])
		for i in kinds.size():
			if (node.get_node(NeedIcons.SPRITES[i]) as Sprite3D).visible:
				out[kinds[i]] += 1
	return out


func _icons_total(ids: Array[int]) -> int:
	var total := 0
	for count: int in _drawn_by_need(ids).values():
		total += count
	return total


func _visible_badges() -> Array[Sprite3D]:
	var out: Array[Sprite3D] = []
	for child in _views.get_node(NeedCluster.ROOT).get_children():
		if (child as Sprite3D).visible:
			out.append(child)
	return out


func test_the_default_view_shows_no_need_icon_and_no_badge() -> void:
	var ids := _crowd_with_all_needs()
	print("overlay off: icons %s, badges %d" % [_drawn_by_need(ids), _visible_badges().size()])
	# The control: the passengers do have every need.
	assert_int(_views.node_for(ids[0]).get_meta(&"need_kinds", []).size()).is_equal(3)
	assert_bool(_views.mood_overlay.is_shown()).is_false()
	assert_int(_icons_total(ids)).is_equal(0)
	assert_int(_visible_badges().size()).is_equal(0)
	assert_int(_views.need_badges().size()).is_equal(0)


func test_plain_mood_mode_shows_no_need_icon_and_no_badge() -> void:
	var ids := _crowd_with_all_needs()
	_mode(MoodTint.Mode.MOOD)
	print("mood mode: icons %s, badges %d" % [_drawn_by_need(ids), _visible_badges().size()])
	assert_bool(_views.mood_overlay.is_shown()).is_true()
	assert_int(_icons_total(ids)).is_equal(0)
	assert_int(_visible_badges().size()).is_equal(0)


func test_each_need_mode_shows_only_its_own_icons() -> void:
	var ids := _crowd_with_all_needs()
	_views.cluster_needs = false
	for need: int in NEEDS:
		_mode(MODE_OF[need])
		var drawn := _drawn_by_need(ids)
		print("mode %d: icons %s" % [MODE_OF[need], drawn])
		for other: int in NEEDS:
			assert_int(drawn[other]).is_equal(CROWD if other == need else 0)


func test_each_need_mode_shows_only_its_own_badge() -> void:
	var ids := _crowd_with_all_needs()
	for need: int in NEEDS:
		_mode(MODE_OF[need])
		var badges := _views.need_badges()
		print("need %d: badges %s, icons %s" % [need, badges, _drawn_by_need(ids)])
		assert_int(badges.size()).is_equal(1)
		assert_int(badges[0]["kind"]).is_equal(need)
		assert_int(badges[0]["count"]).is_equal(CROWD)
		assert_int(_visible_badges().size()).is_equal(1)
		assert_int(_icons_total(ids)).is_equal(0)


func test_closing_the_overlay_hides_the_icons_again() -> void:
	var ids := _crowd_with_all_needs()
	_views.cluster_needs = false
	_mode(MoodTint.Mode.TOILET)
	assert_int(_icons_total(ids)).is_equal(CROWD)
	_mode(MoodTint.Mode.TOILET, false)
	assert_int(_icons_total(ids)).is_equal(0)


func test_zoomed_out_past_home_no_icon_shows_even_in_a_need_mode() -> void:
	var ids := _crowd_with_all_needs()
	_mode(MoodTint.Mode.HUNGER)
	# The control: close in, the badge shows.
	assert_int(_visible_badges().size()).is_equal(1)
	_rig.distance = _rig.home_distance
	_views.draw()
	print("zoomed out: icons %s, badges %d" % [_drawn_by_need(ids), _visible_badges().size()])
	assert_int(_icons_total(ids)).is_equal(0)
	assert_int(_visible_badges().size()).is_equal(0)
	assert_int(_views.need_badges().size()).is_equal(0)


func test_a_wish_bubble_shows_only_in_boredom_mode() -> void:
	var grid := BuildGrid.new()
	WishTestLayout.build(grid, [&"kiosk"])
	_open(grid, &"kiosk")
	var p := ShopTestLayout.airside_guest(_world, BoredomSim.MAX)
	_views.sync()
	var node := _views.node_for(p.id)
	var wish := node.get_node(WishIconView.SPRITE) as Sprite3D
	_camera.global_position = node.global_position + Vector3(0.0, 12.0, 9.0)
	_camera.look_at(node.global_position + Vector3(0.0, NeedIcons.LIFT_M, 0.0))
	_views.draw()
	var need_icons := func() -> int:
		var shown := 0
		for sprite_name: String in NeedIcons.SPRITES:
			shown += 1 if (node.get_node(sprite_name) as Sprite3D).visible else 0
		return shown
	print("overlay off: wish %s, need icons %d" % [wish.visible, need_icons.call()])
	# The control: the passenger does wish.
	assert_str(node.get_meta(&"wish", "")).is_not_empty()
	assert_bool(wish.visible).is_false()
	assert_int(need_icons.call()).is_equal(0)
	for mode: MoodTint.Mode in MoodTint.Mode.values():
		_mode(mode)
		print("mode %d: wish %s" % [mode, wish.visible])
		assert_bool(wish.visible).is_equal(mode == MoodTint.Mode.BOREDOM)
	# In Boredom mode the wish takes the hourglass's place in the row.
	_mode(MoodTint.Mode.BOREDOM)
	assert_int(need_icons.call()).is_equal(0)
	# The wish hides with the zoom-out rule, as before.
	_rig.distance = _rig.home_distance
	_views.draw()
	assert_bool(wish.visible).is_false()


func test_the_toggle_need_icons_action_is_gone() -> void:
	assert_bool(InputMap.has_action(&"toggle_need_icons")).is_false()
