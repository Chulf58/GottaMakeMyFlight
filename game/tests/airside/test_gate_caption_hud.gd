class_name TestGateCaptionHud
extends GdUnitTestSuite
## A gate caption never draws under the HUD (board 9773af2f, smoke playtest 12:
## with the camera putting the gate sign near the top of the screen, "Gate A"
## sat between the Runway and Offers buttons). GateLinksView.layout_captions()
## slides a caption clear of the HUD's rectangles (HudRects.collect), the way
## the room labels do (decision status-banner-fades-under-the-build-ghost-room-
## labels-slide), and the lift that clears other captions never goes into it.
## The slide also keeps clear of the captions already placed and of the
## unlinked signs, so the declutter of two nearby captions survives it.
##
## The starter shell with a gate desk by its exit (gate A), a copy 19 cells east
## (gate B) and one 38 cells east whose exit is taken away (an unlinked sign);
## a camera straight over the desks; a panel on a canvas layer beside the view
## stands in for the top row.

const SITE := preload("res://build/terminal_site.tres")
const EAST := Vector2i(19, 0)

var _desk := ReferenceTerminal.GATE_DESK_CELL + SITE.starter_offset
var _exit := ReferenceTerminal.EXIT_CELL + SITE.starter_offset

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
	for copy in [1, 2]:
		for result in _grid.apply_batch(
			ReferenceTerminal.shell_edits(SITE.starter_offset + EAST * copy)
		):
			assert_bool(result.ok).is_true()
	_flights = FlightSim.new()
	_flights.open_airport()
	_gates = GateDesks.new()
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	for copy in [0, 1, 2]:
		var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, _desk + EAST * copy, 0))
		assert_bool(desk.ok).is_true()
	(
		assert_bool(_grid.apply(BuildEdit.remove_object(_grid.object_at(_exit + EAST * 2))).ok)
		. is_true()
	)
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


func after() -> void:
	_port.free()
	_gates.free()
	_flights.free()


func before_test() -> void:
	_view.markers = null
	_hud.visible = true
	_look_down(_desk, 40.0)


## The camera `height` metres straight over `cell`, north up.
func _look_down(cell: Vector2i, height: float) -> void:
	var down := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	_camera.global_transform = Transform3D(down, _grid.cell_to_world(cell) + Vector3.UP * height)


## The shown gate captions' rectangles with no lift or slide, in screen pixels.
func _unplaced() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for caption in _view.gate_captions():
		var point := _camera.unproject_position(caption.global_position)
		var size := GateLinksView.caption_size(caption.text)
		out.append(Rect2(point.x - size.x / 2.0, point.y - size.y, size.x, size.y))
	return out


## A full-width HUD strip from the top of the view down to `y`.
func _cover_down_to(y: float) -> Rect2:
	var strip := Rect2(0.0, 0.0, 1920.0, y)
	_hud.position = strip.position
	_hud.size = strip.size
	return strip


func test_a_caption_under_the_top_row_slides_down_clear_of_it() -> void:
	var unplaced := _unplaced()[0]
	var strip := _cover_down_to(unplaced.get_center().y)
	var placed := _view.layout_captions()
	print("unplaced %s; hud %s; placed %s" % [unplaced, strip, placed])
	# The control: unplaced, the caption does reach under the strip.
	assert_bool(unplaced.intersects(strip)).is_true()
	assert_int(placed.size()).is_equal(2)
	assert_bool(placed[0].grow(RoomLabelLayout.GAP_PX).intersects(strip)).is_false()
	assert_float(placed[0].position.y).is_greater(unplaced.position.y)
	var caption: Label3D = _view.gate_captions()[0]
	assert_float(caption.offset.y).is_less(0.0)


func test_a_caption_clear_of_the_hud_stays_on_its_desk() -> void:
	var unplaced := _unplaced()[0]
	_hud.position = Vector2(0.0, unplaced.end.y + 200.0)
	_hud.size = Vector2(1920.0, 100.0)
	var placed := _view.layout_captions()
	print("unplaced %s; placed %s" % [unplaced, placed])
	assert_bool(placed[0].is_equal_approx(unplaced)).is_true()
	var caption: Label3D = _view.gate_captions()[0]
	assert_vector(caption.offset).is_equal(Vector2.ZERO)


func test_two_nearby_captions_under_the_top_row_end_clear_of_it_and_of_each_other() -> void:
	_look_down(_desk + EAST / 2, 215.0)
	var unplaced := _unplaced()
	var strip := _cover_down_to(maxf(unplaced[0].get_center().y, unplaced[1].get_center().y))
	var view_size := Vector2(1920.0, 1080.0)
	# The controls: unplaced, both captions reach under the strip and meet, and
	# sliding each off the strip alone lands them on each other.
	assert_bool(unplaced[0].intersects(strip) and unplaced[1].intersects(strip)).is_true()
	assert_bool(unplaced[0].intersects(unplaced[1])).is_true()
	var first := RoomLabelLayout.slide_clear(unplaced[0], [strip], view_size)
	var second := RoomLabelLayout.slide_clear(unplaced[1], [strip], view_size)
	assert_bool(first.grow(MissMarkers.CAPTION_MARGIN_PX).intersects(second)).is_true()
	var placed := _view.layout_captions()
	print("unplaced %s; hud %s; placed %s" % [unplaced, strip, placed])
	for rect in placed:
		assert_bool(rect.grow(RoomLabelLayout.GAP_PX).intersects(strip)).is_false()
	assert_bool(placed[0].grow(MissMarkers.CAPTION_MARGIN_PX).intersects(placed[1])).is_false()


func test_a_caption_under_the_top_row_slides_clear_of_an_unlinked_sign() -> void:
	_look_down(_desk + EAST * 3 / 2, 215.0)
	var unplaced := _unplaced()[1]
	var strip := _cover_down_to(unplaced.position.y + 18.0)
	var view_size := Vector2(1920.0, 1080.0)
	_view.layout_signs()
	assert_int(_view.signs().size()).is_equal(1)
	var sign: Sprite3D = _view.signs()[0]
	var foot := _camera.unproject_position(sign.global_position)
	var size := MissMarkers.SIGN_PX
	var obstacles: Array[Rect2] = [Rect2(foot.x - size / 2.0, foot.y - size, size, size)]
	obstacles.append_array(_view.layout_signs())
	# The controls: unplaced, the caption reaches under the strip, and sliding it
	# off the strip alone lands it on the sign or its caption.
	assert_bool(unplaced.intersects(strip)).is_true()
	var alone := RoomLabelLayout.slide_clear(unplaced, [strip], view_size)
	var margin := MissMarkers.CAPTION_MARGIN_PX
	var lands_on := obstacles.filter(
		func(r: Rect2) -> bool: return alone.grow(margin).intersects(r)
	)
	assert_array(lands_on).is_not_empty()
	var placed := _view.layout_captions()
	print("unplaced %s; hud %s; sign %s; placed %s" % [unplaced, strip, obstacles, placed])
	for rect in placed:
		assert_bool(rect.grow(RoomLabelLayout.GAP_PX).intersects(strip)).is_false()
	var hits := obstacles.filter(
		func(r: Rect2) -> bool: return placed[1].grow(margin).intersects(r)
	)
	assert_array(hits).is_empty()


func test_a_caption_covered_with_no_clear_spot_hides_instead_of_overlapping() -> void:
	_hud.position = Vector2.ZERO
	_hud.size = Vector2(1920.0, 1080.0)
	var placed := _view.layout_captions()
	assert_array(placed).is_empty()
	for caption in _view._captions:
		assert_bool(caption.visible).is_false()
	# Control: clearing the HUD restores visibility on the next layout.
	_hud.visible = false
	var restored := _view.layout_captions()
	assert_int(restored.size()).is_equal(2)


func test_a_covered_caption_with_only_an_occupied_spot_nearby_hides_instead_of_stacking() -> void:
	_look_down(_desk + EAST / 2, 120.0)
	var homes := _unplaced()
	assert_int(homes.size()).is_equal(2)
	# Keep only Gate A's padded rect uncovered; cover the rest of the screen so
	# Gate B's home is under HUD and the only un-covered spot holds Gate A.
	var hole := homes[0].grow(RoomLabelLayout.GAP_PX + 1.0)
	_hud.position = Vector2(hole.end.x, 0.0)
	_hud.size = Vector2(1920.0 - hole.end.x, 1080.0)
	var extras: Array[Panel] = []
	var rects := [
		Rect2(0.0, 0.0, hole.position.x, 1080.0),
		Rect2(hole.position.x, 0.0, hole.size.x, hole.position.y),
		Rect2(hole.position.x, hole.end.y, hole.size.x, 1080.0 - hole.end.y),
	]
	for rect in rects:
		var panel := Panel.new()
		panel.position = rect.position
		panel.size = rect.size
		_hud.get_parent().add_child(panel)
		extras.append(panel)
	var placed := _view.layout_captions()
	for panel in extras:
		panel.free()
	assert_int(placed.size()).is_equal(1)
	assert_bool(_view._captions[0].visible).is_true()
	assert_bool(_view._captions[1].visible).is_false()
