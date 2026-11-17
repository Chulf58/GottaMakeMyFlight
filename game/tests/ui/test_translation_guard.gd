class_name TestTranslationGuard
extends GdUnitTestSuite
## The translation guard (decision translation-format-po-gettext-files-with-tr-
## and-tr-n-for-all). TranslationScan finds every statement in game/ui/*.gd that
## sets .text, .tooltip_text or set_text( to a string literal with no tr(). The
## offences that exist today are listed, file and line text and count, in
## locale/guard_baseline.tsv. A new offence fails, even in a file already on the
## list. A baselined offence that disappears fails too, until its line is removed
## from the file, so the list only shrinks. Each translation item (T1 to T7)
## wraps its strings and deletes the matching lines.

const UI_DIR := "res://ui"
const BASELINE := "res://locale/guard_baseline.tsv"


func _baseline() -> Dictionary:
	return TranslationScan.parse_baseline(FileAccess.get_file_as_string(BASELINE))


func test_no_ui_file_gains_a_text_literal_beyond_the_baseline() -> void:
	var fresh: Array = TranslationScan.diff(TranslationScan.count_dir(UI_DIR), _baseline())["new"]
	(
		assert_array(fresh)
		. override_failure_message(
			"New text literal without tr() (file | line); wrap it:\n%s" % ["\n".join(fresh)]
		)
		. is_empty()
	)


func test_a_wrapped_line_comes_off_the_baseline() -> void:
	var gone: Array = TranslationScan.diff(TranslationScan.count_dir(UI_DIR), _baseline())["gone"]
	(
		assert_array(gone)
		. override_failure_message(
			"Wrapped; delete from locale/guard_baseline.tsv (file | line):\n%s" % ["\n".join(gone)]
		)
		. is_empty()
	)


func test_the_baseline_is_not_empty_and_the_migrated_example_is_scanned_and_clean() -> void:
	assert_int(_baseline().size()).is_greater(0)
	assert_array(DirAccess.get_files_at(UI_DIR)).contains(["rating_badge.gd"])
	for key: String in TranslationScan.count_dir(UI_DIR):
		assert_bool(key.begins_with("rating_badge.gd\t")).is_false()
	for key: String in _baseline():
		assert_bool(key.begins_with("rating_badge.gd\t")).is_false()


func test_control_a_new_literal_in_a_baselined_file_fails() -> void:
	var old := 'func f(l: Label) -> void:\n\tl.text = "Hello there"\n'
	var baseline := TranslationScan.parse_baseline(
		TranslationScan.format_baseline(_counts("a.gd", old))
	)
	assert_array(TranslationScan.diff(_counts("a.gd", old), baseline)["new"]).is_empty()
	var other := old + '\tl.text = "Another one"\n'
	assert_array(TranslationScan.diff(_counts("a.gd", other), baseline)["new"]).has_size(1)
	var repeat := old + '\tl.text = "Hello there"\n'
	assert_array(TranslationScan.diff(_counts("a.gd", repeat), baseline)["new"]).has_size(1)


func test_control_a_wrapped_baselined_line_must_leave_the_baseline() -> void:
	var old := 'func f(l: Label) -> void:\n\tl.text = "Hello there"\n'
	var baseline := TranslationScan.parse_baseline(
		TranslationScan.format_baseline(_counts("a.gd", old))
	)
	var wrapped := 'func f(l: Label) -> void:\n\tl.text = tr("Hello there")\n'
	var result := TranslationScan.diff(_counts("a.gd", wrapped), baseline)
	assert_array(result["new"]).is_empty()
	assert_array(result["gone"]).has_size(1)


func _counts(file: String, source: String) -> Dictionary:
	var counts := {}
	for offence in TranslationScan.offences(source):
		var key := "%s\t%s" % [file, offence["text"]]
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


func test_control_the_matcher_catches_a_planted_literal() -> void:
	var planted := 'extends Node\nfunc f(l: Label) -> void:\n\tl.text = "Hello there"\n'
	assert_array(TranslationScan.offending_lines(planted)).is_equal([3])
	assert_bool(TranslationScan.offends('\t_card.tooltip_text = "Made it"')).is_true()
	assert_bool(TranslationScan.offends('\tbutton.set_text("Spawn %d passengers" % n)')).is_true()


func test_control_the_matcher_passes_routed_and_non_text_lines() -> void:
	assert_bool(TranslationScan.offends('\tl.text = tr("Hello there")')).is_false()
	assert_bool(TranslationScan.offends('\tl.text = tr_n("one", "many", n).format({})')).is_false()
	assert_bool(TranslationScan.offends('\tl.text = ""')).is_false()
	assert_bool(TranslationScan.offends('\tl.text = "%.1f" % stars')).is_false()
	assert_bool(TranslationScan.offends("\tl.text = text_for(x)")).is_false()
	assert_bool(TranslationScan.offends('\t# l.text = "Hello there"')).is_false()


func test_control_str_is_not_a_tr_call() -> void:
	assert_bool(TranslationScan.offends('\t_label.text = "Passengers: " + str(count)')).is_true()
	(
		assert_bool(TranslationScan.offends('\t_label.text = "Passengers: " + tr("x").format({})'))
		. is_true()
	)


func test_control_a_literal_after_the_first_token_is_seen() -> void:
	assert_bool(TranslationScan.offends('\t_label.text = old if ok else "Fallback"')).is_true()
	assert_bool(TranslationScan.offends('\t_label.text = tr("Yes") if ok else "No"')).is_true()
	assert_bool(TranslationScan.offends('\t_label.text = tr("Yes") if ok else tr("No")')).is_false()


func test_control_a_comment_that_names_tr_does_not_route_the_line() -> void:
	assert_bool(TranslationScan.offends('\t_label.text = "Hello"  # wrap in tr() later')).is_true()
	(
		assert_bool(TranslationScan.offends('\t_label.text = tr("Hello")  # "Hello" is the msgid'))
		. is_false()
	)


func test_control_one_routed_and_one_unrouted_literal_on_a_line() -> void:
	assert_bool(TranslationScan.offends('\t_label.text = tr("Mood") + ": unknown"')).is_true()
	assert_bool(TranslationScan.offends('\t_label.text = other.tr("Mood")')).is_true()


func test_control_format_keys_and_index_keys_are_not_text() -> void:
	(
		assert_bool(TranslationScan.offends('\t_label.text = tr("Mood {m}").format({"m": mood})'))
		. is_false()
	)
	assert_bool(TranslationScan.offends('\t_label.text = NAMES["mood"]')).is_false()


func test_control_a_statement_over_several_lines_is_one_statement() -> void:
	var planted := 'func f(l: Label) -> void:\n\tl.text = (\n\t\t"Hello there"\n\t)\n'
	assert_array(TranslationScan.offending_lines(planted)).is_equal([2])
	var routed := 'func f(l: Label) -> void:\n\tl.text = (\n\t\ttr("Hello")\n\t)\n'
	assert_array(TranslationScan.offending_lines(routed)).is_empty()
