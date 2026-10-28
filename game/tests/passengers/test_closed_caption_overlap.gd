# gdlint:disable = max-public-methods
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
## The column test: where on the screen it stands, how far apart the signs are
## and how far from the camera they are put (any depth in front of it will do).
const COLUMN_X := 960.0
const COLUMN_STEP := 40.0
const COLUMN_DEPTH := 60.0
const VIEW := Rect2(0.0, 0.0, 1920.0, 1080.0)

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


## The rectangle a showing caption covers, with any lift or side shift it was given.
func _rect_of(station: int) -> Rect2:
	var caption := _caption_of(station)
	var lift := caption.offset.y - MissMarkers.SIGN_PX - MissMarkers.CAPTION_GAP_PX
	return MissMarkers.caption_rect(_point_of(station), caption.text, lift, caption.offset.x)


## The screen rectangle of a station's icon: a SIGN_PX square standing on its point.
func _icon_rect_of(station: int) -> Rect2:
	var point := _point_of(station)
	var side := MissMarkers.SIGN_PX
	return Rect2(point.x - side / 2.0, point.y - side, side, side)


## Moves every closed sign to one column on the screen, `top` pixels down for the
## first and COLUMN_STEP lower for each next, and gives each a staff-spot caption.
## Returns the stations top first. Needs a camera (the rig from _frame_closed_signs).
func _stack_signs_in_a_column(top: float) -> Array[int]:
	var stations: Array[int] = []
	stations.assign(MissSignals.closed_stations(_world.sim))
	for i in stations.size():
		_place_sign(stations[i], Vector2(COLUMN_X, top + COLUMN_STEP * i))
		_caption_of(stations[i]).text = MissMarkers.UNREACHABLE_CAPTION
	_nudge_camera()
	return stations


## Puts a closed sign at a point of the screen (the next draw lays it out there).
func _place_sign(station: int, at: Vector2) -> void:
	_markers.closed_sign_for(station).global_position = _camera().project_position(at, COLUMN_DEPTH)


## Every closed sign in a short row dead ahead of a camera-less port, so their
## plain "Closed" captions overlap as soon as there is a camera to see them from.
func _bunch_signs_ahead() -> void:
	var i := 0
	for station: int in MissSignals.closed_stations(_world.sim):
		_markers.closed_sign_for(station).global_position = Vector3(0.01 * i, 0.0, -20.0)
		i += 1


## A camera at the origin looking down -Z with the fallback field of view: the
## same pose and field of view the layout assumes when there is no camera.
func _add_plain_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = MissMarkers.FALLBACK_FOV
	_port.add_child(camera)
	camera.current = true
	return camera


func _hidden_captions() -> int:
	var hidden := 0
	for station: int in MissSignals.closed_stations(_world.sim):
		if not _caption_of(station).visible:
			hidden += 1
	return hidden


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
		var left: int = pair[0] if _point_of(pair[0]).x <= _point_of(pair[1]).x else pair[1]
		var right: int = pair[1] if left == pair[0] else pair[0]
		var staff := left if order == 0 else right
		var queue := right if order == 0 else left
		print("staff %s, queue visible %s" % [_rect_of(staff), _caption_of(queue).visible])
		# The staff-spot caption always shows (it may move off an icon); the
		# queue-full one shows only where it clears it.
		assert_bool(_caption_of(staff).visible).is_true()
		if _caption_of(queue).visible:
			_assert_clear_by_the_margin([_rect_of(staff), _rect_of(queue)])


## Two signs side by side in open space, every other sign parked along the
## bottom: the staff-spot caption keeps its own place and the wide queue-full
## caption that overlaps it is the one that hides.
func test_in_open_space_the_staff_spot_caption_stays_put_and_the_wide_one_hides() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var stations: Array[int] = []
	stations.assign(MissSignals.closed_stations(_world.sim))
	for i in stations.size():
		_place_sign(stations[i], Vector2(100.0 + 200.0 * i, 950.0))
	var wide := "Queue full · +30000 waiting, lane at capacity"
	var home := Vector2(0.0, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX)
	for order in [0, 1]:
		var staff: int = stations[order]
		var queue: int = stations[1 - order]
		_place_sign(stations[0], Vector2(900.0, 500.0))
		_place_sign(stations[1], Vector2(940.0, 500.0))
		_caption_of(staff).text = MissMarkers.UNREACHABLE_CAPTION
		_caption_of(queue).text = wide
		_nudge_camera()
		# Control: left alone the pair overlaps, and the queue caption is the wider.
		assert_bool(_pair_overlaps([staff, queue])).is_true()
		assert_bool(_caption_of(staff).visible).is_true()
		assert_vector(_caption_of(staff).offset).is_equal(home)
		assert_bool(_caption_of(queue).visible).is_false()


func test_two_staff_spot_captions_that_overlap_both_show_one_lifted_clear() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var pair := _leftmost_pair()
	_set_pair(pair, MissMarkers.SPOT_BLOCKED_CAPTION, MissMarkers.UNREACHABLE_CAPTION)
	# Control: unlifted they would overlap.
	assert_bool(_pair_overlaps(pair)).is_true()
	for station in pair:
		assert_bool(_caption_of(station).visible).is_true()
	var home := Vector2(0.0, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX)
	var moved := 0
	for station in pair:
		print("pair caption %s offset %s" % [_rect_of(station), _caption_of(station).offset])
		if not _caption_of(station).offset.is_equal_approx(home):
			moved += 1
	# At least one moved (the second to place cannot keep the first one's spot).
	assert_int(moved).is_greater(0)
	_assert_clear_by_the_margin([_rect_of(pair[0]), _rect_of(pair[1])])
	for station in pair:
		assert_bool(VIEW.encloses(_rect_of(station))).is_true()
		for other: int in MissSignals.closed_stations(_world.sim):
			assert_bool(_rect_of(station).intersects(_icon_rect_of(other))).is_false()


## A column of staff-spot captions with the first icon near the top of the
## screen: lifting each one upward alone would carry it out of the view, so the
## layout must find room elsewhere, in the view and off every icon.
func test_a_column_of_staff_spot_captions_near_the_top_stays_in_view_and_off_icons() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var stations := _stack_signs_in_a_column(130.0)
	# Control: the column has several captions, and unlifted they pile up.
	assert_int(stations.size()).is_greater(3)
	var piled := 0
	for i in range(1, stations.size()):
		var plain := MissMarkers.caption_rect(
			_point_of(stations[i]), MissMarkers.UNREACHABLE_CAPTION
		)
		var above := MissMarkers.caption_rect(
			_point_of(stations[i - 1]), MissMarkers.UNREACHABLE_CAPTION
		)
		if plain.intersects(above):
			piled += 1
	assert_int(piled).is_greater(0)
	for station in stations:
		var rect := _rect_of(station)
		print("column station %d caption %s" % [station, rect])
		# Never hidden, and wholly inside the view.
		assert_bool(_caption_of(station).visible).is_true()
		assert_bool(VIEW.encloses(rect)).is_true()
		# Off every icon, its own included.
		for other in stations:
			assert_bool(rect.intersects(_icon_rect_of(other))).is_false()
	_assert_clear_by_the_margin(_shown_rects())


## A view too small for any caption to fit in leaves a staff-spot caption no
## valid spot. It stays visible, and the error is raised once per station, also
## after the view grows back and shrinks again: the first one is caught with
## assert_error, and no_spot_errors showing 1 afterwards means no later layout
## raised a second.
func test_a_staff_spot_caption_with_no_valid_spot_stays_visible_and_errors_once() -> void:
	_frame_closed_signs(HOME_DISTANCE)
	var station: int = MissSignals.closed_stations(_world.sim)[0]
	_caption_of(station).text = MissMarkers.UNREACHABLE_CAPTION
	_nudge_camera()
	# Control: in the full view it has a spot, so there is no error yet.
	assert_int(_markers.no_spot_errors).is_equal(0)
	# Control: the caption is wider than the small view, so no spot can fit.
	var small := Vector2i(100, 100)
	assert_float(MissMarkers.caption_size(MissMarkers.UNREACHABLE_CAPTION).x).is_greater(small.x)
	_port.size = small
	# The first layout in the small view raises the error itself, naming the station.
	await (
		assert_error(func() -> void: _nudge_camera())
		. is_push_error(
			"MissMarkers: no clear spot inside the view for the caption of station %d" % station
		)
	)
	assert_int(_markers.no_spot_errors).is_equal(1)
	assert_bool(_caption_of(station).visible).is_true()
	# The same station laid out again: still shown, no second error.
	_nudge_camera()
	assert_int(_markers.no_spot_errors).is_equal(1)
	assert_bool(_caption_of(station).visible).is_true()
	# Zoom out and back in: the view grows, then shrinks again.
	_port.size = Vector2i(1920, 1080)
	_nudge_camera()
	_port.size = small
	_nudge_camera()
	assert_int(_markers.no_spot_errors).is_equal(1)
	assert_bool(_caption_of(station).visible).is_true()


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


## Without a camera nothing is hidden. A camera that appears has to lay the
## captions out again even when its pose and field of view equal the defaults
## the layout assumed, and one that goes away has to bring them all back.
func test_a_camera_added_after_a_cameraless_draw_reruns_the_layout() -> void:
	_bunch_signs_ahead()
	_markers.draw()
	var runs := _markers.declutter_runs
	assert_int(_hidden_captions()).is_equal(0)
	var camera := _add_plain_camera()
	assert_object(_camera()).is_same(camera)
	_markers.draw()
	assert_int(_markers.declutter_runs).is_equal(runs + 1)
	# Control: the bunched captions really crowd, so the camera hides some.
	assert_int(_hidden_captions()).is_greater(0)


func test_removing_the_camera_brings_every_caption_back() -> void:
	_bunch_signs_ahead()
	var camera := _add_plain_camera()
	_markers.draw()
	var runs := _markers.declutter_runs
	assert_int(_hidden_captions()).is_greater(0)
	_port.remove_child(camera)
	camera.free()
	assert_object(_camera()).is_null()
	_markers.draw()
	assert_int(_markers.declutter_runs).is_equal(runs + 1)
	assert_int(_hidden_captions()).is_equal(0)


func test_swapping_in_another_identical_camera_reruns_the_layout() -> void:
	_bunch_signs_ahead()
	var first := _add_plain_camera()
	_markers.draw()
	var runs := _markers.declutter_runs
	_port.remove_child(first)
	first.free()
	var second := _add_plain_camera()
	assert_object(_camera()).is_same(second)
	_markers.draw()
	assert_int(_markers.declutter_runs).is_equal(runs + 1)


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
