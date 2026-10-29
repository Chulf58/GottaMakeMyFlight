class_name TestLaneHintCaptionAnchor
extends GdUnitTestSuite
## A lane-hint caption is a Label3D, culled by its bounding box around its world
## anchor, and a fixed-size label's box is tiny. Smoke playtest 9: the arch sign
## sat just off the left edge, the layout placed the caption inside the view, and
## nothing was drawn. A caption placed inside the view must be anchored inside
## it too. Also here: the ring search finds a clear pocket between its
## directions, and a drawn control spanning the view counts as HUD.
##
## Checked on the caption's drawn anchor (its world position projected by a real
## camera in a 1920x1080 viewport). What this does not prove is that the renderer
## draws it; a windowed plate at the playtest's edge position is that check.

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


## The caption's drawn anchor in screen pixels: its own world anchor projected by
## the camera, times the stretch from layout units to pixels.
func _anchor(to_output := 1.0) -> Vector2:
	return _port.get_camera_3d().unproject_position(_caption().global_position) * to_output


## The rectangle the caption covers: its anchor, its lift and its shift.
func _drawn_rect(to_output := 1.0) -> Rect2:
	var caption := _caption()
	var lift := caption.offset.y - MissMarkers.SIGN_PX - MissMarkers.CAPTION_GAP_PX
	return MissMarkers.caption_rect(_anchor(to_output), caption.text, lift, caption.offset.x)


func _inside_with_margin(rect: Rect2) -> bool:
	return VIEW.grow(-MissMarkers.VIEW_MARGIN_PX + 0.01).encloses(rect)


func test_a_caption_whose_sign_is_just_off_screen_is_anchored_inside_the_view() -> void:
	var sign_at := Vector2(-46.0, 387.0)
	_place_sign(sign_at)
	# Control: the sign itself is outside the view, as in the playtest.
	assert_bool(VIEW.has_point(_point())).is_false()
	assert_vector(_point()).is_equal_approx(sign_at, Vector2(0.5, 0.5))
	assert_bool(_caption().visible).is_true()
	print("anchor %s sign %s drawn %s" % [_anchor(), _point(), _drawn_rect()])
	assert_bool(VIEW.grow(-MissMarkers.VIEW_MARGIN_PX + 0.01).has_point(_anchor())).is_true()
	# The caption is still drawn at the spot the layout chose.
	assert_bool(_inside_with_margin(_drawn_rect())).is_true()


## The layout works in screen pixels and the camera in layout units: the anchor
## is converted back at a content scale of 1.25.
func test_the_anchor_is_inside_the_view_at_a_ui_scale_of_1_25() -> void:
	_port.size_2d_override = Vector2i(1536, 864)
	_port.size_2d_override_stretch = true
	var camera := _port.get_camera_3d()
	camera.position.x += 0.001
	_markers.hint_sign_for(_arch).global_position = camera.project_position(
		Vector2(-37.0, 310.0), DEPTH
	)
	_markers.draw()
	print("scaled anchor %s" % _anchor(1.25))
	assert_bool(_caption().visible).is_true()
	assert_bool(VIEW.grow(-MissMarkers.VIEW_MARGIN_PX + 0.01).has_point(_anchor(1.25))).is_true()
	assert_bool(_inside_with_margin(_drawn_rect(1.25))).is_true()


## A sign inside the view keeps its caption on its own anchor.
func test_a_caption_whose_sign_is_in_view_keeps_the_sign_as_its_anchor() -> void:
	_place_sign(Vector2(900.0, 600.0))
	assert_vector(_caption().global_position).is_equal_approx(
		_markers.hint_sign_for(_arch).global_position, Vector3.ONE * 0.0001
	)


## The ring search used to try 16 directions at every radius, so a clear pocket
## between two rays was never found. The HUD here covers the whole view but one
## pocket, a little larger than the caption, 11 degrees off the search's first
## direction and far from the sign.
func test_a_clear_pocket_between_the_search_directions_is_found() -> void:
	var home := MissMarkers.caption_rect(Vector2(960.0, 540.0), _caption().text)
	var pocket := Rect2(Vector2.ZERO, home.size + Vector2(60.0, 60.0))
	pocket.position = (
		home.get_center() + Vector2.from_angle(deg_to_rad(11.25)) * 600.0 - pocket.size / 2.0
	)
	var panels: Array[Rect2] = [
		Rect2(0.0, 0.0, 1920.0, pocket.position.y),
		Rect2(0.0, pocket.end.y, 1920.0, 1080.0 - pocket.end.y),
		Rect2(0.0, pocket.position.y, pocket.position.x, pocket.size.y),
		Rect2(pocket.end.x, pocket.position.y, 1920.0 - pocket.end.x, pocket.size.y),
	]
	for area in panels:
		var panel := PanelContainer.new()
		_layer.add_child(panel)
		panel.position = area.position
		panel.size = area.size
	_place_sign(Vector2(960.0, 540.0))
	print("pocket %s drawn %s" % [pocket, _drawn_rect()])
	assert_bool(_caption().visible).is_true()
	assert_int(_markers.hint_no_spot_hides).is_equal(0)
	assert_bool(pocket.encloses(_drawn_rect())).is_true()


## A panel that covers nearly the whole view is drawn over the world like any
## other: the caption hides (counted) rather than sit under it.
func test_a_drawn_control_spanning_the_view_hides_the_caption() -> void:
	var panel := PanelContainer.new()
	_layer.add_child(panel)
	panel.position = Vector2.ZERO
	panel.size = Vector2(1920.0, 1080.0)
	_place_sign(Vector2(960.0, 560.0))
	assert_bool(_caption().visible).is_false()
	assert_int(_markers.hint_no_spot_hides).is_greater(0)
	# Control: with the panel gone the caption is back.
	panel.visible = false
	_markers.draw()
	assert_bool(_caption().visible).is_true()
