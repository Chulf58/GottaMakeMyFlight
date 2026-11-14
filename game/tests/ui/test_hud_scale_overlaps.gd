class_name TestHudScaleOverlaps
extends GdUnitTestSuite
## Board 8d9a8f13: at UI scale 1.5 the Templates button covered the first build
## bar button, Debug sat on the bar's right end and Offers overlapped the clock
## panel. The real main scene is laid out at each supported UI scale (a 1920x1080
## window divided by the scale, as the canvas_items stretch does) and no pair of
## HUD buttons or panels may intersect, resting and in build mode with the tray
## and the Debug panel open (decision hud-grid-and-rails-one-spacing-grid-
## centred-top-row-right-ra).

## UI scale 1.0, the project's 1.25 and 1.5, on a 1920x1080 window.
const LAYOUTS := {1.0: Vector2i(1920, 1080), 1.25: Vector2i(1536, 864), 1.5: Vector2i(1280, 720)}
const RESTING := [
	"MoneySlot",
	"RatingCard",
	"RunwayButton",
	"OffersButton",
	"FlightPanel",
	"MoodToggle",
	"DeparturesToggle",
	"TemplatesButton",
	"DebugToggle",
]
const IN_BUILD_MODE := ["BuildModeSign", "DebugPanel"]

var _port: SubViewport
var _main: Node


func after_test() -> void:
	if _port != null:
		_port.free()
		_port = null


func _boot(size: Vector2i) -> void:
	_port = SubViewport.new()
	_port.size = size
	add_child(_port)
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_port.add_child(_main)
	await await_idle_frame()
	await await_idle_frame()


func _rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


## The rects of the named windows, the open tray and every bar button.
func _rects(names: Array) -> Dictionary:
	var rects := {}
	for node_name in names:
		var control := _main.find_child(node_name, true, false) as Control
		assert_object(control).is_not_null()
		assert_bool(control.is_visible_in_tree()).is_true()
		rects[node_name] = _rect(control)
	var menu := _main.get_node("BuildMenu") as BuildMenu
	if menu.tray().is_visible_in_tree():
		rects["Tray"] = _rect(menu.tray())
	var index := 0
	for node in menu.bar().find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree():
			rects["bar_button_%d" % index] = _rect(button)
			index += 1
	assert_int(index).is_greater(3)
	return rects


func _overlaps(rects: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var keys := rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (rects[keys[i]] as Rect2).intersects(rects[keys[j]]):
				found.append("%s %s x %s %s" % [keys[i], rects[keys[i]], keys[j], rects[keys[j]]])
	return found


func test_no_two_resting_hud_windows_overlap_at_any_ui_scale() -> void:
	for ui_scale in LAYOUTS:
		await _boot(LAYOUTS[ui_scale])
		var rects := _rects(RESTING)
		var found := _overlaps(rects)
		print("ui scale %.2f layout %s overlaps %s" % [ui_scale, LAYOUTS[ui_scale], found])
		assert_array(found).is_empty()
		_port.free()
		_port = null


func test_no_two_windows_overlap_in_build_mode_with_the_tray_and_debug_open() -> void:
	for ui_scale in LAYOUTS:
		await _boot(LAYOUTS[ui_scale])
		(_main.get_node("BuildMenu") as BuildMenu).press_category(0)
		var frame := _main.find_child("BuildModeFrame", true, false) as BuildModeFrame
		assert_object(frame).is_not_null()
		frame.set_building(true)
		(_main.get_node("PassengerHud") as PassengerHud).set_debug_open(true)
		await await_idle_frame()
		await await_idle_frame()
		var rects := _rects(RESTING + IN_BUILD_MODE)
		var found := _overlaps(rects)
		print("ui scale %.2f layout %s build overlaps %s" % [ui_scale, LAYOUTS[ui_scale], found])
		assert_array(found).is_empty()
		_port.free()
		_port = null
