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
	["", "{count} station is closed · staff are on the way"],
]
const STAGE_2_3_ENTRIES := [
	["", "Achievement Unlocked"],
	["", "Airport Certification"],
	["", "Certification tracking is not active."],
	["", "Unrated"],
	["", "Certified {star}★: {title}"],
	["", "Your airport earned {star}★ {title} certification!"],
	["", "Year {year} Airport Awards"],
	["", "Sandbox"],
	["", "{slot}, {time} (Sandbox)"],
	["", "Career"],
	["", "Free-Build Sandbox"],
	["", "Unlimited Funds"],
	["", "All Tiers & Land Unlocked"],
	["menu", "Start Airport"],
	["mood overlay mode", "Congestion"],
	["mood overlay mode", "Prestige"],
	["", "floor congestion: light flow to bottleneck"],
	["", "room prestige level"],
	["", "Light"],
	["", "Busy"],
	["", "Congested"],
	["", "Lv. 1"],
	["", "Lv. 5"],
	["", "Prestige: Lv. {level} / 5 ({score} pts · +{bonus}% spend)"],
	["", "Prestige: Lv. {level} / 5 ({score} pts · +{bonus}% recovery)"],
	["", "Size {size} · Setup {setup} · Decor {decor} · Awards {trophy}"],
	["", "Add decor or trophies to raise prestige"],
	["", "Lv. {level}"],
	["", "Train ${cost}"],
	["", "Upgrade work speed to +{pct}%"],
	["", "Max"],
	["", "On break {pct}%"],
	["", "Tired {pct}%"],
	["", "Energy {pct}%"],
	["", "Morning Peak +15%"],
	["", "Evening Peak +15%"],
	["", "Peak"],
	["", "Bronze +5%"],
	["", "Silver +10%"],
	["", "Gold +15%"],
	["", "Hub Contract"],
	["", "Hub"],
	["", "Peak rush wave: +15% passenger fee included."],
	["", "Fixed speed"],
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


func test_stage_2_and_3_entries_are_in_the_template() -> void:
	var entries := _entries()
	assert_array(PotEntries.malformed(entries)).is_empty()
	assert_array(PotEntries.duplicates(entries)).is_empty()
	var pairs := STAGE_2_3_ENTRIES.duplicate()
	for level: Dictionary in AirportCertification.LEVELS:
		pairs.append(["", str(level["title"])])
	for item: Dictionary in Achievements.CATALOG:
		pairs.append(["", str(item["title"])])
		pairs.append(["", str(item["description"])])
	for cat: Dictionary in AirportAwards.CATEGORIES:
		pairs.append(["", str(cat["title"])])
	var missing := []
	for pair: Array in pairs:
		var complete := PotEntries.complete(entries, pair[0], pair[1])
		if complete != 1:
			missing.append([pair[0], pair[1], complete])
	print("missing stage 2/3 msgids: %s" % [missing])
	assert_array(missing).is_empty()
	(
		assert_int(
			PotEntries.complete(
				entries,
				"",
				"Total awarded: +${cash} · {count} Award Trophy unlocked",
				"Total awarded: +${cash} · {count} Award Trophies unlocked"
			)
		)
		. is_equal(1)
	)
