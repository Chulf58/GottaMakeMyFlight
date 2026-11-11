class_name TestUnlockFamilies
extends GdUnitTestSuite
## The unlock dialog's family lines (decision new-unlock-tier-phone-ring-and-a-
## short-per-family-dialog-onc) come from BuildUnlocks.TIERS: the tools of the
## opened tiers are grouped into food, security, baggage, comfort, runway and
## other, and only the families a tier brings get a line.


func _families(first: int, last: int) -> Array:
	return UnlockFamilies.grouped(first, last).keys()


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
		var groups := UnlockFamilies.grouped(tier, tier)
		for family: StringName in groups:
			for tool: BuildMode.Tool in groups[family]:
				assert_str(UnlockFamilies.family_of(tool)).is_equal(family)
				seen += 1
		var listed: Array = BuildUnlocks.TIERS[tier - 1]["tools"]
		assert_int(seen).is_equal(listed.size())


func test_one_line_per_family_and_other_names_its_pieces() -> void:
	var lines := UnlockFamilies.lines(2, 2)
	assert_int(lines.size()).is_equal(6)
	assert_str(lines[0]).starts_with("Food:")
	assert_str(lines[5]).starts_with("Also new:")
	assert_str(lines[5]).contains("kiosk")


func test_the_tools_of_the_start_tier_and_an_out_of_range_tier_bring_nothing() -> void:
	assert_array(_families(1, 1)).not_contains([UnlockFamilies.FOOD])
	assert_array(_families(5, 9)).is_empty()
