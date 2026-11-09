class_name TestRunway
extends GdUnitTestSuite
## The runway's size (decision runway-and-taxi-technical-design-movement-plan-
## analytic-bookings-planned-pauses, points 1 and 8): small, medium or large,
## 384, 576 or 768 m of the 96 m pack pieces. A runway takes its own class and
## every smaller one. The size is the one thing it saves.


func test_a_new_runway_is_small_like_the_one_in_the_scene() -> void:
	assert_str(Runway.new().size).is_equal(PlaneClasses.SMALL)
	assert_float(Runway.length_m(Runway.new().size)).is_equal(384.0)


func test_a_runway_takes_its_own_class_and_every_smaller_one() -> void:
	var expected := {
		"small": ["small"],
		"medium": ["small", "medium"],
		"large": ["small", "medium", "large"],
	}
	for size: String in expected:
		var runway := Runway.new()
		runway.size = size
		for plane_class in PlaneClasses.ORDER:
			var takes: bool = (expected[size] as Array).has(plane_class)
			(
				assert_bool(runway.takes(plane_class))
				. override_failure_message("%s runway, %s plane" % [size, plane_class])
				. is_equal(takes)
			)
	assert_bool(Runway.new().takes("jumbo")).is_false()
	assert_bool(Runway.new().takes("")).is_false()


func test_the_three_lengths_are_384_576_and_768_metres() -> void:
	assert_float(Runway.length_m(PlaneClasses.SMALL)).is_equal(384.0)
	assert_float(Runway.length_m(PlaneClasses.MEDIUM)).is_equal(576.0)
	assert_float(Runway.length_m(PlaneClasses.LARGE)).is_equal(768.0)


## The pieces of the small runway are the five the scene places by hand: the
## two end pieces turned to face outward and three strips.
func test_the_small_runway_pieces_are_the_ones_in_the_scene() -> void:
	var pieces := Runway.pieces(PlaneClasses.SMALL)
	var seen := []
	for piece in pieces:
		seen.append([piece["piece"], piece["x"], piece["turned"]])
	(
		assert_array(seen)
		. contains_exactly_in_any_order(
			[
				["tp_runway_01a", -144.0, true],
				["tp_runway_03a", -96.0, false],
				["tp_runway_03a", 0.0, false],
				["tp_runway_03a", 96.0, false],
				["tp_runway_01a", 144.0, false],
			]
		)
	)


## Each size's pieces meet end to end with no gap or overlap, centred on x 0,
## and cover exactly the size's length.
func test_every_size_is_a_gapless_run_of_its_length() -> void:
	for size in PlaneClasses.ORDER:
		var spans := []
		for piece in Runway.pieces(size):
			var box: AABB = PlaneModels.PIECES[piece["piece"]]["aabb"]
			var from: float = piece["x"] + (-box.end.x if piece["turned"] else box.position.x)
			var to: float = piece["x"] + (-box.position.x if piece["turned"] else box.end.x)
			spans.append([from, to])
		spans.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		print("%s runway spans %s" % [size, spans])
		assert_float(spans[0][0]).is_equal(-Runway.length_m(size) / 2.0)
		assert_float(spans[-1][1]).is_equal(Runway.length_m(size) / 2.0)
		for i in range(1, spans.size()):
			assert_float(spans[i][0]).is_equal_approx(spans[i - 1][1], 0.001)


func test_a_bigger_runway_has_more_strips_between_the_same_ends() -> void:
	var counts := []
	for size in PlaneClasses.ORDER:
		var strips := Runway.pieces(size).filter(
			func(piece: Dictionary) -> bool: return piece["piece"] == Runway.STRIP_PIECE
		)
		counts.append(strips.size())
	assert_array(counts).is_equal([3, 5, 7])


func test_build_places_one_child_per_piece() -> void:
	for size in PlaneClasses.ORDER:
		var root := auto_free(Runway.build(size)) as Node3D
		assert_int(root.get_child_count()).is_equal(Runway.pieces(size).size())
		var xs := []
		for child in root.get_children():
			xs.append((child as Node3D).position.x)
		xs.sort()
		var planned := Runway.pieces(size).map(func(piece: Dictionary) -> float: return piece["x"])
		planned.sort()
		assert_array(xs).is_equal(planned)


func test_the_size_saves_and_loads() -> void:
	var runway := Runway.new()
	runway.size = PlaneClasses.LARGE
	var data: Dictionary = JSON.parse_string(JSON.stringify(runway.to_snapshot()))
	var loaded := Runway.new()
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_str(loaded.size).is_equal(PlaneClasses.LARGE)
	assert_dict(loaded.to_snapshot()).is_equal(runway.to_snapshot())


func test_a_bad_snapshot_is_refused_and_changes_nothing() -> void:
	var runway := Runway.new()
	runway.size = PlaneClasses.MEDIUM
	var good := runway.to_snapshot()
	var wrong_version := good.duplicate()
	wrong_version["save_version"] = Runway.SAVE_VERSION + 1
	var unknown_size := good.duplicate()
	unknown_size["size"] = "huge"
	var extra := good.duplicate()
	extra["lights"] = true
	var missing := {"save_version": Runway.SAVE_VERSION}
	var not_text := good.duplicate()
	not_text["size"] = 1
	for bad: Dictionary in [wrong_version, unknown_size, extra, missing, not_text]:
		(
			assert_error(func() -> void: assert_bool(runway.from_snapshot(bad)).is_false())
			. is_push_error("Runway.from_snapshot: " + _reason_of(bad))
		)
		assert_str(runway.size).is_equal(PlaneClasses.MEDIUM)


func _reason_of(bad: Dictionary) -> String:
	var probe := Runway.new()
	return probe.snapshot_problem(bad)
