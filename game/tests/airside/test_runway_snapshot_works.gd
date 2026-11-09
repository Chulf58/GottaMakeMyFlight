class_name TestRunwaySnapshotWorks
extends GdUnitTestSuite
## The runway part of a save holds the works state too (Runway save version 2).


func test_the_part_holds_the_size_and_the_works() -> void:
	var runway := Runway.new(PlaneClasses.MEDIUM)
	runway.works.begin(PlaneClasses.LARGE, 900)
	var data := JSON.parse_string(JSON.stringify(runway.to_snapshot())) as Dictionary
	assert_int(int(data["save_version"])).is_equal(2)
	var loaded := Runway.new()
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_str(loaded.size).is_equal(PlaneClasses.MEDIUM)
	assert_str(loaded.works.target).is_equal(PlaneClasses.LARGE)
	assert_int(loaded.works.finish).is_equal(900 + RunwayWorks.ticks(PlaneClasses.LARGE))


func test_works_that_do_not_grow_the_runway_are_refused() -> void:
	var runway := Runway.new(PlaneClasses.MEDIUM)
	runway.works.begin(PlaneClasses.MEDIUM, 900)
	assert_str(runway.snapshot_problem(runway.to_snapshot())).contains("larger")
	runway.works.clear()
	runway.size = PlaneClasses.LARGE
	runway.works.begin(PlaneClasses.MEDIUM, 900)
	assert_str(runway.snapshot_problem(runway.to_snapshot())).contains("larger")


func test_a_version_1_part_is_refused() -> void:
	var runway := Runway.new()
	assert_str(runway.snapshot_problem({"save_version": 1, "size": "small"})).is_not_empty()
