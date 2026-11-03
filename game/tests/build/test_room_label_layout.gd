class_name TestRoomLabelLayout
extends GdUnitTestSuite
## A room's world label (RoomView) keeps clear of the HUD, keeps a capped size on
## screen and fades out when the camera zooms in close (user rulings 2026-11-03,
## board item 9c2b0d32): it slides toward the screen's middle until no HUD
## control covers it and hides when no spot is clear; its text never draws bigger
## than RoomLabelLayout.MAX_SCALE screen pixels per font pixel; it fades out
## between FADE_FAR and FADE_NEAR of the camera rig's home distance, and comes
## back as the camera zooms out.
##
## Checked on the label's screen rectangle from a real camera and a real Control
## tree in a 1920x1080 viewport. How it looks next to the real HUD is a windowed
## plate's question, not this file's.

const VIEW := Rect2(0.0, 0.0, 1920.0, 1080.0)

var _port: SubViewport
var _view: RoomView
var _camera: Camera3D
var _layer: CanvasLayer
var _room := 0
var _anchor := Vector3.ZERO


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(16, 12))
	_room = grid.apply(BuildEdit.place_room(Rect2i(2, 2, 5, 4), &"cafe")).room_id
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_port.add_child(_camera)
	_camera.current = true
	_layer = CanvasLayer.new()
	_port.add_child(_layer)
	_view = RoomView.new()
	_port.add_child(_view)
	_view.watch(grid)
	_anchor = _view.label_of(_room).position


func after_test() -> void:
	_port.free()


## Puts `camera` `distance` metres from the label, aimed `side` metres to the
## right of it, so the label stands left of the screen's middle.
func _aim(camera: Camera3D, distance: float, side := 8.0) -> void:
	var target := _anchor + Vector3(side, 0.0, 0.0)
	camera.global_position = target + Vector3(0.0, 0.766, 0.643) * distance
	camera.look_at(target)


## Screen pixels one font pixel of the label covers now.
func _scale(camera: Camera3D, label: Label3D) -> float:
	var at := label.global_position
	var up := camera.unproject_position(at + camera.global_basis.y)
	return absf(up.y - camera.unproject_position(at).y) * label.pixel_size


## The rectangle the label covers on screen now, with its slide.
func _rect(camera: Camera3D) -> Rect2:
	var label := _view.label_of(_room)
	var scale := _scale(camera, label)
	var rect := RoomLabelLayout.label_rect(
		camera.unproject_position(label.global_position),
		label.text,
		label.font_size,
		label.outline_size,
		scale
	)
	return Rect2(rect.position + Vector2(label.offset.x, -label.offset.y) * scale, rect.size)


func _add_button(rect: Rect2) -> Button:
	var button := Button.new()
	_layer.add_child(button)
	button.position = rect.position
	button.size = rect.size
	return button


func test_a_label_clear_of_the_hud_stays_where_it_is() -> void:
	_aim(_camera, 30.0)
	_view.layout_labels()
	var label := _view.label_of(_room)
	assert_bool(label.visible).is_true()
	assert_vector(label.offset).is_equal(Vector2.ZERO)
	assert_vector(label.position).is_equal(_anchor)
	assert_bool(VIEW.encloses(_rect(_camera))).is_true()


func test_a_label_under_a_hud_button_slides_toward_the_middle_until_clear() -> void:
	_aim(_camera, 30.0)
	_view.layout_labels()
	var home := _rect(_camera)
	var button_rect := home.grow(10.0)
	_add_button(button_rect)
	# Control: the button covers the label where it stands.
	assert_bool(home.intersects(button_rect)).is_true()
	_view.layout_labels()
	var label := _view.label_of(_room)
	var rect := _rect(_camera)
	print("label %s (home %s) button %s offset %s" % [rect, home, button_rect, label.offset])
	assert_bool(label.visible).is_true()
	assert_bool(rect.grow(RoomLabelLayout.GAP_PX - 0.01).intersects(button_rect)).is_false()
	assert_float(rect.get_center().distance_to(VIEW.get_center())).is_less(
		home.get_center().distance_to(VIEW.get_center())
	)
	assert_float(rect.get_center().distance_to(home.get_center())).is_less_equal(
		RoomLabelLayout.MAX_TRAVEL_PX
	)
	# The label's world anchor stays put: the cafe '+$' pop hangs under it.
	assert_vector(label.position).is_equal(_anchor)
	# The slide is undone once the button is gone.
	_layer.get_child(0).free()
	_view.layout_labels()
	assert_vector(label.offset).is_equal(Vector2.ZERO)


func test_a_label_with_no_clear_spot_hides() -> void:
	_aim(_camera, 30.0)
	_add_button(VIEW)
	_view.layout_labels()
	assert_bool(_view.label_of(_room).visible).is_false()
	_layer.get_child(0).free()
	_view.layout_labels()
	assert_bool(_view.label_of(_room).visible).is_true()


## A big partial panel (the offer sheet) blocks the way to the middle, but a
## pocket beside it is clear: the label goes there and is not hidden.
func test_a_label_with_a_blocked_way_to_the_middle_takes_a_clear_spot_elsewhere() -> void:
	var rect := Rect2(700.0, 70.0, 200.0, 100.0)
	var sheet: Array[Rect2] = [Rect2(630.0, 60.0, 700.0, 440.0)]
	# Control: the way toward the middle is blocked for the whole travel.
	var toward := (
		(VIEW.get_center() - rect.get_center()).normalized() * RoomLabelLayout.MAX_TRAVEL_PX
	)
	(
		assert_bool(
			sheet[0].grow(RoomLabelLayout.GAP_PX).intersects(
				Rect2(rect.position + toward, rect.size)
			)
		)
		. is_true()
	)
	var spot := RoomLabelLayout.slide_clear(rect, sheet, VIEW.size)
	print("blocked way: spot %s" % spot)
	assert_vector(spot.size).is_equal(rect.size)
	assert_bool(spot.grow(RoomLabelLayout.GAP_PX - 0.01).intersects(sheet[0])).is_false()
	assert_bool(VIEW.grow(-RoomLabelLayout.VIEW_MARGIN_PX).encloses(spot)).is_true()


## A drawn control over the whole view (a dim layer) hides the label at once: the
## search for a spot is not entered.
func test_a_hud_rect_over_the_whole_view_hides_the_label_without_a_search() -> void:
	var rect := Rect2(700.0, 70.0, 200.0, 100.0)
	var dim: Array[Rect2] = [VIEW]
	RoomLabelLayout.ring_candidates = 0
	assert_vector(RoomLabelLayout.slide_clear(rect, dim, VIEW.size).size).is_equal(Vector2.ZERO)
	assert_int(RoomLabelLayout.ring_candidates).is_equal(0)
	# Control: a panel that leaves a pocket still gets the ring search.
	var sheet: Array[Rect2] = [Rect2(630.0, 60.0, 700.0, 440.0)]
	RoomLabelLayout.slide_clear(rect, sheet, VIEW.size)
	assert_int(RoomLabelLayout.ring_candidates).is_greater(0)
	# In the layout: the label hides, counted, with no ring spot tried.
	_aim(_camera, 30.0)
	_add_button(VIEW)
	RoomLabelLayout.ring_candidates = 0
	_view.layout_labels()
	assert_bool(_view.label_of(_room).visible).is_false()
	assert_int(RoomLabelLayout.ring_candidates).is_equal(0)


func test_the_label_never_draws_bigger_than_the_cap_on_screen() -> void:
	var label := _view.label_of(_room)
	# Far out the world-size label is small and stays as it was.
	_aim(_camera, 60.0)
	assert_float(_scale(_camera, label)).is_less(RoomLabelLayout.MAX_SCALE)
	_view.layout_labels()
	assert_float(label.pixel_size).is_equal_approx(RoomView.LABEL_PIXEL_SIZE, 0.00001)
	# Control: close in, the uncapped label would be well over the cap.
	_aim(_camera, 14.0)
	_view.layout_labels()
	label.pixel_size = RoomView.LABEL_PIXEL_SIZE
	assert_float(_scale(_camera, label)).is_greater(RoomLabelLayout.MAX_SCALE * 1.3)
	_view.layout_labels()
	print("close scale %s, cap %s" % [_scale(_camera, label), RoomLabelLayout.MAX_SCALE])
	assert_float(_scale(_camera, label)).is_equal_approx(RoomLabelLayout.MAX_SCALE, 0.001)
	# Closer still it stays at the cap.
	_aim(_camera, 8.0)
	_view.layout_labels()
	assert_float(_scale(_camera, label)).is_equal_approx(RoomLabelLayout.MAX_SCALE, 0.001)


func test_the_zoom_alpha_follows_the_rigs_distance_from_home() -> void:
	var rig := _rig(40.0)
	var camera := rig.get_node("Camera3D") as Camera3D
	var seen := {}
	for distance in [60.0, 24.0, 19.0, 14.0, 6.0]:
		rig.distance = distance
		seen[distance] = RoomLabelLayout.zoom_alpha(camera)
	print("home 40: distance -> alpha %s" % seen)
	assert_float(seen[60.0]).is_equal(1.0)
	assert_float(seen[24.0]).is_equal(1.0)
	assert_float(seen[19.0]).is_between(0.2, 0.8)
	assert_float(seen[14.0]).is_equal(0.0)
	assert_float(seen[6.0]).is_equal(0.0)
	# A camera outside a rig, or none, never fades the label.
	assert_float(RoomLabelLayout.zoom_alpha(_camera)).is_equal(1.0)
	assert_float(RoomLabelLayout.zoom_alpha(null)).is_equal(1.0)


func test_the_label_fades_out_zoomed_in_and_returns_zoomed_out() -> void:
	var rig := _rig(40.0)
	var camera := rig.get_node("Camera3D") as Camera3D
	var label := _view.label_of(_room)
	rig.distance = 40.0
	_aim(camera, 30.0)
	_view.layout_labels()
	assert_bool(label.visible).is_true()
	assert_float(label.modulate.a).is_equal(1.0)
	assert_float(label.outline_modulate.a).is_equal(1.0)
	rig.distance = 19.0
	_aim(camera, 30.0)
	_view.layout_labels()
	assert_bool(label.visible).is_true()
	assert_float(label.modulate.a).is_between(0.2, 0.8)
	assert_float(label.outline_modulate.a).is_between(0.2, 0.8)
	rig.distance = 8.0
	_aim(camera, 30.0)
	_view.layout_labels()
	assert_bool(label.visible).is_false()
	rig.distance = 40.0
	_aim(camera, 30.0)
	_view.layout_labels()
	assert_bool(label.visible).is_true()
	assert_float(label.modulate.a).is_equal(1.0)
	# The text colour the room's status chose is not touched by the fade.
	assert_that(Color(label.modulate, 1.0)).is_equal(RoomView.NEEDS_TEXT)


## The game's camera rig with `home` as its home distance, current in the port.
func _rig(home: float) -> TycoonCamera:
	var rig := (
		(load("res://camera/tycoon_camera.tscn") as PackedScene).instantiate() as TycoonCamera
	)
	rig.home_distance = home
	_port.add_child(rig)
	rig.set_process(false)
	(rig.get_node("Camera3D") as Camera3D).make_current()
	return rig
