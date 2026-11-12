class_name TestIncidentPanelCopy
extends GdUnitTestSuite
## The words of the four major incidents in the panel (IncidentCatalogue.
## panel_copy, IncidentCopy.fill; board 03e71ed7): each says the cause, the
## reward and the failure, with the numbers of the incident's own saved plan.
## A MajorTestDirector holds the records, the real catalogue gives the words.

const DEPARTS := 60_000

var _k := IncidentPanelKit.new()


func before_test() -> void:
	_k.build(self)
	_k.panel.copy_for = IncidentCatalogue.panel_copy


func after_test() -> void:
	_k.port.free()


## A major of `kind` with `plan`, presented, and the open dialog's words.
func _words(kind: String, plan: Dictionary) -> String:
	var id := _k.director.add_scheduled(kind, plan)
	assert_bool(_k.director.present(id, IncidentCatalogue.is_offer(kind))).is_true()
	assert_bool(_k.panel.is_open()).is_true()
	return _k.panel.dialog().body_text()


func test_a_rush_card_names_the_counts_the_reward_and_the_failure() -> void:
	var plan := {
		"flights":
		[
			{"flight": "AM-d2", "extra": 4, "departs": DEPARTS},
			{"flight": "BM-d2", "extra": 6, "departs": DEPARTS + 6000},
		],
		"total": 10,
		"until": 79_200,
	}
	var text := _words(IncidentCatalogue.RUSH, plan)
	print(text)
	assert_str(text).contains("10 extra passengers")
	assert_str(text).contains("2 of tomorrow's flights")
	assert_str(text).contains(
		"%s +4, %s +6" % [GameCalendar.clock_text(DEPARTS), GameCalendar.clock_text(DEPARTS + 6000)]
	)
	assert_str(text).contains("Reward:")
	assert_str(text).contains("If it fails:")
	assert_str(text).contains(IncidentPanel.ANNOUNCE_FOOTER)
	assert_str(text).not_contains("{")
	assert_object(_k.panel.dialog().continue_button()).is_not_null()


func test_an_inspector_card_names_the_window_the_reward_and_the_failure() -> void:
	var plan := {"window_from": 50_000, "window_to": 58_000, "visit_tick": 52_000}
	var text := _words(IncidentCatalogue.INSPECTOR, plan)
	print(text)
	assert_str(text).contains(GameCalendar.clock_text(50_000))
	assert_str(text).contains(GameCalendar.clock_text(58_000))
	assert_str(text).contains("%d money" % IncidentTuning.INSPECTOR_PASS_MONEY)
	assert_str(text).contains("at most %d messes" % IncidentTuning.INSPECTOR_MAX_MESSES)
	assert_str(text).contains("your rating drops by 1 star")
	assert_str(text).not_contains("{")


func test_a_vip_offer_names_the_flight_the_bonus_and_the_penalty() -> void:
	var plan := {"flight": "AM-d1", "departs": DEPARTS, "bonus": 500, "target": 0}
	var text := _words(IncidentCatalogue.VIP, plan)
	print(text)
	assert_str(text).contains("the %s flight" % GameCalendar.clock_text(DEPARTS))
	assert_str(text).contains("Reward: 500 money if the VIP makes the flight in a good mood.")
	assert_str(text).contains("If it fails: your rating drops by 1 star")
	assert_str(text).contains(IncidentPanel.OFFER_FOOTER)
	assert_object(_k.panel.dialog().accept_button()).is_not_null()


func test_a_favour_offer_names_the_passengers_the_money_and_the_failure() -> void:
	var plan := {"flight": "AM-d1", "departs": DEPARTS, "extra": 4, "bonus": 300}
	var text := _words(IncidentCatalogue.FAVOUR, plan)
	print(text)
	assert_str(text).contains("fit 4 more passengers")
	assert_str(text).contains("Reward: 300 money now, and 4 more passengers")
	assert_str(text).contains("If it fails: the extra passengers need check-in")
	assert_str(text).not_contains("{")


func test_the_penalty_words_follow_the_half_stars() -> void:
	assert_str(IncidentCopy.stars_text(1)).is_equal("half a star")
	assert_str(IncidentCopy.stars_text(2)).is_equal("1 star")
	assert_str(IncidentCopy.stars_text(3)).is_equal("1.5 stars")
	assert_str(IncidentCopy.stars_text(4)).is_equal("2 stars")
