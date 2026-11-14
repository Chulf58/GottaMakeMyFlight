class_name TestUnlinkedSignSlide
extends GdUnitTestSuite
## The unlinked sign (GateLinksView) has no caption; its words show in the
## HoverTarget tooltip only in build mode (decision calm-cozy-default-view-
## quiet-world-detail-on-ask-soft-statio, part 2). A wall-gap sign on it slides
## it sideways (user ruling unlinked-gate-sign-moves-sideways-off-a-wall-gap-
## sign-so-its), and the layout is cached while nothing changed.
##
## The starter shell with a gate desk by its exit, the exit then taken away
## (NO_EXIT).

const SITE := preload("res://build/terminal_site.tres")
const DESK := Vector2i(19, 115)
const EXIT := Vector2i(20, 112)

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _view: GateLinksView
var _camera: Camera3D
## A view of a real screen size: the headless window is tiny.
var _port: SubViewport
var _desk_id := 0


func before() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_flights = FlightSim.new()
	_flights.open_airport()
	_gates = GateDesks.new()
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK, 0))
	assert_bool(desk.ok).is_true()
	_desk_id = desk.object_id
	assert_bool(_grid.apply(BuildEdit.remove_object(_grid.object_at(EXIT))).ok).is_true()
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)
	_view = GateLinksView.new()
	_port.add_child(_view)
	_view.bind(_grid, _gates)
	_camera = Camera3D.new()
	_port.add_child(_camera)
	_camera.make_current()


func after() -> void:
	_port.free()
	_gates.free()
	_flights.free()


func after_test() -> void:
	_view.set_building(false)


## The camera `distance` metres from the desk, pitched `pitch` degrees down,
## looking north.
func _look(distance: float, pitch: float) -> void:
	var at := _grid.cell_to_world(DESK) + Vector3(0.5, 0.0, 0.0)
	var down := deg_to_rad(pitch)
	var eye := at + Vector3(0.0, sin(down), cos(down)) * distance
	_camera.global_transform = Transform3D.IDENTITY.translated(eye).looking_at(at)


func _to_output() -> float:
	return _view.get_viewport().get_stretch_transform().get_scale().y


## The sign's icon on screen: SIGN_PX square standing on its point.
func _icon() -> Rect2:
	var marker: Sprite3D = _view.signs()[0]
	var foot := _camera.unproject_position(marker.global_position) * _to_output()
	var side := MissMarkers.SIGN_PX
	return Rect2(foot.x - side / 2.0, foot.y - side, side, side)


## A wall-gap mark as GapMarkers draws it: a fixed-size sign standing on its
## point.
func _gap_marks(at: Vector3) -> Node3D:
	var gaps := Node3D.new()
	_port.add_child(gaps)
	var gap_sign := Sprite3D.new()
	gap_sign.texture = GapMarkers.wall_gap_icon()
	gap_sign.fixed_size = true
	gap_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gap_sign.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	gap_sign.pixel_size = _view.signs()[0].pixel_size
	gaps.add_child(gap_sign)
	gap_sign.global_position = at
	return gaps


## The unlinked sign's icon on screen as drawn: its point, slid by its offset.
func _drawn_icon() -> Rect2:
	var marker: Sprite3D = _view.signs()[0]
	var slide := marker.offset.x * MissMarkers.SIGN_PX / MarkerIcons.SIZE
	return Rect2(_icon().position + Vector2(slide, 0.0), _icon().size)


## A wall-gap sign up and to the right, overlapping the unlinked sign.
func _gap_over_sign() -> Node3D:
	var marker: Sprite3D = _view.signs()[0]
	var foot := _camera.unproject_position(marker.global_position)
	var depth := _camera.global_position.distance_to(marker.global_position)
	return _gap_marks(_camera.project_position(foot + Vector2(12.0, -16.0), depth))


func test_the_sign_has_the_broken_link_glyph_and_no_caption() -> void:
	var marker: Sprite3D = _view.signs()[0]
	assert_object(marker.texture).is_same(MarkerIcons.icon(MarkerIcons.Glyph.UNLINKED_GATE))
	assert_int(marker.find_children("*", "Label3D", true, false).size()).is_equal(0)
	assert_str(GateLinksView.text_of(marker)).is_equal("Unlinked: no north exit in 4 cells")


func test_the_hover_text_is_reported_only_in_build_mode() -> void:
	_look(25.0, 54.0)
	_view.set_building(false)
	print("hover signs outside build mode: %d" % _view.hover_signs().size())
	assert_int(_view.hover_signs().size()).is_equal(0)
	_view.set_building(true)
	var signs := _view.hover_signs()
	print("hover signs in build mode: %s" % [signs])
	assert_int(signs.size()).is_equal(1)
	assert_int(signs[0]["key"]).is_equal(_desk_id)
	assert_int(signs[0]["select"]).is_equal(_desk_id)
	assert_str(signs[0]["text"]).is_equal("Unlinked: no north exit in 4 cells")
	# The rect is the drawn icon, in viewport px.
	var rect: Rect2 = signs[0]["rect"]
	var icon := _icon()
	var scale := _to_output()
	var expected := Rect2(icon.position / scale, icon.size / scale)
	assert_vector(rect.position).is_equal_approx(expected.position, Vector2.ONE * 0.01)
	assert_vector(rect.size).is_equal_approx(expected.size, Vector2.ONE * 0.01)


func test_a_wall_gap_sign_on_the_unlinked_sign_moves_it_sideways() -> void:
	_look(25.0, 54.0)
	_view.layout_signs()
	var marker: Sprite3D = _view.signs()[0]
	var gaps := _gap_over_sign()
	var marks := GateLinksView.marker_rects(gaps, _camera, _to_output())
	var unshifted := _icon()
	# The control: unshifted, the unlinked sign meets the wall-gap sign.
	assert_int(marks.size()).is_equal(1)
	assert_bool(unshifted.intersects(marks[0])).is_true()
	_view.gaps = gaps
	var placed := _view.layout_signs()
	var icon := _drawn_icon()
	print("marks %s unshifted %s icon %s placed %s" % [marks, unshifted, icon, placed])
	# The sign moved sideways, away from the wall-gap sign (to the left).
	assert_float(icon.position.x).is_less(unshifted.position.x)
	assert_float(icon.position.y).is_equal_approx(unshifted.position.y, 0.01)
	assert_bool(icon.grow(MissMarkers.CAPTION_MARGIN_PX).intersects(marks[0])).is_false()
	assert_bool(placed[0].is_equal_approx(icon)).is_true()
	# The hover rect follows the slide.
	_view.set_building(true)
	var rect: Rect2 = _view.hover_signs()[0]["rect"]
	assert_float(rect.position.x * _to_output()).is_equal_approx(icon.position.x, 0.01)
	# With the wall-gap mark gone the sign goes back over its desk.
	_view.gaps = null
	gaps.free()
	_view.layout_signs()
	assert_float(marker.offset.x).is_equal(0.0)


func test_an_unchanged_camera_and_marks_lay_out_once() -> void:
	_look(25.0, 54.0)
	var first := _view.layout_signs()
	var runs := _view.sign_layouts
	for i in 3:
		var again := _view.layout_signs()
		assert_array(again).is_equal(first)
	print("layouts after 4 calls, nothing changed: %d (was %d)" % [_view.sign_layouts, runs])
	assert_int(_view.sign_layouts).is_equal(runs)


func test_moving_the_camera_lays_out_again() -> void:
	_look(25.0, 54.0)
	_view.layout_signs()
	var runs := _view.sign_layouts
	_look(26.0, 54.0)
	_view.layout_signs()
	print("layouts after a camera move: %d (was %d)" % [_view.sign_layouts, runs])
	assert_int(_view.sign_layouts).is_equal(runs + 1)
	_view.layout_signs()
	assert_int(_view.sign_layouts).is_equal(runs + 1)


func test_a_wall_gap_mark_coming_and_going_lays_out_again_with_the_camera_still() -> void:
	_look(25.0, 54.0)
	_view.layout_signs()
	var marker: Sprite3D = _view.signs()[0]
	var runs := _view.sign_layouts
	assert_float(marker.offset.x).is_equal(0.0)
	var gaps := _gap_over_sign()
	_view.gaps = gaps
	_view.layout_signs()
	print("layouts after a mark came: %d (was %d)" % [_view.sign_layouts, runs])
	assert_int(_view.sign_layouts).is_equal(runs + 1)
	# The control: the sign slid off the mark, so the answer is not the old one.
	assert_float(marker.offset.x).is_not_equal(0.0)
	# The mark stays put: nothing more to do.
	_view.layout_signs()
	assert_int(_view.sign_layouts).is_equal(runs + 1)
	# The mark vanishes, `gaps` itself still set and the camera still.
	for child in gaps.get_children():
		gaps.remove_child(child)
		child.free()
	_view.layout_signs()
	print("layouts after the mark went: %d" % _view.sign_layouts)
	assert_int(_view.sign_layouts).is_equal(runs + 2)
	assert_float(marker.offset.x).is_equal(0.0)
	_view.gaps = null
	gaps.free()
