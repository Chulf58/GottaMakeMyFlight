class_name TestIncidentSnapshot
extends GdUnitTestSuite
## The "incidents" save part's shape check (IncidentSnapshot.load): a good
## part, also after JSON, loads with ints; each malformed field is refused
## with a reason that names it.


static func _good() -> Dictionary:
	return {
		"save_version": IncidentSnapshot.SAVE_VERSION,
		"enabled": true,
		"last_rolled_day": 3,
		"next_major_day": 0,
		"next_id": 3,
		"incidents":
		[
			{
				"id": 1,
				"kind": IncidentCatalogue.SPILL,
				"roll_day": 2,
				"state": IncidentCatalogue.ACTIVE,
				"fire_tick": 40_000,
				"cell": [12, 7],
				"mess_id": 4,
				"place": "Check-in",
				"outcome": "",
				"shown": false,
				"plan": {},
			},
			{
				"id": 2,
				"kind": IncidentCatalogue.SPILL,
				"roll_day": 3,
				"state": IncidentCatalogue.SCHEDULED,
				"fire_tick": 70_000,
				"cell": [-1, -1],
				"mess_id": 0,
				"place": "",
				"outcome": "",
				"shown": false,
				"plan": {},
			},
		],
	}


func _refusal(data: Dictionary) -> String:
	return str(IncidentSnapshot.load(data).get("error", ""))


func test_a_good_part_loads_also_after_json() -> void:
	var through: Dictionary = JSON.parse_string(JSON.stringify(_good()))
	var loaded := IncidentSnapshot.load(through)
	print("loaded %s" % [loaded])
	assert_bool(loaded.has("error")).is_false()
	assert_int(loaded["incidents"].size()).is_equal(2)
	assert_int(typeof(loaded["incidents"][0]["fire_tick"])).is_equal(TYPE_INT)
	assert_object(loaded["incidents"][0]["cell"]).is_equal(Vector2i(12, 7))
	assert_int(loaded["last_rolled_day"]).is_equal(3)


func test_the_shown_flag_loads_as_saved_also_after_json() -> void:
	var loaded := IncidentSnapshot.load(JSON.parse_string(JSON.stringify(_good())))
	assert_bool(loaded.has("error")).is_false()
	assert_bool(loaded["incidents"][0]["shown"]).is_false()
	assert_bool(loaded["incidents"][1]["shown"]).is_false()
	assert_int(IncidentSnapshot.SAVE_VERSION).is_equal(3)


## Only an announcement can be shown. The rule is checked on the state check itself,
## which takes no kind.
func test_only_an_announcement_can_be_shown() -> void:
	var cases := {
		IncidentCatalogue.ANNOUNCED: true,
		IncidentCatalogue.SCHEDULED: false,
		IncidentCatalogue.OFFERED: false,
		IncidentCatalogue.ACCEPTED: false,
		IncidentCatalogue.DECLINED: false,
		IncidentCatalogue.DONE: false,
	}
	for state: String in cases:
		var incident := _good()["incidents"][1] as Dictionary
		incident["state"] = state
		incident["shown"] = true
		var got := IncidentSnapshot._state_problem(incident, IncidentSnapshot.NO_CELL)
		print("%s shown -> '%s'" % [state, got])
		if cases[state]:
			assert_str(got).is_empty()
		else:
			assert_str(got).contains("shown but is not an announcement")
		incident["shown"] = false
		assert_str(IncidentSnapshot._state_problem(incident, IncidentSnapshot.NO_CELL)).is_empty()


func test_a_spill_that_had_no_place_loads_as_done_with_its_outcome() -> void:
	var data := _good()
	data["incidents"][1]["state"] = IncidentCatalogue.DONE
	data["incidents"][1]["outcome"] = IncidentSnapshot.NO_PLACE
	var loaded := IncidentSnapshot.load(data)
	assert_bool(loaded.has("error")).is_false()
	assert_str(loaded["incidents"][1]["outcome"]).is_equal(IncidentSnapshot.NO_PLACE)


## The cross-part check (SaveGame staging): an active spill names a SPILL mess
## of the staged messes at its own cell.
## A done incident is placed all the way (it happened) or not at all; one that
## never happened (no_place) has no cell, mess or place.
func test_a_done_incident_is_placed_whole_or_not_at_all() -> void:
	var never := "did not happen but has"
	var partly := "only partly placed"
	var cases := [
		[never, {"cell": [3, 2], "outcome": IncidentSnapshot.NO_PLACE}],
		[never, {"mess_id": 5, "outcome": IncidentSnapshot.NO_PLACE}],
		[never, {"place": "Security", "outcome": IncidentSnapshot.NO_PLACE}],
		[partly, {"cell": [3, 2], "mess_id": 5}],
		[partly, {"place": "Security"}],
	]
	for entry: Array in cases:
		var data := _good()
		data["incidents"][1]["state"] = IncidentCatalogue.DONE
		(data["incidents"][1] as Dictionary).merge(entry[1], true)
		var got := _refusal(data)
		print("%s -> %s" % [entry[1], got])
		assert_str(got).contains(entry[0])
	# The controls: done after it happened, and done before it was placed.
	var happened := _good()
	happened["incidents"][0]["state"] = IncidentCatalogue.DONE
	assert_str(_refusal(happened)).is_empty()
	var dropped := _good()
	dropped["incidents"][1]["state"] = IncidentCatalogue.DONE
	assert_str(_refusal(dropped)).is_empty()


func test_an_active_spill_must_name_a_spill_mess_at_its_cell() -> void:
	var incidents := IncidentSnapshot.load(_good())
	var spill := {"cell": Vector2i(12, 7), "kind": MessSim.Kind.SPILL}
	var cases := {
		"": {4: spill},
		"no mess 4": {5: spill},
		"not a spill": {4: {"cell": Vector2i(12, 7), "kind": MessSim.Kind.LITTER}},
		"not at the incident's cell": {4: {"cell": Vector2i(12, 8), "kind": MessSim.Kind.SPILL}},
	}
	for want: String in cases:
		var got := IncidentSnapshot.links_problem(incidents, {"messes": cases[want]})
		print("'%s' -> '%s'" % [want, got])
		if want == "":
			assert_str(got).is_empty()
		else:
			assert_str(got).contains(want)


func test_each_malformed_field_is_refused() -> void:
	var cases := {
		"missing key 'next_major_day'": func(d: Dictionary) -> void: d.erase("next_major_day"),
		"unknown key 'extra'": func(d: Dictionary) -> void: d["extra"] = 1,
		"save_version must be": func(d: Dictionary) -> void: d["save_version"] = 1,
		"enabled must be a bool": func(d: Dictionary) -> void: d["enabled"] = 1,
		"last_rolled_day must be": func(d: Dictionary) -> void: d["last_rolled_day"] = -2,
		"incidents must be an array": func(d: Dictionary) -> void: d["incidents"] = {},
		"unknown kind": func(d: Dictionary) -> void: d["incidents"][0]["kind"] = "fire",
		"cannot be in state": func(d: Dictionary) -> void: d["incidents"][0]["state"] = "offered",
		"active but lacks": func(d: Dictionary) -> void: d["incidents"][0]["mess_id"] = 0,
		"scheduled but has": func(d: Dictionary) -> void: d["incidents"][1]["place"] = "Security",
		"not below next_id": func(d: Dictionary) -> void: d["next_id"] = 2,
		"saved twice": func(d: Dictionary) -> void: d["incidents"][1]["id"] = 1,
		"cell must be": func(d: Dictionary) -> void: d["incidents"][0]["cell"] = [1.5, 2],
		"fire_tick must be": func(d: Dictionary) -> void: d["incidents"][0]["fire_tick"] = "9",
		"not a spill place": func(d: Dictionary) -> void: d["incidents"][0]["place"] = "Gate",
		"unknown outcome": func(d: Dictionary) -> void: d["incidents"][1]["outcome"] = "lost",
		"outcome but is not done":
		func(d: Dictionary) -> void: d["incidents"][1]["outcome"] = IncidentSnapshot.NO_PLACE,
		"missing key 'shown'": func(d: Dictionary) -> void: d["incidents"][0].erase("shown"),
		"shown must be a bool": func(d: Dictionary) -> void: d["incidents"][0]["shown"] = 1,
		"shown but is not an announcement":
		func(d: Dictionary) -> void: d["incidents"][0]["shown"] = true,
	}
	for want: String in cases:
		var data := _good()
		(cases[want] as Callable).call(data)
		var got := _refusal(data)
		print("%s -> %s" % [want, got])
		assert_str(got).contains(want)
