class_name TestIncidentMajorSeam
extends GdUnitTestSuite
## What a major incident's panel needs of the IncidentDirector (slice F): a
## scheduled major becomes an announcement or an offer and says so
## (major_presented); the player's answer moves an offer to accepted or
## declined; visibility marks an announcement shown; pending_presentation()
## lists what the player has not dealt with yet, which is what a load
## re-presents. A MajorTestDirector stands in for the majors of slice G.

var _director: MajorTestDirector
var _presented: Array[Dictionary] = []


func before_test() -> void:
	_presented.clear()
	_director = auto_free(MajorTestDirector.new())
	_director.major_presented.connect(
		func(incident: Dictionary) -> void: _presented.append(incident)
	)


func _state_of(id: int) -> String:
	for incident in _director.incidents():
		if incident["id"] == id:
			return incident["state"]
	return ""


func _shown(id: int) -> bool:
	for incident in _director.incidents():
		if incident["id"] == id:
			return incident["shown"]
	return false


func test_presenting_a_scheduled_major_announces_it_and_says_so() -> void:
	var id := _director.add_scheduled()
	assert_bool(_director.present(id, false)).is_true()
	assert_str(_state_of(id)).is_equal(IncidentCatalogue.ANNOUNCED)
	assert_int(_presented.size()).is_equal(1)
	assert_int(_presented[0]["id"]).is_equal(id)
	assert_str(_presented[0]["state"]).is_equal(IncidentCatalogue.ANNOUNCED)


func test_presenting_as_an_offer_makes_it_offered() -> void:
	var id := _director.add_scheduled()
	assert_bool(_director.present(id, true)).is_true()
	assert_str(_state_of(id)).is_equal(IncidentCatalogue.OFFERED)
	assert_str(_presented[0]["state"]).is_equal(IncidentCatalogue.OFFERED)


func test_only_a_scheduled_incident_can_be_presented_and_only_once() -> void:
	var id := _director.add_scheduled()
	assert_bool(_director.present(999, false)).is_false()
	assert_bool(_director.present(id, true)).is_true()
	assert_bool(_director.present(id, true)).is_false()
	assert_bool(_director.present(id, false)).is_false()
	assert_int(_presented.size()).is_equal(1)
	assert_str(_state_of(id)).is_equal(IncidentCatalogue.OFFERED)


func test_accepting_and_declining_move_an_offer_on() -> void:
	var yes := _director.add_scheduled()
	var no := _director.add_scheduled()
	_director.present(yes, true)
	_director.present(no, true)
	assert_bool(_director.answer(yes, true)).is_true()
	assert_bool(_director.answer(no, false)).is_true()
	assert_str(_state_of(yes)).is_equal(IncidentCatalogue.ACCEPTED)
	assert_str(_state_of(no)).is_equal(IncidentCatalogue.DECLINED)


func test_an_answer_is_taken_once_and_only_for_an_offer() -> void:
	var offer := _director.add_scheduled()
	var announced := _director.add_scheduled()
	_director.present(offer, true)
	_director.present(announced, false)
	assert_bool(_director.answer(offer, true)).is_true()
	assert_bool(_director.answer(offer, false)).is_false()
	assert_str(_state_of(offer)).is_equal(IncidentCatalogue.ACCEPTED)
	assert_bool(_director.answer(announced, true)).is_false()
	assert_str(_state_of(announced)).is_equal(IncidentCatalogue.ANNOUNCED)
	assert_bool(_director.answer(999, true)).is_false()


func test_a_minor_is_never_presented_and_stays_scheduled() -> void:
	var spill := _director.add_scheduled(IncidentCatalogue.SPILL)
	assert_bool(_director.present(spill, false)).is_false()
	assert_bool(_director.present(spill, true)).is_false()
	assert_str(_state_of(spill)).is_equal(IncidentCatalogue.SCHEDULED)
	assert_array(_presented).is_empty()
	assert_array(_director.pending_presentation()).is_empty()


func test_an_announcement_is_marked_shown_once() -> void:
	var id := _director.add_scheduled()
	_director.present(id, false)
	assert_bool(_shown(id)).is_false()
	assert_bool(_director.acknowledge(id)).is_true()
	assert_bool(_shown(id)).is_true()
	assert_bool(_director.acknowledge(id)).is_false()
	assert_str(_state_of(id)).is_equal(IncidentCatalogue.ANNOUNCED)


func test_only_an_announcement_can_be_acknowledged() -> void:
	var offer := _director.add_scheduled()
	var waiting := _director.add_scheduled()
	_director.present(offer, true)
	assert_bool(_director.acknowledge(offer)).is_false()
	assert_bool(_director.acknowledge(waiting)).is_false()
	assert_bool(_director.acknowledge(999)).is_false()


func test_pending_presentation_lists_what_the_player_has_not_dealt_with() -> void:
	var unseen := _director.add_scheduled()
	var seen := _director.add_scheduled()
	var open_offer := _director.add_scheduled()
	var answered := _director.add_scheduled()
	var not_yet := _director.add_scheduled()
	_director.present(unseen, false)
	_director.present(seen, false)
	_director.acknowledge(seen)
	_director.present(open_offer, true)
	_director.present(answered, true)
	_director.answer(answered, false)
	var ids: Array = _director.pending_presentation().map(
		func(incident: Dictionary) -> int: return incident["id"]
	)
	print("pending %s, not yet presented %d" % [ids, not_yet])
	assert_array(ids).is_equal([unseen, open_offer])


func test_the_shown_flag_is_saved_with_the_incident() -> void:
	var id := _director.add_scheduled()
	_director.present(id, false)
	_director.acknowledge(id)
	var saved: Array = _director.to_snapshot()["incidents"]
	assert_bool(saved[0]["shown"]).is_true()
