class_name TestFlightResultDrama
extends GdUnitTestSuite
## FlightResultPanel card colour tiers (green / cream / coral matching
## IncidentCards ed443eea) and the translated close-call saves line (board
## ccbc48f5).

var _translation: Translation


func after_test() -> void:
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null


func _summary(made: int, missed: int, close_calls := 0) -> Dictionary:
	return {
		"flight": "GMF101",
		"made": made,
		"missed": missed,
		"close_calls": close_calls,
		"reasons": [],
	}


func test_result_card_colours_match_miss_tiers() -> void:
	var card := auto_free(FlightResultPanel.new()) as FlightResultPanel
	add_child(card)
	# Zero misses -> green.
	card.show_result(_summary(5, 0))
	assert_str(String(card.theme_type_variation)).is_equal("HudCardGreen")
	# Partial misses (made > missed) -> ordinary cream card (no variation).
	card.show_result(_summary(6, 2))
	assert_str(String(card.theme_type_variation)).is_equal("")
	# Heavy misses (made <= missed, including tie and zero made) -> coral.
	card.show_result(_summary(3, 3))
	assert_str(String(card.theme_type_variation)).is_equal("HudCardCoral")
	card.show_result(_summary(0, 4))
	assert_str(String(card.theme_type_variation)).is_equal("HudCardCoral")


func test_close_call_line_is_shown_when_positive_and_translated() -> void:
	var none := FlightResultPanel.text_for(_summary(4, 0, 0))
	assert_str(none).not_contains("last second")
	var one := FlightResultPanel.text_for(_summary(4, 0, 1))
	assert_str(one).contains("1 made it at the last second!")
	var many := FlightResultPanel.text_for(_summary(4, 0, 3))
	assert_str(many).contains("3 made it at the last second!")
	# Plural translation path (tr_n / translate_plural is not pseudolocalized).
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_plural_message(
		"{count} made it at the last second!",
		["{count} just made it!", "{count} all just made it!"]
	)
	TranslationServer.add_translation(_translation)
	assert_str(FlightResultPanel.text_for(_summary(4, 0, 1))).contains("1 just made it!")
	assert_str(FlightResultPanel.text_for(_summary(4, 0, 3))).contains("3 all just made it!")
