class_name TestHudTopRowMain
extends GdUnitTestSuite
## On the real main scene, the top row clears the clock panel (FlightPanel):
## money, rating, the Build mode sign, Runway, Offers and the clock panel
## overlap in no pair, and the two sheets end left of the clock panel. The
## sizes are checked in test_hud_top_row.gd; here the layout is whatever the
## test window gives, and only pairs are compared.

var _main: Node


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame


func after() -> void:
	_main.free()


func _rect(node_name: String) -> Rect2:
	var control := _main.find_child(node_name, true, false) as Control
	assert_object(control).is_not_null()
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func test_the_top_row_and_the_clock_panel_overlap_in_no_pair() -> void:
	(_main.get_node("BuildMenu") as BuildMenu).press_category(0)
	var names := ["MoneySlot", "RatingCard", "BuildModeSign", "RunwayButton", "OffersButton"]
	names.append("FlightPanel")
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a := _rect(names[i])
			var b := _rect(names[j])
			print("%s %s vs %s %s" % [names[i], a, names[j], b])
			assert_bool(a.intersects(b)).is_false()


func test_the_top_row_windows_are_all_button_height() -> void:
	(_main.get_node("BuildMenu") as BuildMenu).press_category(0)
	for node_name in ["MoneySlot", "RatingCard", "BuildModeSign", "RunwayButton", "OffersButton"]:
		assert_float(_rect(node_name).size.y).is_equal_approx(float(HudLayout.BUTTON_H), 0.5)


func test_an_open_sheet_ends_left_of_the_clock_panel() -> void:
	var clock_panel := _rect("FlightPanel")
	for pair in [["RunwayCard", "RunwaySheet"], ["OfferPanel", "OfferSheet"]]:
		var owner_node := _main.get_node(pair[0])
		owner_node.open()
		var sheet := _rect(pair[1])
		owner_node.close()
		print("%s %s vs FlightPanel %s" % [pair[1], sheet, clock_panel])
		assert_float(sheet.end.x).is_less(clock_panel.position.x)
