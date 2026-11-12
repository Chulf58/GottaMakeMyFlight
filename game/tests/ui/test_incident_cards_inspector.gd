class_name TestIncidentCardsInspector
extends MajorTestBase
## The result cards of the inspector's visit (IncidentCards, board a392ed0a):
## a passed visit posts one coral card on the rail that names the reward, a
## failed visit posts one that names the reason and the rating drop, both with
## the numbers of the incident's saved plan. The card comes back when the rail
## resets or the director loads and is never posted twice.

## The plan numbers, none of them the tuning's, so a card that read
## IncidentTuning instead of the saved plan would say the wrong thing.
const PASS_MONEY := 123
const FAIL_HALF_STARS := 3
const MAX_MESSES := 3

var _rail: AlertStack
var _cards: IncidentCards


func before_test() -> void:
	super.before_test()
	_rail = AlertStack.new()
	_rail.sim = _world.sim
	add_child(_rail)
	_cards = auto_free(IncidentCards.new()) as IncidentCards
	_cards.rail = _rail
	_cards.bind(_director)


func after_test() -> void:
	_rail.free()
	super.after_test()


## The inspector announced, its saved plan carrying the test numbers; returns
## its id. The visit has not happened yet.
func _announced_inspector() -> int:
	var incident := _presented_major(IncidentCatalogue.INSPECTOR)
	var data := _director.to_snapshot()
	for saved: Dictionary in data["incidents"]:
		if saved["id"] == incident["id"]:
			saved["plan"]["pass_money"] = PASS_MONEY
			saved["plan"]["fail_half_stars"] = FAIL_HALF_STARS
			saved["plan"]["max_messes"] = MAX_MESSES
	assert_bool(_director.from_snapshot(data)).is_true()
	assert_object(_rail.notice_card(IncidentCards.key_of(incident))).is_null()
	return incident["id"]


func _visit(id: int) -> void:
	_director.on_tick(_record(id)["plan"]["visit_tick"])


func _words(id: int) -> String:
	var card := _rail.notice_card(IncidentCards.key_of({"id": id}))
	assert_object(card).is_not_null()
	var parts := PackedStringArray()
	for label in card.find_children("*", "Label", true, false):
		parts.append((label as Label).text)
	return "\n".join(parts)


func test_a_passed_visit_posts_a_card_that_names_the_reward() -> void:
	var id := _announced_inspector()
	var before := _balance()
	_visit(id)
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.PASSED)
	assert_int(_balance()).is_equal(before + PASS_MONEY)
	var text := _words(id)
	print(text)
	assert_str(text).contains("The inspector was happy")
	assert_str(text).contains("You earn 123 money")
	assert_str(text).not_contains("%d" % IncidentTuning.INSPECTOR_PASS_MONEY)
	assert_bool(_world.clock.holds.is_holding()).is_false()


func test_a_failed_visit_posts_a_card_that_names_the_reason_and_the_drop() -> void:
	var id := _announced_inspector()
	_add_messes(MAX_MESSES + 1)
	_visit(id)
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.FAILED)
	var text := _words(id)
	print(text)
	assert_str(text).contains("The inspector was not happy")
	assert_str(text).contains("more than 3 messes")
	assert_str(text).contains("full queue")
	assert_str(text).contains("Your rating drops by 1.5 stars")
	assert_bool(_world.clock.holds.is_holding()).is_false()


func test_the_visit_posts_one_card_and_a_later_tick_posts_no_other() -> void:
	var id := _announced_inspector()
	_visit(id)
	var key := IncidentCards.key_of({"id": id})
	var first := _rail.notice_card(key)
	assert_object(first).is_not_null()
	var visit: int = _record(id)["plan"]["visit_tick"]
	_director.on_tick(visit + 1)
	_director.on_tick(visit + 100)
	assert_object(_rail.notice_card(key)).is_same(first)


func test_the_card_comes_back_after_the_rail_resets() -> void:
	var id := _announced_inspector()
	_add_messes(MAX_MESSES + 1)
	_visit(id)
	var key := IncidentCards.key_of({"id": id})
	_rail.reset()
	assert_object(_rail.notice_card(key)).is_not_null()
	assert_str(_words(id)).contains("The inspector was not happy")


func test_the_card_comes_back_after_the_director_loads() -> void:
	var id := _announced_inspector()
	_visit(id)
	var key := IncidentCards.key_of({"id": id})
	var saved := JSON.parse_string(JSON.stringify(_director.to_snapshot())) as Dictionary
	_rail.drop_notice(key)
	assert_bool(_director.from_snapshot(saved)).is_true()
	assert_object(_rail.notice_card(key)).is_not_null()
	assert_str(_words(id)).contains("You earn 123 money")


func test_an_inspector_still_waiting_posts_no_card() -> void:
	var id := _announced_inspector()
	_rail.reset()
	_director.restored.emit()
	assert_object(_rail.notice_card(IncidentCards.key_of({"id": id}))).is_null()
