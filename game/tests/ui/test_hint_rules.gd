class_name TestHintRules
extends GdUnitTestSuite
## The first-time hints' rules (HUD 7/7, decision first-time-hints-above-the-
## build-bar-moment-of-need-per-profile-memory): which cause each hint
## teaches, when a cause counts as met, and which hint is picked.

const CHECKIN := StaffMember.Role.CHECKIN
const SECURITY := StaffMember.Role.SECURITY


## A world with every need met: a desk, a scanner, a stall, a cafe, nobody short.
func _world(over := {}) -> Dictionary:
	var world := {
		"desks": 1,
		"scanners": 1,
		"arches": 0,
		"shortage_roles": [],
		"hiring_roles": [],
		"max_toilet_need": 0,
		"max_hunger": 0,
		"stalls": 1,
		"cafes": 1,
	}
	world.merge(over, true)
	return world


func test_a_world_with_every_need_met_has_no_cause() -> void:
	assert_array(HintRules.causes(_world())).is_empty()


func test_the_five_hints_are_the_ruled_ones_and_first_miss_is_cut() -> void:
	(
		assert_array(HintRules.IDS)
		. is_equal(
			[
				HintRules.PLACE_CHECKIN,
				HintRules.PLACE_SECURITY,
				HintRules.SECOND_HIRE,
				HintRules.TOILET,
				HintRules.FOOD,
			]
		)
	)
	for id in HintRules.IDS:
		assert_str(HintRules.text(id)).is_not_empty()


func test_the_check_in_hint_says_each_desk_needs_a_hired_agent() -> void:
	var text := HintRules.text(HintRules.PLACE_CHECKIN)
	assert_str(text).contains("check-in desk")
	assert_str(text).contains("hired agent")


func test_no_desk_is_the_check_in_cause() -> void:
	assert_array(HintRules.causes(_world({"desks": 0, "scanners": 0}))).contains(
		[HintRules.PLACE_CHECKIN]
	)
	assert_array(HintRules.causes(_world())).not_contains([HintRules.PLACE_CHECKIN])


func test_security_is_the_cause_only_with_a_desk_and_no_scanner_or_lane_part() -> void:
	var open := {"scanners": 0}
	assert_array(HintRules.causes(_world(open))).is_equal([HintRules.PLACE_SECURITY])
	assert_array(HintRules.causes(_world({"scanners": 0, "desks": 0}))).not_contains(
		[HintRules.PLACE_SECURITY]
	)
	# A lane begun with one part is on its way: the hint has done its job.
	assert_array(HintRules.causes(_world({"scanners": 0, "arches": 1}))).is_empty()


func test_a_shortage_is_the_second_hire_cause() -> void:
	assert_array(HintRules.causes(_world({"shortage_roles": [CHECKIN]}))).is_equal(
		[HintRules.SECOND_HIRE]
	)


func test_a_shortage_the_banner_already_names_is_not_a_second_hire_cause() -> void:
	# The banner's "Hire a check-in agent" line means the same thing for that role.
	var covered := _world({"shortage_roles": [CHECKIN], "hiring_roles": [CHECKIN]})
	assert_array(HintRules.causes(covered)).is_empty()
	# Another role's shortage is not what the banner names.
	var other := _world({"shortage_roles": [SECURITY], "hiring_roles": [CHECKIN]})
	assert_array(HintRules.causes(other)).is_equal([HintRules.SECOND_HIRE])


func test_toilet_needs_a_needy_passenger_and_no_usable_stall() -> void:
	var needy := ToiletSim.NEED_AT
	assert_array(HintRules.causes(_world({"stalls": 0, "max_toilet_need": needy}))).is_equal(
		[HintRules.TOILET]
	)
	assert_array(HintRules.causes(_world({"stalls": 0, "max_toilet_need": needy - 1}))).is_empty()
	assert_array(HintRules.causes(_world({"stalls": 1, "max_toilet_need": needy}))).is_empty()


func test_food_needs_a_hungry_passenger_and_no_usable_cafe() -> void:
	var hungry := CafeSim.HUNGRY_AT
	assert_array(HintRules.causes(_world({"cafes": 0, "max_hunger": hungry}))).is_equal(
		[HintRules.FOOD]
	)
	assert_array(HintRules.causes(_world({"cafes": 0, "max_hunger": hungry - 1}))).is_empty()
	assert_array(HintRules.causes(_world({"cafes": 1, "max_hunger": hungry}))).is_empty()


func test_pick_takes_the_first_hint_in_order_that_is_ready() -> void:
	var held := {HintRules.TOILET: HintRules.HOLD_S, HintRules.FOOD: HintRules.HOLD_S}
	var triggers := {HintRules.TOILET: true, HintRules.FOOD: true}
	var causes: Array[StringName] = [HintRules.TOILET, HintRules.FOOD]
	assert_str(HintRules.pick(causes, {}, held, triggers)).is_equal(HintRules.TOILET)


func test_pick_skips_a_seen_hint_and_takes_the_next() -> void:
	var held := {HintRules.TOILET: HintRules.HOLD_S, HintRules.FOOD: HintRules.HOLD_S}
	var triggers := {HintRules.TOILET: true, HintRules.FOOD: true}
	var causes: Array[StringName] = [HintRules.TOILET, HintRules.FOOD]
	var seen := {HintRules.TOILET: true}
	assert_str(HintRules.pick(causes, seen, held, triggers)).is_equal(HintRules.FOOD)


func test_pick_waits_for_the_cause_to_hold_and_for_a_trigger() -> void:
	var causes: Array[StringName] = [HintRules.FOOD]
	var triggers := {HintRules.FOOD: true}
	var young := {HintRules.FOOD: HintRules.HOLD_S - 0.1}
	assert_str(HintRules.pick(causes, {}, young, triggers)).is_equal("")
	var held := {HintRules.FOOD: HintRules.HOLD_S}
	assert_str(HintRules.pick(causes, {}, held, {})).is_equal("")
	assert_str(HintRules.pick(causes, {}, held, triggers)).is_equal(HintRules.FOOD)


func test_each_hint_names_the_build_categories_that_are_its_opportunity() -> void:
	var names := {}
	for category in BuildMenu.CATEGORIES:
		names[category["name"]] = true
	for id in HintRules.IDS:
		for category: String in HintRules.categories_for(id):
			if category != HintRules.STAFF_CARD:
				assert_bool(names.has(category)).is_true()
	assert_array(HintRules.categories_for(HintRules.PLACE_CHECKIN)).contains(["Check-in"])
	assert_array(HintRules.categories_for(HintRules.TOILET)).contains(["Toilets"])
	assert_array(HintRules.categories_for(HintRules.SECOND_HIRE)).contains([HintRules.STAFF_CARD])
