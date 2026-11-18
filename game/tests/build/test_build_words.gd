class_name TestBuildWords
extends GdUnitTestSuite
## Every build refusal and ghost reason reaches the screen through BuildWords
## (board e68913dc, decision translation-format-po-gettext-files-with-tr-and-tr-n-
## for-all). Pseudolocalization brackets every translated string, so a bracketed
## line proves the display path went through translation; the English run proves
## the keys (BuildResult.REASON_TEXT, GhostReason.SHORT_TEXT, SecurityLanes.STATUS_TEXT)
## still match, and the msgid list holds every line the data can produce.

const ANCHOR := Vector2i(5, 6)
const CAFE := Rect2i(2, 2, 6, 4)
const S := SecurityLanes.Status

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(14, 14)
	add_child(_mode)
	_mode.set_process(false)
	for y in 14:
		for x in 14:
			_mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))


func after_test() -> void:
	PseudoLocale.disable()
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()
	_mode.free()


func _refusal(why: BuildResult.Reason, detail := "") -> BuildResult:
	var result := BuildResult.refused(why)
	result.detail = detail
	return result


func _hover(cell: Vector2i) -> String:
	_mode._update_ghost(_mode.grid.cell_to_world(cell))
	return _mode.status_text()


func test_the_msgids_hold_every_line_the_data_can_produce() -> void:
	var ids := BuildWords.msgids()
	var wanted: Array[String] = []
	for reason: int in BuildResult.REASON_TEXT:
		var text: String = BuildResult.REASON_TEXT[reason]
		if text != "" and reason != BuildResult.Reason.GATE_STAND_OVERLAP:
			wanted.append(text)
	wanted.append_array(GhostReason.SHORT_TEXT.values())
	wanted.append_array(SecurityLanes.STATUS_TEXT.values())
	wanted.append_array([BuildMode.BELT_HINT, BuildMode.NOT_IN_LANE, BuildMode.FRONT_OUTSIDE_ROOM])
	wanted.append(BuildMode.DRAG_OVER_UI)
	wanted.append_array(BuildMode.DOOR_NAMES.values())
	var missing: Array[String] = []
	for text in wanted:
		if not ids.has(text):
			missing.append(text)
	print("data lines checked: %d, msgids: %d, missing: %s" % [wanted.size(), ids.size(), missing])
	assert_int(wanted.size()).is_greater(100)
	assert_array(missing).is_empty()


func test_every_refusal_reads_as_its_english_key_in_english() -> void:
	for reason: int in BuildResult.REASON_TEXT:
		var shown := _refusal(reason).reason_text()
		if reason == BuildResult.Reason.GATE_STAND_OVERLAP:
			assert_str(shown).is_equal(BuildResult.REASON_TEXT[reason])
		else:
			assert_str(shown).is_equal(BuildResult.REASON_TEXT[reason])
	var detailed := _refusal(BuildResult.Reason.GATE_IN_USE, "gate A")
	assert_str(detailed.reason_text()).is_equal(
		"%s: gate A" % BuildResult.REASON_TEXT[BuildResult.Reason.GATE_IN_USE]
	)


func test_every_refusal_is_translated_when_shown() -> void:
	PseudoLocale.enable(0.4)
	var plain := 0
	for reason: int in BuildResult.REASON_TEXT:
		if reason == BuildResult.Reason.NONE:
			assert_str(_refusal(reason).reason_text()).is_empty()
			continue
		var shown := _refusal(reason).reason_text()
		if not shown.begins_with("["):
			plain += 1
			print("not translated: %s -> %s" % [reason, shown])
	var detailed := _refusal(BuildResult.Reason.GATE_IN_USE, "gate A").reason_text()
	print("refusal with a detail (pseudo): %s" % detailed)
	assert_int(plain).is_equal(0)
	# Only the reason is translated here. The detail (gate_desks, spur_trial, door_placement,
	# template_paste, room_move) stays English until board item c1b2a404 (T12) translates
	# each producer, so nothing asserts that part of the line.
	assert_str(detailed).starts_with("[").contains(
		BuildWords.refusal(BuildResult.REASON_TEXT[BuildResult.Reason.GATE_IN_USE])
	)


func test_the_gate_spacing_refusal_names_its_metres_in_one_sentence() -> void:
	var metres := StandPlacement.EXIT_SPACING_CELLS
	PseudoLocale.enable(0.4)
	var shown := _refusal(BuildResult.Reason.GATE_STAND_OVERLAP).reason_text()
	print("gate spacing (pseudo): %s" % shown)
	assert_str(shown).starts_with("[").contains("%d m" % metres)


func test_every_ghost_reason_is_translated_and_english_keeps_its_key() -> void:
	for reason: int in GhostReason.SHORT_TEXT:
		assert_str(GhostReason.short_text(_refusal(reason))).is_equal(
			GhostReason.SHORT_TEXT[reason]
		)
	PseudoLocale.enable(0.4)
	var plain := 0
	for reason: int in GhostReason.SHORT_TEXT:
		var shown := GhostReason.short_text(_refusal(reason))
		if not shown.begins_with("["):
			plain += 1
			print("ghost not translated: %s -> %s" % [reason, shown])
	var fallback := GhostReason.short_text(_refusal(BuildResult.Reason.NO_FLOOR))
	var blocked := GhostReason.short_text(_refusal(BuildResult.Reason.DOOR_FRONT_BLOCKED, "bin"))
	var unknown := GhostReason.short_text(_refusal(BuildResult.Reason.DOOR_FRONT_BLOCKED, "zzz"))
	print(
		"ghost fallback (pseudo): %s; blocked door: %s; unknown: %s" % [fallback, blocked, unknown]
	)
	assert_int(plain).is_equal(0)
	assert_str(fallback).starts_with("[")
	# The blocker's catalog name is translated (DisplayWords.item), never the raw English.
	assert_str(blocked).starts_with("[").contains(DisplayWords.item("Bin"))
	# A name no piece has is not shown raw: the card falls back to the translated generic line.
	assert_str(unknown).is_equal(
		BuildWords.short_refusal(GhostReason.SHORT_TEXT[BuildResult.Reason.DOOR_FRONT_BLOCKED])
	)
	assert_str(unknown).starts_with("[").not_contains("zzz")


func test_a_blocked_door_names_its_blocker_in_english() -> void:
	var blocked := GhostReason.short_text(_refusal(BuildResult.Reason.DOOR_FRONT_BLOCKED, "bin"))
	assert_str(blocked).is_equal("Bin in front")


func test_a_lane_status_is_translated_and_its_english_key_is_unchanged() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	SecurityLaneBuilder.build(_mode.grid, ANCHOR, 0, SecurityLanes.RIGHT, [SecurityLanes.XRAY_BELT])
	var english: String = SecurityLanes.STATUS_TEXT[S.NO_XRAY_BELT]
	assert_str(_hover(ANCHOR)).is_equal(english)
	PseudoLocale.enable(0.4)
	_mode._hint_cached = false
	var shown := _hover(ANCHOR)
	var lanes := SecurityLanes.new()
	lanes.rebuild(_mode.grid)
	var arch: int = lanes.arches[0]
	print("lane hint (pseudo): %s; key: %s" % [shown, lanes.status_text(arch)])
	assert_str(shown).starts_with("[").contains(english)
	assert_str(lanes.status_text(arch)).is_equal(english)
	assert_str(lanes.status_words(arch)).starts_with("[")
	# The sim-facing hint stays the English key; MissMarkers translates it at display.
	assert_str(MissSignals.lane_hint(_sim_with(lanes), arch)).is_equal(english)


func test_every_lane_status_is_translated() -> void:
	PseudoLocale.enable(0.4)
	for text: String in SecurityLanes.STATUS_TEXT.values():
		assert_str(BuildWords.lane_status(text)).starts_with("[").contains(text)


func test_the_door_hints_are_whole_sentences_with_a_translated_door_name() -> void:
	for tool: BuildMode.Tool in BuildMode.DOOR_NAMES:
		for reason: int in BuildMode.DOOR_HINTS:
			var english: String = BuildMode.DOOR_HINTS[reason] % BuildMode.DOOR_NAMES[tool]
			assert_str(BuildWords.door_hint(reason, BuildMode.DOOR_NAMES[tool])).is_equal(english)
	PseudoLocale.enable(0.4)
	var shown := BuildWords.door_hint(BuildResult.Reason.DOOR_WALLED, "entrance")
	print("door hint (pseudo): %s" % shown)
	assert_str(shown).starts_with("[").contains("[")
	assert_int(shown.count("[")).is_greater(1)


func test_the_status_constants_are_translated() -> void:
	var texts := [
		BuildMode.BELT_HINT,
		BuildMode.NOT_IN_LANE,
		BuildMode.FRONT_OUTSIDE_ROOM,
		BuildMode.DRAG_OVER_UI
	]
	for text: String in texts:
		assert_str(BuildWords.status(text)).is_equal(text)
	PseudoLocale.enable(0.4)
	for text: String in texts:
		assert_str(BuildWords.status(text)).starts_with("[").contains(text)


func test_a_placed_piece_is_announced_in_one_translated_sentence() -> void:
	_mode.set_tool(BuildMode.Tool.EXIT)
	PseudoLocale.enable(0.4)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(13, 4))).ok).is_true()
	var shown := _mode.status_text()
	print("placed (pseudo): %s" % shown)
	assert_str(shown).starts_with("[").ends_with("]")
	assert_int(shown.count("placed")).is_equal(1)


func test_the_room_move_says_its_hint_and_its_result_in_translated_sentences() -> void:
	assert_bool(_mode.grid.apply(BuildEdit.place_room(CAFE, &"cafe")).ok).is_true()
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	var mover := _mode.room_mover
	mover.set_process(false)
	var middle := Vector2i(4, 3)
	_mode.begin_area(_mode.grid.cell_to_world(middle))
	assert_bool(mover.active).is_true()
	assert_str(mover.status_text()).is_equal("Cafe: click to set down, right-click cancels")
	mover.cancel()
	PseudoLocale.enable(0.4)
	_mode.begin_area(_mode.grid.cell_to_world(middle))
	var hint := mover.status_text()
	mover.hover_at(Vector2i(8, 8))
	var moved := mover.set_down(Vector2i(8, 8))
	var note := mover.status_text()
	print("room move (pseudo): %s | %s" % [hint, note])
	assert_str(hint).starts_with("[").contains("click to set down")
	assert_bool(moved != null and moved.ok).is_true()
	assert_str(note).starts_with("[").contains("Moved")
	assert_str(note).contains("[Cafe")


## A PassengerSim shell whose layout holds `lanes`, enough for MissSignals.lane_hint.
func _sim_with(lanes: SecurityLanes) -> PassengerSim:
	var sim: PassengerSim = auto_free(PassengerSim.new())
	sim.layout.security_lanes = lanes
	return sim
