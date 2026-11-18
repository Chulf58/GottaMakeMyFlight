class_name TestRemainingTranslation
extends GdUnitTestSuite
## The strings board T11 routed: the departures list's status words and doors
## text, the taxiway works hover words and the passenger inspect card's stuck
## words (decision translation-format-po-gettext-files-with-tr-and-tr-n-for-all).
## Pseudolocalization is the proof: a string that skips tr() comes back without
## the "[" lead. The Debug panel's buttons are dev-only and stay English
## (decision debug-panel-is-for-dev-builds-only-the-hud-s-debug-toggle-an).
## The follow line's bubble is checked in test_hud_translation, the gap-marker
## hover in test_gap_markers.

## The context the departure status words carry (short words, so they have one).
const STATUS_CONTEXT := "departure status"

## Every [context, msgid] T11 added to messages.pot; each must be there once, with a msgstr.
const NEW_ENTRIES := [
	["", "Wall gap · close the outer wall so the roof can go on"],
	["", "Taxiway works: the taxiway moves when the west side is quiet"],
	["", "Taxiway works: the taxiway moves when the east side is quiet"],
	["", "Taxiway works: the taxiway moves when the west side is quiet, forecast {when}"],
	["", "Taxiway works: the taxiway moves when the east side is quiet, forecast {when}"],
	["departure status", "Boarding"],
	["departure status", "Doors closed"],
	["departure status", "Pushback"],
	["departure status", "Taxiing"],
	["departure status", "Taking off"],
	["departure status", "Departed"],
	["", "doors close {time}"],
]

const AFTER_DOORS := {
	FlightSim.State.DOORS_CLOSED: "Doors closed",
	FlightSim.State.PUSHBACK: "Pushback",
	FlightSim.State.TAXI_OUT: "Taxiing",
	FlightSim.State.TAKEOFF: "Taking off",
	FlightSim.State.DEPARTED: "Departed",
}

var _translation: Translation


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	PseudoLocale.disable()
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null


## "[___Boarding___]" becomes "Boarding___]": the lead is checked here, the text by
## the caller.
func _bare(text: String) -> String:
	assert_str(text).starts_with("[")
	return text.lstrip("[_")


func test_the_departure_status_words_are_translated() -> void:
	assert_str(DepartureList.status_word(FlightSim.State.BOARDING)).is_equal("Boarding")
	for state: int in AFTER_DOORS:
		assert_str(DepartureList.status_word(state)).is_equal(AFTER_DOORS[state])
	# A state before boarding has no word: the row shows no status at all.
	assert_str(DepartureList.status_word(FlightSim.State.SCHEDULED)).is_equal("")
	PseudoLocale.enable(0.4)
	assert_str(_bare(DepartureList.status_word(FlightSim.State.BOARDING))).starts_with("Boarding")
	for state: int in AFTER_DOORS:
		var shown := DepartureList.status_word(state)
		print("status %d: '%s'" % [state, shown])
		assert_str(_bare(shown)).starts_with(AFTER_DOORS[state])
	assert_str(DepartureList.status_word(FlightSim.State.SCHEDULED)).is_equal("")


## A run-time Translation for the current locale, one [msgid, msgstr, context] per line:
## it proves the context and the sentence shape, which pseudolocalization cannot.
func _translate(lines: Array) -> void:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	for line: Array in lines:
		_translation.add_message(line[0], line[1], line[2])
	TranslationServer.add_translation(_translation)


func test_the_status_words_are_looked_up_in_the_departure_status_context() -> void:
	var lines := []
	for state: int in AFTER_DOORS:
		lines.append([AFTER_DOORS[state], "ctx:" + AFTER_DOORS[state], STATUS_CONTEXT])
	lines.append(["Boarding", "ctx:Boarding", STATUS_CONTEXT])
	# A context-less entry for the same word must not be the one used.
	lines.append(["Boarding", "plain:Boarding", ""])
	_translate(lines)
	assert_str(DepartureList.status_word(FlightSim.State.BOARDING)).is_equal("ctx:Boarding")
	for state: int in AFTER_DOORS:
		assert_str(DepartureList.status_word(state)).is_equal("ctx:" + AFTER_DOORS[state])
	assert_str(DepartureList.status_word(FlightSim.State.SCHEDULED)).is_equal("")


func test_a_row_carries_the_translated_status_and_doors_text() -> void:
	PseudoLocale.enable(0.4)
	var row := DepartureList._row(
		600, 590, ["Oslo", "Gotta Air"], FlightSim.State.BOARDING, "C1", "A", "C1#0"
	)
	print("row status '%s' line '%s'" % [row["status"], row["line"]])
	assert_str(_bare(row["status"])).starts_with("Boarding")
	assert_str(row["line"]).contains(row["status"])
	assert_str(_bare(DepartureList.doors_text(row))).starts_with(
		"doors close %s" % GameCalendar.clock_text(590)
	)
	# The control: a state with no word leaves the line as the head and airline.
	var quiet := DepartureList._row(
		600, 590, ["Oslo", "Gotta Air"], FlightSim.State.SCHEDULED, "C1", "A", "C1#0"
	)
	assert_str(quiet["status"]).is_equal("")
	assert_str(quiet["line"]).is_equal(quiet["base"])


func test_the_works_hover_words_are_whole_translated_sentences() -> void:
	var west := "Taxiway works: the taxiway moves when the west side is quiet"
	var east := "Taxiway works: the taxiway moves when the east side is quiet"
	assert_str(SideSpurs.works_text(StandPlacement.WEST)).is_equal(west)
	assert_str(SideSpurs.works_text(StandPlacement.EAST)).is_equal(east)
	assert_str(SideSpurs.works_text(StandPlacement.WEST, 600, 0)).is_equal(
		"%s, forecast %s" % [west, RunwayWorks.when_text(600, 0)]
	)
	PseudoLocale.enable(0.4)
	var plain := SideSpurs.works_text(StandPlacement.EAST)
	var forecast := SideSpurs.works_text(StandPlacement.WEST, 600, 0)
	print("works: '%s' | '%s'" % [plain, forecast])
	assert_str(_bare(plain)).starts_with(east)
	assert_str(_bare(forecast)).contains(west)
	assert_str(forecast).contains("forecast")
	# The forecast time is the translated clock phrase, so it carries its own lead.
	assert_str(forecast).contains("[")
	assert_str(forecast.substr(forecast.find("forecast"))).contains("[")


## Each works sentence, with and without a forecast, is one whole msgid: the run-time
## Translation holds all four and the forecast time is the only thing put into them.
func test_each_works_sentence_is_one_whole_msgid_with_and_without_a_forecast() -> void:
	var west := "Taxiway works: the taxiway moves when the west side is quiet"
	var east := "Taxiway works: the taxiway moves when the east side is quiet"
	_translate(
		[
			[west, "W", ""],
			[east, "E", ""],
			[west + ", forecast {when}", "W laeter {when}", ""],
			[east + ", forecast {when}", "E laeter {when}", ""],
		]
	)
	var when := RunwayWorks.when_text(600, 0)
	assert_str(SideSpurs.works_text(StandPlacement.WEST)).is_equal("W")
	assert_str(SideSpurs.works_text(StandPlacement.EAST)).is_equal("E")
	assert_str(SideSpurs.works_text(StandPlacement.WEST, 600, 0)).is_equal("W laeter " + when)
	assert_str(SideSpurs.works_text(StandPlacement.EAST, 600, 0)).is_equal("E laeter " + when)


func test_the_inspect_card_says_the_stuck_words_in_the_players_language() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.stuck = Passenger.Stuck.NO_ROUTE
	assert_str(PassengerInspect.now_line(world.sim, p)).is_equal('Stuck: "I can\'t get there"')
	PseudoLocale.enable(0.4)
	var shown := PassengerInspect.now_line(world.sim, p)
	print("now line: '%s'" % shown)
	assert_str(_bare(shown)).starts_with('Stuck: "[')
	assert_str(shown).contains("I can't get there")
	world.free_all()


func test_every_new_msgid_is_in_the_template_once_with_a_msgstr() -> void:
	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	var counts := {}
	var finished := {}
	for pair: Array in NEW_ENTRIES:
		counts[pair[1]] = PotEntries.count(entries, pair[0], pair[1])
		finished[pair[1]] = PotEntries.complete(entries, pair[0], pair[1])
	print("entries: %d, counts: %s, with msgstr: %s" % [entries.size(), counts, finished])
	for pair: Array in NEW_ENTRIES:
		assert_int(counts[pair[1]]).override_failure_message(pair[1]).is_equal(1)
		assert_int(finished[pair[1]]).override_failure_message(pair[1]).is_equal(1)


## Every entry in the template is whole (a msgid and a msgstr) and none repeats.
func test_the_template_has_no_malformed_or_duplicate_entry() -> void:
	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	var broken := PotEntries.malformed(entries)
	var repeated := PotEntries.duplicates(entries)
	print("entries: %d, malformed: %s, duplicates: %s" % [entries.size(), broken, repeated])
	assert_int(entries.size()).is_greater(1000)
	assert_array(broken).is_empty()
	assert_array(repeated).is_empty()


## Control: the parser flags a msgid with no msgstr, a repeat and a wrong context.
func test_the_template_parser_catches_a_missing_msgstr_a_repeat_and_a_wrong_context() -> void:
	var text := 'msgid ""\nmsgstr ""\n\n#: a.gd\nmsgid "one"\n\n'
	text += '#: a.gd\nmsgctxt "ctx"\nmsgid "two"\nmsgstr ""\n\n'
	text += '#: a.gd\nmsgctxt "ctx"\nmsgid "two"\nmsgstr ""\n'
	var entries := PotEntries.parse(text)
	assert_int(entries.size()).is_equal(4)
	assert_array(PotEntries.malformed(entries)).has_size(1)
	assert_array(PotEntries.duplicates(entries)).has_size(1)
	assert_int(PotEntries.count(entries, "ctx", "two")).is_equal(2)
	assert_int(PotEntries.count(entries, "", "two")).is_equal(0)
	assert_int(PotEntries.complete(entries, "", "one")).is_equal(0)
	assert_int(PotEntries.count(entries, "", "one")).is_equal(1)


## Control: a plural entry needs msgstr[0] and msgstr[1] and no plain msgstr, and a
## singular entry needs one plain msgstr, whatever the lines are split into.
func test_the_template_parser_tells_plural_and_singular_msgstr_shapes_apart() -> void:
	var whole := 'msgid "a"\nmsgid_plural "as"\nmsgstr[0] ""\n"x"\nmsgstr[1] ""\n"y"\n\n'
	assert_array(PotEntries.malformed(PotEntries.parse(whole))).is_empty()
	assert_int(PotEntries.complete(PotEntries.parse(whole), "", "a", "as")).is_equal(1)
	var cases := {
		"plural without msgstr[1]": 'msgid "a"\nmsgid_plural "as"\nmsgstr[0] ""\n',
		"plural with a plain msgstr": 'msgid "a"\nmsgid_plural "as"\nmsgstr ""\n',
		"plural with a plain msgstr and both forms":
		'msgid "a"\nmsgid_plural "as"\nmsgstr ""\nmsgstr[0] ""\nmsgstr[1] ""\n',
		"singular with msgstr[0]": 'msgid "a"\nmsgstr[0] ""\n',
	}
	for label: String in cases:
		var entries := PotEntries.parse(cases[label])
		var broken := PotEntries.malformed(entries)
		print("%s: %s" % [label, broken])
		assert_array(broken).override_failure_message(label).has_size(1)
		assert_str(broken[0]).override_failure_message(label).starts_with("line 1: a")
		assert_int(PotEntries.complete(entries, "", "a", entries[0].get("plural", ""))).is_equal(0)


func test_the_debug_panel_buttons_are_dev_only_and_stay_english() -> void:
	PseudoLocale.enable(0.4)
	var pressed := []
	var batch := DebugPanelParts.spawn_button(300, func() -> void: pressed.append("batch"))
	var starter := DebugPanelParts.starter_button(func() -> void: pressed.append("starter"))
	var toggled := []
	var toggle := DebugPanelParts.toggle(func(on: bool) -> void: toggled.append(on))
	assert_str(batch.text).is_equal("Spawn 300 passengers")
	assert_str(starter.text).is_equal("Starter terminal")
	assert_str(toggle.text).is_equal("Debug")
	assert_str(String(toggle.name)).is_equal("DebugToggle")
	assert_bool(toggle.toggle_mode).is_true()
	for button: Button in [batch, starter, toggle]:
		assert_int(button.focus_mode).is_equal(Control.FOCUS_NONE)
	batch.pressed.emit()
	starter.pressed.emit()
	toggle.toggled.emit(true)
	assert_array(pressed).is_equal(["batch", "starter"])
	assert_array(toggled).is_equal([true])
	for button: Button in [batch, starter, toggle]:
		button.free()
