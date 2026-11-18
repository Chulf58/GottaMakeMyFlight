class_name TestWorldCaptionTranslation
extends GdUnitTestSuite
## Every world caption and sign text reaches its Label3D or hover text through
## tr() at display time (board t7, decision translation-format-po-gettext-files-
## with-tr-and-tr-n-for-all). Pseudolocalization is the proof: a string that
## skips tr() comes back without the "[_" lead. The English text stays the key
## the logic compares with. The sign, bubble, pop, room and land captions are
## checked in their own suites (test_miss_markers, test_calm_bubbles,
## test_cafe_views, test_room_view, test_build_mode_buy_land).

## Scripts whose tr() calls this suite expects in messages.pot.
const ROUTED := [
	"res://airside/apron_stand.gd",
	"res://airside/gate_links_view.gd",
	"res://airside/gate_walk.gd",
	"res://build/land_tool.gd",
	"res://passengers/bubble_words.gd",
	"res://passengers/cafe_pops.gd",
	"res://passengers/miss_markers.gd",
]


func after_test() -> void:
	PseudoLocale.disable()


## "[___Gate A___]" becomes "Gate A___]": the lead is checked here, the text by
## the caller.
func _bare(text: String) -> String:
	assert_str(text).starts_with("[")
	return text.lstrip("[_")


func test_the_gate_caption_lines_are_whole_translated_sentences() -> void:
	assert_str(GateLinksView.caption_text("A", "large", 12)).is_equal(
		"Gate A\nup to large planes\n12 min walk"
	)
	assert_str(GateLinksView.caption_text("B", "", GateWalk.NO_ROUTE)).is_equal(
		"Gate B\nno room for a plane"
	)
	PseudoLocale.enable(0.4)
	var lines := GateLinksView.caption_text("A", "large", 12).split("\n")
	print("gate caption lines: %s" % [lines])
	assert_int(lines.size()).is_equal(3)
	assert_str(_bare(lines[0])).starts_with("Gate A")
	assert_str(_bare(lines[1])).starts_with("up to large planes")
	assert_str(_bare(lines[2])).starts_with("12 min walk")
	assert_str(_bare(GateWalk.caption_line(5))).starts_with("5 min walk")
	assert_str(GateWalk.caption_line(GateWalk.NO_ROUTE)).is_equal("")
	var no_room := GateLinksView.caption_text("B", "", GateWalk.NO_ROUTE).split("\n")
	assert_str(_bare(no_room[1])).starts_with("no room for a plane")


func test_every_plane_class_has_its_own_caption_line() -> void:
	PseudoLocale.enable(0.4)
	var seen := {}
	for plane_class: String in [PlaneClasses.SMALL, PlaneClasses.MEDIUM, PlaneClasses.LARGE]:
		var line := GateLinksView.caption_text("A", plane_class).split("\n")[1]
		assert_str(_bare(line)).starts_with("up to %s planes" % plane_class)
		seen[line] = true
	assert_int(seen.size()).is_equal(3)


func test_the_unlinked_sign_reasons_are_whole_translated_sentences() -> void:
	var cases := {
		GateDesks.Unlinked.NO_EXIT:
		[
			"Unlinked: no exit facing the planes in %d cells" % GateDesks.LINK_CELLS,
			{"why": GateDesks.Unlinked.NO_EXIT, "gate": ""}
		],
		GateDesks.Unlinked.EXIT_TAKEN:
		["Unlinked: Gate B uses the exit", {"why": GateDesks.Unlinked.EXIT_TAKEN, "gate": "B"}],
		GateDesks.Unlinked.STAND_OVERLAP:
		[
			"Unlinked: stand would overlap Gate C",
			{"why": GateDesks.Unlinked.STAND_OVERLAP, "gate": "C"}
		],
		GateDesks.Unlinked.NO_ROOM:
		["Unlinked: no room for a plane", {"why": GateDesks.Unlinked.NO_ROOM, "gate": ""}],
		GateDesks.Unlinked.ROUTE_BLOCKED:
		[
			"Unlinked: way to the lane blocked",
			{"why": GateDesks.Unlinked.ROUTE_BLOCKED, "gate": ""}
		],
		GateDesks.Unlinked.NO_LETTER:
		["Unlinked: every gate letter in use", {"why": GateDesks.Unlinked.NO_LETTER, "gate": ""}],
	}
	for why: int in cases:
		assert_str(GateLinksView.caption_for(cases[why][1])).is_equal(cases[why][0])
	PseudoLocale.enable(0.4)
	for why: int in cases:
		var shown := GateLinksView.caption_for(cases[why][1])
		print("unlinked %d: '%s'" % [why, shown])
		assert_str(_bare(shown)).starts_with(cases[why][0])


func test_the_apron_labels_say_their_words_in_the_players_language() -> void:
	var stand := auto_free(ApronStand.new()) as ApronStand
	stand.gate_stands = {
		"A": {"placement": {"status": StandPlacement.UNAVAILABLE, "warning": false}},
		"B": {"placement": {"status": StandPlacement.OK, "warning": true, "walk_m": 41.6}},
		"C": {"placement": {"status": StandPlacement.OK, "warning": false}},
	}
	stand.placement = {"status": StandPlacement.UNAVAILABLE}
	assert_str(stand.gate_status_text("A")).is_equal(
		"Gate A: no usable stand. Keep its apron and the walk to it clear"
	)
	assert_str(stand.gate_status_text("B")).is_equal("Gate B: long walk to the plane: 42 m")
	assert_str(stand.gate_status_text("C")).is_equal("")
	assert_str(stand.status_text()).is_equal(
		"No usable stand: no exit facing the planes has a clear apron"
	)
	PseudoLocale.enable(0.4)
	print("apron: '%s' | '%s'" % [stand.gate_status_text("A"), stand.gate_status_text("B")])
	assert_str(_bare(stand.gate_status_text("A"))).starts_with("Gate A: no usable stand.")
	assert_str(_bare(stand.gate_status_text("B"))).starts_with(
		"Gate B: long walk to the plane: 42 m"
	)
	assert_str(stand.gate_status_text("C")).is_equal("")
	assert_str(_bare(stand.status_text())).starts_with("No usable stand: no exit facing")
	stand.placement = {"status": StandPlacement.OK, "warning": true, "longest_walk_m": 17.2}
	assert_str(_bare(stand.status_text())).starts_with("Long walk to the plane: 17 m")


func test_the_closed_sign_words_are_translated_and_the_english_keys_stay() -> void:
	var english := {
		MissSignals.NO_STAFF_REASON: MissMarkers.CLOSED_TEXT,
		MissSignals.PLAYER_CLOSED_REASON: MissMarkers.PLAYER_CLOSED_TEXT,
		MissSignals.SPOT_BLOCKED_REASON: MissMarkers.SPOT_BLOCKED_TEXT,
	}
	for reason: String in english:
		assert_str(MissMarkers.closed_look(reason, "desk")[1]).is_equal(english[reason])
	assert_str(MissMarkers.closed_caption()).is_equal(MissMarkers.CLOSED_CAPTION)
	var reach := {
		"desk": "Closed · staff can't reach the desk",
		"scanner": "Closed · staff can't reach the scanner",
		"counter": "Closed · staff can't reach the counter",
	}
	for noun: String in reach:
		var look := MissMarkers.closed_look(MissSignals.UNREACHABLE_REASON, noun)
		assert_str(look[1]).is_equal(reach[noun])
	PseudoLocale.enable(0.4)
	for reason: String in english:
		var shown: String = MissMarkers.closed_look(reason, "desk")[1]
		print("closed %s: '%s'" % [reason, shown])
		assert_str(_bare(shown)).starts_with(english[reason])
	for noun: String in reach:
		var look := MissMarkers.closed_look(MissSignals.UNREACHABLE_REASON, noun)
		assert_str(_bare(look[1])).starts_with(reach[noun])
	assert_str(_bare(MissMarkers.closed_caption())).starts_with("Closed")


func test_every_speech_bubble_text_has_a_translation() -> void:
	var sim_texts: Array[String] = [
		BubbleDeclutter.LATE_TEXT,
		"Missed my flight!",
		"Where is check-in?",
		"Where is security?",
		"Queue full",
		"I can't get there",
		"The exit is blocked",
		"The gate is full",
		"Check-in is closed",
		"Security is closed",
	]
	assert_array(BubbleWords.msgids()).contains_exactly_in_any_order(sim_texts)
	assert_str(BubbleWords.say("")).is_equal("")
	for text in sim_texts:
		assert_str(BubbleWords.say(text)).is_equal(text)
	PseudoLocale.enable(0.4)
	for text in sim_texts:
		assert_str(_bare(BubbleWords.say(text))).starts_with(text)
	assert_str(BubbleWords.say("")).is_equal("")
	# The English text still ranks the late bubble first.
	assert_int(BubbleDeclutter.tier_of(BubbleDeclutter.LATE_TEXT)).is_equal(0)
	assert_int(BubbleDeclutter.tier_of(BubbleWords.say(BubbleDeclutter.LATE_TEXT))).is_equal(1)


## What the POT must hold for each tr() and tr_n() call in `source`: one entry with
## the full msgctxt, msgid (and msgid_plural for tr_n) text, as {"ctx", "id", "plural"}.
## tr(msgid, context) has its context as argument 2; tr_n(singular, plural, n,
## context) has it as argument 4.
func _wanted_entries(source: String) -> Array[Dictionary]:
	var string_arg := '"((?:[^"\\\\]|\\\\.)*)"'
	var tr_pattern := RegEx.create_from_string(
		"\\btr\\(\\s*" + string_arg + "\\s*(?:,\\s*" + string_arg + ")?"
	)
	var tr_n_pattern := RegEx.create_from_string(
		"\\btr_n\\(\\s*" + string_arg + "\\s*,\\s*" + string_arg + "\\s*,[^,]*,\\s*" + string_arg
	)
	var wanted: Array[Dictionary] = []
	for found in tr_pattern.search_all(source):
		wanted.append({"ctx": found.get_string(2), "id": found.get_string(1), "plural": ""})
	for found in tr_n_pattern.search_all(source):
		wanted.append(
			{"ctx": found.get_string(3), "id": found.get_string(1), "plural": found.get_string(2)}
		)
	return wanted


## The wanted entries the template does not hold exactly once with a msgstr line.
func _missing_entries(source: String, template: String) -> Array[String]:
	var entries := PotEntries.parse(template)
	var missing: Array[String] = []
	for want in _wanted_entries(source):
		if (
			PotEntries.count(entries, want["ctx"], want["id"], want["plural"]) != 1
			or (PotEntries.complete(entries, want["ctx"], want["id"], want["plural"]) != 1)
		):
			missing.append(str(want))
	return missing


## Every tr() and tr_n() call in the routed scripts has its msgid, context and
## (for tr_n) plural in the POT, so the extractor and the template agree.
func test_every_routed_msgid_is_in_the_template() -> void:
	var template := FileAccess.get_file_as_string("res://locale/messages.pot").replace("\r\n", "\n")
	var checked := 0
	var missing: Array[String] = []
	for path: String in ROUTED:
		var source := FileAccess.get_file_as_string(path)
		checked += _wanted_entries(source).size()
		for entry in _missing_entries(source, template):
			missing.append("%s: %s" % [path, entry])
	print("routed tr() calls checked: %d, missing: %s" % [checked, missing])
	assert_int(checked).is_greater(30)
	assert_array(missing).is_empty()


## Control: the check fails when the template has only the singular entry of a
## tr_n() call, the wrong context, a repeat or no msgstr, so it cannot pass by accident.
func test_the_template_check_catches_a_missing_plural_context_or_msgstr() -> void:
	var text := "Queue full · {count} waiting"
	var source := 'tr_n("%s", "%s", n, "sign text")' % [text, text]
	var context := 'msgctxt "sign text"\n'
	var singular := 'msgid "%s"\n' % text
	var plural := 'msgid_plural "%s"\n' % text
	var whole := context + singular + plural + 'msgstr[0] ""\nmsgstr[1] ""\n'
	assert_array(_missing_entries(source, whole)).is_empty()
	# Only the singular entry: the plural is missing.
	assert_array(_missing_entries(source, context + singular + 'msgstr ""\n')).has_size(1)
	# No context.
	assert_array(_missing_entries(source, singular + plural + 'msgstr[0] ""\n')).has_size(1)
	# A different plural.
	var other := context + singular + 'msgid_plural "other"\nmsgstr[0] ""\n'
	assert_array(_missing_entries(source, other)).has_size(1)
	# No msgstr line.
	assert_array(_missing_entries(source, context + singular + plural)).has_size(1)
	# The same entry twice.
	assert_array(_missing_entries(source, whole + "\n" + whole)).has_size(1)
