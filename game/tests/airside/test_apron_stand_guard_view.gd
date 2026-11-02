class_name TestApronStandGuardView
extends GdUnitTestSuite
## The orange guarded area round the plane stand (ApronStand's GuardView) is
## drawn only while build mode lasts (user ruling plane-guard-area-shows-only-
## in-build-mode-the-site-paving-ex, point 1): with a plane at the stand it is
## hidden while no build tray is open and shown while one is.

const SITE := preload("res://build/terminal_site.tres")
## The first flight's start ticks.
const FIRST := 1000

var _mode: BuildMode
var _menu: BuildMenu
var _flights: FlightSim
var _apron: ApronStand
var _view: Node3D


func before() -> void:
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.site = SITE
	_mode.starter_shell = true
	add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	add_child(_menu)
	_flights = FlightSim.new()
	add_child(_flights)
	_apron = ApronStand.new()
	_apron.build_mode = _mode
	_apron.flights = _flights
	_apron.menu = _menu
	add_child(_apron)
	_view = _apron.get_node("GuardView")
	var starts := FlightSim.schedule_starts(FIRST)
	assert_bool(_flights.add_flight("F1", starts)).is_true()
	_flights.on_tick(starts[FlightSim.State.BOARDING])


func after() -> void:
	for node in [_apron, _flights, _menu, _mode]:
		node.free()


## Every test starts and ends outside build mode.
func after_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	if _menu.is_tray_open():
		_menu.press_category(_menu.open_category())


## The guarded meshes after a frame's update: how many are drawn in the tree.
func _drawn_areas() -> int:
	_apron._process(0.0)
	var drawn := 0
	for area in _view.get_children():
		if (area as Node3D).is_visible_in_tree():
			drawn += 1
	return drawn


func test_a_plane_is_at_the_stand_so_there_is_a_guarded_area() -> void:
	print("busy flight '%s', guard rects %s" % [_apron.busy_flight(), _apron.guard_rects()])
	assert_str(_apron.busy_flight()).is_equal("F1")
	assert_int(_apron.guard_rects().size()).is_equal(2)
	assert_int(_view.get_child_count()).is_equal(2)


func test_hidden_with_no_tray_open() -> void:
	assert_bool(_menu.is_tray_open()).is_false()
	var drawn := _drawn_areas()
	print("no tray: view visible %s, areas drawn %d" % [_view.visible, drawn])
	assert_bool(_view.visible).is_false()
	assert_int(drawn).is_equal(0)


func test_visible_while_a_tray_is_open_and_hidden_once_it_closes() -> void:
	_menu.press_category(0)
	assert_bool(_menu.is_tray_open()).is_true()
	var drawn := _drawn_areas()
	print("tray open: view visible %s, areas drawn %d" % [_view.visible, drawn])
	assert_bool(_view.visible).is_true()
	assert_int(drawn).is_equal(2)
	_menu.press_category(0)
	assert_bool(_menu.is_tray_open()).is_false()
	drawn = _drawn_areas()
	print("tray closed: view visible %s, areas drawn %d" % [_view.visible, drawn])
	assert_bool(_view.visible).is_false()
	assert_int(drawn).is_equal(0)


## The world xz rectangle a guarded mesh covers.
func _area_rect(area: MeshInstance3D) -> Rect2:
	var size := (area.mesh as PlaneMesh).size
	return Rect2(Vector2(area.position.x, area.position.z) - size / 2.0, size)


func _site_frame() -> Rect2:
	return Rect2(Vector2(SITE.grid_origin.x, SITE.grid_origin.z), Vector2(SITE.grid_size))


func test_no_drawn_area_reaches_past_the_site_edge() -> void:
	_apron._process(0.0)
	var frame := _site_frame()
	var raw_past := 0
	for rect in _apron.guard_rects():
		if not frame.encloses(rect):
			raw_past += 1
	var drawn := 0
	for area in _view.get_children():
		if (area as MeshInstance3D).visible:
			drawn += 1
			var rect := _area_rect(area as MeshInstance3D)
			print("drawn %s within site %s" % [rect, frame])
			assert_bool(frame.grow(0.001).encloses(rect)).is_true()
	print("raw rects past the edge: %d, drawn: %d" % [raw_past, drawn])
	assert_int(raw_past).is_greater(0)
	assert_int(drawn).is_equal(2)


func test_clipping_leaves_an_interior_rect_alone_and_drops_an_outside_one() -> void:
	var frame := _site_frame()
	var inside := Rect2(frame.position + Vector2(10, 10), Vector2(8, 6))
	var past := Rect2(frame.position - Vector2(5, 0), Vector2(8, 6))
	var outside := Rect2(frame.position - Vector2(20, 0), Vector2(8, 6))
	var out := ApronStand.clip_rects([inside, past, outside] as Array[Rect2], frame)
	assert_int(out.size()).is_equal(2)
	assert_that(out[0]).is_equal(inside)
	assert_that(out[1]).is_equal(Rect2(frame.position, Vector2(3, 6)))
