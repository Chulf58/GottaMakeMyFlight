class_name TestIncidentCardsVip
extends MajorTestBase
## The result cards of a VIP (IncidentCards, board 3717fc7d): every outcome of
## an accepted VIP posts exactly one rail card (green when the VIP made the
## flight, coral when they missed it) with the plan's
## numbers (bonus, made without the bonus, missed), no pause, and the card
## comes back when the rail resets or the director loads. A VIP whose flight
## is dropped posts none.

## The VIP's plan numbers, none of them the tuning's, so a card that read
## IncidentTuning instead of the saved plan would say the wrong thing.
const BONUS := 123
const GOOD_MOOD := 90
const MISS_HALF_STARS := 3
const PLAN := {"bonus": BONUS, "good_mood": GOOD_MOOD, "miss_half_stars": MISS_HALF_STARS}

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


## The VIP (PLAN) on its flight, finished: made or missed, at `mood`. The card
## never pauses the clock: it is neither held nor changed in speed. Returns the
## incident id.
func _finished_vip(made: bool, mood: int) -> int:
	var id := _accepted_vip(VIP_FLIGHT, PLAN)
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	var p := _world.sim.get_passenger(vip)
	p.mood = mood
	var speed := _world.clock.speed
	var paused := _world.clock.paused
	PassengerLifecycle.finish(_world.sim, p, made)
	assert_object(_rail.notice_card(IncidentCards.key_of({"id": id}))).is_not_null()
	assert_bool(_world.clock.holds.is_holding()).is_false()
	assert_int(_world.clock.speed).is_equal(speed)
	assert_bool(_world.clock.paused).is_equal(paused)
	return id


func _words(id: int) -> String:
	var card := _rail.notice_card(IncidentCards.key_of({"id": id}))
	assert_object(card).is_not_null()
	var parts := PackedStringArray()
	for label in card.find_children("*", "Label", true, false):
		parts.append((label as Label).text)
	return "\n".join(parts)


func test_a_vip_who_makes_it_in_a_good_mood_posts_a_bonus_card() -> void:
	var id := _finished_vip(true, GOOD_MOOD)
	var text := _words(id)
	print(text)
	assert_str(text).contains("The VIP made the flight")
	assert_str(text).contains("good mood")
	assert_str(text).contains("You earn 123 money")
	assert_str(text).not_contains("%d" % IncidentTuning.VIP_BONUS_MONEY)


func test_a_vip_who_makes_it_in_a_low_mood_posts_a_no_bonus_card() -> void:
	var id := _finished_vip(true, GOOD_MOOD - 1)
	var text := _words(id)
	print(text)
	assert_str(text).contains("The VIP made the flight")
	assert_str(text).contains("no bonus")
	assert_str(text).contains("below 90 when boarding")
	assert_str(text).not_contains("%d" % IncidentTuning.VIP_GOOD_MOOD)
	assert_str(text).not_contains("money")


func test_a_vip_who_misses_posts_a_rating_card() -> void:
	var id := _finished_vip(false, GOOD_MOOD)
	var text := _words(id)
	print(text)
	assert_str(text).contains("The VIP missed the flight")
	assert_str(text).contains("Your rating drops by 1.5 stars")


func test_an_outcome_posts_one_card_and_a_repeat_posts_no_other() -> void:
	var id := _finished_vip(true, GOOD_MOOD)
	var key := IncidentCards.key_of({"id": id})
	var first := _rail.notice_card(key)
	assert_object(first).is_not_null()
	_world.sim.outcome.emit(_record(id)["plan"]["target"], true)
	assert_object(_rail.notice_card(key)).is_same(first)


func test_a_vip_whose_flight_is_dropped_posts_no_card() -> void:
	var id := _accepted_vip(VIP_FLIGHT)
	var closed := _world.flights.state_start(VIP_FLIGHT, FlightSim.State.PUSHBACK)
	_world.run_to(closed + 1)
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.NOT_HELD)
	assert_object(_rail.notice_card(IncidentCards.key_of({"id": id}))).is_null()


func test_the_result_card_comes_back_after_the_rail_resets() -> void:
	var id := _finished_vip(false, 10)
	var key := IncidentCards.key_of({"id": id})
	_rail.reset()
	assert_object(_rail.notice_card(key)).is_not_null()
	assert_str(_words(id)).contains("The VIP missed the flight")


func test_the_result_card_comes_back_after_the_director_loads() -> void:
	var id := _finished_vip(true, GOOD_MOOD)
	var key := IncidentCards.key_of({"id": id})
	var saved := JSON.parse_string(JSON.stringify(_director.to_snapshot())) as Dictionary
	_rail.drop_notice(key)
	assert_bool(_director.from_snapshot(saved)).is_true()
	assert_object(_rail.notice_card(key)).is_not_null()
	assert_str(_words(id)).contains("The VIP made the flight")


## Good news is a green rail card (the flight result card's look), a missed
## flight a coral one (decision hud-grid-and-rails-one-spacing-grid-centred-
## top-row-right-ra, colour meanings per 0b50e074).
func test_a_vip_who_makes_it_posts_a_green_card_with_or_without_the_bonus() -> void:
	for mood in [GOOD_MOOD, GOOD_MOOD - 1]:
		var id := _finished_vip(true, mood)
		var card := _rail.notice_card(IncidentCards.key_of({"id": id})) as PanelContainer
		assert_str(card.theme_type_variation).is_equal("HudCardGreen")
		assert_bool(card.has_theme_stylebox_override("panel")).is_false()


func test_a_vip_who_misses_posts_a_coral_card() -> void:
	var id := _finished_vip(false, GOOD_MOOD)
	var card := _rail.notice_card(IncidentCards.key_of({"id": id})) as PanelContainer
	assert_str(card.theme_type_variation).is_equal("HudCardCoral")
