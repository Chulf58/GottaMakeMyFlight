class_name TestListWords
extends GdUnitTestSuite
## ListWords joins names into one list whose grammar the translator owns (board
## T13): a two-item msgid and a start, middle and end join for three or more,
## each in its own context, following CLDR's list patterns. English adds "and"
## before the last name; a run-time Translation proves every join is its own msgid.

var _translation: Translation


func after_test() -> void:
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null


func _translate_joins() -> void:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_message("{first} and {second}", "{first} und {second}", "list of two")
	_translation.add_message("{first}, {rest}", "{first}; {rest}", "list start")
	_translation.add_message("{item}, {rest}", "{item} / {rest}", "list middle")
	_translation.add_message("{item} and {last}", "{item} & {last}", "list end")
	TranslationServer.add_translation(_translation)


func test_english_lists_of_none_one_two_three_and_four() -> void:
	assert_str(ListWords.join(PackedStringArray())).is_equal("")
	assert_str(ListWords.join(PackedStringArray(["Oslo"]))).is_equal("Oslo")
	assert_str(ListWords.join(PackedStringArray(["Oslo", "Rome"]))).is_equal("Oslo and Rome")
	assert_str(ListWords.join(PackedStringArray(["Oslo", "Rome", "Paris"]))).is_equal(
		"Oslo, Rome and Paris"
	)
	assert_str(ListWords.join(PackedStringArray(["a", "b", "c", "d"]))).is_equal("a, b, c and d")


func test_each_join_is_its_own_translated_msgid() -> void:
	_translate_joins()
	var one := ListWords.join(PackedStringArray(["Oslo"]))
	var two := ListWords.join(PackedStringArray(["Oslo", "Rome"]))
	var three := ListWords.join(PackedStringArray(["Oslo", "Rome", "Paris"]))
	var five := ListWords.join(PackedStringArray(["a", "b", "c", "d", "e"]))
	print("one: %s | two: %s | three: %s | five: %s" % [one, two, three, five])
	assert_str(one).is_equal("Oslo")
	assert_str(two).is_equal("Oslo und Rome")
	assert_str(three).is_equal("Oslo; Rome & Paris")
	assert_str(five).is_equal("a; b / c / d & e")


## The unlock guide's "Also new" line lists its pieces through ListWords, so the
## translator's joins reach it and no bare ", " stays between two names.
func test_the_also_new_line_lists_its_pieces_in_the_translated_grammar() -> void:
	var english := UnlockFamilies.lines([2])[5]
	_translate_joins()
	var shown := UnlockFamilies.lines([2])[5]
	print("english: %s | translated joins: %s" % [english, shown])
	assert_str(english).starts_with("Also new: ").ends_with(".")
	assert_str(english).contains(" and ")
	assert_str(shown).contains("; ").contains(" & ")
	assert_str(shown).not_contains(", ").not_contains(" and ")


## Every join is in messages.pot once, with its own context and a msgstr.
func test_every_join_is_in_the_template_once() -> void:
	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	var joins := [
		["list of two", "{first} and {second}"],
		["list start", "{first}, {rest}"],
		["list middle", "{item}, {rest}"],
		["list end", "{item} and {last}"],
	]
	var counts := {}
	for pair: Array in joins:
		counts[pair[1]] = [
			PotEntries.count(entries, pair[0], pair[1]),
			PotEntries.complete(entries, pair[0], pair[1]),
		]
	print("join entries (count, with msgstr): %s" % [counts])
	for pair: Array in joins:
		assert_array(counts[pair[1]]).override_failure_message(pair[1]).is_equal([1, 1])
	assert_int(PotEntries.count(entries, "list separator", ", ")).is_equal(0)
