class_name TestBuildUnlocks
extends GdUnitTestSuite
## The build tiers (decision build-unlocks-need-stars-and-passengers-served-
## hunger-cafe-a): a new game offers only the start set, a tier opens when the
## stars AND the made-flight passengers are both met, an open tier stays open,
## the check runs once a game day, the cafe tier turns hunger on, and the
## state goes through a snapshot. BuildMode refuses a locked tool.

var _rating: AirportRating
var _pax: PassengerSim
var _unlocks: BuildUnlocks
var _opened: Array[String] = []


func before_test() -> void:
	_rating = auto_free(AirportRating.new())
	_pax = auto_free(PassengerSim.new())
	_unlocks = auto_free(BuildUnlocks.new())
	_unlocks.rating = _rating
	_unlocks.passengers = _pax
	_unlocks.manual = true
	add_child(_unlocks)
	_opened.clear()
	_unlocks.unlocked.connect(func(_tier: int, text: String) -> void: _opened.append(text))


## `count` passengers that made their flight at mood 100 (rating stars rise).
func _good_days(count: int) -> void:
	for i in count:
		_rating.record_passenger(0, true, PassengerSim.MOOD_MAX)


## `count` passengers that missed it (the rating falls to 1 star).
func _bad_days(count: int) -> void:
	for i in count:
		_rating.record_passenger(0, false, 0)


## `count` more passengers made their flight, through the sim's own signal.
func _made(count: int) -> void:
	for i in count:
		_pax.outcome.emit(i, true)


func test_a_new_game_offers_only_the_start_set() -> void:
	var start: Array = BuildUnlocks.TIERS[0]["tools"]
	var open := 0
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		var expect_open := (
			tool == BuildMode.Tool.NONE or tool == BuildMode.Tool.REMOVE or start.has(tool)
		)
		assert_bool(_unlocks.allows(tool)).is_equal(expect_open)
		open += 1 if _unlocks.allows(tool) else 0
	print("open tools in a new game: %d of %d" % [open, BuildMode.Tool.size()])
	assert_int(_unlocks.tier()).is_equal(1)
	assert_int(open).is_equal(start.size() + 2)
	assert_bool(_unlocks.cafe_open()).is_false()


func test_the_start_set_is_the_ruled_one() -> void:
	var names: Array = []
	for tool: BuildMode.Tool in BuildUnlocks.TIERS[0]["tools"]:
		names.append(BuildMode.Tool.find_key(tool))
	(
		assert_array(names)
		. contains_exactly(
			[
				"FLOOR",
				"WALL",
				"GLASS",
				"DOOR",
				"ENTRANCE",
				"EXIT",
				"DESK",
				"SCANNER",
				"GATE_DESK",
				"SEATS",
				"TOILET_ROOM",
				"TOILET_STALL",
				"TOILET_SINK",
				"BUY_LAND",
			]
		)
	)


func test_every_tool_is_in_exactly_one_tier() -> void:
	var seen := {}
	for tier in BuildUnlocks.TIERS:
		for tool: BuildMode.Tool in tier["tools"]:
			assert_bool(seen.has(tool)).is_false()
			seen[tool] = true
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		if tool == BuildMode.Tool.NONE or tool == BuildMode.Tool.REMOVE:
			assert_int(BuildUnlocks.tier_of(tool)).is_equal(0)
		else:
			assert_int(BuildUnlocks.tier_of(tool)).is_between(1, BuildUnlocks.TIERS.size())


func test_the_tiers_hold_the_ruled_bundles() -> void:
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.CAFE_ROOM)).is_equal(2)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.BIN)).is_equal(2)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.ARCH)).is_equal(2)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.CURB)).is_equal(2)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.TREE)).is_equal(3)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.LOT_GATE)).is_equal(3)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.WORK_DESK)).is_equal(3)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.MULTI_STOREY)).is_equal(4)
	assert_int(BuildUnlocks.tier_of(BuildMode.Tool.PRIZE_PODIUM)).is_equal(4)


func test_stars_alone_do_not_open_a_tier() -> void:
	_good_days(60)
	assert_float(_rating.stars()).is_greater_equal(4.0)
	_unlocks.check()
	assert_int(_unlocks.tier()).is_equal(1)


func test_passengers_alone_do_not_open_a_tier() -> void:
	_bad_days(60)
	assert_float(_rating.stars()).is_less(2.0)
	_made(700)
	_unlocks.check()
	assert_int(_unlocks.made_total()).is_equal(700)
	assert_int(_unlocks.tier()).is_equal(1)


func test_meeting_the_stars_and_the_passengers_opens_the_tier() -> void:
	_good_days(60)
	_made(49)
	_unlocks.check()
	assert_int(_unlocks.tier()).is_equal(1)
	_made(1)
	_unlocks.check()
	print("after 50 made: tier %d, announced %s" % [_unlocks.tier(), _opened])
	assert_int(_unlocks.tier()).is_equal(2)
	assert_bool(_unlocks.allows(BuildMode.Tool.CAFE_ROOM)).is_true()
	assert_bool(_unlocks.allows(BuildMode.Tool.TREE)).is_false()
	assert_array(_opened).has_size(1)
	assert_str(_opened[0]).contains("cafe")


func test_a_missed_passenger_is_not_counted() -> void:
	_pax.outcome.emit(1, false)
	assert_int(_unlocks.made_total()).is_equal(0)


func test_a_good_game_can_open_several_tiers_at_once() -> void:
	_good_days(700)
	_made(600)
	_unlocks.check()
	assert_int(_unlocks.tier()).is_equal(4)
	assert_array(_opened).has_size(1)
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		assert_bool(_unlocks.allows(tool)).is_true()


func test_an_open_tier_stays_open_when_the_rating_falls() -> void:
	_good_days(60)
	_made(50)
	_unlocks.check()
	assert_int(_unlocks.tier()).is_equal(2)
	# A rating that only missed passengers: 1 star.
	_rating = auto_free(AirportRating.new())
	_unlocks.rating = _rating
	_bad_days(60)
	assert_float(_rating.stars()).is_less(2.0)
	_unlocks.check()
	assert_int(_unlocks.tier()).is_equal(2)
	assert_bool(_unlocks.allows(BuildMode.Tool.CAFE_ROOM)).is_true()


func test_the_check_runs_on_the_first_tick_of_each_game_day() -> void:
	_unlocks.on_tick(0)
	_good_days(60)
	_made(50)
	_unlocks.on_tick(1)
	assert_int(_unlocks.tier()).is_equal(1)
	_unlocks.on_tick(GameCalendar.TICKS_PER_DAY)
	assert_int(_unlocks.tier()).is_equal(2)


func test_hunger_starts_with_the_cafe_tier() -> void:
	assert_bool(_pax.cafes.hunger_enabled).is_false()
	_good_days(60)
	_made(50)
	_unlocks.check()
	assert_bool(_pax.cafes.hunger_enabled).is_true()


func test_a_card_says_what_unlocks_it_and_how_far_the_game_is() -> void:
	_made(12)
	assert_str(_unlocks.unlock_text(BuildMode.Tool.CAFE_ROOM)).is_equal(
		"Unlocks at 2 stars and 50 passengers (now 2.5 stars, 12 passengers)"
	)
	assert_str(BuildUnlocks.requirement_text(3)).is_equal("Unlocks at 3 stars and 200 passengers")
	assert_str(BuildUnlocks.requirement_text(4)).is_equal("Unlocks at 4 stars and 600 passengers")


func test_the_state_goes_through_a_snapshot_and_json() -> void:
	assert_bool(_unlocks.from_snapshot({"tier": 3, "made": 250, "shown": [], "seen": []})).is_true()
	var json := JSON.new()
	assert_int(json.parse(JSON.stringify(_unlocks.to_snapshot()))).is_equal(OK)
	var other: BuildUnlocks = auto_free(BuildUnlocks.new())
	var changed: Array[int] = []
	other.tier_changed.connect(func(tier: int) -> void: changed.append(tier))
	assert_bool(other.from_snapshot(json.data)).is_true()
	assert_int(other.tier()).is_equal(3)
	assert_int(other.made_total()).is_equal(250)
	assert_array(changed).is_equal([3])


func test_a_bad_snapshot_is_refused_and_changes_nothing() -> void:
	_unlocks.from_snapshot({"tier": 2, "made": 60, "shown": [], "seen": []})
	var bad := [
		{"tier": 0, "made": 0, "shown": [], "seen": []},
		{"tier": 5, "made": 0, "shown": [], "seen": []},
		{"tier": 2, "made": -1, "shown": [], "seen": []},
		{"tier": 2, "shown": [], "seen": []},
		{"made": 5, "shown": [], "seen": []},
		# A snapshot without the marks the guide keeps (save version 15).
		{"tier": 2, "made": 60},
		{"tier": "2", "made": 5, "shown": [], "seen": []},
		{"tier": 2.5, "made": 5, "shown": [], "seen": []},
		{"tier": 2, "made": 5, "shown": [], "seen": [], "extra": 1},
		# A tier saved with fewer made-flight passengers than it takes to open it.
		{"tier": 2, "made": 49, "shown": [], "seen": []},
		{"tier": 3, "made": 199, "shown": [], "seen": []},
		{"tier": 4, "made": 0, "shown": [], "seen": []},
		{"tier": 4, "made": 599, "shown": [], "seen": []},
	]
	for data: Dictionary in bad:
		assert_bool(_unlocks.from_snapshot(data)).is_false()
		assert_int(_unlocks.tier()).is_equal(2)
		assert_int(_unlocks.made_total()).is_equal(60)


func test_a_snapshot_at_exactly_the_tier_requirement_is_taken() -> void:
	for data: Dictionary in [
		{"tier": 2, "made": 50, "shown": [], "seen": []},
		{"tier": 3, "made": 200, "shown": [], "seen": []},
		{"tier": 4, "made": 600, "shown": [], "seen": []}
	]:
		assert_bool(_unlocks.from_snapshot(data)).is_true()
		assert_int(_unlocks.tier()).is_equal(data["tier"])
