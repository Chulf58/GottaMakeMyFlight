class_name TestPassengerCardLines
extends GdUnitTestSuite
## The lines of the passenger inspect card (decision follow-invitation-and-
## passenger-card-a-click-a-passenger-fir): a generated name, a trip line from
## the arrival type and the shop wish, and a bag line from the carry-on count,
## liquids and the checked bag's state. The name and the trip line come from the
## passenger's id and arrival type alone, so a save and a load give the same.

var _a: PassengerTestWorld
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


func _passenger(stage: Passenger.Stage, carry_on := 1, liquids := false) -> Passenger:
	var p := Passenger.new()
	p.id = 7
	p.stage = stage
	p.carry_on = carry_on
	p.liquids = liquids
	return p


func _bag(state: Bag.State) -> Bag:
	var bag := Bag.new()
	bag.passenger = 7
	bag.state = state
	return bag


func test_a_name_is_two_words_and_the_same_for_the_same_id() -> void:
	for id in range(1, 200):
		var named := PassengerNames.name_of(id)
		assert_int(named.split(" ").size()).is_equal(2)
		assert_str(named).is_equal(PassengerNames.name_of(id))
		assert_bool(named.contains("Passenger")).is_false()


func test_names_spread_over_the_pool() -> void:
	var seen := {}
	for id in range(1, 301):
		seen[PassengerNames.name_of(id)] = true
	# 300 ids over 1600 combinations: nearly all distinct, so passengers read as people.
	print("distinct names in 300 ids: %d" % seen.size())
	assert_int(seen.size()).is_greater(250)
	var firsts := {}
	for id in range(1, 301):
		firsts[PassengerNames.name_of(id).split(" ")[0]] = true
	assert_int(firsts.size()).is_greater(30)


func test_the_pools_are_plain_unique_letters() -> void:
	for pool: Array[String] in [PassengerNames.FIRST, PassengerNames.LAST]:
		var unique := {}
		for word in pool:
			unique[word] = true
			assert_bool(word.to_ascii_buffer().size() == word.length()).is_true()
		assert_int(unique.size()).is_equal(pool.size())


func test_every_arrival_type_and_wish_has_a_trip_line() -> void:
	var seen := {}
	for type in ArrivalTypes.Type.values():
		var lines: Dictionary = PassengerTrip.LINES[type]
		assert_array(lines.keys()).contains_exactly_in_any_order(
			[WishTable.NONE] + WishTable.CANDIDATES
		)
		for wish: StringName in lines:
			assert_str(lines[wish]).is_not_empty()
			seen[lines[wish]] = true
	assert_int(seen.size()).is_equal(15)


func test_the_trip_line_names_the_arrival_and_the_wish() -> void:
	var p := Passenger.new()
	var relaxed_duty_free := false
	var rushed_none := false
	for id in range(1, 400):
		p.id = id
		for type in ArrivalTypes.Type.values():
			p.arrival_type = type
			var line := PassengerTrip.line(p)
			assert_str(line).is_equal(PassengerTrip.english(p))
			if type == ArrivalTypes.Type.RELAXED and WishTable.of(p) == &"duty_free":
				assert_str(line).is_equal("Early bird, hoping for duty free")
				relaxed_duty_free = true
			if type == ArrivalTypes.Type.RUSHED and WishTable.of(p) == WishTable.NONE:
				assert_str(line).is_equal("Cutting it fine, no shopping planned")
				rushed_none = true
	assert_bool(relaxed_duty_free and rushed_none).is_true()


func test_the_trip_msgids_match_the_lines() -> void:
	PseudoLocale.disable()
	var ids := PassengerTrip.Words.new().msgids()
	var wanted := []
	for type in PassengerTrip.LINES:
		wanted.append_array((PassengerTrip.LINES[type] as Dictionary).values())
	assert_array(Array(ids)).contains_exactly_in_any_order(wanted)


func test_the_bag_line_for_every_checked_bag_state() -> void:
	var words := {
		Bag.State.AT_DESK: "a checked bag at the desk",
		Bag.State.RIDING: "a checked bag on the belt",
		Bag.State.BLOCKED: "a checked bag stuck on the belt",
		Bag.State.IN_ROOM: "a checked bag in the bag room",
		Bag.State.LOADED: "a checked bag loaded on the plane",
		Bag.State.MISSED: "a checked bag that missed the plane",
	}
	var baggage := BaggageSim.new()
	for state: Bag.State in words:
		var p := _passenger(Passenger.Stage.TO_GATE)
		baggage.bags().append(_bag(state))
		assert_str(PassengerBags.line(p, baggage)).is_equal("1 carry-on bag and %s" % words[state])
		baggage.bags().clear()
	baggage.free()


func test_a_passenger_without_a_bag_is_still_to_drop_one_off_or_has_none() -> void:
	var baggage := BaggageSim.new()
	var before_desk := _passenger(Passenger.Stage.CHECKIN_QUEUE)
	assert_str(PassengerBags.line(before_desk, baggage)).is_equal(
		"1 carry-on bag and a checked bag still to drop off"
	)
	var after_desk := _passenger(Passenger.Stage.SECURITY_QUEUE)
	assert_str(PassengerBags.line(after_desk, baggage)).is_equal(
		"1 carry-on bag and no checked bag"
	)
	baggage.free()


func test_the_bag_line_counts_carry_ons_and_names_liquids() -> void:
	var baggage := BaggageSim.new()
	baggage.bags().append(_bag(Bag.State.RIDING))
	assert_str(PassengerBags.line(_passenger(Passenger.Stage.TO_GATE, 0), baggage)).is_equal(
		"No carry-on bags and a checked bag on the belt"
	)
	assert_str(PassengerBags.line(_passenger(Passenger.Stage.TO_GATE, 2), baggage)).is_equal(
		"2 carry-on bags and a checked bag on the belt"
	)
	assert_str(PassengerBags.line(_passenger(Passenger.Stage.TO_GATE, 1, true), baggage)).is_equal(
		"1 carry-on bag, carrying liquids and a checked bag on the belt"
	)
	# Liquids are carried in a carry-on: none, none to name.
	assert_str(PassengerBags.line(_passenger(Passenger.Stage.TO_GATE, 0, true), baggage)).is_equal(
		"No carry-on bags and a checked bag on the belt"
	)
	baggage.free()


func test_without_a_baggage_sim_the_line_leaves_the_checked_bag_out() -> void:
	assert_str(PassengerBags.line(_passenger(Passenger.Stage.TO_GATE, 2, true), null)).is_equal(
		"2 carry-on bags and carrying liquids"
	)


func test_the_bag_msgids_cover_every_state() -> void:
	PseudoLocale.disable()
	var ids := PassengerBags.Words.new().msgids()
	assert_int(ids.size()).is_equal(3 + PassengerBags.Checked.size())
	assert_array(Array(ids)).contains(["a checked bag that missed the plane"])


## The name, the trip line and the bag line of each passenger of world `world`.
func _cards(world: PassengerTestWorld, ids: Array[int]) -> Dictionary:
	var out := {}
	for id in ids:
		var p := world.passenger(id)
		out[id] = [PassengerNames.name_of(id), PassengerTrip.line(p), PassengerBags.line(p, null)]
	return out


func test_name_trip_and_bag_lines_are_the_same_after_a_save_and_a_load() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_a = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	var ids: Array[int] = []
	for i in 9:
		var id := _a.sim.spawn_now(PassengerTestWorld.FLIGHT)
		_a.passenger(id).arrival_type = ArrivalTypes.Type.values()[i % 3]
		ids.append(id)
	_a.step()
	var before := _cards(_a, ids)
	var data: Dictionary = (
		JSON
		. parse_string(
			(
				JSON
				. stringify(
					{
						"clock": _a.clock.to_snapshot(),
						"flights": _a.flights.to_snapshot(),
						"grid": _a.grid.to_snapshot(),
						"passengers": _a.sim.to_snapshot(),
					}
				)
			)
		)
	)
	var other := BuildGrid.new()
	assert_bool(other.from_snapshot(data["grid"])).is_true()
	_b = PassengerTestWorld.make(other, PassengerTestWorld.starts_with(10, 20), 99)
	assert_bool(_b.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(_b.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(_b.sim.from_snapshot(data["passengers"])).is_true()
	var after := _cards(_b, ids)
	print("saved cards: %s" % before)
	assert_dict(after).is_equal(before)
	# The control: the three arrival types did give different trip lines.
	var trips := {}
	for id in ids:
		trips[before[id][1]] = true
	assert_int(trips.size()).is_greater(2)
