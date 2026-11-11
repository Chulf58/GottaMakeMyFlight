class_name TestIncidentPanel
extends GdUnitTestSuite
## The major incident panel (decisions f49eac2a, decbc7ce; slice F): an
## announcement pauses the game until Continue and then gives back the player's
## speed; an offer carries Accept and Decline, which reach the director; the
## panel takes the clock's exclusive turn, so it waits behind an open unlock
## dialog or the Offers sheet and they wait behind it (first come, first
## served); a minor never opens it. What a load does is
## TestIncidentPanelLoad's. A MajorTestDirector stands in for the majors of
## slice G.

var _k := IncidentPanelKit.new()
var _clock: SimClock
var _director: MajorTestDirector
var _panel: IncidentPanel


func before_test() -> void:
	_k.build(self)
	_clock = _k.clock
	_director = _k.director
	_panel = _k.panel


func after_test() -> void:
	_k.port.free()


func test_an_announcement_pauses_and_continue_gives_back_the_players_speed() -> void:
	_clock.set_speed(2)
	_clock.set_paused(false)
	_k.announce()
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_true()
	assert_str(_panel.dialog().body_text()).contains("A test crew")
	_panel.dialog().continue_button().pressed.emit()
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)
	assert_array(_director.pending_presentation()).is_empty()


func test_the_players_own_speed_change_does_not_end_the_pause() -> void:
	_clock.set_paused(false)
	_k.announce()
	_clock.set_speed(3)
	_clock.set_paused(false)
	assert_bool(_clock.paused).is_true()
	_panel.dialog().continue_button().pressed.emit()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_an_announcement_has_continue_and_no_choice() -> void:
	_k.announce()
	assert_bool(_panel.dialog().accept_button() == null).is_true()
	assert_bool(_panel.dialog().continue_button().is_visible_in_tree()).is_true()
	assert_str(_panel.dialog().body_text()).not_contains("Reward")


func test_accept_reaches_the_director_and_resumes_the_game() -> void:
	_clock.set_speed(2)
	_clock.set_paused(false)
	var id := _k.offer()
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_true()
	assert_str(_k.state_of(id)).is_equal(IncidentCatalogue.OFFERED)
	_panel.dialog().accept_button().pressed.emit()
	assert_str(_k.state_of(id)).is_equal(IncidentCatalogue.ACCEPTED)
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_decline_reaches_the_director() -> void:
	var id := _k.offer()
	_panel.dialog().decline_button().pressed.emit()
	assert_str(_k.state_of(id)).is_equal(IncidentCatalogue.DECLINED)
	assert_bool(_panel.is_open()).is_false()
	assert_array(_director.pending_presentation()).is_empty()


func test_an_offer_names_its_reward_and_its_failure() -> void:
	_k.offer()
	var body := _panel.dialog().body_text()
	print("offer body: %s" % body)
	assert_str(body).contains("A test crew")
	assert_str(body).contains("Reward: Two stars of goodwill.")
	assert_str(body).contains("If it fails: They leave and tell their friends.")


func test_an_offer_without_a_reward_or_a_failure_is_not_shown() -> void:
	_panel.copy_for = func(_kind: String) -> Dictionary: return {"title": "T", "body": "B"}
	var id := _director.add_scheduled()
	assert_bool(_director.present(id, true)).is_true()
	assert_bool(_panel.is_open()).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_bool(_clock.paused).is_false()


func test_a_minor_incident_never_opens_the_panel() -> void:
	var spill := {
		"id": 1,
		"kind": IncidentCatalogue.SPILL,
		"state": IncidentCatalogue.ACTIVE,
		"place": "Check-in",
		"shown": false,
	}
	_director.started.emit(spill)
	_director.ended.emit(spill)
	assert_bool(_panel.is_open()).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_bool(_clock.paused).is_false()


func test_the_panel_waits_behind_an_open_unlock_dialog_and_opens_when_it_closes() -> void:
	_clock.set_speed(2)
	_clock.set_paused(false)
	var guide := _k.unlock_dialog()
	assert_bool(guide.is_open()).is_true()
	var id := _k.offer()
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_true()
	guide.dismiss()
	assert_bool(guide.is_open()).is_false()
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_true()
	_panel.dialog().accept_button().pressed.emit()
	assert_str(_k.state_of(id)).is_equal(IncidentCatalogue.ACCEPTED)
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_the_panel_waits_behind_the_offers_sheet_and_opens_when_it_is_released() -> void:
	var token := _k.sheet_takes_the_turn()
	assert_int(_k.sheet_turns).is_equal(1)
	_k.announce()
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_true()
	_clock.holds.release(token)
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_clock.paused).is_true()


func test_dialogs_take_the_turn_in_the_order_they_asked() -> void:
	var token := _k.sheet_takes_the_turn()
	_k.announce()
	var guide := _k.unlock_dialog()
	assert_bool(_panel.is_open()).is_false()
	assert_bool(guide.is_open()).is_false()
	_clock.holds.release(token)
	assert_bool(_panel.is_open()).is_true()
	assert_bool(guide.is_open()).is_false()
	_panel.dialog().continue_button().pressed.emit()
	assert_bool(_panel.is_open()).is_false()
	assert_bool(guide.is_open()).is_true()
	assert_bool(_clock.paused).is_true()
	guide.dismiss()
	assert_bool(_clock.paused).is_false()


func test_two_majors_show_one_after_the_other() -> void:
	var first := _k.offer()
	_k.announce()
	assert_bool(_panel.dialog().accept_button() != null).is_true()
	_panel.dialog().decline_button().pressed.emit()
	assert_str(_k.state_of(first)).is_equal(IncidentCatalogue.DECLINED)
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_panel.dialog().accept_button() == null).is_true()
	assert_bool(_clock.paused).is_true()
	_panel.dialog().continue_button().pressed.emit()
	assert_bool(_panel.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_array(_director.pending_presentation()).is_empty()


func test_leaving_the_tree_with_the_panel_open_does_not_leave_the_game_paused() -> void:
	_clock.set_paused(false)
	_k.offer()
	assert_bool(_clock.paused).is_true()
	_k.port.remove_child(_panel)
	assert_bool(_clock.paused).is_false()
	_panel.free()


func test_dialog_changed_tells_when_the_panel_opens_and_closes() -> void:
	var seen: Array[bool] = []
	_panel.dialog_changed.connect(func(open: bool) -> void: seen.append(open))
	_k.announce()
	_panel.dialog().continue_button().pressed.emit()
	assert_array(seen).is_equal([true, false])


func test_the_text_of_an_announcement_and_of_an_offer() -> void:
	var copy := MajorTestDirector.copy(MajorTestDirector.KIND)
	var announced := IncidentPanel.body_for(copy, false)
	var offered := IncidentPanel.body_for(copy, true)
	assert_str(announced).contains("A test crew")
	assert_str(announced).contains("The clock goes on when you close this.")
	assert_str(announced).not_contains("Reward")
	assert_str(offered).contains("Reward: Two stars of goodwill.")
	assert_str(offered).contains("If it fails: They leave and tell their friends.")
	assert_str(offered).contains("The clock stays paused until you choose.")
