class_name TestUnlinkedSignCaption
extends GdUnitTestSuite
## The unlinked sign's caption stays off its desk and the seats near it (smoke
## playtest 11, board f0fbae3c (g)): GateLinksView.layout_signs() puts it over
## the sign, lifted MissMarkers' way clear of the desk, of the seat pieces
## within GateReach.NEAR_CELLS and of every sign. The control is the old caption,
## one line hung under the sign's foot, which the desk's box on screen meets.
##
## The starter shell with a gate desk by its exit, the exit then taken away
## (NO_EXIT), a seat row west of the desk and one two cells north of it.

const SITE := preload("res://build/terminal_site.tres")
const DESK := Vector2i(19, 115)
const EXIT := Vector2i(20, 112)
const SEATS_WEST := Vector2i(16, 115)
const SEATS_NORTH := Vector2i(18, 113)
const OLD_TEXT := "Unlinked: no north exit within 4 cells"

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
	for at in [SEATS_WEST, SEATS_NORTH]:
		var seats := _grid.apply(BuildEdit.place_object(&"seat_row", at, 0))
		assert_bool(seats.ok).override_failure_message(seats.reason_text()).is_true()
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


## The camera `distance` metres from the desk, pitched `pitch` degrees down,
## looking north.
func _look(distance: float, pitch: float) -> void:
	var at := _grid.cell_to_world(DESK) + Vector3(0.5, 0.0, 0.0)
	var down := deg_to_rad(pitch)
	var eye := at + Vector3(0.0, sin(down), cos(down)) * distance
	_camera.global_transform = Transform3D.IDENTITY.translated(eye).looking_at(at)


## The camera `height` metres straight over the desk, north up.
func _look_down(height: float) -> void:
	var at := _grid.cell_to_world(DESK) + Vector3(0.5, 0.0, 0.0)
	var down := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	_camera.global_transform = Transform3D(down, at + Vector3.UP * height)


func _to_output() -> float:
	return _view.get_viewport().get_stretch_transform().get_scale().y


## The screen boxes of the caption's obstacles: the desk first, then each
## seat row.
func _boxes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for corners in GateLinksView.sign_obstacles(_grid, _desk_id):
		out.append(GateLinksView.screen_box(_camera, corners, _to_output()))
	return out


## The sign's icon on screen: SIGN_PX square standing on its point.
func _icon() -> Rect2:
	var marker: Sprite3D = _view.signs()[0]
	var foot := _camera.unproject_position(marker.global_position) * _to_output()
	var side := MissMarkers.SIGN_PX
	return Rect2(foot.x - side / 2.0, foot.y - side, side, side)


func test_the_sign_names_the_reason_on_two_short_lines() -> void:
	var marker: Sprite3D = _view.signs()[0]
	var text := _view.caption_of(marker).text
	var size := GateLinksView.caption_size(text)
	var old := GateLinksView.caption_size(OLD_TEXT)
	print("text %s size %s; old %s" % [text.c_escape(), size, old])
	assert_str(text).is_equal("Unlinked\nno north exit in 4 cells")
	assert_int(text.split("\n").size()).is_equal(2)
	# The control: the old one-line caption is wider than the new one.
	assert_float(size.x).is_less(old.x * 0.75)


func test_the_caption_stands_over_the_sign_clear_of_the_desk_and_seats() -> void:
	for distance in [80.0, 25.0]:
		_look(distance, 54.0)
		var placed := _view.layout_signs()
		var icon := _icon()
		var boxes := _boxes()
		var caption := _view.caption_of(_view.signs()[0])
		print(
			(
				"distance %.0f: caption %s offset %.1f icon %s boxes %s"
				% [distance, placed, caption.offset.y, icon, boxes]
			)
		)
		assert_int(placed.size()).is_equal(1)
		assert_int(boxes.size()).is_equal(3)
		var padded := placed[0].grow(MissMarkers.CAPTION_MARGIN_PX)
		# Over its own sign by CAPTION_GAP_PX at least (nearer than the margin).
		var gap := icon.position.y - placed[0].end.y
		assert_float(gap).is_greater_equal(MissMarkers.CAPTION_GAP_PX - 0.01)
		for box in boxes:
			assert_bool(box.has_area()).is_true()
			assert_bool(padded.intersects(box)).is_false()
		var over := MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX
		assert_float(caption.offset.y).is_greater_equal(over)
		if distance == 80.0:
			# Nothing stands over the sign at play distance: no lift.
			assert_float(caption.offset.y).is_equal(over)
		# The control: the old caption, its top a gap under the sign's foot,
		# meets the desk on screen.
		var old_size := GateLinksView.caption_size(OLD_TEXT)
		var foot := icon.end
		var old := Rect2(
			icon.get_center().x - old_size.x / 2.0,
			foot.y + MissMarkers.CAPTION_GAP_PX,
			old_size.x,
			old_size.y
		)
		assert_bool(old.intersects(boxes[0])).is_true()


func test_a_seat_row_behind_the_sign_lifts_the_caption_over_it() -> void:
	_look_down(15.0)
	var to_output := _to_output()
	var marker: Sprite3D = _view.signs()[0]
	var caption := _view.caption_of(marker)
	var size := GateLinksView.caption_size(caption.text)
	var foot := _camera.unproject_position(marker.global_position) * to_output
	var over := MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX
	var home := Rect2(foot.x - size.x / 2.0, foot.y - over - size.y, size.x, size.y)
	var north := _boxes()[2]
	print("home %s north seats %s" % [home, north])
	# The control: right over the sign, the caption would meet the north row.
	assert_bool(home.grow(MissMarkers.CAPTION_MARGIN_PX).intersects(north)).is_true()
	var placed := _view.layout_signs()
	print("placed %s offset %.1f" % [placed, caption.offset.y])
	assert_float(caption.offset.y).is_greater(over)
	assert_bool(placed[0].grow(MissMarkers.CAPTION_MARGIN_PX).intersects(north)).is_false()
	# The drawn caption is where layout_signs() says: its bottom `offset` over
	# the sign's point.
	assert_float(foot.y - caption.offset.y).is_equal_approx(placed[0].end.y, 0.01)


func test_a_wall_gap_sign_over_the_desk_lifts_the_caption_over_it() -> void:
	_look(25.0, 54.0)
	_view.layout_signs()
	var caption := _view.caption_of(_view.signs()[0])
	var over := MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX
	# The control: with no wall-gap sign the caption stands right over its sign.
	assert_float(caption.offset.y).is_equal(over)
	var gaps := Node3D.new()
	_port.add_child(gaps)
	var gap_sign := Sprite3D.new()
	gap_sign.texture = GateLinksView.unlinked_icon()
	gap_sign.fixed_size = true
	gap_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gap_sign.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	gap_sign.pixel_size = _view.signs()[0].pixel_size
	gaps.add_child(gap_sign)
	# A sign's height (SIGN_PX) over the unlinked sign: where the caption was.
	var marker: Sprite3D = _view.signs()[0]
	var foot := _camera.unproject_position(marker.global_position)
	var depth := _camera.global_position.distance_to(marker.global_position)
	var lifted := foot - Vector2(0.0, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX)
	gap_sign.global_position = _camera.project_position(lifted, depth)
	_view.gaps = gaps
	var placed := _view.layout_signs()
	var icon: Rect2 = GateLinksView.marker_rects(gaps, _camera, _to_output())[0]
	print("gap sign %s placed %s offset %.1f" % [icon, placed, caption.offset.y])
	assert_float(caption.offset.y).is_greater(over)
	assert_bool(placed[0].grow(MissMarkers.CAPTION_MARGIN_PX).intersects(icon)).is_false()
	_view.gaps = null
	gaps.free()
	_view.layout_signs()
	assert_float(caption.offset.y).is_equal(over)
