class_name TestNeedIcons
extends GdUnitTestSuite
## The need icons over passengers (Toilets 5/5; decision passenger-needs-are-
## hunger-toilet-and-boredom-met-by-food-st: each need shows as an icon above
## the passenger): which needs show, the painted icons, the row's layout on
## screen, the views wiring and the follow panel's toilet need.

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func after_test() -> void:
	_views.free()
	_world.free_all()


func _calm_passenger() -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	return p


func _sprite(node: Node3D, i: int) -> Sprite3D:
	return node.get_node(NeedIcons.SPRITES[i]) as Sprite3D


func test_a_need_shows_from_the_level_its_facility_acts_on() -> void:
	var p := Passenger.new()
	p.stage = Passenger.Stage.TO_SECURITY
	assert_array(NeedIcons.shown(p)).is_empty()
	p.hunger = CafeSim.HUNGRY_AT - 1
	p.toilet_need = ToiletSim.NEED_AT - 1
	assert_array(NeedIcons.shown(p)).is_empty()
	p.hunger = CafeSim.HUNGRY_AT
	assert_array(NeedIcons.shown(p)).is_equal([NeedIcons.Need.HUNGER])
	p.hunger = 0
	p.toilet_need = ToiletSim.NEED_AT
	assert_array(NeedIcons.shown(p)).is_equal([NeedIcons.Need.TOILET])
	p.hunger = CafeSim.HUNGER_MAX
	assert_array(NeedIcons.shown(p)).is_equal([NeedIcons.Need.HUNGER, NeedIcons.Need.TOILET])


func test_an_icon_hides_at_the_facility_meeting_its_need_and_after_a_miss() -> void:
	var p := Passenger.new()
	p.hunger = CafeSim.HUNGER_MAX
	p.toilet_need = ToiletSim.NEED_MAX
	var both := [NeedIcons.Need.HUNGER, NeedIcons.Need.TOILET]
	# Walking to and queueing for a facility keeps both icons.
	for stage in [
		Passenger.Stage.TOILET_WALK, Passenger.Stage.CAFE_WALK, Passenger.Stage.CAFE_QUEUE
	]:
		p.stage = stage
		assert_array(NeedIcons.shown(p)).override_failure_message(str(stage)).is_equal(both)
	# Inside a stall the toilet icon goes; the hunger icon stays.
	for stage in [
		Passenger.Stage.TOILET_ENTER,
		Passenger.Stage.TOILET_SITTING_DOWN,
		Passenger.Stage.TOILET_USE,
		Passenger.Stage.TOILET_STANDING_UP,
		Passenger.Stage.TOILET_EXIT,
	]:
		p.stage = stage
		assert_array(NeedIcons.shown(p)).override_failure_message(str(stage)).is_equal(
			[NeedIcons.Need.HUNGER]
		)
	# At a cafe table the hunger icon goes; the toilet icon stays.
	for stage in [
		Passenger.Stage.CAFE_SITTING_DOWN,
		Passenger.Stage.CAFE_SEATED,
		Passenger.Stage.CAFE_STANDING_UP,
	]:
		p.stage = stage
		assert_array(NeedIcons.shown(p)).override_failure_message(str(stage)).is_equal(
			[NeedIcons.Need.TOILET]
		)
	p.stage = Passenger.Stage.MISSED
	assert_array(NeedIcons.shown(p)).is_empty()


func test_the_icons_are_yellow_circles_with_a_dark_outline_and_differ_by_glyph() -> void:
	var hunger := NeedIcons.texture(NeedIcons.Need.HUNGER).get_image()
	var toilet := NeedIcons.texture(NeedIcons.Need.TOILET).get_image()
	assert_int(hunger.get_width()).is_equal(NeedIcons.SIZE)
	var edge := int(NeedIcons.SIZE / 2.0 - NeedIcons.RADIUS + NeedIcons.OUTLINE_PX / 2.0)
	var mid := NeedIcons.SIZE / 2
	var fill_spot := Vector2i(mid, int(mid + NeedIcons.RADIUS - NeedIcons.OUTLINE_PX - 3.0))
	var differ := 0
	for img in [hunger, toilet]:
		assert_float(img.get_pixel(0, 0).a).is_equal(0.0)
		var rim: Color = img.get_pixel(mid, edge)
		var fill: Color = img.get_pixel(fill_spot.x, fill_spot.y)
		print("rim %s fill %s" % [rim, fill])
		assert_bool(_near(rim, Color(NeedIcons.OUTLINE, 1.0))).is_true()
		assert_bool(_near(fill, Color(NeedIcons.FILL, 1.0))).is_true()
	for y in range(16, NeedIcons.SIZE - 16, 2):
		for x in range(16, NeedIcons.SIZE - 16, 2):
			if not hunger.get_pixel(x, y).is_equal_approx(toilet.get_pixel(x, y)):
				differ += 1
	print("glyph pixels that differ: %d" % differ)
	assert_int(differ).is_greater(200)


## Equal to within the 8-bit image's rounding.
func _near(a: Color, b: Color) -> bool:
	const TOLERANCE := 2.0 / 255.0
	return (
		absf(a.r - b.r) <= TOLERANCE
		and absf(a.g - b.g) <= TOLERANCE
		and absf(a.b - b.b) <= TOLERANCE
		and absf(a.a - b.a) <= TOLERANCE
	)


func test_one_icon_is_centred_and_two_stand_apart_along_the_screen() -> void:
	var one := NeedIcons.offset_of(0, 1)
	assert_float(one.x).is_equal(0.0)
	assert_float(one.y).is_equal(NeedIcons.SIZE / 2.0)
	var left := NeedIcons.offset_of(0, 2)
	var right := NeedIcons.offset_of(1, 2)
	var gap_texture := NeedIcons.GAP_PX * NeedIcons.SIZE / NeedIcons.ICON_PX
	print("two icons at %s and %s" % [left, right])
	assert_float(left.x).is_equal_approx(-right.x, 0.001)
	assert_float(right.x - left.x).is_equal_approx(NeedIcons.SIZE + gap_texture, 0.001)
	# A lift is in screen pixels, scaled to the texture's pixels.
	var lifted := NeedIcons.offset_of(0, 1, 10.0)
	assert_float(lifted.y - one.y).is_equal_approx(10.0 * NeedIcons.SIZE / NeedIcons.ICON_PX, 0.001)


func test_the_views_show_a_passengers_needs_over_its_head() -> void:
	var p := _calm_passenger()
	_world.step()
	var node := _views.node_for(p.id)
	assert_object(node).is_not_null()
	assert_bool(_sprite(node, 0).visible).is_false()
	assert_bool(_sprite(node, 1).visible).is_false()
	p.hunger = CafeSim.HUNGRY_AT
	p.cafe_cooldown = 1000000
	_world.step()
	assert_bool(_sprite(node, 0).visible).is_true()
	assert_object(_sprite(node, 0).texture).is_same(NeedIcons.texture(NeedIcons.Need.HUNGER))
	assert_bool(_sprite(node, 1).visible).is_false()
	p.toilet_need = ToiletSim.NEED_MAX
	p.toilet_cooldown = 1000000
	_world.step()
	assert_bool(_sprite(node, 1).visible).is_true()
	assert_object(_sprite(node, 1).texture).is_same(NeedIcons.texture(NeedIcons.Need.TOILET))
	var icon := _sprite(node, 0)
	print(
		"icon at %s, fixed %s, no depth %s" % [icon.position, icon.fixed_size, icon.no_depth_test]
	)
	assert_float(icon.position.y).is_equal(NeedIcons.LIFT_M)
	assert_bool(icon.fixed_size).is_true()
	assert_bool(icon.no_depth_test).is_true()
	assert_bool(icon.billboard == BaseMaterial3D.BILLBOARD_ENABLED).is_true()


func test_with_a_camera_the_row_keeps_its_screen_size_and_clears_a_bubble() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 55.0
	camera.look_at_from_position(Vector3(10.0, 12.0, 30.0), Vector3(10.0, 0.0, 10.0))
	camera.make_current()
	var p := _calm_passenger()
	p.hunger = CafeSim.HUNGER_MAX
	p.toilet_need = ToiletSim.NEED_MAX
	_world.step()
	var node := _views.node_for(p.id)
	(node.get_node("Bubble") as Label3D).text = ""
	_views.draw()
	var unit := NeedIcons.unit_of(get_viewport(), camera)
	assert_float(unit).is_greater(0.0)
	var icon := _sprite(node, 1)
	print("unit %.6f pixel_size %.6f offset %s" % [unit, icon.pixel_size, icon.offset])
	assert_float(icon.pixel_size).is_equal_approx(NeedIcons.ICON_PX * unit / NeedIcons.SIZE, 1e-9)
	assert_vector(icon.offset).is_equal(NeedIcons.offset_of(1, 2))
	var bubble := node.get_node("Bubble") as Label3D
	bubble.text = "I'm late!"
	_views.draw()
	print("with a bubble: at %s offset %s" % [icon.position, icon.offset])
	assert_vector(icon.position).is_equal(bubble.position)
	# The lift is the bubble's top on screen plus the gap: the bubble's font of
	# 56 and outline of 14 at 0.006 m a pixel reach 0.21 m over its centre (a
	# control against an empty height passing on the gap alone). The windowed
	# toilet probe measures the drawn gap.
	var top_m := (56 + 14) * 0.006 / 2.0
	assert_float(NeedIcons.bubble_top_m(bubble)).is_equal_approx(top_m, 0.0001)
	var at := node.global_transform * bubble.position
	var depth := (at - camera.global_position).dot(-camera.global_basis.z)
	var lift_px := top_m / (depth * unit) + NeedIcons.GAP_PX
	print("bubble top %.3f m, depth %.2f m, lift %.1f px" % [top_m, depth, lift_px])
	assert_float(top_m).is_greater(0.1)
	# The headless view is small and the passenger far off, so the bubble is
	# well under a pixel here; the lift must still hold more than the gap.
	assert_float(lift_px).is_greater(NeedIcons.GAP_PX)
	assert_vector(icon.offset).is_equal_approx(
		NeedIcons.offset_of(1, 2, lift_px), Vector2.ONE * 0.001
	)
	camera.free()


## User ruling: need icons show only while the camera is closer than its home
## zoom; at the home zoom or farther out they are hidden.
func test_icons_hide_at_and_past_the_home_zoom_and_show_closer_in() -> void:
	var rig := (
		(load("res://camera/tycoon_camera.tscn") as PackedScene).instantiate() as TycoonCamera
	)
	rig.home_distance = 40.0
	add_child(rig)
	rig.set_process(false)
	var camera := rig.get_node("Camera3D") as Camera3D
	camera.make_current()
	var p := _calm_passenger()
	p.hunger = CafeSim.HUNGER_MAX
	p.toilet_need = ToiletSim.NEED_MAX
	_world.step()
	var node := _views.node_for(p.id)
	var seen := {}
	for distance in [39.0, 40.0, 41.0, 120.0, 12.0]:
		rig.distance = distance
		_views.draw()
		seen[distance] = [
			NeedIcons.shown_at(camera), _sprite(node, 0).visible, _sprite(node, 1).visible
		]
	print("home 40: distance -> [shown_at, icon 0, icon 1] %s" % seen)
	assert_array(seen[39.0]).is_equal([true, true, true])
	assert_array(seen[12.0]).is_equal([true, true, true])
	assert_array(seen[40.0]).is_equal([false, false, false])
	assert_array(seen[41.0]).is_equal([false, false, false])
	assert_array(seen[120.0]).is_equal([false, false, false])
	# A tick while zoomed out keeps them hidden: the frame's layout wins.
	rig.distance = 60.0
	_world.step()
	_views.draw()
	assert_bool(_sprite(node, 0).visible).is_false()
	# Any camera outside a TycoonCamera rig, or none, shows them.
	assert_bool(NeedIcons.shown_at(null)).is_true()
	rig.free()


func test_the_follow_panel_shows_the_toilet_need() -> void:
	var hud := PassengerHud.new()
	hud.clock = _world.clock
	hud.flights = _world.flights
	hud.sim = _world.sim
	hud.views = _views
	add_child(hud)
	var p := _calm_passenger()
	p.hunger = 47
	p.toilet_need = 81
	_views.selected_id = p.id
	print(hud.follow_text())
	assert_str(hud.follow_text()).contains("hunger 47   toilet 81")
	hud.free()
