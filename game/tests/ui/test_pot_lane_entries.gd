class_name TestPotLaneEntries
extends GdUnitTestSuite
## The strings the D3a, D3b, D3d and version lanes added are in messages.pot
## once each: the hint sentences, the Show me button, the passenger card's bag
## and trip lines, the short-queue alert and sign words, the Hire wage button and
## the version label. The sentences that have a Words list (msgids()) are read
## from it, so a new line there that skips the template fails here.

## The English msgids of the short-queue alert and sign words, with their context.
const SHORT_QUEUE := [
	["", "{count} desk full · {waiting} waiting · short queue: move the desk away from the wall"],
	[
		"",
		"{count} lane full · {waiting} waiting · short queue: move the scanner away from the wall"
	],
	["sign text", "Queue full · {count} waiting · short queue: move the desk away from the wall"],
	[
		"sign text",
		"Queue full · {count} waiting · short queue: move the scanner away from the wall"
	],
	[
		"sign text",
		"Queue full · {count} waiting · short queue: move the counter away from the wall"
	],
]
const OTHERS := [
	["", "Show me"],
	["", "v{version}"],
	["staff button", "Hire · {wage}/day"],
]


func _entries() -> Array[Dictionary]:
	return PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))


func _missing(pairs: Array) -> Array:
	var entries := _entries()
	var out := []
	for pair: Array in pairs:
		var count := 0
		for entry in entries:
			if entry.get("ctx", "") == pair[0] and entry.get("id", "") == pair[1]:
				count += 1
		if count != 1:
			out.append([pair[1], count])
	return out


func _plain(ids: PackedStringArray) -> Array:
	var pairs := []
	for id in ids:
		pairs.append(["", id])
	return pairs


func test_the_hint_sentences_are_in_the_template() -> void:
	PseudoLocale.disable()
	var missing := _missing(_plain(HintRules.Words.new().msgids()))
	print("missing hint msgids: %s" % [missing])
	assert_array(missing).is_empty()
	for id in [HintRules.PLACE_GATE_DESK, HintRules.PLACE_SEATS, HintRules.FOLLOW_PASSENGER]:
		assert_array(_missing([["", HintRules.TEXT[id]]])).is_empty()


func test_the_passenger_card_bag_and_trip_lines_are_in_the_template() -> void:
	PseudoLocale.disable()
	var missing := _missing(_plain(PassengerBags.Words.new().msgids()))
	missing.append_array(_missing(_plain(PassengerTrip.Words.new().msgids())))
	print("missing card msgids: %s" % [missing])
	assert_array(missing).is_empty()


func test_the_short_queue_words_the_wage_button_and_the_version_are_in_the_template() -> void:
	var missing := _missing(SHORT_QUEUE)
	missing.append_array(_missing(OTHERS))
	print("missing other msgids: %s" % [missing])
	assert_array(missing).is_empty()
