class_name TestHudTopRow
extends GdUnitTestSuite
## The HUD's top row (HUD 2/7, decision hud-grid-and-rails-one-spacing-grid-
## centred-top-row-right-ra, parts 1 and 2), checked on rects of the real
## controls. Money and rating sit at the margin in one row; the Build mode sign,
## Runway and Offers are one centred row of three 176x40 slots, 8 apart, tops on
## the margin. A 1920x1080 and a 1280x720 window have the same layout: the
## canvas_items stretch makes both 1536x864 layout px, so each world is a
## SubViewport with that 2D size override, stretched to its pixel size.

const LAYOUT_W := 1536.0
const SIZES: Array[Vector2i] = [Vector2i(1536, 864), Vector2i(1280, 720)]

var _worlds: Array[Dictionary] = []


func before() -> void:
	for size in SIZES:
		_worlds.append(_build_world(size))
	await get_tree().process_frame
	await get_tree().process_frame


func after() -> void:
	for world in _worlds:
		(world["port"] as SubViewport).free()
	_worlds.clear()


func _build_world(size: Vector2i) -> Dictionary:
	var port := SubViewport.new()
	port.size = size
	port.size_2d_override = Vector2i(int(LAYOUT_W), int(LAYOUT_W * size.y / size.x))
	port.size_2d_override_stretch = true
	add_child(port)
	var mode := BuildMode.new()
	mode.initial_tool = BuildMode.Tool.NONE
	mode.grid_size = Vector2i(20, 20)
	port.add_child(mode)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	var rating := AirportRating.new()
	port.add_child(rating)
	var badge := RatingBadge.new()
	badge.rating = rating
	port.add_child(badge)
	var sim := FlightSim.new()
	sim.runway.size = PlaneClasses.SMALL
	sim.open_airport()
	port.add_child(sim)
	var finances := Finances.new()
	port.add_child(finances)
	var runway := RunwayCard.new()
	runway.flights = sim
	runway.finances = finances
	runway.build_mode = mode
	port.add_child(runway)
	var desk := OfferDesk.new()
	desk.runway = Runway.new(PlaneClasses.LARGE)
	port.add_child(desk)
	var offers := OfferPanel.new()
	offers.desk = desk
	offers.flights = sim
	offers.build_mode = mode
	port.add_child(offers)
	return {
		"port": port,
		"menu": menu,
		"badge": badge,
		"runway": runway,
		"offers": offers,
	}


## A control's rectangle in layout px: the canvas transform leaves out the
## stretch, so a control's rectangle through it is already in layout px.
func _layout(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _money(world: Dictionary) -> Control:
	return (world["menu"] as BuildMenu).money_label().get_parent() as Control


func _sign(world: Dictionary) -> Control:
	return (world["menu"] as BuildMenu).build_frame.sign_panel()


func _set_build_mode(world: Dictionary, on: bool) -> void:
	var menu: BuildMenu = world["menu"]
	if on:
		menu.press_category(0)
	else:
		menu.build_mode.set_tool(BuildMode.Tool.NONE)
	assert_bool(menu.build_frame.visible).is_equal(on)


## Money, rating and the three row buttons, each with a label for the report.
func _top_row(world: Dictionary) -> Dictionary:
	return {
		"money": _layout(_money(world)),
		"rating": _layout((world["badge"] as RatingBadge).card()),
		"sign": _layout(_sign(world)),
		"runway": _layout((world["runway"] as RunwayCard).toggle_button()),
		"offers": _layout((world["offers"] as OfferPanel).toggle_button()),
	}


func test_no_two_top_row_windows_overlap_at_both_sizes() -> void:
	for world in _worlds:
		_set_build_mode(world, true)
		var rects := _top_row(world)
		var names := rects.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				var a: Rect2 = rects[names[i]]
				var b: Rect2 = rects[names[j]]
				print(
					(
						"%s: %s %s vs %s %s"
						% [(world["port"] as SubViewport).size, names[i], a, names[j], b]
					)
				)
				assert_bool(a.intersects(b)).is_false()
		_set_build_mode(world, false)


func test_every_top_row_window_has_its_top_on_the_margin() -> void:
	for world in _worlds:
		_set_build_mode(world, true)
		var rects := _top_row(world)
		for key in rects:
			assert_float((rects[key] as Rect2).position.y).is_equal_approx(
				float(HudLayout.MARGIN), 0.5
			)
		_set_build_mode(world, false)


func test_the_rating_card_ends_a_gap_before_the_sign_slot() -> void:
	for world in _worlds:
		var rects := _top_row(world)
		var rating: Rect2 = rects["rating"]
		var sign_slot: Rect2 = rects["sign"]
		assert_float(sign_slot.position.x - rating.end.x).is_greater_equal(
			float(HudLayout.GAP) - 0.5
		)


func test_every_top_row_window_is_button_height() -> void:
	for world in _worlds:
		_set_build_mode(world, true)
		var rects := _top_row(world)
		for key in rects:
			print("%s height %s" % [key, (rects[key] as Rect2).size.y])
			assert_float((rects[key] as Rect2).size.y).is_equal_approx(
				float(HudLayout.BUTTON_H), 0.5
			)
		_set_build_mode(world, false)


func test_money_and_rating_sit_in_one_row_from_the_margin() -> void:
	for world in _worlds:
		var rects := _top_row(world)
		var money: Rect2 = rects["money"]
		var rating: Rect2 = rects["rating"]
		assert_float(money.position.x).is_equal_approx(float(HudLayout.MARGIN), 0.5)
		assert_float(money.size.x).is_greater_equal(float(HudLayout.MONEY_W) - 0.5)
		assert_float(rating.position.x - money.end.x).is_equal_approx(float(HudLayout.GAP), 0.5)


func test_the_three_slots_are_toggle_sized_gap_apart_and_centred() -> void:
	for world in _worlds:
		_set_build_mode(world, true)
		var rects := _top_row(world)
		var slots: Array[Rect2] = [rects["sign"], rects["runway"], rects["offers"]]
		for slot in slots:
			assert_vector(slot.size).is_equal_approx(
				Vector2(HudLayout.TOGGLE_W, HudLayout.BUTTON_H), Vector2(0.5, 0.5)
			)
		assert_float(slots[1].position.x - slots[0].end.x).is_equal_approx(
			float(HudLayout.GAP), 0.5
		)
		assert_float(slots[2].position.x - slots[1].end.x).is_equal_approx(
			float(HudLayout.GAP), 0.5
		)
		var centre := (slots[0].position.x + slots[2].end.x) / 2.0
		assert_float(centre).is_equal_approx(LAYOUT_W / 2.0, 1.0)
		_set_build_mode(world, false)


func test_runway_and_offers_do_not_move_when_build_mode_toggles() -> void:
	for world in _worlds:
		_set_build_mode(world, false)
		var before := _top_row(world)
		_set_build_mode(world, true)
		var during := _top_row(world)
		_set_build_mode(world, false)
		for key in ["runway", "offers"]:
			assert_vector((during[key] as Rect2).position).is_equal_approx(
				(before[key] as Rect2).position, Vector2(0.5, 0.5)
			)


func test_the_sheets_open_under_their_buttons_in_one_560_family() -> void:
	for world in _worlds:
		var runway: RunwayCard = world["runway"]
		var offers: OfferPanel = world["offers"]
		for pair in [[runway, runway.toggle_button()], [offers, offers.toggle_button()]]:
			var owner_node: Node = pair[0]
			owner_node.open()
			var button := _layout(pair[1])
			var sheet := _layout(owner_node.sheet())
			owner_node.close()
			assert_float(sheet.size.x).is_equal_approx(float(HudLayout.SHEET_W), 0.5)
			assert_float(sheet.position.y).is_greater_equal(button.end.y)
			assert_bool(sheet.position.x <= button.position.x + 0.5).is_true()
			assert_bool(sheet.end.x >= button.end.x - 0.5).is_true()


func test_opening_one_sheet_closes_the_other() -> void:
	for world in _worlds:
		var runway: RunwayCard = world["runway"]
		var offers: OfferPanel = world["offers"]
		runway.open()
		assert_bool(runway.is_open()).is_true()
		assert_bool(offers.is_open()).is_false()
		offers.open()
		assert_bool(offers.is_open()).is_true()
		assert_bool(runway.is_open()).is_false()
		runway.open()
		assert_bool(runway.is_open()).is_true()
		assert_bool(offers.is_open()).is_false()
		runway.close()
