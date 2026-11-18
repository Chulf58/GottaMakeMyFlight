class_name TestFlightLabelWords
extends GdUnitTestSuite
## A flight's name reaches the player as one whole msgid per shape, with
## {time}, {airline}, {city} and {gate} placeholders, and a build refusal that
## names flights is one whole sentence whose form follows the flight count
## (board T13). The English stays the stored detail; a run-time Translation
## proves the shapes, the plural forms (tr_n is never pseudolocalized) and the
## list grammar.

const OSLO := {"time": "10:20", "airline": "Gotta Air", "city": "Oslo"}
const ONE_OFF := {"time": "08:13", "airline": "", "city": ""}
const IN_USE := "A flight is still due at this gate. Remove it after the flight leaves: {flights}"
const STUCK := "No other gate is free for these flights. Move them in Departures first: {flights}"
const STRANDS := (
	"The side taxiway would have to move and leave a booked flight with no way to its gate:"
	+ " {flights}"
)
const SHAPES := [
	"the {time} flight",
	"the {time} {airline} flight to {city}",
	"the {time} {airline} flight to {city} on the runway",
	"the {time} {airline} flight to {city} on the taxi lane",
	"the {time} {airline} flight to {city} at gate {gate}",
	"the {time} flight on the runway",
	"the {time} flight on the taxi lane",
	"the {time} flight at gate {gate}",
	"another flight on the runway",
	"another flight on the taxi lane",
	"another flight at gate {gate}",
]

var _translation: Translation


func after_test() -> void:
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null


func _new_translation() -> Translation:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	TranslationServer.add_translation(_translation)
	return _translation


func _refusal(why: BuildResult.Reason, labels: Array[Dictionary]) -> BuildResult:
	var result := BuildResult.refused(why)
	result.detail = FlightLabel.english_list(labels)
	result.detail_args = {"flights": labels}
	return result


func _clash(label: Dictionary, reason: String) -> String:
	return FlightLabel.Words.new().clash(label, FlightLabel.parse_clash(reason))


func _hour(hour: int) -> Dictionary:
	return {"time": "%02d:00" % hour, "airline": "", "city": ""}


func test_the_label_shapes_read_as_before_in_english() -> void:
	assert_str(FlightLabel.words(OSLO)).is_equal("the 10:20 Gotta Air flight to Oslo")
	assert_str(FlightLabel.english(OSLO)).is_equal("the 10:20 Gotta Air flight to Oslo")
	assert_str(FlightLabel.words(ONE_OFF)).is_equal("the 08:13 flight")
	assert_str(FlightLabel.english(ONE_OFF)).is_equal("the 08:13 flight")
	assert_str(FlightLabel.words({})).is_equal("")
	assert_str(FlightLabel.english_list([OSLO, ONE_OFF])).is_equal(
		"the 10:20 Gotta Air flight to Oslo, the 08:13 flight"
	)


func test_each_label_shape_is_one_translated_msgid_and_the_english_stays_data() -> void:
	var german := _new_translation()
	german.add_message(
		"the {time} {airline} flight to {city}",
		"der {airline}-Flug um {time} nach {city}",
		"flight label"
	)
	german.add_message("the {time} flight", "der Flug um {time}", "flight label")
	print("full: %s | one-off: %s" % [FlightLabel.words(OSLO), FlightLabel.words(ONE_OFF)])
	assert_str(FlightLabel.words(OSLO)).is_equal("der Gotta Air-Flug um 10:20 nach Oslo")
	assert_str(FlightLabel.words(ONE_OFF)).is_equal("der Flug um 08:13")
	assert_str(FlightLabel.english(OSLO)).is_equal("the 10:20 Gotta Air flight to Oslo")


func test_every_clash_shape_reads_as_before_in_english() -> void:
	var gate := "contract Y clashes with X at gate A"
	var runway := "contract Y clashes with flight X-d0 on the runway"
	var lane := "contract Y clashes with flight X-d0 on the taxi lane"
	var shown := [
		_clash(OSLO, gate),
		_clash(OSLO, runway),
		_clash(OSLO, lane),
		_clash(ONE_OFF, gate),
		_clash(ONE_OFF, runway),
		_clash(ONE_OFF, lane),
		_clash({}, gate),
		_clash({}, runway),
		_clash({}, lane),
	]
	print("clash shapes: %s" % [shown])
	(
		assert_array(shown)
		. is_equal(
			[
				"the 10:20 Gotta Air flight to Oslo at gate A",
				"the 10:20 Gotta Air flight to Oslo on the runway",
				"the 10:20 Gotta Air flight to Oslo on the taxi lane",
				"the 08:13 flight at gate A",
				"the 08:13 flight on the runway",
				"the 08:13 flight on the taxi lane",
				"another flight at gate A",
				"another flight on the runway",
				"another flight on the taxi lane",
			]
		)
	)


func test_a_clash_shape_is_one_translated_msgid_with_its_gate() -> void:
	var german := _new_translation()
	german.add_message(
		"the {time} {airline} flight to {city} at gate {gate}",
		"der {airline}-Flug um {time} nach {city} an Gate {gate}",
		"flight label"
	)
	german.add_message(
		"another flight on the runway", "ein anderer Flug auf der Piste", "flight label"
	)
	var at_gate := _clash(OSLO, "contract Y clashes with X at gate B")
	var other := _clash({}, "contract Y clashes with flight X-d0 on the runway")
	print("at gate: %s | unknown: %s" % [at_gate, other])
	assert_str(at_gate).is_equal("der Gotta Air-Flug um 10:20 nach Oslo an Gate B")
	assert_str(other).is_equal("ein anderer Flug auf der Piste")


func test_a_refusal_naming_one_or_several_flights_reads_as_before_in_english() -> void:
	var one := _refusal(BuildResult.Reason.GATE_IN_USE, [OSLO])
	var three := _refusal(BuildResult.Reason.GATE_FLIGHTS_STUCK, [_hour(10), _hour(11), _hour(12)])
	var spur := _refusal(BuildResult.Reason.SPUR_STRANDS, [OSLO])
	print(
		(
			"one: %s\nthree: %s\nspur: %s"
			% [one.reason_text(), three.reason_text(), spur.reason_text()]
		)
	)
	assert_str(one.reason_text()).is_equal(IN_USE.format({"flights": FlightLabel.english(OSLO)}))
	assert_str(three.reason_text()).is_equal(
		STUCK.format({"flights": "the 10:00 flight, the 11:00 flight and the 12:00 flight"})
	)
	assert_str(spur.reason_text()).is_equal(STRANDS.format({"flights": FlightLabel.english(OSLO)}))
	# The stored detail keeps today's English list.
	assert_str(three.detail).is_equal("the 10:00 flight, the 11:00 flight, the 12:00 flight")


func test_one_flight_and_several_take_their_own_plural_form_and_list_grammar() -> void:
	var german := _new_translation()
	german.add_plural_message(
		IN_USE,
		PackedStringArray(
			["Ein Flug ist noch fällig: {flights}", "Flüge sind noch fällig: {flights}"]
		),
		"build refusal"
	)
	german.add_message("the {time} flight", "Flug {time}", "flight label")
	german.add_message("{first} and {second}", "{first} und {second}", "list of two")
	german.add_message("{first}, {rest}", "{first}; {rest}", "list start")
	german.add_message("{item} and {last}", "{item} sowie {last}", "list end")
	var one := _refusal(BuildResult.Reason.GATE_IN_USE, [_hour(9)]).reason_text()
	var two := _refusal(BuildResult.Reason.GATE_IN_USE, [_hour(9), _hour(10)]).reason_text()
	var three := (
		_refusal(BuildResult.Reason.GATE_IN_USE, [_hour(9), _hour(10), _hour(11)]).reason_text()
	)
	print("one: %s\ntwo: %s\nthree: %s" % [one, two, three])
	assert_str(one).is_equal("Ein Flug ist noch fällig: Flug 09:00")
	assert_str(two).is_equal("Flüge sind noch fällig: Flug 09:00 und Flug 10:00")
	assert_str(three).is_equal("Flüge sind noch fällig: Flug 09:00; Flug 10:00 sowie Flug 11:00")


## A flight that cannot be named has no values to translate: the refusal is
## shown with its English detail as it came, never with a gap in the list.
func test_an_unknown_flight_shows_the_detail_as_it_came() -> void:
	var result := BuildResult.refused(BuildResult.Reason.SPUR_STRANDS)
	result.detail = "C9-d4"
	var unknown: Array[Dictionary] = [{}]
	result.detail_args = {"flights": unknown}
	var reason := BuildResult.REASON_TEXT[BuildResult.Reason.SPUR_STRANDS]
	assert_str(result.reason_text()).is_equal("%s: C9-d4" % reason)


## Every new flight msgid is in messages.pot once with its msgstr fields, the
## refusals with their plural form.
func test_every_flight_msgid_is_in_the_template_once() -> void:
	var entries := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	var missing: Array[String] = []
	for shape: String in SHAPES:
		if PotEntries.complete(entries, "flight label", shape) != 1:
			missing.append(shape)
	for sentence: String in [IN_USE, STUCK, STRANDS]:
		if PotEntries.complete(entries, "build refusal", sentence, sentence) != 1:
			missing.append(sentence)
	print("flight msgids checked: %d, missing: %s" % [SHAPES.size() + 3, missing])
	assert_array(missing).is_empty()
	assert_int(PotEntries.count(entries, "build refusal", IN_USE, IN_USE)).is_equal(1)
