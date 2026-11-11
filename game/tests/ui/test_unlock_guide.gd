class_name TestUnlockGuide
extends GdUnitTestSuite
## The new-tier dialog and the "New" marks (decision new-unlock-tier-phone-ring-
## and-a-short-per-family-dialog-onc): the dialog shows once per tier when play
## opens it, never on a load, never again for a tier already shown on this
## profile; it pauses the clock and gives back the player's speed; the cards of
## the newest tier stay "New" until hovered or picked, and a reload does not
## mark old cards again.

var _port: SubViewport
var _rating: AirportRating
var _pax: PassengerSim
var _clock: SimClock
var _unlocks: BuildUnlocks
var _guide: UnlockGuide
var _path := SaveTestKit.run_path("test_unlock_guide")
var _rings: Array[int] = []


func before_test() -> void:
	_remove_files()
	_rings.clear()
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_clock = SimClock.new()
	_port.add_child(_clock)
	_build_world()


func after_test() -> void:
	_port.free()
	_remove_files()


func _remove_files() -> void:
	for file in [_path, _path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## A fresh rating, passenger sim, unlocks and guide on the same settings file:
## what a new session of the same profile builds.
func _build_world(mode := UnlockGuide.Mode.PROFILE) -> void:
	if is_instance_valid(_unlocks):
		_unlocks.queue_free()
	if is_instance_valid(_guide):
		_guide.queue_free()
	_rating = auto_free(AirportRating.new())
	_pax = auto_free(PassengerSim.new())
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = _rating
	_unlocks.passengers = _pax
	_unlocks.manual = true
	_port.add_child(_unlocks)
	_guide = UnlockGuide.new()
	_guide.mode = mode
	_guide.settings_path = _path
	_guide.unlocks = _unlocks
	_guide.clock = _clock
	_port.add_child(_guide)
	_guide.phone_ring.connect(func(tier: int) -> void: _rings.append(tier))


## Makes the airport earn `stars` and `made` flights, then runs the check.
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
	assert_bool(_guide.dialog_shown(2)).is_true()


func test_the_phone_ring_hook_fires_with_the_dialog() -> void:
	_earn(50)
	assert_array(_rings).is_equal([2])


func test_a_load_opens_no_dialog() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 3, "made": 260})).is_true()
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_guide.dialog_shown(3)).is_false()
	assert_array(_rings).is_empty()


func test_a_tier_shown_once_never_shows_again_after_a_reload() -> void:
	_earn(50)
	_guide.dismiss()
	assert_bool(_guide.is_open()).is_false()
	# The same profile in a new session: an earlier save is loaded and the tier
	# opens by play a second time.
	_build_world()
	_rings.clear()
	assert_bool(_unlocks.from_snapshot({"tier": 1, "made": 0})).is_true()
	_earn(50)
	assert_int(_unlocks.tier()).is_equal(2)
	assert_bool(_guide.is_open()).is_false()
	assert_array(_rings).is_empty()


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
	assert_bool(_guide.dialog_shown(2)).is_true()
	assert_bool(_guide.dialog_shown(3)).is_true()
	assert_array(_rings).is_equal([3])


func test_a_guide_that_is_off_shows_nothing_and_marks_nothing() -> void:
	_build_world(UnlockGuide.Mode.OFF)
	_earn(50)
	assert_int(_unlocks.tier()).is_equal(2)
	assert_bool(_guide.is_open()).is_false()
	assert_bool(_guide.is_new(BuildMode.Tool.CAFE_ROOM)).is_false()
	assert_bool(_guide.dialog_shown(2)).is_false()


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


func test_the_cards_of_the_newest_tier_are_new_until_picked() -> void:
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


func test_a_reload_does_not_mark_seen_cards_again_but_marks_unseen_ones() -> void:
	_earn(50)
	_guide.mark_seen(BuildMode.Tool.CAFE_ROOM)
	_build_world()
	assert_bool(_unlocks.from_snapshot({"tier": 2, "made": 60})).is_true()
	assert_bool(_guide.is_new(BuildMode.Tool.CAFE_ROOM)).is_false()
	assert_bool(_guide.is_new(BuildMode.Tool.COUNTER)).is_true()
	assert_bool(_guide.is_open()).is_false()


func test_a_load_to_a_higher_tier_marks_only_that_tiers_cards() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 3, "made": 260})).is_true()
	assert_bool(_guide.is_new(BuildMode.Tool.TREE)).is_true()
	assert_bool(_guide.is_new(BuildMode.Tool.CAFE_ROOM)).is_false()
