# gdlint:disable = max-public-methods
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


func test_the_twelve_hints_are_the_ruled_ones_and_first_miss_is_cut() -> void:
	(
		assert_array(HintRules.IDS)
		. is_equal(
			[
				HintRules.PLACE_CHECKIN,
				HintRules.PLACE_SECURITY,
				HintRules.PLACE_GATE_DESK,
				HintRules.PLACE_SEATS,
				HintRules.SECOND_HIRE,
				HintRules.TOILET,
				HintRules.FOOD,
				HintRules.BAGGAGE_CONNECT,
				HintRules.OFFERS,
				HintRules.FLIGHT_PLANNER,
				HintRules.CLEANERS,
				HintRules.FOLLOW_PASSENGER,
			]
		)
	)
	for id in HintRules.IDS:
		assert_str(HintRules.text(id)).is_not_empty()


func test_flight_planner_hint_fires_when_open_with_flights_until_opened() -> void:
	(
		assert_array(
			(
				HintRules
				. causes(
					_world(
						{
							"airport_open": false,
							"offers_opened": true,
							"has_scheduled_flights": true,
							"planner_opened": false,
						}
					)
				)
			)
		)
		. is_empty()
	)
	(
		assert_array(
			(
				HintRules
				. causes(
					_world(
						{
							"airport_open": true,
							"offers_opened": true,
							"has_scheduled_flights": false,
							"planner_opened": false,
						}
					)
				)
			)
		)
		. is_empty()
	)
	(
		assert_array(
			(
				HintRules
				. causes(
					_world(
						{
							"airport_open": true,
							"offers_opened": true,
							"has_scheduled_flights": true,
							"planner_opened": true,
						}
					)
				)
			)
		)
		. is_empty()
	)
	(
		assert_array(
			(
				HintRules
				. causes(
					_world(
						{
							"airport_open": true,
							"offers_opened": true,
							"has_scheduled_flights": true,
							"planner_opened": false,
						}
					)
				)
			)
		)
		. is_equal([HintRules.FLIGHT_PLANNER])
	)
	assert_str(HintRules.text(HintRules.FLIGHT_PLANNER)).is_equal(
		"Open Planner (P) to view today's schedule or move flights between gates."
	)


func test_cleaners_hint_fires_when_messes_appear_with_zero_cleaners_hired() -> void:
	assert_array(HintRules.causes(_world({"mess_count": 0, "cleaners_hired": 0}))).is_empty()
	assert_array(HintRules.causes(_world({"mess_count": 2, "cleaners_hired": 1}))).is_empty()
	assert_array(HintRules.causes(_world({"mess_count": 1, "cleaners_hired": 0}))).is_equal(
		[HintRules.CLEANERS]
	)
	assert_array(HintRules.categories_for(HintRules.CLEANERS)).is_equal([HintRules.STAFF_CARD])
	(
		assert_str(HintRules.text(HintRules.CLEANERS))
		. is_equal(
			"Terminal messes lower passenger mood. Hire a Cleaner on the Staff card to keep things tidy."
		)
	)


func test_offers_hint_is_due_once_airport_opens_and_clears_once_opened() -> void:
	(
		assert_array(HintRules.causes(_world({"airport_open": false, "offers_opened": false})))
		. is_empty()
	)
	(
		assert_array(HintRules.causes(_world({"airport_open": true, "offers_waiting": false})))
		. is_empty()
	)
	(
		assert_array(
			HintRules.causes(
				_world({"airport_open": true, "offers_waiting": true, "offers_opened": true})
			)
		)
		. is_empty()
	)
	(
		assert_array(
			HintRules.causes(
				_world({"airport_open": true, "offers_waiting": true, "offers_opened": false})
			)
		)
		. is_equal([HintRules.OFFERS])
	)
	assert_str(HintRules.text(HintRules.OFFERS)).is_equal(
		"Airlines are ready with new flights — click Offers at the top to review contracts."
	)


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


func test_the_gate_desk_is_the_cause_once_check_in_and_security_stand() -> void:
	var none := {"gate_desks": 0}
	assert_array(HintRules.causes(_world(none))).is_equal([HintRules.PLACE_GATE_DESK])
	# A lane part counts as security placed, as it does for the security hint.
	assert_array(HintRules.causes(_world({"gate_desks": 0, "scanners": 0, "arches": 1}))).is_equal(
		[HintRules.PLACE_GATE_DESK]
	)
	# No desk or no security yet: those hints come first, the gate desk is not due.
	assert_array(HintRules.causes(_world({"gate_desks": 0, "desks": 0}))).not_contains(
		[HintRules.PLACE_GATE_DESK]
	)
	assert_array(HintRules.causes(_world({"gate_desks": 0, "scanners": 0}))).not_contains(
		[HintRules.PLACE_GATE_DESK]
	)
	assert_array(HintRules.causes(_world({"gate_desks": 1}))).is_empty()


func test_seats_are_the_cause_once_a_gate_has_a_desk_and_no_seat_stands() -> void:
	assert_array(HintRules.causes(_world({"gate_desks": 1, "seats": 0}))).is_equal(
		[HintRules.PLACE_SEATS]
	)
	assert_array(HintRules.causes(_world({"gate_desks": 1, "seats": 3}))).is_empty()
	# Without a gate desk the desk hint comes first and the seats hint waits.
	assert_array(HintRules.causes(_world({"gate_desks": 0, "seats": 0}))).is_equal(
		[HintRules.PLACE_GATE_DESK]
	)


func test_a_world_without_gate_facts_has_neither_gate_cause() -> void:
	var world := _world()
	world.erase("gate_desks")
	world.erase("seats")
	assert_array(HintRules.causes(world)).is_empty()


func test_the_seats_hint_is_advice_and_both_open_on_the_operations_category() -> void:
	assert_str(HintRules.text(HintRules.PLACE_SEATS)).contains("opens without them")
	assert_str(HintRules.text(HintRules.PLACE_GATE_DESK)).contains("gate desk")
	assert_array(HintRules.categories_for(HintRules.PLACE_GATE_DESK)).is_equal(
		[BuildMode.Tool.GATE_DESK]
	)
	assert_array(HintRules.categories_for(HintRules.PLACE_SEATS)).is_equal([BuildMode.Tool.SEATS])
	var ops := BuildMenu.category_index("operations")
	assert_int(BuildMenu.category_of(BuildMode.Tool.GATE_DESK)).is_equal(ops)
	assert_int(BuildMenu.category_of(BuildMode.Tool.SEATS)).is_equal(ops)


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


func test_each_hint_names_valid_build_tool_categories_for_its_opportunity() -> void:
	for id in HintRules.IDS:
		for entry: Variant in HintRules.categories_for(id):
			if entry is String:
				assert_str(entry).is_equal(HintRules.STAFF_CARD)
			else:
				var cat := BuildMenu.category_of(entry)
				assert_int(cat).is_greater_equal(0)
				assert_int(cat).is_less(BuildMenu.REMOVE_CATEGORY)
	assert_array(HintRules.categories_for(HintRules.PLACE_CHECKIN)).contains([BuildMode.Tool.DESK])
	assert_array(HintRules.categories_for(HintRules.TOILET)).contains([BuildMode.Tool.TOILET_ROOM])
	assert_array(HintRules.categories_for(HintRules.SECOND_HIRE)).contains([HintRules.STAFF_CARD])


func test_overnight_off_shift_does_not_trigger_shortage_or_poll_gaps() -> void:
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var w := PassengerTestWorld.make(grid, FlightSim.schedule_starts(20_000))
	w.auto_staff = false
	assert_bool(w.flights.open_airport()).is_true()
	var gate := auto_free(AirportGate.new()) as AirportGate
	gate.bind(w.flights, w.staff)
	var panel := auto_free(StaffPanel.new()) as StaffPanel
	panel.staff = w.staff
	panel.gate = gate
	add_child(panel)
	# Staff every desk and scanner (2 each), then step into overnight off-shift.
	StaffTestKit.staff_all(w.staff, [CHECKIN, SECURITY])
	w.step()
	assert_bool(w.staff.is_off_shift()).is_true()
	var world := HintRules.read_world(w.sim, panel.hiring_hint_roles())
	assert_array(world["shortage_roles"]).is_empty()
	assert_array(HintRules.causes(world)).not_contains([HintRules.SECOND_HIRE])
	panel.poll_gaps()
	var gap_texts: Array[String] = []
	for entry in panel.card_lines():
		gap_texts.append(str(entry["text"]))
	assert_array(gap_texts).not_contains([Checklist.GAPS[HintRules.SECOND_HIRE]])
	# Firing one check-in agent while off-shift leaves 2 desks vs 1 hired agent -> real shortage.
	assert_bool(w.staff.fire(CHECKIN)).is_true()
	world = HintRules.read_world(w.sim, panel.hiring_hint_roles())
	assert_array(world["shortage_roles"]).is_equal([CHECKIN])
	assert_array(HintRules.causes(world)).contains([HintRules.SECOND_HIRE])
	panel.poll_gaps()
	gap_texts.clear()
	for entry in panel.card_lines():
		gap_texts.append(str(entry["text"]))
	assert_array(gap_texts).contains([Checklist.GAPS[HintRules.SECOND_HIRE]])
	# Firing the second check-in agent -> 0-hired banner role takes over.
	assert_bool(w.staff.fire(CHECKIN)).is_true()
	assert_array(panel.hiring_hint_roles()).contains([CHECKIN])
	world = HintRules.read_world(w.sim, panel.hiring_hint_roles())
	assert_array(world["shortage_roles"]).is_equal([CHECKIN])
	panel.free()
	gate.free()
	w.free_all()
