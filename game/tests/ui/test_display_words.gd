class_name TestDisplayWords
extends GdUnitTestSuite
## The names and reasons that live as English data reach the screen through
## DisplayWords (Sol review of the merged translation lanes, findings 1, 3 and 4):
## the built item card, the room panel and the incident panel set translated
## text, while the logic keys stay English. Pseudolocalization brackets every
## translated string, so a bracketed label proves the display path went through
## translation; the English run proves the keys still match.

const CAFE := &"cafe"
const ROOM_AT := Vector2i(3, 3)

var _grid: BuildGrid
var _world: PassengerTestWorld
var _mode: BuildMode


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(14, 14))
	_world = PassengerTestWorld.make(_grid, PassengerTestWorld.starts_with(10, 20))
	_mode = BuildMode.new()
	add_child(_mode)
	_mode.set_process(false)


func after_test() -> void:
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()
	_mode.free()
	_world.free_all()


func _room(size: Vector2i, type: StringName = CAFE) -> int:
	var result := _grid.apply(BuildEdit.place_room(Rect2i(ROOM_AT, size), type))
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	return result.room_id


func _card(kind: BuiltSelection.Kind, id: int) -> BuiltItemCard:
	var card := BuiltItemCard.new()
	card.sim = _world.sim
	card.build_mode = _mode
	card.selection = BuiltSelection.new()
	card.selection.kind = kind
	card.selection.id = id
	add_child(card)
	card.refresh()
	return card


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


## A pseudolocalized string without its bracket and padding lead: "[___Cafe___]"
## becomes "Cafe___]". The bracket itself is asserted by the caller.
func _bare(text: String) -> String:
	assert_str(text).starts_with("[")
	return text.lstrip("[_")


func _count(text: String, part: String) -> int:
	return text.count(part)


func test_the_msgids_hold_every_name_note_and_reason_of_the_data() -> void:
	var ids := DisplayWords.Words.new().msgids()
	var wanted: Array[String] = []
	for id in BuildCatalog.ids():
		wanted.append(BuildCatalog.get_def(id).display_name)
	for id in RoomTypes.ids():
		var type := RoomTypes.get_type(id)
		wanted.append(type.display_name)
		wanted.append(type.display_name.to_lower())
		for need in type.required:
			wanted.append(need[1])
			wanted.append(need[1].to_lower())
	wanted.append(RoomRules.NO_OPENING)
	wanted.append(RoomRules.NO_OPENING.to_lower())
	wanted.append_array(LandsidePlacement.NAMES.values())
	for status: SecurityLanes.Status in SecurityLanes.STATUS_TEXT:
		if status != SecurityLanes.Status.COMPLETE:
			wanted.append(SecurityLanes.STATUS_TEXT[status].to_lower())
	for reason: String in [
		MissSignals.PLAYER_CLOSED_REASON,
		MissSignals.SPOT_BLOCKED_REASON,
		MissSignals.UNREACHABLE_REASON,
		MissSignals.NO_STAFF_REASON,
		MissSignals.FAULT_REASON,
	]:
		wanted.append(reason.to_lower())
	var missing: Array[String] = []
	for name in wanted:
		if not ids.has(name):
			missing.append(name)
	print(
		"data strings checked: %d, msgids: %d, missing: %s" % [wanted.size(), ids.size(), missing]
	)
	assert_array(missing).is_empty()
	assert_int(wanted.size()).is_greater(100)


func test_english_output_and_the_logic_keys_are_unchanged() -> void:
	assert_str(DisplayWords.item("Check-in desk")).is_equal("Check-in desk")
	assert_str(DisplayWords.room_type("Bag room")).is_equal("Bag room")
	assert_str(DisplayWords.landside("Curb bay")).is_equal("Curb bay")
	assert_str(DisplayWords.ready()).is_equal(RoomRules.READY)
	assert_str(DisplayWords.reason("Needs a belt end")).is_equal("needs a belt end")
	assert_str(DisplayWords.biggest_plane("large")).is_equal("Biggest plane: Large")
	var taken := DisplayWords.gate_unlinked({"why": GateDesks.Unlinked.EXIT_TAKEN, "gate": "B"})
	assert_str(taken).is_equal("Status: unlinked: gate B uses the exit")
	# The keys the logic reads are still the English data.
	var room := _room(Vector2i(2, 2))
	var status := RoomRules.status(_grid, room)
	assert_str(status.type_name).is_equal("Cafe")
	assert_bool(status.too_small).is_true()
	assert_str(status.notes[0]).is_equal("Too small: a cafe needs at least 3x3")
	assert_str(DisplayWords.notes(status)[0]).is_equal("Too small: a cafe needs at least 3x3")
	assert_str(status.notes[1]).is_equal("Needs a counter")


func test_pseudolocalization_reaches_each_display_helper() -> void:
	PseudoLocale.enable(0.4)
	var shown := {
		"item": DisplayWords.item("Check-in desk"),
		"room type": DisplayWords.room_type("Cafe"),
		"landside": DisplayWords.landside("Surface lot"),
		"ready": DisplayWords.ready(),
		"reason": DisplayWords.reason("No staff on duty"),
		"plane": DisplayWords.biggest_plane("medium"),
		"fault": DisplayWords.fault_status(120, 0),
		"gate": DisplayWords.gate_unlinked({"why": GateDesks.Unlinked.NO_ROOM, "gate": ""}),
	}
	print("pseudolocalized: %s" % [shown])
	for key: String in shown:
		assert_str(shown[key]).override_failure_message(key).starts_with("[")
		assert_str(shown[key]).override_failure_message(key).ends_with("]")


func test_the_card_for_a_room_shows_translated_name_and_reason() -> void:
	var room := _room(Vector2i(3, 3))
	PseudoLocale.enable(0.4)
	var card := _card(BuiltSelection.Kind.ROOM, room)
	var name := card.name_text()
	var status := card.field_text("status")
	print("room card: '%s' | '%s'" % [name, status])
	assert_str(_bare(name)).starts_with("Cafe")
	assert_str(_bare(status)).starts_with("Status: Not ready, ")
	# The reason inside the sentence is itself translated: two bracket pairs.
	assert_int(_count(status, "[")).is_equal(2)
	assert_str(status).contains("needs a counter")
	PseudoLocale.disable()
	var plain := _card(BuiltSelection.Kind.ROOM, room)
	assert_str(plain.name_text()).is_equal("Cafe")
	assert_str(plain.field_text("status")).is_equal("Status: Not ready, needs a counter")


func test_the_card_for_a_piece_shows_translated_name_and_room() -> void:
	var room := _room(Vector2i(4, 4))
	var table := PassengerTestWorld.place(_grid, &"cafe_table", ROOM_AT + Vector2i(1, 1), 0)
	assert_int(_grid.room_at(ROOM_AT + Vector2i(1, 1))).is_equal(room)
	PseudoLocale.enable(0.4)
	var card := _card(BuiltSelection.Kind.OBJECT, table)
	var where := card.field_text("where")
	print("piece card: '%s' | '%s'" % [card.name_text(), where])
	assert_str(_bare(card.name_text())).starts_with("Cafe table")
	assert_str(_bare(where)).starts_with("In ")
	assert_int(_count(where, "[")).is_equal(2)
	PseudoLocale.disable()
	var plain := _card(BuiltSelection.Kind.OBJECT, table)
	assert_str(plain.name_text()).is_equal("Cafe table")
	assert_str(plain.field_text("where")).is_equal("In Cafe")


## The panel reads the mode's own grid, so the bag room is built there.
func _panel_with_bag_room(with_end: bool) -> Array:
	var edits: Array[BuildEdit] = []
	for y in range(2, 10):
		for x in range(2, 10):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	var room := Rect2i(3, 3, 3, 3)
	var made := _mode.grid.apply(BuildEdit.place_room(room, &"bag_room"))
	assert_bool(made.ok).override_failure_message(made.reason_text()).is_true()
	if with_end:
		PassengerTestWorld.place(_mode.grid, &"baggage_belt_end", room.position, 0)
	var panel := RoomPanel.new()
	add_child(panel)
	panel.watch(_mode)
	return [panel, made.room_id]


func test_the_room_panel_translates_title_and_requirement() -> void:
	var made := _panel_with_bag_room(false)
	var panel: RoomPanel = made[0]
	PseudoLocale.enable(0.4)
	panel.show_room(made[1])
	var texts := _texts(panel)
	print("room panel (pseudo): %s" % [texts])
	assert_str(_bare(texts[0])).starts_with("Bag room")
	assert_str(_bare(texts[1])).starts_with("Needs a belt end")
	PseudoLocale.disable()
	panel.show_room(made[1])
	assert_array(_texts(panel).slice(0, 2)).is_equal(["Bag room", "Needs a belt end"])
	panel.free()


func test_the_room_panel_translates_the_ready_state() -> void:
	var made := _panel_with_bag_room(true)
	var panel: RoomPanel = made[0]
	PseudoLocale.enable(0.4)
	panel.show_room(made[1])
	var texts := _texts(panel)
	print("room panel ready (pseudo): %s" % [texts])
	assert_str(_bare(texts[1])).starts_with("Ready")
	PseudoLocale.disable()
	panel.show_room(made[1])
	assert_array(_texts(panel).slice(0, 2)).is_equal(["Bag room", RoomRules.READY])
	panel.free()


func test_the_incident_offers_hold_each_whole_reward_and_failure_line() -> void:
	for kind: String in [IncidentCatalogue.VIP, IncidentCatalogue.FAVOUR]:
		var copy := IncidentCopy.template(kind)
		assert_str(copy["reward"]).starts_with("Reward: ")
		assert_str(copy["failure"]).starts_with("If it fails: ")
		PseudoLocale.enable(0.4)
		var shown := IncidentCopy.template(kind)
		var body := IncidentPanel.body_for(shown, true)
		print("%s offer (pseudo): %s" % [kind, body])
		assert_str(_bare(shown["reward"])).starts_with("Reward: ")
		assert_str(_bare(shown["failure"])).starts_with("If it fails: ")
		# One line each: the lead is inside the translated sentence, not added around it.
		assert_int(_count(body, "Reward:")).is_equal(1)
		assert_int(_count(body, "If it fails:")).is_equal(1)
		PseudoLocale.disable()
		var plain := IncidentPanel.body_for(IncidentCopy.template(kind), true)
		assert_int(_count(plain, "Reward: ")).is_equal(1)
		assert_int(_count(plain, "If it fails: ")).is_equal(1)


## A German-style locale whose room names are capitalised nouns: the too-small note
## must keep the capital, so no translated text is case-transformed.
func test_the_too_small_note_never_changes_the_case_of_a_translated_room_name() -> void:
	var german := Translation.new()
	german.locale = "de"
	german.add_message("Cafe", "Kaffeehaus", "room type")
	german.add_message("cafe", "Kaffeehaus", "room name, mid-sentence")
	var old_locale := TranslationServer.get_locale()
	TranslationServer.add_translation(german)
	TranslationServer.set_locale("de")
	var room := _room(Vector2i(2, 2))
	var status := RoomRules.status(_grid, room)
	var note := DisplayWords.notes(status)[0]
	var reason := DisplayWords.room_reason(status)
	TranslationServer.set_locale(old_locale)
	TranslationServer.remove_translation(german)
	print("too small note: '%s' | reason: '%s'" % [note, reason])
	assert_str(note).is_equal("Too small: a Kaffeehaus needs at least 3x3")
	assert_str(reason).is_equal("too small: a Kaffeehaus needs at least 3x3")
