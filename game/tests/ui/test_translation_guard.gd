class_name TestTranslationGuard
extends GdUnitTestSuite
## The translation guard (decision translation-format-po-gettext-files-with-tr-
## and-tr-n-for-all). It scans game/ui/*.gd for a line that sets .text,
## .tooltip_text or set_text( to a quoted literal with no tr(), and fails for any
## file that does so and is not on UNMIGRATED. The list is a ratchet: a file that
## is migrated must come off it, so the list only shrinks. Each translation item
## (T1 to T7) removes the files it wraps.
##
## The matcher reads one line at a time. A literal split over several lines or
## held in a const is not seen; those stay for review.

const UI_DIR := "res://ui"
const SET_TEXT := '(?:\\.text|\\.tooltip_text)\\s*\\+?=\\s*"([^"]*)"|set_text\\(\\s*"([^"]*)"'
const FORMAT_SPEC := "%[-+0-9.]*[sdfxXcoi]|%%"

## Files under game/ui that still set a literal. Remove a file once it is wrapped.
const UNMIGRATED: Array[String] = [
	"alert_stack.gd",
	"built_item_actions.gd",
	"departures_board.gd",
	"flight_planner.gd",
	"flight_result_panel.gd",
	"hints.gd",
	"mood_overlay.gd",
	"offer_panel.gd",
	"passenger_hud.gd",
	"passenger_inspect.gd",
	"runway_card.gd",
	"templates_page.gd",
]

static var _matcher: RegEx
static var _format: RegEx


static func _regexes() -> void:
	if _matcher != null:
		return
	_matcher = RegEx.create_from_string(SET_TEXT)
	_format = RegEx.create_from_string(FORMAT_SPEC)


## True when `line` sets a text property to a literal that has a letter in it
## and does not go through tr(), tr_n() or atr(). Comments never count.
static func offends(line: String) -> bool:
	_regexes()
	var code := line.strip_edges()
	if code.begins_with("#") or code.contains("tr(") or code.contains("tr_n("):
		return false
	for found in _matcher.search_all(code):
		var literal := found.get_string(1) + found.get_string(2)
		if _has_letter(_format.sub(literal, "", true)):
			return true
	return false


static func _has_letter(text: String) -> bool:
	for i in text.length():
		if _is_letter(text, i):
			return true
	return false


static func _is_letter(text: String, i: int) -> bool:
	var c := text.unicode_at(i)
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c > 127


## The 1-based line numbers of `source` that offend.
static func offending_lines(source: String) -> Array[int]:
	var found: Array[int] = []
	var lines := source.split("\n")
	for i in lines.size():
		if offends(lines[i]):
			found.append(i + 1)
	return found


## Every game/ui/*.gd that has an offending line, as file names.
static func offending_files() -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(UI_DIR):
		if not file.ends_with(".gd"):
			continue
		if not offending_lines(FileAccess.get_file_as_string("%s/%s" % [UI_DIR, file])).is_empty():
			found.append(file)
	found.sort()
	return found


func test_no_ui_file_sets_a_literal_unless_it_is_on_the_unmigrated_list() -> void:
	var fresh: Array[String] = []
	for file in offending_files():
		if not UNMIGRATED.has(file):
			fresh.append(file)
	(
		assert_array(fresh)
		. override_failure_message(
			"These ui files set a text literal without tr(); wrap it: %s" % [fresh]
		)
		. is_empty()
	)


func test_a_migrated_file_comes_off_the_unmigrated_list() -> void:
	var offenders := offending_files()
	var stale: Array[String] = []
	for file in UNMIGRATED:
		if not offenders.has(file):
			stale.append(file)
	(
		assert_array(stale)
		. override_failure_message(
			"These files are clean now; remove them from UNMIGRATED: %s" % [stale]
		)
		. is_empty()
	)


func test_the_migrated_example_is_scanned_and_clean() -> void:
	assert_array(DirAccess.get_files_at(UI_DIR)).contains(["rating_badge.gd"])
	assert_array(offending_files()).not_contains(["rating_badge.gd"])
	assert_array(UNMIGRATED).not_contains(["rating_badge.gd"])


func test_control_the_matcher_catches_a_planted_literal() -> void:
	var planted := 'extends Node\nfunc f(l: Label) -> void:\n\tl.text = "Hello there"\n'
	assert_array(offending_lines(planted)).is_equal([3])
	assert_bool(offends('\t_card.tooltip_text = "Made it"')).is_true()
	assert_bool(offends('\tbutton.set_text("Spawn %d passengers" % n)')).is_true()


func test_control_the_matcher_passes_routed_and_non_text_lines() -> void:
	assert_bool(offends('\tl.text = tr("Hello there")')).is_false()
	assert_bool(offends('\tl.text = tr_n("one", "many", n).format({})')).is_false()
	assert_bool(offends('\tl.text = ""')).is_false()
	assert_bool(offends('\tl.text = "%.1f" % stars')).is_false()
	assert_bool(offends("\tl.text = text_for(x)")).is_false()
	assert_bool(offends('\t# l.text = "Hello there"')).is_false()
