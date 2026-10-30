class_name TestDebugButtonClearOfBar
extends GdUnitTestSuite
## Smoke playtest 10 (board 13d090fa): at 1920x1080 the Debug button sat partly
## under the right end of the build bar. With the HUD 6/7 icon bar the bar ends
## well left of it. Checked at the project's 1.25 UI scale, where 1920x1080 and
## 3440x1440 windows lay out as 1536x864 and 2752x1152.

const SIZES := [Vector2i(1536, 864), Vector2i(2752, 1152)]
## The least gap between the bar's right end and the Debug button.
const MIN_GAP := 24.0

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


func test_the_debug_button_is_clear_of_the_bar() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	for size in SIZES:
		var port := SubViewport.new()
		port.size = size
		add_child(port)
		var mode := BuildMode.new()
		mode.grid_size = Vector2i(10, 10)
		port.add_child(mode)
		mode.set_process(false)
		var menu := BuildMenu.new()
		menu.build_mode = mode
		port.add_child(menu)
		var hud := PassengerHud.new()
		hud.clock = _world.clock
		hud.flights = _world.flights
		hud.sim = _world.sim
		port.add_child(hud)
		await await_idle_frame()
		await await_idle_frame()
		var bar := menu.bar().get_global_rect()
		var toggle := hud.find_child("DebugToggle", true, false) as Button
		assert_object(toggle).is_not_null()
		var debug := toggle.get_global_rect()
		print(
			"window %s bar %s debug %s gap %.1f" % [size, bar, debug, debug.position.x - bar.end.x]
		)
		assert_float(bar.size.x).is_greater(500.0)
		assert_float(debug.size.x).is_greater(20.0)
		assert_bool(bar.intersects(debug)).is_false()
		assert_float(debug.position.x - bar.end.x).is_greater_equal(MIN_GAP)
		# The open Debug panel is wider than the button: it docks above the bar's
		# height, so it never reaches over the bar's right end (plate d at 1280).
		hud.set_debug_open(true)
		await await_idle_frame()
		await await_idle_frame()
		var panel := (hud.find_child("DebugPanel", true, false) as Control).get_global_rect()
		print("window %s open debug panel %s" % [size, panel])
		assert_float(panel.size.x).is_greater_equal(PassengerHud.DEBUG_W)
		assert_bool(bar.intersects(panel)).is_false()
		assert_float(panel.end.y).is_less_equal(bar.position.y)
		assert_bool(panel.intersects(debug)).is_false()
		port.free()
