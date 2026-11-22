class_name TestBuildMenuSessionOrder
extends GdUnitTestSuite
## The sim keeps ticking normally when a build tray opens (ruling
## player-owns-clock-and-persistent-build-undo-no-auto-pause-on-trays-offers-planner-direct-delete).

const STRUCTURE := 0

var _port: SubViewport
var _clock: SimClock
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	_mode = BuildMode.new()
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_menu.clock = _clock
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


## Leaves the accumulator one sliver short of a step, so any frame the clock
## processes unpaused ticks.
func _arm_the_clock() -> void:
	_clock._accumulator = SimClock.STEP * 0.99
	_clock.set_speed(3)


func test_clock_keeps_ticking_when_the_tray_opens() -> void:
	await get_tree().process_frame
	_arm_the_clock()
	var before := _clock.tick
	_menu.press_category(STRUCTURE)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("ticks across opening the tray: %d -> %d" % [before, _clock.tick])
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.tick).is_greater(before)


func test_the_armed_clock_does_tick_when_no_tray_opens() -> void:
	await get_tree().process_frame
	_arm_the_clock()
	var before := _clock.tick
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_clock.tick).is_greater(before)
