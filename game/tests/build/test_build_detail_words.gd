class_name TestBuildDetailWords
extends GdUnitTestSuite
## The build-mode text T2 left in English reaches the screen through BuildWords
## (board c1b2a404, T12 parts 1 and 2): a refusal's detail, the belt and facing
## status lines, the room tool's drag and hint lines and the drag's size. English
## stays the key, pseudolocalization proves the display path, and a run-time
## Translation proves the sentences are whole and the plural rule is the language's.

const CONTEXT := "build status"

var _translation: Translation


func after_test() -> void:
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null


func _refusal(why: BuildResult.Reason, detail: String, args := {}) -> BuildResult:
	var result := BuildResult.refused(why)
	result.detail = detail
	result.detail_args = args
	return result


func _one_off(time: String) -> Dictionary:
	return {"time": time, "airline": "", "city": ""}


func _translate(lines: Dictionary, context: String) -> void:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	for msgid: String in lines:
		_translation.add_message(msgid, lines[msgid], context)
	TranslationServer.add_translation(_translation)


func test_the_msgids_hold_every_item_name_mid_sentence() -> void:
	var ids := BuildWords.msgids()
	var missing: Array[String] = []
	for id in BuildCatalog.ids():
		var lower := BuildCatalog.get_def(id).display_name.to_lower()
		if not ids.has(lower):
			missing.append(lower)
	print(
		(
			"catalog items: %d, msgids: %d, missing: %s"
			% [BuildCatalog.ids().size(), ids.size(), missing]
		)
	)
	assert_int(BuildCatalog.ids().size()).is_greater(40)
	assert_array(missing).is_empty()


func test_the_msgids_hold_the_detail_and_status_sentences() -> void:
	var ids := BuildWords.msgids()
	for text: String in [
		"gate {gate} is too close",
		"gate {gate}, a small plane",
		"gate {gate}, a medium plane",
		"gate {gate}, a large plane",
		"Belt {count} cell",
		"Facing auto",
		"Facing {facing}",
		"{room} {width} x {height}",
		"{room} marked: {status}",
		"Drag to mark a {room}",
		"{width} x {height}",
	]:
		assert_array(ids).contains([text])


func test_each_detail_reads_as_before_in_english() -> void:
	var overlap := _refusal(
		BuildResult.Reason.GATE_STAND_OVERLAP, "gate A is too close", {"gate": "A"}
	)
	assert_str(overlap.reason_text()).ends_with(": gate A is too close")
	var route := _refusal(
		BuildResult.Reason.GATE_ROUTE, "gate B, a large plane", {"gate": "B", "plane": "large"}
	)
	assert_str(route.reason_text()).ends_with(": gate B, a large plane")
	var flights: Array[Dictionary] = [_one_off("10:00"), _one_off("11:00")]
	var busy := _refusal(
		BuildResult.Reason.GATE_IN_USE, FlightLabel.english_list(flights), {"flights": flights}
	)
	# The list grammar (ListWords) joins the last two flights with "and" (board T13).
	assert_str(busy.reason_text()).ends_with(": the 10:00 flight and the 11:00 flight")
	assert_str(busy.detail).is_equal("the 10:00 flight, the 11:00 flight")
	var door := _refusal(BuildResult.Reason.DOOR_FRONT_BLOCKED, "gate seats")
	assert_str(door.reason_text()).is_equal("Something is in front of the door: gate seats")
	var inner := _refusal(BuildResult.Reason.OVERLAP, "")
	var moved := _refusal(
		BuildResult.Reason.MOVE_NO_FIT,
		BuildResult.REASON_TEXT[BuildResult.Reason.OVERLAP],
		{"inner": inner}
	)
	assert_str(moved.reason_text()).ends_with(
		": %s" % BuildResult.REASON_TEXT[BuildResult.Reason.OVERLAP]
	)
	# A detail with no arguments is shown as it came.
	assert_str(_refusal(BuildResult.Reason.GATE_IN_USE, "gate A").reason_text()).ends_with(
		": gate A"
	)


func test_every_detail_is_translated_when_shown() -> void:
	PseudoLocale.enable(0.4)
	var overlap := (
		_refusal(BuildResult.Reason.GATE_STAND_OVERLAP, "gate A is too close", {"gate": "A"})
		. reason_text()
	)
	var route := (
		_refusal(
			BuildResult.Reason.GATE_ROUTE, "gate B, a large plane", {"gate": "B", "plane": "large"}
		)
		. reason_text()
	)
	var flights: Array[Dictionary] = [_one_off("10:00"), _one_off("11:00")]
	var busy := (
		_refusal(
			BuildResult.Reason.GATE_IN_USE, FlightLabel.english_list(flights), {"flights": flights}
		)
		. reason_text()
	)
	var door := _refusal(BuildResult.Reason.DOOR_FRONT_BLOCKED, "gate seats").reason_text()
	var inner := _refusal(BuildResult.Reason.OVERLAP, "")
	var moved := (
		_refusal(
			BuildResult.Reason.MOVE_NO_FIT,
			BuildResult.REASON_TEXT[BuildResult.Reason.OVERLAP],
			{"inner": inner}
		)
		. reason_text()
	)
	print(
		(
			"overlap: %s\nroute: %s\nbusy: %s\ndoor: %s\nmoved: %s"
			% [overlap, route, busy, door, moved]
		)
	)
	# The reason is one bracketed string inside the joiner's, and the detail is a second one.
	for shown in [overlap, route, door, moved]:
		assert_int(shown.count("[")).is_greater(2)
	assert_str(overlap).contains("gate A is too close")
	assert_str(route).contains("gate B, a large plane")
	assert_str(door).contains("gate seats")
	assert_str(overlap.get_slice(": ", 1)).starts_with("[")
	assert_str(route.get_slice(": ", 1)).starts_with("[")
	assert_str(door.get_slice(": ", 1)).starts_with("[")
	# The refusal sentence is a tr_n (never pseudolocalized); the list join and
	# each flight label inside it are their own translated strings.
	assert_int(busy.count("[")).is_equal(3)
	assert_str(busy).contains("10:00").contains("11:00")
	# The move's detail is the inner reason translated once, not a stored translation.
	assert_str(moved).contains(
		BuildWords.refusal(BuildResult.REASON_TEXT[BuildResult.Reason.OVERLAP])
	)


func test_a_stored_detail_stays_english_whatever_the_language() -> void:
	PseudoLocale.enable(0.4)
	var inner := _refusal(BuildResult.Reason.OVERLAP, "")
	var moved := _refusal(
		BuildResult.Reason.MOVE_NO_FIT,
		BuildResult.REASON_TEXT[BuildResult.Reason.OVERLAP],
		{"inner": inner}
	)
	assert_str(moved.detail).is_equal(BuildResult.REASON_TEXT[BuildResult.Reason.OVERLAP])


func test_a_door_blocker_is_one_lower_case_msgid_never_a_case_transformed_name() -> void:
	_translate({"gate seats": "Wartebank", "bin": "Eimer"}, "item name, mid-sentence")
	var door := _refusal(BuildResult.Reason.DOOR_FRONT_BLOCKED, "gate seats").reason_text()
	print("door with German blocker: %s" % door)
	assert_str(door).ends_with("Wartebank")
	assert_str(_refusal(BuildResult.Reason.DOOR_FRONT_BLOCKED, "bin").reason_text()).ends_with(
		"Eimer"
	)


func test_a_gate_sentence_is_one_msgid_with_its_gate_in_a_placeholder() -> void:
	_translate(
		{
			"gate {gate} is too close": "Tor {gate} ist zu nah",
			"gate {gate}, a large plane": "Tor {gate}, ein grosses Flugzeug",
		},
		"refusal detail"
	)
	var overlap := (
		_refusal(BuildResult.Reason.GATE_STAND_OVERLAP, "gate C is too close", {"gate": "C"})
		. reason_text()
	)
	var route := (
		_refusal(
			BuildResult.Reason.GATE_ROUTE, "gate D, a large plane", {"gate": "D", "plane": "large"}
		)
		. reason_text()
	)
	assert_str(overlap).ends_with("Tor C ist zu nah")
	assert_str(route).ends_with("Tor D, ein grosses Flugzeug")


func test_a_locked_paste_shows_the_tier_text_in_the_players_plural_words() -> void:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_plural_message(
		"Unlocks at {stars} stars and {passengers} passenger",
		PackedStringArray(["U1 {stars} {passengers}", "UN {stars} {passengers}"])
	)
	TranslationServer.add_translation(_translation)
	var need := BuildUnlocks.requirement_text(2)
	var shown := _refusal(BuildResult.Reason.LOCKED, need).reason_text()
	print("locked (run-time translation): %s" % shown)
	assert_str(need).starts_with("UN 2 ")
	assert_str(shown).ends_with(": %s" % need)


func test_the_belt_line_follows_the_plural_rule_and_reads_as_before_in_english() -> void:
	assert_str(BuildWords.belt_cells(7)).is_equal("Belt 7 cells")
	assert_str(BuildWords.belt_cells(1)).is_equal("Belt 1 cell")
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_plural_message(
		"Belt {count} cell", PackedStringArray(["BE1 {count}", "BEN {count}"]), CONTEXT
	)
	TranslationServer.add_translation(_translation)
	assert_str(BuildWords.belt_cells(1)).is_equal("BE1 1")
	assert_str(BuildWords.belt_cells(7)).is_equal("BEN 7")


func test_the_facing_line_is_translated_and_keeps_its_english() -> void:
	assert_str(BuildWords.facing_text(true, 0)).is_equal("Facing auto")
	assert_str(BuildWords.facing_text(false, 3)).is_equal("Facing 3")
	PseudoLocale.enable(0.4)
	assert_str(BuildWords.facing_text(true, 0)).starts_with("[").contains("Facing auto")
	assert_str(BuildWords.facing_text(false, 3)).starts_with("[").contains("Facing 3")


func test_the_size_line_is_one_whole_msgid() -> void:
	assert_str(BuildWords.size_text(12, 8)).is_equal("12 x 8")
	_translate({"{width} x {height}": "{width} mal {height}"}, CONTEXT)
	assert_str(BuildWords.size_text(12, 8)).is_equal("12 mal 8")


func test_the_room_tool_lines_read_as_before_in_english_and_translate() -> void:
	var grid := BuildGrid.new(Vector2i(14, 14), Vector3.ZERO)
	var area := Rect2i(2, 2, 4, 3)
	assert_str(RoomTool.hint(&"cafe")).is_equal("Drag to mark a cafe")
	assert_str(RoomTool.drag_label(grid, area, &"cafe")).starts_with("Cafe 4 x 3")
	PseudoLocale.enable(0.4)
	var hint := RoomTool.hint(&"cafe")
	var drag := RoomTool.drag_label(grid, area, &"cafe")
	print("hint (pseudo): %s; drag (pseudo): %s" % [hint, drag])
	assert_str(hint).starts_with("[")
	assert_str(drag).starts_with("[")


func test_the_room_hint_names_the_room_in_its_own_mid_sentence_msgid() -> void:
	_translate({"Drag to mark a {room}": "Ziehen, um {room} zu markieren"}, CONTEXT)
	assert_str(RoomTool.hint(&"cafe")).starts_with("Ziehen, um ").ends_with(" zu markieren")
	assert_str(RoomTool.hint(&"cafe")).is_equal(
		(
			"Ziehen, um %s zu markieren"
			% TranslationServer.translate("cafe", DisplayWords.ROOM_MID_CONTEXT)
		)
	)


func test_the_marked_room_line_is_one_sentence() -> void:
	var grid := BuildGrid.new(Vector2i(14, 14), Vector3.ZERO)
	for y in 14:
		for x in 14:
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var result := RoomTool.mark(grid, Rect2i(2, 2, 6, 4), &"cafe")
	assert_bool(result.ok).is_true()
	assert_str(RoomTool.message(grid, result, &"cafe")).is_equal("Cafe marked: Needs a counter")
	PseudoLocale.enable(0.4)
	var shown := RoomTool.message(grid, result, &"cafe")
	print("marked (pseudo): %s" % shown)
	assert_str(shown).starts_with("[").contains("marked")
