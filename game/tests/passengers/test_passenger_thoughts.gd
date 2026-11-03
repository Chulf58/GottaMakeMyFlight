class_name TestPassengerThoughts
extends GdUnitTestSuite
## The shared thought recorder (decision passenger-inspect-thoughts-recorded-
## at-sim-outcomes-saved-pin-marks-where): what one record holds, the cap of
## shown thoughts, the long-queue episode that is updated and never added
## again, and repeat suppression that outlives an entry dropped by the cap.

const CELL := Vector2i(4, 7)
const ROOM := 31


func _passenger() -> Passenger:
	var p := Passenger.new()
	p.id = 9
	p.at = CELL
	return p


## A passenger standing in the check-in queue since `since`.
func _queuer(since: int) -> Passenger:
	var p := _passenger()
	p.stage = Passenger.Stage.CHECKIN_QUEUE
	p.stage_tick = since
	p.station = ROOM
	return p


func test_a_passenger_with_no_event_has_no_thoughts() -> void:
	var p := _passenger()
	PassengerThoughts.queued(p, 5000)
	print("thoughts %s" % [PassengerThoughts.entries(p)])
	assert_int(PassengerThoughts.count(p)).is_equal(0)
	assert_array(PassengerThoughts.entries(p)).is_empty()


func test_a_record_keeps_its_kind_tick_cell_facility_and_words() -> void:
	var p := _passenger()
	PassengerThoughts.record(p, PassengerThoughts.Kind.MEAL, 120, CELL, ROOM)
	var entries := PassengerThoughts.entries(p)
	print(entries)
	assert_int(entries.size()).is_equal(1)
	var entry: Dictionary = entries[0]
	assert_int(entry["kind"]).is_equal(PassengerThoughts.Kind.MEAL)
	assert_int(entry["tick"]).is_equal(120)
	assert_that(entry["cell"]).is_equal(CELL)
	assert_int(entry["facility"]).is_equal(ROOM)
	assert_str(entry["text"]).is_equal("That hit the spot")
	assert_bool(entry["positive"]).is_true()


func test_entries_are_newest_first_and_the_cap_drops_the_oldest() -> void:
	var p := _passenger()
	for i in PassengerThoughts.CAP + 2:
		PassengerThoughts.record(p, PassengerThoughts.Kind.TOILET_RELIEF, 100 + i, CELL, i + 1)
	var facilities := []
	for entry in PassengerThoughts.entries(p):
		facilities.append(entry["facility"])
	print("facilities newest first %s" % [facilities])
	assert_int(PassengerThoughts.count(p)).is_equal(PassengerThoughts.CAP)
	assert_array(facilities).is_equal([7, 6, 5, 4, 3])


func test_a_food_given_up_is_a_negative_thought() -> void:
	var p := _passenger()
	PassengerThoughts.record(p, PassengerThoughts.Kind.FOOD_GIVEN_UP, 50, CELL, ROOM)
	var entry: Dictionary = PassengerThoughts.entries(p)[0]
	assert_str(entry["text"]).is_equal("Gave up on getting food")
	assert_bool(entry["positive"]).is_false()


func test_a_short_wait_in_the_queue_is_no_thought() -> void:
	var p := _queuer(1000)
	PassengerThoughts.queued(p, 1000 + PassengerThoughts.LONG_QUEUE_TICKS - 1)
	assert_int(PassengerThoughts.count(p)).is_equal(0)


func test_a_long_queue_is_one_entry_that_grows_while_the_wait_lasts() -> void:
	var p := _queuer(1000)
	var long := PassengerThoughts.LONG_QUEUE_TICKS
	PassengerThoughts.queued(p, 1000 + long)
	PassengerThoughts.queued(p, 1000 + long + 5 * GameCalendar.TICKS_PER_MINUTE)
	p.at = CELL + Vector2i(0, -1)
	PassengerThoughts.queued(p, 1000 + long + 8 * GameCalendar.TICKS_PER_MINUTE)
	var entries := PassengerThoughts.entries(p)
	print(entries)
	assert_int(entries.size()).is_equal(1)
	var entry: Dictionary = entries[0]
	assert_int(entry["kind"]).is_equal(PassengerThoughts.Kind.LONG_QUEUE)
	assert_int(entry["tick"]).is_equal(1000)
	assert_int(entry["facility"]).is_equal(ROOM)
	assert_int(entry["value"]).is_equal(18)
	assert_that(entry["cell"]).is_equal(CELL + Vector2i(0, -1))
	assert_str(entry["text"]).is_equal("Waited 18 min in the queue")
	assert_bool(entry["positive"]).is_false()


func test_a_long_queue_dropped_by_the_cap_is_not_added_again() -> void:
	var p := _queuer(1000)
	var long := PassengerThoughts.LONG_QUEUE_TICKS
	PassengerThoughts.queued(p, 1000 + long)
	for i in PassengerThoughts.CAP:
		PassengerThoughts.record(p, PassengerThoughts.Kind.MEAL, 1300 + i, CELL, ROOM)
	PassengerThoughts.queued(p, 1000 + long + 100)
	var kinds := []
	for entry in PassengerThoughts.entries(p):
		kinds.append(entry["kind"])
	print("kinds %s" % [kinds])
	assert_array(kinds).not_contains([PassengerThoughts.Kind.LONG_QUEUE])
	assert_int(kinds.size()).is_equal(PassengerThoughts.CAP)


func test_a_new_queue_is_a_new_episode() -> void:
	var p := _queuer(1000)
	var long := PassengerThoughts.LONG_QUEUE_TICKS
	PassengerThoughts.queued(p, 1000 + long)
	p.stage = Passenger.Stage.SECURITY_QUEUE
	p.stage_tick = 3000
	PassengerThoughts.queued(p, 3000 + long)
	var ticks := []
	for entry in PassengerThoughts.entries(p):
		ticks.append(entry["tick"])
	print("episode starts %s" % [ticks])
	assert_array(ticks).is_equal([3000, 1000])


func test_nice_decor_is_kept_quiet_for_a_while_even_after_its_entry_is_dropped() -> void:
	var p := _passenger()
	PassengerThoughts.decor(p, 100, CELL)
	PassengerThoughts.decor(p, 100 + PassengerThoughts.DECOR_REPEAT_TICKS - 1, CELL)
	assert_int(PassengerThoughts.count(p)).is_equal(1)
	for i in PassengerThoughts.CAP:
		PassengerThoughts.record(p, PassengerThoughts.Kind.MEAL, 200 + i, CELL, ROOM)
	PassengerThoughts.decor(p, 300, CELL)
	var decor := 0
	for entry in PassengerThoughts.entries(p):
		if entry["kind"] == PassengerThoughts.Kind.NICE_DECOR:
			decor += 1
	assert_int(decor).is_equal(0)
	PassengerThoughts.decor(p, 100 + PassengerThoughts.DECOR_REPEAT_TICKS, CELL)
	var newest: Dictionary = PassengerThoughts.entries(p)[0]
	print(newest)
	assert_int(newest["kind"]).is_equal(PassengerThoughts.Kind.NICE_DECOR)
	assert_str(newest["text"]).is_equal("Nice decor here")
	assert_bool(newest["positive"]).is_true()


func test_the_recorder_refuses_a_thought_with_no_cell_or_the_wrong_facility() -> void:
	var p := _passenger()
	PassengerThoughts.record(p, PassengerThoughts.Kind.MEAL, 10, Passenger.NO_CELL, ROOM)
	PassengerThoughts.record(p, PassengerThoughts.Kind.TOILET_RELIEF, 11, CELL, 0)
	PassengerThoughts.record(p, PassengerThoughts.Kind.NICE_DECOR, 12, CELL, ROOM)
	assert_int(PassengerThoughts.count(p)).is_equal(0)
	assert_int(PassengerThoughts.mark_of(p, PassengerThoughts.Kind.MEAL)).is_equal(-1)
	PassengerThoughts.record(p, PassengerThoughts.Kind.MEAL, 13, CELL, ROOM)
	assert_int(PassengerThoughts.count(p)).is_equal(1)
	assert_bool(PassengerThoughts.sound(PassengerThoughts.Kind.LONG_QUEUE, ROOM, 7)).is_true()
	assert_bool(PassengerThoughts.sound(PassengerThoughts.Kind.LONG_QUEUE, 0, 7)).is_false()
	assert_bool(PassengerThoughts.sound(PassengerThoughts.Kind.NICE_DECOR, 0, 0)).is_true()
	assert_bool(PassengerThoughts.sound(PassengerThoughts.Kind.MEAL, ROOM, 1)).is_false()
