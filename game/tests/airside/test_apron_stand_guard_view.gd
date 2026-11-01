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
