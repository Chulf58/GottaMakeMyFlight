class_name TestIncidentRoll
extends GdUnitTestSuite
## The incident draws (IncidentRoll): the seed derivation and the xorshift32
## generator are pinned by fixed vectors worked out outside Godot (Node BigInt,
## the same text and FNV-1a 32), so an engine upgrade cannot change a replay
## unnoticed. The roll is a pure function of its stream and inputs.

const WINDOW := Vector2i(1000, 1999)


static func _candidates(spill_weight: int) -> Array[Dictionary]:
	return [
		{"kind": IncidentCatalogue.NONE, "weight": IncidentCatalogue.NONE_WEIGHT, "major": false},
		{"kind": IncidentCatalogue.SPILL, "weight": spill_weight, "major": false},
	]


func test_fnv1a_32_matches_the_published_vectors() -> void:
	assert_int(IncidentRoll.fnv1a_32("".to_utf8_buffer())).is_equal(2166136261)
	assert_int(IncidentRoll.fnv1a_32("a".to_utf8_buffer())).is_equal(3826002220)


func test_the_seed_derivation_matches_its_fixed_vectors() -> void:
	var cases := [
		[0, 0, 1, "roll", 2909125191],
		[7311042, 3, 1, "roll", 1222463354],
		[-42, 12, 1, "place:5", 1094700058],
		[123456789012345, 1, 2, "roll", 4206118377],
	]
	for entry: Array in cases:
		var got := IncidentRoll.seed_for(entry[0], entry[1], entry[2], entry[3])
		print("seed_for%s = %d" % [entry.slice(0, 4), got])
		assert_int(got).is_equal(entry[4])


func test_the_generator_matches_its_fixed_vectors() -> void:
	var cases := [
		[2909125191, [1602731377, 2903565765, 2225848113]],
		[1222463354, [3346891651, 2528565413, 4192833780]],
		[1094700058, [2938558660, 4092737979, 744847609]],
	]
	for entry: Array in cases:
		var draws := IncidentRoll.new(entry[0])
		var got := [draws.next_u32(), draws.next_u32(), draws.next_u32()]
		print("xorshift32(%d) = %s" % [entry[0], got])
		assert_array(got).is_equal(entry[1])


func test_the_catalogue_version_and_the_day_change_the_seed() -> void:
	var base := IncidentRoll.seed_for(99, 4, 1, "roll")
	assert_int(IncidentRoll.seed_for(99, 4, 2, "roll")).is_not_equal(base)
	assert_int(IncidentRoll.seed_for(99, 5, 1, "roll")).is_not_equal(base)
	assert_int(IncidentRoll.seed_for(98, 4, 1, "roll")).is_not_equal(base)
	assert_int(IncidentRoll.seed_for(99, 4, 1, "place:1")).is_not_equal(base)


func test_the_same_seed_and_day_give_the_same_roll() -> void:
	var spills := 0
	for day in range(1, 41):
		var first := IncidentRoll.roll(
			IncidentRoll.stream(7311042, day, 1, "roll"), _candidates(2), day, 0, WINDOW
		)
		var again := IncidentRoll.roll(
			IncidentRoll.stream(7311042, day, 1, "roll"), _candidates(2), day, 0, WINDOW
		)
		assert_dict(again).is_equal(first)
		if first["kind"] == IncidentCatalogue.SPILL:
			spills += 1
			assert_int(first["fire_tick"]).is_between(WINDOW.x, WINDOW.y)
	# Both kinds come up over 40 days at a 2 in 6 spill weight.
	print("spills in 40 days: %d" % spills)
	assert_int(spills).is_greater(0)
	assert_int(spills).is_less(40)


func test_a_zero_weight_or_an_empty_window_keeps_the_day_quiet() -> void:
	for day in range(1, 21):
		var none_built := IncidentRoll.roll(
			IncidentRoll.stream(5, day, 1, "roll"), _candidates(0), day, 0, WINDOW
		)
		assert_str(none_built["kind"]).is_equal(IncidentCatalogue.NONE)
		var no_window := IncidentRoll.roll(
			IncidentRoll.stream(5, day, 1, "roll"), _candidates(4), day, 0, Vector2i(1, 0)
		)
		assert_str(no_window["kind"]).is_equal(IncidentCatalogue.NONE)
		assert_int(no_window["fire_tick"]).is_equal(-1)


## The only weighted kind is a major: it comes every day it is allowed, then
## waits 2 or 3 days, and the days between stay quiet.
func test_a_major_sets_the_next_major_day_two_or_three_days_on() -> void:
	var candidates: Array[Dictionary] = [
		{"kind": IncidentCatalogue.NONE, "weight": 0, "major": false},
		{"kind": IncidentCatalogue.SPILL, "weight": 0, "major": false},
		{"kind": "test_major", "weight": 1, "major": true},
	]
	var next_major := 0
	var majors: Array[int] = []
	for day in range(1, 31):
		var result := IncidentRoll.roll(
			IncidentRoll.stream(11, day, 1, "roll"), candidates, day, next_major, WINDOW
		)
		if IncidentRoll.major_allowed(day, next_major):
			majors.append(day)
			assert_str(result["kind"]).is_equal("test_major")
			assert_int(result["next_major_day"] - day).is_between(2, 3)
		else:
			assert_str(result["kind"]).is_equal(IncidentCatalogue.NONE)
			assert_int(result["next_major_day"]).is_equal(next_major)
		next_major = result["next_major_day"]
	print("major days: %s" % [majors])
	assert_int(majors.size()).is_greater(7)
	for index in range(1, majors.size()):
		assert_int(majors[index] - majors[index - 1]).is_between(2, 3)
