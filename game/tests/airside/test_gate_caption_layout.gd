class_name TestGateCaptionLayout
extends GdUnitTestSuite
## Gate captions keep clear of each other and of the desks' signs (conductor
## ruling on the Runway R5 plates, option iii): two gates 19 m apart stand
## closer on screen than a caption is wide when the camera is high, so
## GateLinksView.layout_captions() lifts the second caption, MissMarkers' way
## (MissMarkers.CAPTION_MARGIN_PX, MAX_LIFTS); close in nothing is lifted; and a
## sign of `markers` over a desk lifts that desk's caption above it.
##
## The starter shell and a copy 19 cells east, each with a gate desk by its
## exit (gates A and B); a camera straight over the desks.

const SITE := preload("res://build/terminal_site.tres")
const EAST := Vector2i(19, 0)
const DESK := Vector2i(19, 115)

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _view: GateLinksView
var _camera: Camera3D
## A view of a real screen size: the headless window is tiny.
var _port: SubViewport


func before() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	for result in _grid.apply_batch(ReferenceTerminal.shell_edits(SITE.starter_offset + EAST)):
		assert_bool(result.ok).is_true()
	_flights = FlightSim.new()
	_flights.open_airport()
	_gates = GateDesks.new()
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	for at in [DESK, DESK + EAST]:
		assert_bool(_grid.apply(BuildEdit.place_object(GateDesks.DESK, at, 0)).ok).is_true()
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


func before_test() -> void:
	_view.markers = null


## The camera `height` metres straight over the two desks, north up.
func _look_down(height: float) -> void:
	var middle := (_grid.cell_to_world(DESK) + _grid.cell_to_world(DESK + EAST)) / 2.0
	var down := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	_camera.global_transform = Transform3D(down, middle + Vector3.UP * height)


## The captions' rectangles with no lift, in screen pixels.
func _unlifted() -> Array[Rect2]:
	var to_output := _view.get_viewport().get_stretch_transform().get_scale().y
	var out: Array[Rect2] = []
	for caption in _view.gate_captions():
		var point := _camera.unproject_position(caption.global_position) * to_output
		var size := GateLinksView.caption_size(caption.text)
		out.append(Rect2(point.x - size.x / 2.0, point.y - size.y, size.x, size.y))
	return out


func _offsets() -> Array:
	var out := []
	for caption in _view.gate_captions():
		out.append(caption.offset.y)
	return out


func test_a_high_camera_lifts_the_second_gate_caption_clear_of_the_first() -> void:
	_look_down(215.0)
	var before := _unlifted()
	var placed := _view.layout_captions()
	print("unlifted %s; placed %s; offsets %s" % [before, placed, _offsets()])
	# The control: unlifted, the two captions overlap.
	assert_bool(before[0].intersects(before[1])).is_true()
	assert_int(placed.size()).is_equal(2)
	var margin := MissMarkers.CAPTION_MARGIN_PX
	assert_bool(placed[0].grow(margin).intersects(placed[1])).is_false()
	assert_float(_offsets()[0]).is_equal(0.0)
	assert_float(_offsets()[1]).is_greater(0.0)


func test_close_in_nothing_is_lifted() -> void:
	_look_down(40.0)
	var placed := _view.layout_captions()
	print("placed %s; offsets %s" % [placed, _offsets()])
	assert_bool(placed[0].intersects(placed[1])).is_false()
	assert_array(_offsets()).is_equal([0.0, 0.0])


func test_a_desk_sign_lifts_its_gate_caption_above_it() -> void:
	_look_down(40.0)
	var signs := Node3D.new()
	_port.add_child(signs)
	var sign := Sprite3D.new()
	sign.texture = GateLinksView.unlinked_icon()
	sign.fixed_size = true
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	var view := _view.get_viewport()
	var height := view.get_visible_rect().size.y * view.get_stretch_transform().get_scale().y
	var unit := 2.0 * tan(deg_to_rad(_camera.fov) / 2.0) / height
	sign.pixel_size = MissMarkers.SIGN_PX * unit / MarkerIcons.SIZE
	signs.add_child(sign)
	var caption: Label3D = _view.gate_captions()[0]
	sign.global_position = caption.global_position - Vector3.UP * GateLinksView.CAPTION_LIFT_M
	_view.markers = signs
	var placed := _view.layout_captions()
	var to_output := view.get_stretch_transform().get_scale().y
	var icon: Rect2 = GateLinksView.marker_rects(signs, _camera, to_output)[0]
	print("sign %s; placed %s; offsets %s" % [icon, placed, _offsets()])
	assert_float(icon.size.x).is_equal_approx(MissMarkers.SIGN_PX, 0.01)
	assert_float(_offsets()[0]).is_greater(0.0)
	assert_bool(placed[0].grow(MissMarkers.CAPTION_MARGIN_PX).intersects(icon)).is_false()
	# The control: without the sign the same caption stays on its desk.
	_view.markers = null
	_view.layout_captions()
	assert_float(_offsets()[0]).is_equal(0.0)
	signs.free()
