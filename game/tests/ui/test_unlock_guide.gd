class_name TestUnlockGuide
extends GdUnitTestSuite
## The new-tier dialog and the "New" marks (decision new-unlock-tier-phone-ring-
## and-a-short-per-family-dialog-onc). What was shown and seen belongs to the
## game, so it lives in the BuildUnlocks snapshot, the save's "unlocks" part:
## the dialog shows once per tier when play opens it, never on a load, and a new
## game shows it again; it pauses the clock and gives back the player's speed;
## every unlocked card stays "New" until hovered or picked.

var _port: SubViewport
var _rating: AirportRating
var _pax: PassengerSim
var _clock: SimClock
var _unlocks: BuildUnlocks
var _guide: UnlockGuide
var _save: SaveGame
var _rings: Array[int] = []


func before_test() -> void:
	_rings.clear()
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	_build_world()


func after_test() -> void:
	_port.free()


## A fresh rating, passenger sim, unlocks and guide: a new game, or the
## session that loads a save.
func _build_world(mode := UnlockGuide.Mode.PROFILE) -> void:
	if is_instance_valid(_unlocks):
		_unlocks.queue_free()
	if is_instance_valid(_guide):
		_guide.queue_free()
	if is_instance_valid(_save):
		_save.queue_free()
	_rating = auto_free(AirportRating.new())
	_pax = auto_free(PassengerSim.new())
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = _rating
	_unlocks.passengers = _pax
	_unlocks.manual = true
	_port.add_child(_unlocks)
	_save = SaveGame.new()
	_port.add_child(_save)
	_guide = UnlockGuide.new()
	_guide.mode = mode
	_guide.unlocks = _unlocks
	_guide.clock = _clock
	_guide.save_game = _save
	_port.add_child(_guide)
	_guide.phone_ring.connect(func(tier: int) -> void: _rings.append(tier))


## Makes the airport earn `made` flights, then runs the check.
func _earn(made: int) -> void:
	for i in made + 10:
		_rating.record_passenger(0, true, PassengerSim.MOOD_MAX)
	for i in made:
		_pax.outcome.emit(i, true)
	_unlocks.check()


func test_the_dialog_opens_when_play_opens_a_tier_and_names_the_families() -> void:
	assert_bool(_guide.is_open()).is_false()
	_earn(50)
	assert_int(_unlocks.tier()).is_equal(2)
	assert_bool(_guide.is_open()).is_true()
	var body := _guide.dialog().body_text()
	assert_str(body).contains("Food:")
	assert_str(body).contains("Security:")
	assert_str(body).contains("Baggage:")
	assert_str(body).contains("Runway:")
	assert_str(body).contains("The clock goes on")
	assert_bool(_unlocks.dialog_shown(2)).is_true()


func test_the_phone_ring_hook_fires_with_the_dialog() -> void:
	_earn(50)
	assert_array(_rings).is_equal([2])


func test_a_load_opens_no_dialog() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 3, "made": 260})).is_true()
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_empty()


func test_a_saved_tier_never_shows_again_after_a_reload() -> void:
	_earn(50)
	_guide.dismiss()
	var data := JSON.parse_string(JSON.stringify(_unlocks.to_snapshot())) as Dictionary
	_build_world()
	_rings.clear()
	assert_bool(_unlocks.from_snapshot(data)).is_true()
	assert_bool(_unlocks.dialog_shown(2)).is_true()
	_earn(0)
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_empty()


func test_a_new_game_shows_the_tier_dialog_again() -> void:
	_earn(50)
	_guide.dismiss()
	_build_world()
	_rings.clear()
	assert_bool(_unlocks.dialog_shown(2)).is_false()
	_earn(50)
	assert_bool(_guide.is_open()).is_true()
	assert_array(_rings).is_equal([2])


func test_the_next_tier_still_shows_after_an_earlier_one_was_shown() -> void:
	_earn(50)
	_guide.dismiss()
	_earn(250)
	assert_int(_unlocks.tier()).is_equal(3)
	assert_bool(_guide.is_open()).is_true()
	assert_str(_guide.dialog().body_text()).not_contains("Security:")


func test_two_tiers_opened_together_get_one_dialog_with_both_tiers_families() -> void:
	_earn(250)
	assert_int(_unlocks.tier()).is_equal(3)
	assert_bool(_guide.is_open()).is_true()
	assert_str(_guide.dialog().body_text()).contains("Security:")
	assert_bool(_unlocks.dialog_shown(2)).is_true()
	assert_bool(_unlocks.dialog_shown(3)).is_true()
	assert_array(_rings).is_equal([3])


func test_a_skip_shows_exactly_the_tiers_not_shown_before() -> void:
	_unlocks.mark_dialog_shown(2)
	_earn(250)
	assert_int(_unlocks.tier()).is_equal(3)
	assert_bool(_guide.is_open()).is_true()
	var body := _guide.dialog().body_text()
	assert_str(body).not_contains("Security:")
	assert_str(body).not_contains("Baggage:")
	assert_str(body).contains("Runway:")


func test_a_guide_that_is_off_shows_nothing_and_marks_nothing() -> void:
	_build_world(UnlockGuide.Mode.OFF)
	_earn(50)
	assert_int(_unlocks.tier()).is_equal(2)
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_guide.is_new(BuildMode.Tool.CAFE_ROOM)).is_false()
	assert_bool(_unlocks.dialog_shown(2)).is_false()


func test_opening_pauses_and_closing_gives_back_the_players_speed() -> void:
	_clock.set_speed(2)
	_clock.set_paused(false)
	_earn(50)
	assert_bool(_clock.paused).is_true()
	_guide.dismiss()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(2)


func test_a_game_the_player_had_paused_stays_paused_after_the_dialog() -> void:
	_clock.set_paused(true)
	_earn(50)
	assert_bool(_guide.is_open()).is_true()
	_guide.dismiss()
	assert_bool(_clock.paused).is_true()


func test_a_clock_change_made_while_open_is_not_undone_on_close() -> void:
	_clock.set_paused(false)
	_earn(50)
	_clock.set_paused(false)
	_clock.set_speed(3)
	_guide.dismiss()
	assert_bool(_clock.paused).is_false()
	assert_int(_clock.speed).is_equal(3)


func test_leaving_the_tree_with_the_dialog_open_does_not_leave_the_game_paused() -> void:
	_clock.set_paused(false)
	_earn(50)
	assert_bool(_clock.paused).is_true()
	_port.remove_child(_guide)
	assert_bool(_clock.paused).is_false()
	_guide.free()


func test_a_save_and_load_with_the_dialog_open_shows_nothing_and_holds_nothing() -> void:
	_clock.set_paused(false)
	_earn(50)
	assert_bool(_guide.is_open()).is_true()
	var data := JSON.parse_string(JSON.stringify(_unlocks.to_snapshot())) as Dictionary
	# The saved clock was paused by the dialog; the load replaces it.
	assert_bool(_unlocks.from_snapshot(data)).is_true()
	_save.loaded.emit(true)
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_clock.paused).is_false()
	assert_array(_rings).is_equal([2])
	_earn(0)
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_equal([2])


func test_every_unlocked_card_is_new_until_picked() -> void:
	assert_bool(_guide.is_new(BuildMode.Tool.FLOOR)).is_false()
	_earn(50)
	assert_bool(_guide.is_new(BuildMode.Tool.CAFE_ROOM)).is_true()
	assert_bool(_guide.is_new(BuildMode.Tool.TREE)).is_false()
	assert_bool(_guide.is_new(BuildMode.Tool.FLOOR)).is_false()
	var marks := [0]
	_guide.changed.connect(func() -> void: marks[0] += 1)
	_guide.mark_seen(BuildMode.Tool.CAFE_ROOM)
	assert_bool(_guide.is_new(BuildMode.Tool.CAFE_ROOM)).is_false()
	assert_bool(_guide.is_new(BuildMode.Tool.COUNTER)).is_true()
	assert_int(marks[0]).is_equal(1)


func test_older_unseen_cards_stay_new_when_a_later_tier_opens() -> void:
	_earn(50)
	_guide.dismiss()
	_guide.mark_seen(BuildMode.Tool.CAFE_ROOM)
	_earn(250)
	assert_int(_unlocks.tier()).is_equal(3)
	assert_bool(_guide.is_new(BuildMode.Tool.COUNTER)).is_true()
	assert_bool(_guide.is_new(BuildMode.Tool.TREE)).is_true()
	assert_bool(_guide.is_new(BuildMode.Tool.CAFE_ROOM)).is_false()


func test_a_reload_keeps_seen_cards_seen_and_unseen_ones_new() -> void:
	_earn(50)
	_guide.mark_seen(BuildMode.Tool.CAFE_ROOM)
	var data := JSON.parse_string(JSON.stringify(_unlocks.to_snapshot())) as Dictionary
	_build_world()
	assert_bool(_unlocks.from_snapshot(data)).is_true()
	assert_bool(_guide.is_new(BuildMode.Tool.CAFE_ROOM)).is_false()
	assert_bool(_guide.is_new(BuildMode.Tool.COUNTER)).is_true()
	assert_bool(_guide.is_open()).is_false()


func test_a_new_game_marks_nothing_seen() -> void:
	_earn(50)
	_guide.mark_seen(BuildMode.Tool.CAFE_ROOM)
	_build_world()
	_earn(50)
	assert_bool(_guide.is_new(BuildMode.Tool.CAFE_ROOM)).is_true()
