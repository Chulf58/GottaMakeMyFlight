class_name TestInfoDeskTuning
extends GdUnitTestSuite
## The info desk numbers (decision info-desk-helps-stuck-passengers-a-short-
## help-visit-with-a-m) are pinned here, each with its reason in InfoDesk, so a
## change to one is a change to this test. The relations between them are what
## make the desk a help and not a mood fountain.

const BEAT := PassengerSim.BEAT_TICKS


func test_the_numbers_are_pinned() -> void:
	assert_int(InfoDesk.RANGE_CELLS).is_equal(10)
	assert_int(InfoDesk.RANGE_MM).is_equal(10000)
	assert_int(InfoDesk.MAX_WALK_MM).is_equal(20000)
	assert_int(InfoDesk.HELP_TICKS).is_equal(60)
	assert_int(InfoDesk.BOOST).is_equal(15)
	assert_int(InfoDesk.STUCK_LOSS).is_equal(3)
	assert_int(InfoDesk.CALM_STUCK_LOSS).is_equal(1)
	assert_int(InfoDesk.COOLDOWN_TICKS).is_equal(600)


func test_the_statuses_and_stages_that_are_helped_are_pinned() -> void:
	(
		assert_array(InfoDesk.HELPABLE)
		. contains_exactly_in_any_order(
			[
				Passenger.Stuck.NO_CHECKIN,
				Passenger.Stuck.NO_SECURITY,
				Passenger.Stuck.NO_ROUTE,
				Passenger.Stuck.EXIT_BLOCKED,
			]
		)
	)
	assert_array(InfoDesk.HELP_STAGES).contains_exactly_in_any_order(
		[Passenger.Stage.TO_CHECKIN, Passenger.Stage.TO_SECURITY, Passenger.Stage.TO_EXIT]
	)


func test_the_numbers_keep_the_relations_their_reasons_rest_on() -> void:
	# A help is a check-in transaction long; the cooldown is the kiosk's.
	assert_int(InfoDesk.HELP_TICKS).is_equal(PassengerSim.CHECKIN_TICKS)
	assert_int(InfoDesk.COOLDOWN_TICKS).is_equal(ShopSim.BROWSE_COOLDOWN_TICKS)
	# The desk's reach is further than a kiosk's browse reach, landside and airside.
	assert_int(InfoDesk.RANGE_MM).is_greater(ShopSim.AIRSIDE_BROWSE_REACH_MM)
	# The calm loss is a queue's (1 a beat) and below the stuck loss.
	assert_int(InfoDesk.CALM_STUCK_LOSS).is_equal(1)
	assert_int(InfoDesk.CALM_STUCK_LOSS).is_less(InfoDesk.STUCK_LOSS)
	# A hopeless wait still costs mood: a calm wait loses more over a cooldown
	# than one help gives back.
	@warning_ignore("integer_division")
	var lost_over_cooldown := InfoDesk.CALM_STUCK_LOSS * InfoDesk.COOLDOWN_TICKS / BEAT
	print("boost %d, lost over one cooldown %d" % [InfoDesk.BOOST, lost_over_cooldown])
	assert_int(InfoDesk.BOOST).is_less(lost_over_cooldown)
	# The boost is a visible lift, never most of the starting mood.
	assert_int(InfoDesk.BOOST).is_less(Passenger.MOOD_START / 2)
	# The walk limit is twice the range, a few seconds at the walking speed.
	assert_int(InfoDesk.MAX_WALK_MM).is_equal(2 * InfoDesk.RANGE_MM)
