class_name TestBuildMenuUnlocks
extends GdUnitTestSuite
## Locked cards (decision build-unlocks-need-stars-and-passengers-served-
## hunger-cafe-a): greyed, "Locked" on the last line, the requirement in the
## hover text, and a click shows the requirement on the status line instead of
## picking the tool. An unlock restores the card and announces what opened.

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu
var _unlocks: BuildUnlocks
var _rating: AirportRating
var _pax: PassengerSim


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


func _last_line(tool: BuildMode.Tool) -> String:
	var labels := _menu.card(tool).find_children("*", "Label", true, false)
	return (labels[labels.size() - 1] as Label).text


func test_a_locked_card_is_greyed_and_says_locked() -> void:
	assert_object(_menu.card(BuildMode.Tool.CAFE_ROOM).modulate).is_equal(BuildMenu.LOCKED_TINT)
	assert_str(_last_line(BuildMode.Tool.CAFE_ROOM)).is_equal(BuildMenu.LOCKED_TEXT)
	assert_str(_menu.card(BuildMode.Tool.CAFE_ROOM).tooltip_text).starts_with(
		"Unlocks at 2 stars and 50 passengers"
	)
	assert_object(_menu.card(BuildMode.Tool.WALL).modulate).is_equal(Color.WHITE)
	assert_str(_last_line(BuildMode.Tool.WALL)).is_not_equal(BuildMenu.LOCKED_TEXT)


func test_clicking_a_locked_card_picks_nothing_and_shows_the_requirement() -> void:
	_menu.press_card(BuildMode.Tool.TREE)
	assert_int(_mode.tool).is_not_equal(BuildMode.Tool.TREE)
	assert_str(_menu.status_label().text).contains("Unlocks at 3 stars and 200 passengers")


func test_an_unlock_restores_the_card_and_announces_what_opened() -> void:
	for i in 60:
		_rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in 50:
		_pax.outcome.emit(i, true)
	_unlocks.check()
	assert_int(_unlocks.tier()).is_equal(2)
	assert_object(_menu.card(BuildMode.Tool.CAFE_ROOM).modulate).is_not_equal(BuildMenu.LOCKED_TINT)
	assert_str(_last_line(BuildMode.Tool.CAFE_ROOM)).is_not_equal(BuildMenu.LOCKED_TEXT)
	assert_str(_menu.status_label().text).starts_with("Unlocked:")
	assert_object(_menu.card(BuildMode.Tool.TREE).modulate).is_equal(BuildMenu.LOCKED_TINT)
	_menu.press_card(BuildMode.Tool.CAFE_ROOM)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.CAFE_ROOM)


func test_a_menu_over_a_bare_mode_shows_every_card_open() -> void:
	var bare: BuildMode = auto_free(BuildMode.new())
	bare.grid_size = Vector2i(20, 20)
	_port.add_child(bare)
	var menu: BuildMenu = auto_free(BuildMenu.new())
	menu.build_mode = bare
	_port.add_child(menu)
	assert_str(menu._lock_text(BuildMode.Tool.MULTI_STOREY)).is_empty()
	assert_object(menu.card(BuildMode.Tool.MULTI_STOREY).modulate).is_not_equal(
		BuildMenu.LOCKED_TINT
	)
