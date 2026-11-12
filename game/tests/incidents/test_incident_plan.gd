class_name TestIncidentPlan
extends GdUnitTestSuite
## The saved plan of a major incident (IncidentPlan, IncidentSnapshot v3): its
## numbers come back as ints also after JSON, a plan of the wrong shape is
## refused whole, a minor and a scheduled major have none, and a major has
## neither a cell, a mess nor a place.

const RUSH_PLAN := {
	"flights": [{"flight": "AM-d2", "extra": 4, "departs": 60_000}], "total": 4, "until": 79_200
}


func _part(kind: String, state: String, plan: Dictionary) -> Dictionary:
	return {
		"save_version": IncidentSnapshot.SAVE_VERSION,
		"enabled": true,
		"last_rolled_day": 3,
		"next_major_day": 5,
		"next_id": 2,
		"incidents":
		[
			{
				"id": 1,
				"kind": kind,
				"roll_day": 2,
				"state": state,
				"fire_tick": 40_000,
				"cell": [-1, -1],
				"mess_id": 0,
				"place": "",
				"outcome": "",
				"shown": false,
				"plan": plan,
			}
		],
	}


func _refusal(data: Dictionary) -> String:
	return str(IncidentSnapshot.load(data).get("error", ""))


func test_a_rush_plan_loads_as_ints_also_after_json() -> void:
	var data := _part(IncidentCatalogue.RUSH, IncidentCatalogue.ANNOUNCED, RUSH_PLAN)
	var through: Dictionary = JSON.parse_string(JSON.stringify(data))
	var loaded := IncidentSnapshot.load(through)
	assert_bool(loaded.has("error")).is_false()
	var plan: Dictionary = loaded["incidents"][0]["plan"]
	assert_dict(plan).is_equal(RUSH_PLAN)
	assert_int(typeof(plan["total"])).is_equal(TYPE_INT)
	assert_int(typeof(plan["flights"][0]["extra"])).is_equal(TYPE_INT)


func test_every_kind_has_a_plan_that_loads() -> void:
	var plans := {
		IncidentCatalogue.INSPECTOR:
		[IncidentCatalogue.ANNOUNCED, {"window_from": 1, "window_to": 9, "visit_tick": 5}],
		IncidentCatalogue.VIP:
		[
			IncidentCatalogue.ACCEPTED,
			{"flight": "AM-d1", "departs": 3, "bonus": 500, "target": 0},
		],
		IncidentCatalogue.FAVOUR:
		[
			IncidentCatalogue.OFFERED,
			{"flight": "AM-d1", "departs": 3, "extra": 4, "bonus": 300},
		],
	}
	for kind: String in plans:
		var data := _part(kind, plans[kind][0], plans[kind][1])
		assert_str(_refusal(data)).is_equal("")


func test_a_bad_plan_is_refused() -> void:
	var bad := {
		"a happened major with no plan":
		_part(IncidentCatalogue.RUSH, IncidentCatalogue.ANNOUNCED, {}),
		"a spill with a plan":
		_part(IncidentCatalogue.SPILL, IncidentCatalogue.SCHEDULED, RUSH_PLAN),
		"a negative number":
		_part(
			IncidentCatalogue.INSPECTOR,
			IncidentCatalogue.ANNOUNCED,
			{"window_from": -1, "window_to": 9, "visit_tick": 5}
		),
		"an extra key":
		_part(
			IncidentCatalogue.INSPECTOR,
			IncidentCatalogue.ANNOUNCED,
			{"window_from": 1, "window_to": 9, "visit_tick": 5, "more": 1}
		),
		"a rush with no flights":
		_part(
			IncidentCatalogue.RUSH,
			IncidentCatalogue.ANNOUNCED,
			{"flights": [], "total": 4, "until": 9}
		),
	}
	for label: String in bad:
		assert_str(_refusal(bad[label])).override_failure_message(label).is_not_empty()


func test_a_vip_state_a_favour_cannot_have_is_refused() -> void:
	var plan := {"flight": "AM-d1", "departs": 3, "extra": 4, "bonus": 300}
	(
		assert_str(_refusal(_part(IncidentCatalogue.FAVOUR, IncidentCatalogue.ACCEPTED, plan)))
		. contains("cannot be in state")
	)


func test_a_major_with_a_place_is_refused() -> void:
	var data := _part(IncidentCatalogue.RUSH, IncidentCatalogue.ANNOUNCED, RUSH_PLAN)
	data["incidents"][0]["place"] = "Check-in"
	assert_str(_refusal(data)).contains("not a spill")


func test_a_never_held_major_loads_done_with_no_plan() -> void:
	var data := _part(IncidentCatalogue.FAVOUR, IncidentCatalogue.DONE, {})
	data["incidents"][0]["outcome"] = IncidentMajors.NOT_HELD
	assert_str(_refusal(data)).is_equal("")
