class_name TestSimClockSaveVersion
extends GdUnitTestSuite
## The clock snapshot is versioned and strict about its keys.


func _new_clock() -> SimClock:
	return auto_free(SimClock.new()) as SimClock


func test_snapshot_carries_its_save_version() -> void:
	var data := _new_clock().to_snapshot()
	assert_int(data["save_version"]).is_equal(SimClock.SAVE_VERSION)
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	assert_bool(_new_clock().from_snapshot(parsed)).is_true()


func test_a_wrong_version_or_an_unknown_key_is_rejected() -> void:
	var clock := _new_clock()
	clock.advance(SimClock.STEP * 3.0)
	var good := clock.to_snapshot()
	var other := _new_clock()
	var cases: Array[Dictionary] = []
	for version in [0, SimClock.SAVE_VERSION + 1, "1", 1.5]:
		var bad := good.duplicate()
		bad["save_version"] = version
		cases.append(bad)
	var extra := good.duplicate()
	extra["calendar"] = {}
	cases.append(extra)
	for bad in cases:
		assert_bool(other.from_snapshot(bad)).override_failure_message(str(bad)).is_false()
		assert_int(other.tick).is_equal(0)
