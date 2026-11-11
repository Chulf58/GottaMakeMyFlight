class_name TestBuildMenuUnlockGuidance
extends GdUnitTestSuite
## The tray's part of the unlock guidance (decision new-unlock-tier-phone-ring-
## and-a-short-per-family-dialog-onc): the unlocked cards the player has not
## seen carry the "New" tint until hovered or picked by any route, a locked card
## shows its description with a requirement worked out when the hover card is
## built, and the "Unlocked:" status line gives way to the dialog.

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu
var _unlocks: BuildUnlocks
var _rating: AirportRating
var _pax: PassengerSim
var _guide: UnlockGuide


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_rating = auto_free(AirportRating.new())
	_pax = auto_free(PassengerSim.new())
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = _rating
	_unlocks.passengers = _pax
	_unlocks.manual = true
	_port.add_child(_unlocks)
	_guide = UnlockGuide.new()
	_guide.mode = UnlockGuide.Mode.PROFILE
	_guide.unlocks = _unlocks
	_port.add_child(_guide)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.unlocks = _unlocks
	_mode.require_unlocks = true
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_menu.watch_guide(_guide)


func after_test() -> void:
	_port.free()


## Opens the cafe tier by play; the guide's dialog is open afterwards.
func _earn_cafe_tier() -> void:
	for i in 60:
		_rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in 50:
		_pax.outcome.emit(i, true)
	_unlocks.check()


func _open_cafe_tier() -> void:
	_earn_cafe_tier()
	_guide.dismiss()


func _new_look(tool: BuildMode.Tool) -> bool:
	return _menu.card(tool).modulate.is_equal_approx(BuildMenu.NEW_TINT)


func test_the_cards_of_a_new_tier_are_tinted_and_older_ones_are_not() -> void:
	assert_bool(_new_look(BuildMode.Tool.CAFE_ROOM)).is_false()
	_open_cafe_tier()
	assert_bool(_new_look(BuildMode.Tool.CAFE_ROOM)).is_true()
	assert_bool(_new_look(BuildMode.Tool.XRAY_BELT)).is_true()
	assert_object(_menu.card(BuildMode.Tool.WALL).modulate).is_equal(Color.WHITE)
	assert_object(_menu.card(BuildMode.Tool.TREE).modulate).is_equal(BuildMenu.LOCKED_TINT)


func test_hovering_a_new_card_clears_its_tint_only() -> void:
	_open_cafe_tier()
	_menu.card(BuildMode.Tool.CAFE_ROOM).mouse_entered.emit()
	assert_bool(_new_look(BuildMode.Tool.CAFE_ROOM)).is_false()
	assert_object(_menu.card(BuildMode.Tool.CAFE_ROOM).modulate).is_equal(Color.WHITE)
	assert_bool(_new_look(BuildMode.Tool.COUNTER)).is_true()


func test_picking_a_new_card_clears_its_tint() -> void:
	_open_cafe_tier()
	_menu.press_card(BuildMode.Tool.COUNTER)
	assert_bool(_new_look(BuildMode.Tool.COUNTER)).is_false()


func test_a_tool_picked_by_key_clears_its_tint_too() -> void:
	_open_cafe_tier()
	# What a number key does: BuildMode picks the tool without the card.
	_mode.set_tool(BuildMode.Tool.TABLE)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.TABLE)
	assert_bool(_new_look(BuildMode.Tool.TABLE)).is_false()
	assert_bool(_new_look(BuildMode.Tool.COUNTER)).is_true()


func test_a_refused_pick_leaves_the_tint_and_the_mark() -> void:
	_open_cafe_tier()
	_mode.set_tool(BuildMode.Tool.TREE)
	assert_int(_mode.tool).is_not_equal(BuildMode.Tool.TREE)
	assert_bool(_unlocks.tool_seen(BuildMode.Tool.TREE)).is_false()


func test_without_a_guide_no_card_is_tinted() -> void:
	var bare: BuildMenu = auto_free(BuildMenu.new())
	bare.build_mode = _mode
	_port.add_child(bare)
	_open_cafe_tier()
	assert_object(bare.card(BuildMode.Tool.CAFE_ROOM).modulate).is_equal(Color.WHITE)


func test_the_unlocked_status_line_gives_way_to_the_open_dialog() -> void:
	_earn_cafe_tier()
	assert_bool(_guide.is_open()).is_true()
	assert_str(_menu.status_label().text).not_contains("Unlocked:")


func test_the_unlocked_status_line_still_shows_without_a_dialog() -> void:
	var bare_guide: UnlockGuide = auto_free(UnlockGuide.new())
	bare_guide.mode = UnlockGuide.Mode.OFF
	bare_guide.unlocks = _unlocks
	_port.add_child(bare_guide)
	_menu.watch_guide(bare_guide)
	_earn_cafe_tier()
	assert_bool(bare_guide.is_open()).is_false()
	assert_str(_menu.status_label().text).starts_with("Unlocked:")


func test_a_locked_card_shows_its_description_and_the_requirement() -> void:
	var card := _menu.card(BuildMode.Tool.CAFE_ROOM)
	assert_array(card.info).is_equal(ItemInfo.of(BuildMode.Tool.CAFE_ROOM))
	var text := card._get_tooltip(Vector2.ZERO)
	assert_str(text).contains(ItemInfo.of(BuildMode.Tool.CAFE_ROOM)[0])
	assert_str(text).contains("Unlocks at 2 stars and 50 passengers")
	var hover: Control = auto_free(card._make_custom_tooltip(text))
	assert_object(hover).is_not_null()
	var requirement := hover.find_child("Requirement", true, false) as Label
	assert_str(requirement.text).starts_with("Unlocks at 2 stars and 50 passengers")
	assert_array(hover.find_children("*", "Label", true, false)).has_size(7)


func test_the_now_numbers_of_a_locked_card_follow_the_flights_made() -> void:
	var card := _menu.card(BuildMode.Tool.CAFE_ROOM)
	assert_str(card._get_tooltip(Vector2.ZERO)).contains("0 passengers)")
	for i in 7:
		_pax.outcome.emit(i, true)
	assert_str(card._get_tooltip(Vector2.ZERO)).contains("7 passengers)")
	var hover: Control = auto_free(card._make_custom_tooltip(""))
	assert_str((hover.find_child("Requirement", true, false) as Label).text).contains(
		"7 passengers"
	)


func test_an_unlocked_card_keeps_its_description_and_loses_the_requirement() -> void:
	_open_cafe_tier()
	var card := _menu.card(BuildMode.Tool.CAFE_ROOM)
	assert_bool(card.requirement.is_valid()).is_false()
	assert_str(card._get_tooltip(Vector2.ZERO)).not_contains("Unlocks at")
	assert_str(card._get_tooltip(Vector2.ZERO)).contains(ItemInfo.of(BuildMode.Tool.CAFE_ROOM)[0])
