class_name TestClosedCaptionOverlap
extends GdUnitTestSuite
## Neighbouring Closed signs must not print their captions over each other
## ("ClCloseded"). At the default zoom the reference terminal's desks stand a
## few pixels apart, far closer than one caption is wide, so MissMarkers shows
## a caption only where it clears the captions already shown. The icons all stay.
##
## This proves the rule on projected screen rectangles with a real camera. It
## does not prove how the glyphs look: caption_rect() estimates the width from
## the default font, so a windowed plate is the check on the pixels.

## The tycoon camera's closest zoom, where neighbouring desks stand far apart on screen.
const NEAR_DISTANCE := 6.0

var _world: PassengerTestWorld
var _port: SubViewport
var _camera: Camera3D
var _views: PassengerViews
var _markers: MissMarkers


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.auto_staff = false
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_port.add_child(_camera)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_port.add_child(_views)
	_markers = _views.get_node("MissMarkers") as MissMarkers


func after_test() -> void:
	_port.free()
	_world.free_all()


## The camera `distance` metres from the closed signs' middle, tilted down.
func _frame_closed_signs(distance: float) -> void:
	var sum := Vector3.ZERO
	var closed := MissSignals.closed_stations(_world.sim)
	for station: int in closed:
		sum += _markers.closed_sign_for(station).position
	var middle := sum / closed.size()
	var pitch := deg_to_rad(50.0)
	_camera.current = true
	_camera.global_position = middle + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	_camera.look_at(middle)
	_markers.draw()


## Screen rectangles of the captions that are showing.
func _shown_caption_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for station: int in MissSignals.closed_stations(_world.sim):
		var sign := _markers.closed_sign_for(station)
		var caption := sign.get_node("Caption") as Label3D
		if caption.visible:
			var point := _camera.unproject_position(sign.global_position)
			rects.append(MissMarkers.caption_rect(point, caption.text))
	return rects


func test_default_zoom_closed_captions_do_not_overlap() -> void:
	var closed := MissSignals.closed_stations(_world.sim)
	# Control: the terminal has several closed stations to crowd together.
	assert_int(closed.size()).is_greater(3)
	_frame_closed_signs(80.0)
	var rects := _shown_caption_rects()
	assert_int(rects.size()).is_greater(0)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_bool(rects[i].intersects(rects[j])).is_false()
	# Control: the crowd really was too tight for every caption, so some hid.
	assert_int(rects.size()).is_less(closed.size())


func test_every_closed_icon_stays_when_a_caption_hides() -> void:
	_frame_closed_signs(80.0)
	for station: int in MissSignals.closed_stations(_world.sim):
		assert_bool(_markers.closed_sign_for(station).visible).is_true()


func test_zoomed_in_every_closed_caption_shows() -> void:
	_frame_closed_signs(80.0)
	var far_shown := _shown_caption_rects().size()
	_frame_closed_signs(NEAR_DISTANCE)
	var closed := MissSignals.closed_stations(_world.sim)
	assert_int(_shown_caption_rects().size()).is_equal(closed.size())
	assert_int(far_shown).is_less(closed.size())


func test_a_longer_reason_caption_wins_over_a_plain_closed_one() -> void:
	_frame_closed_signs(80.0)
	var closed := MissSignals.closed_stations(_world.sim)
	var station: int = closed[0]
	var caption := _markers.closed_sign_for(station).get_node("Caption") as Label3D
	caption.text = MissMarkers.UNREACHABLE_CAPTION
	_markers.draw()
	assert_bool(caption.visible).is_true()
	var rects := _shown_caption_rects()
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_bool(rects[i].intersects(rects[j])).is_false()


func test_caption_rect_is_wider_for_longer_text_and_centred_on_the_point() -> void:
	var point := Vector2(500.0, 400.0)
	var short := MissMarkers.caption_rect(point, MissMarkers.CLOSED_CAPTION)
	var long := MissMarkers.caption_rect(point, MissMarkers.SPOT_BLOCKED_CAPTION)
	assert_float(long.size.x).is_greater(short.size.x)
	assert_float(short.get_center().x).is_equal_approx(point.x, 0.01)
	assert_float(short.end.y).is_less(point.y - MissMarkers.SIGN_PX + 0.01)
