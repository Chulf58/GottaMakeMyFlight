class_name TestIncidentMajorsPlan
extends MajorTestBase
## Everything that decides an inspector's or a VIP's outcome is in its saved plan
## (decision daily-incidents-technical-design-incidentdirector-shared-clo): the
## card and the execution read the plan alone, never IncidentTuning, so a later
## retune cannot change an incident that already rolled. Each case builds a plan
## with numbers unlike IncidentTuning's. And an accepted VIP whose contract ends
## before its flight is issued is dropped (not_held) instead of waiting for ever.

const INSPECTOR_PLAN := {
	"window_from": 50_000,
	"window_to": 58_000,
	"visit_tick": 52_000,
	"max_messes": 0,
	"max_full_queue": 0,
	"pass_money": 77,
	"fail_half_stars": 3,
}
const VIP_PLAN := {
	"flight": VIP_FLIGHT,
	"departs": 1,
	"bonus": 123,
	"target": 0,
	"good_mood": 90,
	"miss_half_stars": 3,
}


func _put(kind: String, state: String, plan: Dictionary) -> int:
	var data := _director.to_snapshot()
	var id: int = data["next_id"]
	data["next_id"] = id + 1
	data["enabled"] = true
	(
		(data["incidents"] as Array)
		. append(
			{
				"id": id,
				"kind": kind,
				"roll_day": 1,
				"state": state,
				"fire_tick": 0,
				"cell": [-1, -1],
				"mess_id": 0,
				"place": "",
				"outcome": "",
				"shown": false,
				"plan": plan.duplicate(true),
			}
		)
	)
	assert_bool(_director.from_snapshot(data)).is_true()
	return id


func test_an_inspector_card_and_visit_follow_the_plan_not_the_tuning() -> void:
	var id := _put(IncidentCatalogue.INSPECTOR, IncidentCatalogue.ANNOUNCED, INSPECTOR_PLAN)
	var copy := IncidentCopy.fill(IncidentCatalogue.panel_copy("inspector"), _record(id))
	var text: String = copy["body"]
	print(text)
	assert_str(text).contains("77 money")
	assert_str(text).contains("at most 0 messes")
	assert_str(text).contains("your rating drops by 1.5 stars")
	# One mess: the tuning (at most 2) would pass it, the plan (at most 0) fails it.
	assert_int(IncidentTuning.INSPECTOR_MAX_MESSES).is_greater(0)
	_add_messes(1)
	var before := _balance()
	_director.on_tick(INSPECTOR_PLAN["visit_tick"])
	var adjustments := _rating.active_adjustments()
	print("adjustments: %s" % [adjustments])
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.FAILED)
	assert_int(adjustments.size()).is_equal(1)
	assert_int(adjustments[0]["half_star_delta"]).is_equal(-3)
	assert_int(_balance()).is_equal(before)


func test_an_inspector_pass_pays_the_money_in_the_plan() -> void:
	var plan := INSPECTOR_PLAN.duplicate()
	plan["max_messes"] = 5
	var id := _put(IncidentCatalogue.INSPECTOR, IncidentCatalogue.ANNOUNCED, plan)
	_add_messes(3)
	var before := _balance()
	_director.on_tick(plan["visit_tick"])
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.PASSED)
	assert_int(_balance()).is_equal(before + 77)


func test_a_vip_card_and_outcome_follow_the_plan_not_the_tuning() -> void:
	var offer := _put(IncidentCatalogue.VIP, IncidentCatalogue.ACCEPTED, VIP_PLAN)
	var copy := IncidentCopy.fill(IncidentCatalogue.panel_copy("vip"), _record(offer))
	print(copy)
	assert_str(copy["reward"]).contains("123 money")
	assert_str(copy["failure"]).contains("1.5 stars")
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	assert_int(_record(offer)["plan"]["target"]).is_equal(vip)
	# Mood 80 is a good arrival by the tuning (75) but not by the plan (90).
	assert_int(IncidentTuning.VIP_GOOD_MOOD).is_less(80)
	var p := _world.sim.get_passenger(vip)
	p.mood = 80
	var before := _balance()
	PassengerLifecycle.finish(_world.sim, p, true)
	assert_str(_record(offer)["outcome"]).is_equal(IncidentMajors.NEUTRAL)
	assert_int(_balance()).is_equal(before)


func test_a_vip_good_arrival_pays_the_bonus_in_the_plan() -> void:
	var offer := _put(IncidentCatalogue.VIP, IncidentCatalogue.ACCEPTED, VIP_PLAN)
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	var p := _world.sim.get_passenger(vip)
	p.mood = 90
	var before := _balance()
	PassengerLifecycle.finish(_world.sim, p, true)
	assert_str(_record(offer)["outcome"]).is_equal(IncidentMajors.BONUS)
	assert_int(_balance()).is_equal(before + 123)


func test_a_vip_miss_costs_the_half_stars_in_the_plan() -> void:
	var offer := _put(IncidentCatalogue.VIP, IncidentCatalogue.ACCEPTED, VIP_PLAN)
	var vip := _world.sim.spawn_now(VIP_FLIGHT)
	PassengerLifecycle.finish(_world.sim, _world.sim.get_passenger(vip), false)
	var adjustments := _rating.active_adjustments()
	assert_int(adjustments.size()).is_equal(1)
	assert_int(adjustments[0]["half_star_delta"]).is_equal(-3)


func test_an_accepted_vip_whose_contract_ends_before_the_flight_is_issued_is_dropped() -> void:
	var incident := _presented_major(IncidentCatalogue.VIP)
	var id: int = incident["id"]
	var flight: String = incident["plan"]["flight"]
	assert_bool(_director.answer(id, true)).is_true()
	_director.on_tick(incident["plan"]["departs"] - 100)
	assert_str(_record(id)["state"]).is_equal(IncidentCatalogue.ACCEPTED)
	(
		assert_bool(
			_world.flights.end_contract(FlightTimetable.parse_occurrence(flight)["contract"])
		)
		. is_true()
	)
	_director.on_tick(incident["plan"]["departs"] - 99)
	print("after the contract ended: %s" % [_record(id)])
	assert_str(_record(id)["state"]).is_equal(IncidentCatalogue.DONE)
	assert_str(_record(id)["outcome"]).is_equal(IncidentMajors.NOT_HELD)
	assert_array(_director.pending_presentation()).is_empty()
