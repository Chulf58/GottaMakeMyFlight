class_name TestBuildMenuUnlocks
extends GdUnitTestSuite
## Progressive tab and card visibility (decision build-menu-rework-six-domain-
## tabs-progressive-tab-and-card-u): locked tabs and locked cards stay hidden
## until their tier opens, unwired require_unlocks fails loud by keeping cards
## visible and greyed with "Locked" / "Build unlocks are not wired", and moving
## an above-tier built item never opens an empty tray.

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu
var _unlocks: BuildUnlocks
var _rating: AirportRating
var _pax: PassengerSim


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	add_child(_port)
	_rating = auto_free(AirportRating.new())
	_pax = auto_free(PassengerSim.new())
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = _rating
	_unlocks.passengers = _pax
	_unlocks.manual = true
	_port.add_child(_unlocks)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.unlocks = _unlocks
	_mode.require_unlocks = true
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func _visible_tab_ids(menu: BuildMenu) -> Array[String]:
	var ids: Array[String] = []
	for i in BuildMenu.CATEGORIES.size():
		if menu.category_button(i).visible:
			ids.append(BuildMenu.category_id(i))
	return ids


func test_tier1_shows_only_three_domain_tabs_and_fourteen_tier1_cards() -> void:
	assert_array(_visible_tab_ids(_menu)).is_equal(
		["building", "operations", "facilities", "remove"]
	)
	var shown_cards := 0
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		var card := _menu.card(tool)
		if card == null:
			continue
		var want := BuildUnlocks.tier_of(tool) == 1
		assert_bool(card.visible).override_failure_message("tool %d" % tool).is_equal(want)
		if card.visible:
			shown_cards += 1
	assert_int(shown_cards).is_equal(16)
	assert_object(_menu.card(BuildMode.Tool.WALL).modulate).is_equal(Color.WHITE)
	assert_str(_menu.card_price_text(BuildMode.Tool.WALL)).is_not_equal(BuildMenu.LOCKED_TEXT)


func test_clicking_a_locked_card_picks_nothing_and_shows_the_requirement() -> void:
	_menu.press_card(BuildMode.Tool.TREE)
	assert_int(_mode.tool).is_not_equal(BuildMode.Tool.TREE)
	assert_str(_menu.status_label().text).contains("Unlocks at 60% quality and 120 passengers")


func test_an_unlock_reveals_new_tabs_and_cards_and_announces_what_opened() -> void:
	for i in 60:
		_rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in 20:
		_pax.outcome.emit(i, true)
	_unlocks.check()
	assert_int(_unlocks.tier()).is_equal(2)
	assert_array(_visible_tab_ids(_menu)).is_equal(
		["building", "operations", "facilities", "food", "shops", "decor", "landside", "remove"]
	)
	assert_bool(_menu.card(BuildMode.Tool.CAFE_ROOM).visible).is_true()
	assert_object(_menu.card(BuildMode.Tool.CAFE_ROOM).modulate).is_not_equal(BuildMenu.LOCKED_TINT)
	assert_bool(_menu.card(BuildMode.Tool.TREE).visible).is_false()
	assert_str(_menu.status_label().text).starts_with("Unlocked:")
	_menu.press_card(BuildMode.Tool.CAFE_ROOM)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.CAFE_ROOM)
	var ok := _unlocks.from_snapshot({"tier": 1, "made": 0, "shown": [], "seen": [], "firsts": []})
	assert_bool(ok).is_true()
	assert_bool(_menu.category_button(BuildMenu.category_index("food")).visible).is_false()
	assert_int(_menu.open_category()).is_equal(BuildMenu.NO_CATEGORY)


func test_move_tool_on_above_tier_item_keeps_tray_closed_while_holding_session() -> void:
	_menu.press_category(BuildMenu.category_index("operations"))
	assert_int(_menu.open_category()).is_equal(BuildMenu.category_index("operations"))
	assert_bool(_menu.is_tray_open()).is_true()
	_mode.set_tool_for_move(BuildMode.Tool.MULTI_STOREY)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.MULTI_STOREY)
	assert_int(_menu.open_category()).is_equal(BuildMenu.NO_CATEGORY)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.build_session.active).is_true()


func test_unwired_unlocks_fails_loud_showing_all_cards_greyed_and_locked() -> void:
	var unwired_mode: BuildMode = auto_free(BuildMode.new())
	unwired_mode.grid_size = Vector2i(20, 20)
	unwired_mode.require_unlocks = true
	unwired_mode.unlocks = null
	_port.add_child(unwired_mode)
	var menu: BuildMenu = auto_free(BuildMenu.new())
	menu.build_mode = unwired_mode
	_port.add_child(menu)
	assert_int(_visible_tab_ids(menu).size()).is_equal(8)
	var cafe := menu.card(BuildMode.Tool.CAFE_ROOM)
	assert_bool(cafe.visible).is_true()
	assert_object(cafe.modulate).is_equal(BuildMenu.LOCKED_TINT)
	assert_str(menu.card_price_text(BuildMode.Tool.CAFE_ROOM)).is_equal(BuildMenu.LOCKED_TEXT)
	assert_str(cafe._get_tooltip(Vector2.ZERO)).contains(BuildUnlocks.NOT_WIRED_TEXT)


func test_a_menu_over_a_bare_mode_shows_every_card_open() -> void:
	var bare: BuildMode = auto_free(BuildMode.new())
	bare.grid_size = Vector2i(20, 20)
	_port.add_child(bare)
	var menu: BuildMenu = auto_free(BuildMenu.new())
	menu.build_mode = bare
	_port.add_child(menu)
	assert_int(_visible_tab_ids(menu).size()).is_equal(8)
	assert_str(menu._lock_text(BuildMode.Tool.MULTI_STOREY)).is_empty()
	assert_bool(menu.card(BuildMode.Tool.MULTI_STOREY).visible).is_true()
	assert_object(menu.card(BuildMode.Tool.MULTI_STOREY).modulate).is_not_equal(
		BuildMenu.LOCKED_TINT
	)
