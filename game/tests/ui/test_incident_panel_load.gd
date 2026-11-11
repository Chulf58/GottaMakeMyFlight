class_name TestIncidentPanelLoad
extends GdUnitTestSuite
## What a load does to the major incident panel (decision loading-a-save-always-
## comes-back-paused-at-1x-speed-with-hin): the clock comes back paused at 1x
## with every hold dropped, so the open panel ends and the director's pending
## majors show again. An unanswered offer and an announcement not yet closed
## do; an announcement already closed does not; a refused load changes nothing.
## The scene is the one TestIncidentPanel builds (IncidentPanelKit).

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


func test_a_load_shows_an_unanswered_offer_again() -> void:
	_clock.set_speed(2)
	_clock.set_paused(false)
	var id := _k.offer()
	assert_bool(_panel.is_open()).is_true()
	_k.load_happens()
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_panel.dialog().accept_button() != null).is_true()
	assert_bool(_clock.paused).is_true()
	_panel.dialog().accept_button().pressed.emit()
	assert_str(_k.state_of(id)).is_equal(IncidentCatalogue.ACCEPTED)
	# The load left the game paused at 1x; the answer gives it back to the player.
	assert_bool(_clock.paused).is_true()
	assert_int(_clock.speed).is_equal(1)
	_clock.set_paused(false)
	assert_bool(_clock.paused).is_false()


func test_a_load_shows_an_offer_that_was_still_waiting_for_its_turn() -> void:
	_k.sheet_takes_the_turn()
	var id := _k.offer()
	assert_bool(_panel.is_open()).is_false()
	_k.load_happens()
	assert_bool(_panel.is_open()).is_true()
	assert_int(_clock.holds.count()).is_equal(1)
	_panel.dialog().decline_button().pressed.emit()
	assert_str(_k.state_of(id)).is_equal(IncidentCatalogue.DECLINED)
	assert_int(_clock.holds.count()).is_equal(0)


func test_a_shown_announcement_is_not_shown_again_after_a_load() -> void:
	_k.announce()
	_panel.dialog().continue_button().pressed.emit()
	assert_bool(_panel.is_open()).is_false()
	_k.load_happens()
	assert_bool(_panel.is_open()).is_false()
	assert_int(_clock.holds.count()).is_equal(0)
	assert_bool(_clock.paused).is_true()


func test_an_announcement_not_closed_before_the_load_is_shown_again() -> void:
	_k.announce()
	assert_bool(_panel.is_open()).is_true()
	_k.load_happens()
	assert_bool(_panel.is_open()).is_true()
	assert_str(_panel.dialog().body_text()).contains("A test crew")
	_panel.dialog().continue_button().pressed.emit()
	assert_array(_director.pending_presentation()).is_empty()


func test_a_load_with_nothing_pending_opens_nothing() -> void:
	_k.load_happens()
	assert_bool(_panel.is_open()).is_false()
	assert_int(_clock.holds.count()).is_equal(0)


func test_a_refused_load_changes_nothing() -> void:
	_k.offer()
	var dialog := _panel.dialog()
	_k.save.loaded.emit(false)
	assert_bool(_panel.is_open()).is_true()
	assert_bool(_panel.dialog() == dialog).is_true()
	assert_bool(_clock.paused).is_true()
