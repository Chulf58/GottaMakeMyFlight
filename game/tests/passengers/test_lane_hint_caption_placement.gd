class_name TestLaneHintCaptionPlacement
extends GdUnitTestSuite
## The lane-incomplete caption ("A wall cuts through the lane") is never hidden
## by the player's own HUD or cut off by the screen edge: it stays inside the
## view with a margin and clear of everything the visible HUD draws, moving
## toward the middle of the screen when it has to move and hiding (counted) only
## when no spot in the view is clear. Smoke playtest 8 saw it clipped at the top
## and half behind the Offers button.
##
## The rules are checked on the caption's screen rectangle, from a real camera
## and a real Control tree in a 1920x1080 viewport. What this does not prove is
## how it looks next to the real HUD; a windowed plate is that check.

const ANCHOR := Vector2i(5, 6)
const VIEW := Rect2(0.0, 0.0, 1920.0, 1080.0)
## Depth in front of the camera the test puts a sign at; any depth will do.
const DEPTH := 40.0

var _world: PassengerTestWorld
var _port: SubViewport
var _views: PassengerViews
var _markers: MissMarkers
var _arch := 0
var _layer: CanvasLayer


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


## A whole lane with no tray table: one arch with a lane-incomplete caption.
func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(14, 14))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 13), 3)
	var parts := SecurityLaneBuilder.build(
		grid, ANCHOR, 0, SecurityLanes.RIGHT, [SecurityLanes.TRAY_TABLE]
	)
	_arch = parts[SecurityLanes.ARCH]
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	_world.auto_staff = false
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_port.add_child(_views)
	_markers = _views.get_node("MissMarkers") as MissMarkers
	var camera := Camera3D.new()
	camera.fov = MissMarkers.FALLBACK_FOV
	_port.add_child(camera)
	camera.current = true
	_layer = CanvasLayer.new()
	_port.add_child(_layer)


func after_test() -> void:
	_port.free()
	_world.free_all()


func _caption() -> Label3D:
	return _markers.hint_sign_for(_arch).get_node("Caption") as Label3D


func _point() -> Vector2:
	return _port.get_camera_3d().unproject_position(_markers.hint_sign_for(_arch).global_position)


## Puts the arch's sign at a point of the screen and lays out again (the camera
## moves a hair so the view differs from the last layout's).
func _place_sign(at: Vector2) -> void:
	_port.get_camera_3d().position.x += 0.001
	_markers.hint_sign_for(_arch).global_position = _port.get_camera_3d().project_position(
		at, DEPTH
	)
	_markers.draw()


## A HUD control as the real HUD has them: a button on a canvas layer.
func _add_button(rect: Rect2, filter := Control.MOUSE_FILTER_STOP) -> Button:
	var button := Button.new()
	button.mouse_filter = filter
	_layer.add_child(button)
	button.position = rect.position
	button.size = rect.size
	return button


## The rectangle the caption covers now, with the lift and shift it was given.
func _rect() -> Rect2:
	var caption := _caption()
	var lift := caption.offset.y - MissMarkers.SIGN_PX - MissMarkers.CAPTION_GAP_PX
	return MissMarkers.caption_rect(_point(), caption.text, lift, caption.offset.x)


## Where the caption stands with no lift and no shift.
func _home_rect() -> Rect2:
	return MissMarkers.caption_rect(_point(), _caption().text)


func _inside_with_margin(rect: Rect2) -> bool:
	return VIEW.grow(-MissMarkers.VIEW_MARGIN_PX + 0.01).encloses(rect)


func test_a_sign_with_room_keeps_its_caption_where_it_always_was() -> void:
	_place_sign(Vector2(900.0, 600.0))
	assert_bool(_caption().visible).is_true()
	assert_vector(_caption().offset).is_equal(
		Vector2(0.0, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX)
	)


func test_a_caption_that_would_cross_the_top_edge_is_moved_inside_the_view() -> void:
	_place_sign(Vector2(960.0, 70.0))
	# Control: left at home the caption is cut off by the top of the screen.
	assert_bool(_inside_with_margin(_home_rect())).is_false()
	assert_float(_home_rect().position.y).is_less(0.0)
	var rect := _rect()
	print("top caption %s (home %s) point %s" % [rect, _home_rect(), _point()])
	assert_bool(_caption().visible).is_true()
	assert_bool(_inside_with_margin(rect)).is_true()
	# It moved toward the middle of the screen, not away from the station.
	assert_float(rect.get_center().distance_to(VIEW.get_center())).is_less(
		_home_rect().get_center().distance_to(VIEW.get_center())
	)
	assert_float(rect.get_center().distance_to(_home_rect().get_center())).is_less_equal(
		MissMarkers.MAX_HINT_TRAVEL_PX
	)


func test_a_caption_that_would_cross_a_side_edge_is_moved_inside_the_view() -> void:
	_place_sign(Vector2(40.0, 600.0))
	assert_bool(_inside_with_margin(_home_rect())).is_false()
	assert_bool(_inside_with_margin(_rect())).is_true()
	_place_sign(Vector2(1890.0, 600.0))
	assert_bool(_inside_with_margin(_home_rect())).is_false()
	assert_bool(_inside_with_margin(_rect())).is_true()


func test_a_caption_under_the_offers_button_moves_clear_of_it() -> void:
	var offers := Rect2(1120.0, 14.0, 210.0, 62.0)
	_add_button(offers)
	_place_sign(Vector2(1225.0, 130.0))
	# Control: the sign is placed so that its home caption is in view and sits on the button.
	assert_bool(_inside_with_margin(_home_rect())).is_true()
	assert_bool(_home_rect().intersects(offers)).is_true()
	var rect := _rect()
	print("offers caption %s (home %s) button %s" % [rect, _home_rect(), offers])
	assert_bool(_caption().visible).is_true()
	assert_bool(rect.grow(MissMarkers.CAPTION_MARGIN_PX - 0.01).intersects(offers)).is_false()
	assert_bool(_inside_with_margin(rect)).is_true()


func test_a_caption_moves_clear_of_a_control_nested_in_a_container() -> void:
	var card := PanelContainer.new()
	_layer.add_child(card)
	var label := Label.new()
	label.text = "Money 18456"
	card.add_child(label)
	card.position = Vector2(860.0, 300.0)
	card.size = Vector2(240.0, 60.0)
	_place_sign(Vector2(960.0, 400.0))
	assert_bool(_home_rect().intersects(Rect2(card.position, card.size))).is_true()
	assert_bool(_rect().intersects(Rect2(card.position, card.size))).is_false()


## A passive card (it ignores the mouse, like the staff hint card) is still
## drawn over the world, so the caption keeps off it.
func test_a_visible_passive_panel_is_avoided() -> void:
	var area := Rect2(800.0, 300.0, 400.0, 400.0)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(card)
	card.position = area.position
	card.size = area.size
	_place_sign(Vector2(960.0, 560.0))
	assert_bool(_home_rect().intersects(area)).is_true()
	assert_bool(_rect().intersects(area)).is_false()
	assert_bool(_inside_with_margin(_rect())).is_true()


func test_a_hidden_control_is_ignored() -> void:
	var area := Rect2(800.0, 300.0, 400.0, 400.0)
	var hidden := _add_button(area)
	hidden.visible = false
	_place_sign(Vector2(960.0, 560.0))
	assert_bool(_home_rect().intersects(area)).is_true()
	assert_vector(_caption().offset).is_equal(
		Vector2(0.0, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX)
	)
	# Control: the same control shown does move it.
	hidden.visible = true
	_markers.draw()
	assert_bool(_rect().intersects(area)).is_false()


func test_containers_that_draw_nothing_and_root_containers_do_not_move_the_caption() -> void:
	var area := Rect2(800.0, 300.0, 400.0, 400.0)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(root)
	var box := VBoxContainer.new()
	box.position = area.position
	box.size = area.size
	root.add_child(box)
	var empty := Label.new()
	box.add_child(empty)
	_place_sign(Vector2(960.0, 560.0))
	assert_bool(_home_rect().intersects(area)).is_true()
	assert_vector(_caption().offset).is_equal(
		Vector2(0.0, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX)
	)
	# Control: a panel with a panel style on the same spot is a drawn one.
	box.add_theme_stylebox_override("panel", StyleBoxFlat.new())
	_markers.draw()
	assert_bool(_rect().intersects(area)).is_false()


## A sheet 560 px wide over the home spot, as the Offers sheet is.
func test_a_large_open_sheet_over_the_home_spot_never_has_the_caption_on_it() -> void:
	var sheet := Rect2(680.0, 200.0, 560.0, 560.0)
	var panel := PanelContainer.new()
	_layer.add_child(panel)
	panel.position = sheet.position
	panel.size = sheet.size
	_place_sign(Vector2(960.0, 500.0))
	assert_bool(_home_rect().intersects(sheet)).is_true()
	assert_bool(_caption().visible).is_true()
	assert_bool(_rect().grow(MissMarkers.CAPTION_MARGIN_PX - 0.01).intersects(sheet)).is_false()
	assert_bool(_inside_with_margin(_rect())).is_true()
	assert_int(_markers.hint_no_spot_hides).is_equal(0)


## The HUD covers the whole view in two halves, so no spot is clear: the
## caption is hidden, counted, and the icon stays.
func test_with_no_clear_spot_anywhere_the_caption_is_hidden_and_counted() -> void:
	for top in [0.0, 540.0]:
		var half := PanelContainer.new()
		_layer.add_child(half)
		half.position = Vector2(0.0, top)
		half.size = Vector2(1920.0, 540.0)
	_place_sign(Vector2(960.0, 500.0))
	assert_bool(_caption().visible).is_false()
	assert_int(_markers.hint_no_spot_hides).is_greater(0)
	assert_bool(_markers.hint_sign_for(_arch).visible).is_true()
	# Control: with the halves gone the caption is back and nothing more is counted.
	var hides := _markers.hint_no_spot_hides
	for half in _layer.get_children():
		half.visible = false
	_markers.draw()
	assert_bool(_caption().visible).is_true()
	assert_int(_markers.hint_no_spot_hides).is_equal(hides)


## Under a content scale of 1.25 the layout is 1536x864 units and the screen
## 1920x1080 pixels: HUD rectangles and the caption are compared in pixels.
func test_at_a_ui_scale_of_1_25_the_hud_rectangles_are_in_screen_pixels() -> void:
	_port.size_2d_override = Vector2i(1536, 864)
	_port.size_2d_override_stretch = true
	var scale := 1.25
	var offers_units := Rect2(900.0, 12.0, 170.0, 40.0)
	_add_button(offers_units)
	_port.get_camera_3d().position.x += 0.001
	_markers.hint_sign_for(_arch).global_position = _port.get_camera_3d().project_position(
		Vector2(985.0, 100.0), DEPTH
	)
	_markers.draw()
	var point := _point() * scale
	var home := MissMarkers.caption_rect(point, _caption().text)
	var lift := _caption().offset.y - MissMarkers.SIGN_PX - MissMarkers.CAPTION_GAP_PX
	var rect := MissMarkers.caption_rect(point, _caption().text, lift, _caption().offset.x)
	var offers := Rect2(offers_units.position * scale, offers_units.size * scale)
	print("scaled point %s home %s moved %s button %s" % [point, home, rect, offers])
	# Control: in pixels the unmoved caption is on the button; the button's
	# rectangle taken in units would miss it, so the scale matters.
	assert_bool(home.intersects(offers)).is_true()
	assert_bool(home.intersects(offers_units)).is_false()
	assert_bool(rect.grow(MissMarkers.CAPTION_MARGIN_PX - 0.01).intersects(offers)).is_false()
	assert_bool(VIEW.grow(-MissMarkers.VIEW_MARGIN_PX + 0.01).encloses(rect)).is_true()


func test_a_control_that_appears_or_goes_while_the_view_stands_still_is_followed() -> void:
	_place_sign(Vector2(960.0, 500.0))
	var home := Vector2(0.0, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX)
	assert_vector(_caption().offset).is_equal(home)
	var area := _home_rect().grow(20.0)
	var panel := _add_button(area)
	_markers.draw()
	assert_vector(_caption().offset).is_not_equal(home)
	assert_bool(_rect().intersects(area)).is_false()
	panel.visible = false
	_markers.draw()
	assert_vector(_caption().offset).is_equal(home)
	# A draw where neither the view nor the HUD changed does no layout.
	var runs := _markers.declutter_runs
	_markers.draw()
	assert_int(_markers.declutter_runs).is_equal(runs)
