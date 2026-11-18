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

## Every msgid T11 added to messages.pot; each must appear there exactly once.
const NEW_MSGIDS := [
	"Wall gap · close the outer wall so the roof can go on",
	"Taxiway works: the taxiway moves when the west side is quiet",
	"Taxiway works: the taxiway moves when the east side is quiet",
	"{works}, forecast {when}",
	"Boarding",
	"Doors closed",
	"Pushback",
	"Taxiing",
	"Taking off",
	"Departed",
	"doors close {time}",
]

const AFTER_DOORS := {
	FlightSim.State.DOORS_CLOSED: "Doors closed",
	FlightSim.State.PUSHBACK: "Pushback",
	FlightSim.State.TAXI_OUT: "Taxiing",
	FlightSim.State.TAKEOFF: "Taking off",
	FlightSim.State.DEPARTED: "Departed",
}


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	PseudoLocale.disable()


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


func test_every_new_msgid_is_in_the_template_once() -> void:
	var template := FileAccess.get_file_as_string("res://locale/messages.pot").replace("\r\n", "\n")
	var counts := {}
	for msgid: String in NEW_MSGIDS:
		counts[msgid] = template.split('\nmsgid "%s"\n' % msgid).size() - 1
	print("msgid counts: %s" % [counts])
	for msgid: String in NEW_MSGIDS:
		assert_int(counts[msgid]).override_failure_message(msgid).is_equal(1)


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
