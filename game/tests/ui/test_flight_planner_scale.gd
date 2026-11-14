class_name TestFlightPlannerScale
extends GdUnitTestSuite
## The open planner sheet fits the viewport at the UI scales the HUD supports
## (a 1920x1080 window divided by the scale, as the canvas_items stretch does):
## the sheet is inside the layer, every gate row and bar is inside the sheet, and
## the Planner toggle sits inside the column's slot beside Departures.

const LAYOUTS := {1.0: Vector2i(1920, 1080), 1.25: Vector2i(1536, 864), 1.5: Vector2i(1280, 720)}
const GATES: Array[String] = ["A", "B", "C"]

var _port: SubViewport
var _planner: FlightPlanner
var _sim: FlightSim
var _clock: SimClock


func after_test() -> void:
	if _port != null:
		_port.free()
		_port = null


func _boot(size: Vector2i) -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.open_airport()
	_sim.gate_source = func() -> Array[String]: return GATES
	for spec: Array in [["X", 600, "Oslo"], ["Y", 660, "Rome"], ["Z", 1230, "Paris"]]:
		var terms := TestFlightContracts.terms(spec[0], spec[1])
		terms["destination"] = spec[2]
		assert_bool(_sim.accept_contract(terms)).is_true()
	_port = SubViewport.new()
	_port.size = size
	add_child(_port)
	_planner = FlightPlanner.new()
	_planner.flights = _sim
	_planner.clock = _clock
	_port.add_child(_planner)
	_planner.open()
	await await_idle_frame()
	await await_idle_frame()


func _rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func test_the_sheet_and_its_rows_and_bars_fit_at_every_ui_scale() -> void:
	for ui_scale in LAYOUTS:
		var layout := Vector2(LAYOUTS[ui_scale])
		await _boot(LAYOUTS[ui_scale])
		var sheet := _rect(_planner.sheet())
		print("ui scale %.2f layout %s sheet %s" % [ui_scale, layout, sheet])
		assert_bool(Rect2(Vector2.ZERO, layout).encloses(sheet)).is_true()
		assert_float(sheet.size.x).is_greater(layout.x - 4.0 * HudLayout.MARGIN)
		var bars := _planner.bar_buttons()
		assert_int(bars.size()).is_equal(3)
		for gate_id in GATES:
			var head := _rect(_planner.part("GateHead_" + gate_id) as PanelContainer)
			var track := _rect(_planner.part("Track_" + gate_id))
			assert_bool(sheet.encloses(head)).is_true()
			assert_bool(sheet.encloses(track)).is_true()
			assert_float(track.size.x).is_greater(float(24 * 36))
			assert_float(head.end.x).is_less_equal(track.position.x)
		for bar in bars:
			var rect := _rect(bar)
			print("  %s %s" % [bar.name, rect])
			assert_float(rect.size.x).is_greater(60.0)
			assert_bool(sheet.encloses(rect)).is_true()
			# The label's room ends before the departure tick.
			var tick := _rect(bar.find_child("DepartureTick", false, false) as Control)
			var room_end := _rect(FlightPlanner.bar_label(bar)).end.x
			print("  label room ends %.1f, tick at %.1f" % [room_end, tick.position.x])
			assert_float(room_end).is_less(tick.position.x)
			# Tight: the destination alone, whole; roomy: time and destination.
			var full: String = bar.get_meta(FlightPlanner.FULL_TEXT)
			var place: String = bar.get_meta(FlightPlanner.SHORT_TEXT)
			var shown := FlightPlanner.bar_text(bar)
			print("  text '%s' (full '%s', destination '%s')" % [shown, full, place])
			assert_bool(shown == full or shown == place).is_true()
			if ui_scale == 1.5:
				assert_str(shown).is_equal(place)
				assert_bool(place.contains(":")).is_false()
				var font := bar.get_theme_font("font")
				var width := font.get_string_size(
					place, HORIZONTAL_ALIGNMENT_LEFT, -1, bar.get_theme_font_size("font_size")
				)
				var left := bar.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT)
				assert_float(left + width.x).is_less_equal(room_end - rect.position.x)
			if ui_scale == 1.0:
				assert_str(shown).is_equal(full)
		var toggle := _rect(_planner.toggle_button())
		assert_bool(Rect2(Vector2.ZERO, layout).encloses(toggle)).is_true()
		assert_float(toggle.end.x).is_equal_approx(float(HudLayout.MARGIN + HudLayout.LIST_W), 0.5)
		_port.free()
		_port = null
