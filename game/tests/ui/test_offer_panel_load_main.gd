class_name TestOfferPanelLoadMain
extends GdUnitTestSuite
## On the real main scene a load of a low-rating save leaves one warning card
## and one warning history line. The HUD resets the rail on SaveGame.loaded
## (it connects before the Offers panel) and the panel's own handler runs after
## it, so the warning must not be posted twice.

const SEED := 6_204_417

var _settings_path := SaveTestKit.run_path("offer_load_main_alerts")
var _main: Node


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	add_child(_main)


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)


func _warning_lines(stack: AlertStack) -> int:
	var count := 0
	for line in stack.history_lines():
		count += 1 if line.contains(OfferPanel.WARNING_TITLE) else 0
	return count


func test_loading_a_low_rating_save_posts_the_warning_once() -> void:
	var stack := _main.find_child("AlertStack", true, false) as AlertStack
	var rating := (_main.get_node("OfferDesk") as OfferDesk).rating
	for i in 12:
		SaveTestKit.step(_main)
	for i in 10:
		rating.record_passenger(10, false, 0)
	assert_bool(rating.warning()).is_true()
	assert_int(_warning_lines(stack)).is_greater(0)
	var save: SaveGame = _main.get_node("SaveGame")
	var data := save.snapshot()
	assert_bool(save.load_world(data)).is_true()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(rating.warning()).is_true()
	assert_object(stack.notice_card(OfferPanel.WARNING_KEY)).is_not_null()
	assert_int(_warning_lines(stack)).is_equal(1)
	var cards := 0
	for card in stack.find_children("OfferNotice_%s" % OfferPanel.WARNING_KEY, "", true, false):
		cards += 1 if not card.is_queued_for_deletion() else 0
	assert_int(cards).is_equal(1)
