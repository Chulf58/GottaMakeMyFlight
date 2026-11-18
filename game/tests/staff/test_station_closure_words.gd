class_name TestStationClosureWords
extends GdUnitTestSuite
## The inspect window's station status (StationClosures.STATUS_TEXT; board c1b2a404,
## T12 part 3) reaches the player through status_words(). The English lines stay the
## keys status_text() hands to tests; the words are translated when a screen asks.

const CONTEXT := "station status"

var _w: PassengerTestWorld
var _a := 0
var _translation: Translation


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_w = PassengerTestWorld.reference_world(41)
	var scanners := _w.sim.layout.scanners.duplicate()
	scanners.sort()
	_a = scanners[0]
	_w.step()


func after_test() -> void:
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
	if _w != null:
		_w.free_all()
	_w = null


func test_the_msgids_hold_every_status_line() -> void:
	var ids := StationClosures.msgids()
	var missing: Array[String] = []
	for text: String in StationClosures.STATUS_TEXT.values():
		if not ids.has(text):
			missing.append(text)
	print(
		(
			"status lines: %d, msgids: %d, missing: %s"
			% [StationClosures.STATUS_TEXT.size(), ids.size(), missing]
		)
	)
	assert_int(StationClosures.STATUS_TEXT.size()).is_equal(6)
	assert_array(missing).is_empty()
	assert_array(ids).contains(["Scanner fault, fixed by {time}"])


func test_the_words_read_as_the_english_key_in_english() -> void:
	assert_str(_w.staff.closures.status_words(_a)).is_equal(_w.staff.closures.status_text(_a))
	_w.staff.closures.set_closed(_a, true)
	assert_str(_w.staff.closures.status_words(_a)).is_equal("Closed by you")
	assert_str(StationClosures.fault_words(900)).is_equal(StationClosures.fault_text(900))


func test_the_words_are_translated_and_the_key_stays_english() -> void:
	_w.staff.closures.set_closed(_a, true)
	PseudoLocale.enable(0.4)
	var shown := _w.staff.closures.status_words(_a)
	print("closed (pseudo): %s; key: %s" % [shown, _w.staff.closures.status_text(_a)])
	assert_str(shown).starts_with("[").contains("Closed by you")
	assert_str(_w.staff.closures.status_text(_a)).is_equal("Closed by you")
	assert_str(StationClosures.fault_words(900)).starts_with("[").contains("fixed by")


func test_a_scanner_fault_is_one_sentence_with_its_time_in_a_placeholder() -> void:
	var repair := _w.sim.tick + 500
	assert_bool(_w.staff.faults.add(_a, repair)).is_true()
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_message("Scanner fault, fixed by {time}", "Defekt, behoben um {time}", CONTEXT)
	TranslationServer.add_translation(_translation)
	var shown := _w.staff.closures.status_words(_a)
	print("fault (German): %s" % shown)
	assert_str(shown).is_equal("Defekt, behoben um %s" % GameCalendar.clock_text(repair))
	assert_str(_w.staff.closures.status_text(_a)).starts_with("Scanner fault, fixed by")
