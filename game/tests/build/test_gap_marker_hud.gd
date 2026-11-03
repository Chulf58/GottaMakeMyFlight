class_name TestGapMarkerHud
extends GdUnitTestSuite
## The 'Wall gap' caption (GapMarkers) keeps clear of the HUD like a room label
## and a station caption do (decision status-banner-fades-under-the-build-ghost-
## room-labels-slide, rule 2): it slides toward the screen's middle off any HUD
## control, tries rings of other spots, and hides only when no spot is clear,
## while the sign's icon stays where it stands. Checked on the caption's screen
## rectangle from a real camera in a 1920x1080 viewport; how it looks next to
## the real HUD is a windowed plate's question.

const BOX := Rect2i(2, 2, 4, 3)
const VIEW_SIZE := Vector2(1920.0, 1080.0)

var _port: SubViewport
var _camera: Camera3D
var _markers: GapMarkers
var _sign: Sprite3D
var _caption: Label3D
var _home := Vector2.ZERO


func before_test() -> void:
	var grid := BuildGrid.new(Vector2i(12, 10))
	var edits: Array[BuildEdit] = []
	for y in range(BOX.position.y, BOX.end.y):
		for x in range(BOX.position.x, BOX.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in grid.apply_batch(edits):
		assert_bool(result.ok).is_true()
	EnclosureKit.close_floor(grid)
	_port = SubViewport.new()
	_port.size = Vector2i(VIEW_SIZE)
	add_child(_port)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_port.add_child(_camera)
	_camera.current = true
	_markers = GapMarkers.new()
	_port.add_child(_markers)
	_markers.bind(grid)
	assert_bool(grid.apply(BuildEdit.remove_wall(Vector2i(5, 2), BuildGrid.Side.EAST)).ok).is_true()
	_sign = _markers.signs()[0]
	_caption = _markers.caption_of(_sign)
	# Aim at the sign, then pitch down so it stands high on the screen.
	_camera.global_position = _sign.position + Vector3(0.0, 12.0, 14.0)
	_camera.look_at(_sign.position)
	_camera.rotate_object_local(Vector3.RIGHT, -0.28)
	_home = _camera.unproject_position(_sign.global_position)


func after_test() -> void:
	_port.free()


## The caption's screen rectangle now: under the sign's foot, shifted by its
## pixel offset from where GapMarkers leaves it.
func _caption_rect() -> Rect2:
	var size := MissMarkers.caption_size(GapMarkers.CAPTION)
	var home_offset := Vector2(0.0, -MissMarkers.CAPTION_GAP_PX)
	var moved := _caption.offset - home_offset
	return Rect2(
		Vector2(_home.x - size.x / 2.0 + moved.x, _home.y + MissMarkers.CAPTION_GAP_PX - moved.y),
		size
	)


func _layout(hud: Array[Rect2]) -> void:
	_markers.layout_captions(_camera, 1.0, VIEW_SIZE, hud)


func test_the_sign_stands_high_in_the_view() -> void:
	assert_bool(Rect2(Vector2.ZERO, VIEW_SIZE).has_point(_home)).is_true()
	assert_float(_home.y).is_less(300.0)


func test_with_no_hud_the_caption_stays_under_the_sign() -> void:
	_layout([] as Array[Rect2])
	assert_bool(_caption.visible).is_true()
	assert_vector(_caption.offset).is_equal(Vector2(0.0, -MissMarkers.CAPTION_GAP_PX))


func test_a_caption_under_a_hud_control_slides_clear_and_the_icon_stays() -> void:
	var hud: Array[Rect2] = [Rect2(_home.x - 150.0, _home.y - 20.0, 300.0, 120.0)]
	assert_bool(_caption_rect().intersects(hud[0])).is_true()
	var sign_at := _sign.position
	var icon_offset := _sign.offset
	_layout(hud)
	var moved := _caption_rect()
	assert_bool(_caption.visible).is_true()
	assert_bool(moved.grow(RoomLabelLayout.GAP_PX).intersects(hud[0])).is_false()
	# It moved, toward the middle of the view (down), and the sign did not.
	assert_float(moved.position.y).is_greater(_home.y + MissMarkers.CAPTION_GAP_PX)
	assert_bool(_sign.visible).is_true()
	assert_vector(_sign.position).is_equal(sign_at)
	assert_vector(_sign.offset).is_equal(icon_offset)
	assert_vector(_sign.get_node("Caption").position).is_equal(Vector3.ZERO)


func test_a_caption_flush_against_a_hud_control_is_moved_off_it() -> void:
	var own := _caption_rect()
	# A control ending 2 px above the caption: closer than the 6 px gap.
	var hud: Array[Rect2] = [Rect2(own.position.x - 100.0, own.position.y - 62.0, 400.0, 60.0)]
	_layout(hud)
	assert_bool(_caption_rect().grow(RoomLabelLayout.GAP_PX).intersects(hud[0])).is_false()
	assert_bool(_caption.visible).is_true()


func test_a_caption_with_no_clear_spot_is_hidden_and_the_icon_stays() -> void:
	_layout([Rect2(Vector2.ZERO, VIEW_SIZE)] as Array[Rect2])
	assert_bool(_caption.visible).is_false()
	assert_bool(_sign.visible).is_true()


func test_a_caption_comes_back_when_the_hud_leaves() -> void:
	_layout([Rect2(Vector2.ZERO, VIEW_SIZE)] as Array[Rect2])
	assert_bool(_caption.visible).is_false()
	_layout([] as Array[Rect2])
	assert_bool(_caption.visible).is_true()
	assert_vector(_caption.offset).is_equal(Vector2(0.0, -MissMarkers.CAPTION_GAP_PX))


## Through the real tree: a panel in a canvas layer over the caption is found by
## HudRects and the caption moves off it each frame.
func test_a_panel_in_the_scene_moves_the_caption() -> void:
	var layer := CanvasLayer.new()
	_port.add_child(layer)
	var panel := Panel.new()
	panel.position = Vector2(_home.x - 150.0, _home.y - 20.0)
	panel.size = Vector2(300.0, 120.0)
	layer.add_child(panel)
	_markers.update_captions()
	assert_bool(_caption.visible).is_true()
	(
		assert_bool(
			_caption_rect().grow(RoomLabelLayout.GAP_PX).intersects(
				Rect2(panel.position, panel.size)
			)
		)
		. is_false()
	)
	assert_vector(_caption.offset).is_not_equal(Vector2(0.0, -MissMarkers.CAPTION_GAP_PX))
