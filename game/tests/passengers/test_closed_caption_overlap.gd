class_name TestClosedCaptionOverlap
extends GdUnitTestSuite
## Neighbouring station captions must not print over each other ("ClCloseded").
## At the home zoom the reference terminal's desks stand a few pixels apart, far
## closer than one caption is wide, so MissMarkers shows a caption only where it
## clears the captions already placed, keeps every icon, and lifts (never hides)
## the two staff-spot reasons.
##
## The rules are checked on the screen rectangles of the captions a real tycoon
## camera rig projects. One test measures the width with the Label3D's own
## bounds instead of caption_rect(). What this does not prove is how the glyphs
## look; the windowed plate (tools/blender/out/caption-declutter/) is that check.

## The tycoon camera's closest zoom, where neighbouring desks stand far apart on screen.
const NEAR_DISTANCE := 6.0
const HOME_DISTANCE := 80.0
const CAMERA_SCENE := "res://camera/tycoon_camera.tscn"
## A layout of the 300 captions below must finish well inside this many
## milliseconds; the real figure is a small fraction of it.
const BIG_LAYOUT_BUDGET_MSEC := 250

var _world: PassengerTestWorld
var _port: SubViewport
var _rig: Node3D
var _views: PassengerViews
var _markers: MissMarkers


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_attach(_unstaffed_reference())


func after_test() -> void:
	_port.free()
	_world.free_all()


func _unstaffed_reference() -> PassengerTestWorld:
	var world := PassengerTestWorld.reference_world()
	world.auto_staff = false
	return world


func _attach(world: PassengerTestWorld) -> void:
	_world = world
	_rig = null
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_port.add_child(_views)
	_markers = _views.get_node("MissMarkers") as MissMarkers


## The real tycoon camera rig `distance` metres from the closed signs' middle,
## at the pitch the rig gives that distance, and a draw from it.
func _frame_closed_signs(distance: float) -> void:
	var sum := Vector3.ZERO
	var closed := MissSignals.closed_stations(_world.sim)
	for station: int in closed:
		sum += _markers.closed_sign_for(station).position
	if is_instance_valid(_rig):
		_rig.free()
	_rig = (load(CAMERA_SCENE) as PackedScene).instantiate() as Node3D
	_rig.set("home_position", sum / closed.size())
	_rig.set("home_distance", distance)
	_port.add_child(_rig)
	_markers.draw()


## Moves the camera a hair so the next draw has a changed view to lay out.
func _nudge_camera() -> void:
	_rig.position.x += 0.001
	_markers.draw()


func _camera() -> Camera3D:
	return _port.get_camera_3d()


func _caption_of(station: int) -> Label3D:
	return _markers.closed_sign_for(station).get_node("Caption") as Label3D


func _point_of(station: int) -> Vector2:
	return _camera().unproject_position(_markers.closed_sign_for(station).global_position)


## The rectangle a showing caption covers, with any lift it was given.
func _rect_of(station: int) -> Rect2:
	var caption := _caption_of(station)
	var lift := caption.offset.y - MissMarkers.SIGN_PX - MissMarkers.CAPTION_GAP_PX
	return MissMarkers.caption_rect(_point_of(station), caption.text, lift)


func _shown_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for station: int in MissSignals.closed_stations(_world.sim):
		if _caption_of(station).visible:
			rects.append(_rect_of(station))
	return rects


func _assert_clear_by_the_margin(rects: Array[Rect2]) -> void:
	var margin := MissMarkers.CAPTION_MARGIN_PX - 0.01
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_bool(rects[i].grow(margin).intersects(rects[j])).is_false()


## The two closed stations furthest left on screen. Nothing is placed ahead of
## them, so what happens to the pair depends only on the pair.
func _leftmost_pair() -> Array[int]:
	var stations: Array[int] = []
	stations.assign(MissSignals.closed_stations(_world.sim))
	stations.sort_custom(func(a: int, b: int) -> bool: return _point_of(a).x < _point_of(b).x)
	return [stations[0], stations[1]]


## Gives the two stations these captions and lays out again.
func _set_pair(pair: Array[int], left_text: String, right_text: String) -> void:
	var left := pair[0] if _point_of(pair[0]).x <= _point_of(pair[1]).x else pair[1]
	var right := pair[1] if left == pair[0] else pair[0]
	_caption_of(left).text = left_text
	_caption_of(right).text = right_text
	_nudge_camera()


func _pair_overlaps(pair: Array[int]) -> bool:
	var a := MissMarkers.caption_rect(_point_of(pair[0]), _caption_of(pair[0]).text)
	var b := MissMarkers.caption_rect(_point_of(pair[1]), _caption_of(pair[1]).text)
	return a.intersects(b)


func test_home_zoom_captions_keep_the_margin_between_them() -> void:
	var closed := MissSignals.closed_stations(_world.sim)
	# Control: the terminal has several closed stations to crowd together.
	assert_int(closed.size()).is_greater(3)
	_frame_closed_signs(HOME_DISTANCE)
	var rects := _shown_rects()
	assert_int(rects.size()).is_greater(0)
	_assert_clear_by_the_margin(rects)
	# Control: the crowd really was too tight for every caption, so some hid.
	assert_int(rects.size()).is_less(closed.size())


func test_every_closed_icon_stays_when_a_caption_hides() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	for station: int in MissSignals.closed_stations(_world.sim):
		assert_bool(_markers.closed_sign_for(station).visible).is_true()


func test_zoomed_in_every_closed_caption_shows() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var far_shown := _shown_rects().size()
	_frame_closed_signs(NEAR_DISTANCE)
	var closed := MissSignals.closed_stations(_world.sim)
	assert_int(_shown_rects().size()).is_equal(closed.size())
	assert_int(far_shown).is_less(closed.size())


func test_the_rig_pose_is_the_one_the_camera_gives_at_that_distance() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var expected := deg_to_rad((_rig as TycoonCamera).pitch_for_distance(HOME_DISTANCE))
	var forward := -_camera().global_transform.basis.z
	assert_float(asin(-forward.y)).is_equal_approx(expected, 0.001)
	assert_float(_camera().global_position.distance_to(_rig.position)).is_equal_approx(
		HOME_DISTANCE, 0.01
	)


func test_a_staff_spot_caption_beats_a_wide_queue_full_one_that_overlaps_it() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var pair := _leftmost_pair()
	var wide := "Queue full · +30000 waiting, lane at capacity"
	# Control: the queue-full caption is the wider, so width alone would pick it.
	assert_float(MissMarkers.caption_size(wide).x).is_greater(
		MissMarkers.caption_size(MissMarkers.UNREACHABLE_CAPTION).x
	)
	# The staff-spot caption on the left, then on the right.
	for order in [0, 1]:
		var texts := [MissMarkers.UNREACHABLE_CAPTION, wide]
		if order == 1:
			texts.reverse()
		_set_pair(pair, texts[0], texts[1])
		# Control: the pair does overlap.
		assert_bool(_pair_overlaps(pair)).is_true()
		for station in pair:
			var staff_spot := MissMarkers.is_staff_spot_caption(_caption_of(station).text)
			assert_bool(_caption_of(station).visible).is_equal(staff_spot)


func test_two_staff_spot_captions_that_overlap_both_show_one_lifted_clear() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var pair := _leftmost_pair()
	_set_pair(pair, MissMarkers.SPOT_BLOCKED_CAPTION, MissMarkers.UNREACHABLE_CAPTION)
	# Control: unlifted they would overlap.
	assert_bool(_pair_overlaps(pair)).is_true()
	for station in pair:
		assert_bool(_caption_of(station).visible).is_true()
	var lifts: Array[float] = []
	for station in pair:
		lifts.append(
			_caption_of(station).offset.y - MissMarkers.SIGN_PX - MissMarkers.CAPTION_GAP_PX
		)
	assert_float(maxf(lifts[0], lifts[1])).is_greater(0.0)
	assert_float(minf(lifts[0], lifts[1])).is_equal(0.0)
	_assert_clear_by_the_margin([_rect_of(pair[0]), _rect_of(pair[1])])


func test_of_two_overlapping_plain_closed_captions_the_leftmost_stays() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var pair := _leftmost_pair()
	_set_pair(pair, MissMarkers.CLOSED_CAPTION, MissMarkers.CLOSED_CAPTION)
	assert_bool(_pair_overlaps(pair)).is_true()
	var left := pair[0] if _point_of(pair[0]).x <= _point_of(pair[1]).x else pair[1]
	var right := pair[1] if left == pair[0] else pair[0]
	assert_bool(_caption_of(left).visible).is_true()
	assert_bool(_caption_of(right).visible).is_false()


## caption_size() is checked against a TextLine shaped from the Label3D's own
## font size and outline, a path that does not go through caption_rect().
## (Label3D.get_aabb() is empty under the headless renderer, so it cannot be used.)
func test_a_caption_is_sized_by_the_labels_own_font_and_outline() -> void:
	_frame_closed_signs(NEAR_DISTANCE)
	var station: int = MissSignals.closed_stations(_world.sim)[0]
	var caption := _caption_of(station)
	var font := caption.font if caption.font != null else ThemeDB.fallback_font
	for text in [
		MissMarkers.CLOSED_CAPTION,
		MissMarkers.SPOT_BLOCKED_CAPTION,
		MissMarkers.UNREACHABLE_CAPTION,
		"Queue full · +12 waiting"
	]:
		var line := TextLine.new()
		line.add_string(text, font, caption.font_size)
		var glyphs := line.get_size()
		assert_float(glyphs.x).is_greater(30.0)
		var size := MissMarkers.caption_size(text)
		# The outline is drawn outline_size beyond the glyphs on every side.
		assert_float(size.x).is_equal_approx(glyphs.x + 2.0 * caption.outline_size, 1.0)
		assert_float(size.y).is_greater_equal(glyphs.y + 2.0 * caption.outline_size - 1.0)


func test_a_draw_where_nothing_changed_skips_the_layout() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var runs := _markers.declutter_runs
	assert_int(runs).is_greater(0)
	_markers.draw()
	_markers.sync()
	_markers.draw()
	assert_int(_markers.declutter_runs).is_equal(runs)
	_nudge_camera()
	assert_int(_markers.declutter_runs).is_equal(runs + 1)
	# A hire changes the signs: the next draw lays out again.
	StaffTestKit.staff_all(_world.staff, [StaffMember.Role.CHECKIN])
	_markers.sync()
	_markers.draw()
	assert_int(_markers.declutter_runs).is_equal(runs + 2)


## 300 desks in a field: one layout of all their captions, then none while the
## view stands still.
func test_three_hundred_closed_captions_lay_out_within_the_budget() -> void:
	_port.free()
	_world.free_all()
	var grid := PassengerTestWorld.floored(Vector2i(60, 40))
	for row in 10:
		for column in 30:
			PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(column * 2, 1 + row * 3), 0)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	world.auto_staff = false
	_attach(world)
	var closed := MissSignals.closed_stations(_world.sim)
	assert_int(closed.size()).is_greater_equal(250)
	_frame_closed_signs(HOME_DISTANCE)
	var runs := _markers.declutter_runs
	_rig.position.x += 0.001
	var started := Time.get_ticks_usec()
	_markers.draw()
	var msec := (Time.get_ticks_usec() - started) / 1000.0
	assert_int(_markers.declutter_runs).is_equal(runs + 1)
	assert_float(msec).is_less(BIG_LAYOUT_BUDGET_MSEC)
	_assert_clear_by_the_margin(_shown_rects())
	_markers.draw()
	assert_int(_markers.declutter_runs).is_equal(runs + 1)


func test_caption_rect_is_wider_for_longer_text_and_centred_on_the_point() -> void:
	var point := Vector2(500.0, 400.0)
	var short := MissMarkers.caption_rect(point, MissMarkers.CLOSED_CAPTION)
	var long := MissMarkers.caption_rect(point, MissMarkers.SPOT_BLOCKED_CAPTION)
	assert_float(long.size.x).is_greater(short.size.x)
	assert_float(short.get_center().x).is_equal_approx(point.x, 0.01)
	assert_float(short.end.y).is_less(point.y - MissMarkers.SIGN_PX + 0.01)
	var lifted := MissMarkers.caption_rect(point, MissMarkers.CLOSED_CAPTION, 30.0)
	assert_float(lifted.end.y).is_equal_approx(short.end.y - 30.0, 0.01)
