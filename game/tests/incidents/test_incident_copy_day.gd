class_name TestIncidentCopyDay
extends GdUnitTestSuite
## The day words of the VIP and favour offers (board 3717fc7d): the offer says
## "today's 10:29 flight" or "tomorrow's 10:29 flight" the way the departures
## board heads its days, from the plan's departure and the day the offer was
## made, on both sides of midnight. The VIP offer also says how its mood is
## judged, with the plan's own number.

const FLIGHT_MINUTE := 10 * 60 + 29


func _incident(kind: String, fired: int, departs_day: int) -> Dictionary:
	var plan := {
		"flight": "AM-d%d" % departs_day,
		"departs": GameCalendar.tick_at(departs_day, FLIGHT_MINUTE),
		"bonus": 500,
		"extra": 4,
		"good_mood": 62,
		"miss_half_stars": 2,
	}
	return {"kind": kind, "fire_tick": fired, "plan": plan}


func _vip_words(fired: int, departs_day: int) -> Dictionary:
	var copy := IncidentCatalogue.panel_copy(IncidentCatalogue.VIP)
	return IncidentCopy.fill(copy, _incident(IncidentCatalogue.VIP, fired, departs_day))


func test_a_vip_flight_later_today_is_todays() -> void:
	var words := _vip_words(GameCalendar.tick_at(2, 8 * 60 + 46), 2)
	assert_str(words["body"]).contains("today's 10:29 flight")
	assert_str(words["body"]).not_contains("tomorrow")


func test_a_vip_flight_the_next_day_is_tomorrows() -> void:
	var words := _vip_words(GameCalendar.tick_at(2, 8 * 60 + 46), 3)
	assert_str(words["body"]).contains("tomorrow's 10:29 flight")


func test_the_same_flight_is_tomorrows_before_midnight_and_todays_after() -> void:
	var before := _vip_words(GameCalendar.tick_at(2, 23 * 60 + 50), 3)
	var after := _vip_words(GameCalendar.tick_at(3, 10), 3)
	assert_str(before["body"]).contains("tomorrow's 10:29 flight")
	assert_str(after["body"]).contains("today's 10:29 flight")


func test_the_day_words_are_the_departures_boards_headings() -> void:
	var today := _vip_words(GameCalendar.tick_at(2, 60), 2)["body"] as String
	var tomorrow := _vip_words(GameCalendar.tick_at(2, 60), 3)["body"] as String
	assert_str(today).contains("%s's 10:29" % DeparturesBoard.TODAY_HEADING.to_lower())
	assert_str(tomorrow).contains("%s's 10:29" % DeparturesBoard.TOMORROW_HEADING.to_lower())


func test_a_flight_two_days_ahead_names_its_day_number() -> void:
	var words := _vip_words(GameCalendar.tick_at(2, 60), 4)
	assert_str(words["body"]).contains("day 5's 10:29 flight")


func test_a_favour_names_its_day_the_same_way() -> void:
	var copy := IncidentCatalogue.panel_copy(IncidentCatalogue.FAVOUR)
	var fired := GameCalendar.tick_at(2, 8 * 60 + 46)
	var today := IncidentCopy.fill(copy, _incident(IncidentCatalogue.FAVOUR, fired, 2))
	var tomorrow := IncidentCopy.fill(copy, _incident(IncidentCatalogue.FAVOUR, fired, 3))
	assert_str(today["body"]).contains("onto today's 10:29 flight")
	assert_str(tomorrow["body"]).contains("onto tomorrow's 10:29 flight")
	assert_str(today["body"]).contains("fit 4 more passengers")


func test_the_vip_offer_says_how_the_mood_is_judged() -> void:
	var words := _vip_words(GameCalendar.tick_at(2, 60), 2)
	assert_str(words["reward"]).contains("500 money")
	assert_str(words["reward"]).contains("mood of 62 or higher when boarding")
	assert_str(words["reward"]).not_contains("{")
