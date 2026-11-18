class_name TestUnlockFamilies
extends GdUnitTestSuite
## The unlock dialog's family lines (decision new-unlock-tier-phone-ring-and-a-
## short-per-family-dialog-onc) come from BuildUnlocks.TIERS: the tools of the
## opened tiers are grouped into food, security, baggage, comfort, runway and
## other, and only the families a tier brings get a line.

var _translation: Translation


func after_test() -> void:
	PseudoLocale.disable()
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null


func _families(first: int, last: int) -> Array:
	return UnlockFamilies.grouped(range(first, last + 1)).keys()


func test_the_cafe_tier_brings_every_named_family_and_the_medium_runway() -> void:
	assert_array(_families(2, 2)).is_equal(
		[
			UnlockFamilies.FOOD,
			UnlockFamilies.SECURITY,
			UnlockFamilies.BAGGAGE,
			UnlockFamilies.COMFORT,
			UnlockFamilies.RUNWAY,
			UnlockFamilies.OTHER
		]
	)


func test_the_third_tier_has_no_security_or_baggage_but_the_large_runway() -> void:
	var families := _families(3, 3)
	assert_array(families).contains([UnlockFamilies.FOOD, UnlockFamilies.RUNWAY])
	assert_array(families).not_contains([UnlockFamilies.SECURITY, UnlockFamilies.BAGGAGE])


func test_the_last_tier_has_no_runway_and_no_food() -> void:
	var families := _families(4, 4)
	assert_array(families).contains([UnlockFamilies.COMFORT, UnlockFamilies.OTHER])
	assert_array(families).not_contains([UnlockFamilies.RUNWAY, UnlockFamilies.FOOD])


func test_a_jump_over_two_tiers_joins_their_families() -> void:
	assert_array(_families(2, 3)).contains([UnlockFamilies.SECURITY, UnlockFamilies.RUNWAY])


func test_every_tool_of_a_tier_is_in_exactly_one_family() -> void:
	for tier in range(2, BuildUnlocks.TIERS.size() + 1):
		var seen := 0
		var groups := UnlockFamilies.grouped([tier])
		for family: StringName in groups:
			for tool: BuildMode.Tool in groups[family]:
				assert_str(UnlockFamilies.family_of(tool)).is_equal(family)
				seen += 1
		var listed: Array = BuildUnlocks.TIERS[tier - 1]["tools"]
		assert_int(seen).is_equal(listed.size())


func test_one_line_per_family_and_other_names_its_pieces() -> void:
	var lines := UnlockFamilies.lines([2])
	assert_int(lines.size()).is_equal(6)
	assert_str(lines[0]).starts_with("Food:")
	assert_str(lines[5]).starts_with("Also new:")
	# The pieces carry their card names as the catalog shows them: a translated
	# name is never case-transformed, so "Kiosk" is no longer lowercased (board T9).
	assert_str(lines[5]).contains("Kiosk")


func test_the_lines_read_as_whole_english_sentences() -> void:
	var lines := UnlockFamilies.lines([2])
	assert_str(lines[0]).is_equal("Food: hungry passengers lose mood. A cafe feeds them.")
	assert_str(lines[1]).is_equal("Security: more lanes mean shorter queues at the checkpoint.")
	assert_str(lines[4]).is_equal("Runway: a longer runway takes bigger planes.")
	assert_str(lines[5]).ends_with(".")
	assert_str(lines[5]).not_contains("{")


func test_every_line_and_each_piece_name_comes_through_tr() -> void:
	PseudoLocale.enable(0.4)
	var lines := UnlockFamilies.lines([2])
	for line in lines:
		print("line: %s" % line)
		assert_str(line).starts_with("[")
	# The pieces are named through the catalog: each one is bracketed on its own.
	assert_int(lines[5].count("[")).is_greater(2)
	assert_str(lines[5]).contains("Kiosk")


## The names are joined by ListWords, so a language that lists names
## differently reaches the line through its own joins (board T9, T13).
func test_the_piece_list_follows_the_translated_list_grammar() -> void:
	var english := UnlockFamilies.lines([2])[5]
	assert_str(english).contains(", ").contains(" and ")
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_message("{first}, {rest}", "{first} SEP {rest}", "list start")
	_translation.add_message("{item}, {rest}", "{item} SEP {rest}", "list middle")
	_translation.add_message("{item} and {last}", "{item} END {last}", "list end")
	TranslationServer.add_translation(_translation)
	var line := UnlockFamilies.lines([2])[5]
	print("english: %s | translated: %s" % [english, line])
	assert_str(line).contains(" SEP ").contains(" END ")
	assert_str(line).not_contains(", ").not_contains(" and ")


func test_the_tools_of_the_start_tier_and_an_out_of_range_tier_bring_nothing() -> void:
	assert_array(_families(1, 1)).is_empty()
	assert_array(_families(5, 9)).is_empty()


## Every tr() literal in unlock_families.gd has its msgid in messages.pot.
func test_every_line_msgid_is_in_the_template() -> void:
	var source := FileAccess.get_file_as_string("res://build/unlock_families.gd")
	var template := FileAccess.get_file_as_string("res://locale/messages.pot").replace("\r\n", "\n")
	var calls := RegEx.create_from_string('tr\\("([^"]+)"\\)')
	var found := calls.search_all(source)
	var missing: Array[String] = []
	for call in found:
		var entry := 'msgid "%s"\nmsgstr ""' % call.get_string(1)
		if not template.contains(entry):
			missing.append(call.get_string(1))
	print("unlock line msgids: %d, missing: %s" % [found.size(), missing])
	assert_int(found.size()).is_equal(6)
	assert_array(missing).is_empty()
