class_name TestGateCaptionHud
extends GdUnitTestSuite
## A gate caption never draws under the HUD (board 9773af2f, smoke playtest 12:
## with the camera putting the gate sign near the top of the screen, "Gate A"
## sat between the Runway and Offers buttons). GateLinksView.layout_captions()
## slides a caption clear of the HUD's rectangles (HudRects.collect), the way
## the room labels do (decision status-banner-fades-under-the-build-ghost-room-
## labels-slide), and the lift that clears other captions never goes into it.
##
## The starter shell with a gate desk by its exit (gate A); a camera straight
## over the desk; a panel on a canvas layer beside the view stands in for the
## top row.

const SITE := preload("res://build/terminal_site.tres")
const DESK := Vector2i(19, 115)

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _view: GateLinksView
var _camera: Camera3D
## A view of a real screen size: the headless window is tiny.
var _port: SubViewport
var _hud: Panel


func before() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_flights = FlightSim.new()
	_flights.open_airport()
	_gates = GateDesks.new()
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	assert_bool(_grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK, 0)).ok).is_true()
	_port = SubViewport.new()
	_port.size = Vector2i(1920, 1080)
	add_child(_port)
	_view = GateLinksView.new()
	_port.add_child(_view)
	_view.bind(_grid, _gates)
	_camera = Camera3D.new()
	_port.add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	_port.add_child(layer)
	_hud = Panel.new()
	layer.add_child(_hud)
	var down := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	_camera.global_transform = Transform3D(down, _grid.cell_to_world(DESK) + Vector3.UP * 40.0)


func after() -> void:
	_port.free()
	_gates.free()
	_flights.free()


func before_test() -> void:
	_view.markers = null
	_hud.visible = true


## The caption's rectangle with no lift or slide, in screen pixels.
func _unplaced() -> Rect2:
	var caption: Label3D = _view.gate_captions()[0]
	var point := _camera.unproject_position(caption.global_position)
	var size := GateLinksView.caption_size(caption.text)
	return Rect2(point.x - size.x / 2.0, point.y - size.y, size.x, size.y)


## A full-width HUD strip from the top of the view down to the caption's middle.
func _cover_top_half_of(caption: Rect2) -> Rect2:
	var strip := Rect2(0.0, 0.0, 1920.0, caption.get_center().y)
	_hud.position = strip.position
	_hud.size = strip.size
	return strip


func test_a_caption_under_the_top_row_slides_down_clear_of_it() -> void:
	var unplaced := _unplaced()
	var strip := _cover_top_half_of(unplaced)
	var placed := _view.layout_captions()
	print("unplaced %s; hud %s; placed %s" % [unplaced, strip, placed])
	# The control: unplaced, the caption does reach under the strip.
	assert_bool(unplaced.intersects(strip)).is_true()
	assert_int(placed.size()).is_equal(1)
	assert_bool(placed[0].grow(RoomLabelLayout.GAP_PX).intersects(strip)).is_false()
	assert_float(placed[0].position.y).is_greater(unplaced.position.y)
	var caption: Label3D = _view.gate_captions()[0]
	assert_float(caption.offset.y).is_less(0.0)


func test_a_caption_clear_of_the_hud_stays_on_its_desk() -> void:
	var unplaced := _unplaced()
	_hud.position = Vector2(0.0, unplaced.end.y + 200.0)
	_hud.size = Vector2(1920.0, 100.0)
	var placed := _view.layout_captions()
	print("unplaced %s; placed %s" % [unplaced, placed])
	assert_bool(placed[0].is_equal_approx(unplaced)).is_true()
	var caption: Label3D = _view.gate_captions()[0]
	assert_vector(caption.offset).is_equal(Vector2.ZERO)
