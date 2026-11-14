class_name TestMarkerIcons
extends GdUnitTestSuite
## The station sign glyphs (MarkerIcons, decision calm-view-technical-design-
## shared-hover-target-reusing-click, part 4): six meaningful glyphs on a soft
## warm disc, no red and no "!", each its own picture; and which glyph and
## words each closed reason gets (MissMarkers.closed_look).

const G := MarkerIcons.Glyph


## True when `c` is `want` as stored in 8 bits a channel.
static func _near(c: Color, want: Color) -> bool:
	return absf(c.r - want.r) < 0.01 and absf(c.g - want.g) < 0.01 and absf(c.b - want.b) < 0.01


## Pixels inside the disc's fill (the outline ring left out) drawn in the glyph
## colour, and the fill's pixels in all.
static func _counts(image: Image) -> Vector2i:
	var glyph := 0
	var inside := 0
	var half := image.get_width() / 2.0
	for y in image.get_height():
		for x in image.get_width():
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			if MarkerIcons.shape_distance(p) > -MarkerIcons.OUTLINE_PX - 1.0:
				continue
			inside += 1
			if _near(image.get_pixel(x, y), MarkerIcons.GLYPH):
				glyph += 1
	return Vector2i(glyph, inside)


func test_every_glyph_is_its_own_picture() -> void:
	var images := {}
	for glyph: int in G.values():
		images[glyph] = MarkerIcons.image(glyph)
	for a: int in G.values():
		for b: int in G.values():
			if a >= b:
				continue
			var differ := 0
			var ia: Image = images[a]
			var ib: Image = images[b]
			for y in MarkerIcons.SIZE:
				for x in MarkerIcons.SIZE:
					if not ia.get_pixel(x, y).is_equal_approx(ib.get_pixel(x, y)):
						differ += 1
			assert_int(differ).override_failure_message("glyphs %d and %d" % [a, b]).is_greater(600)


## Each glyph covers a share of the disc big enough to read at 32 px, and
## leaves most of the disc its soft fill.
func test_every_glyph_is_drawn_and_leaves_the_disc_soft() -> void:
	for glyph: int in G.values():
		var counts := _counts(MarkerIcons.image(glyph))
		var share := float(counts.x) / counts.y
		print("glyph %d: %d glyph px of %d opaque (%.2f)" % [glyph, counts.x, counts.y, share])
		assert_float(share).is_greater(0.12)
		assert_float(share).is_less(0.5)


## No red anywhere: every opaque pixel lies between the outline navy and a warm
## fill, and no pixel is red-dominant the way the old "!" sign was.
func test_no_glyph_is_red() -> void:
	for glyph: int in G.values():
		var image := MarkerIcons.image(glyph)
		var red := 0
		for y in MarkerIcons.SIZE:
			for x in MarkerIcons.SIZE:
				var c := image.get_pixel(x, y)
				if c.a > 0.5 and c.r > 0.6 and c.g < 0.45 and c.b < 0.45:
					red += 1
		assert_int(red).override_failure_message("glyph %d" % glyph).is_equal(0)


func test_problems_are_honey_and_build_hints_cream() -> void:
	for glyph in [G.QUEUE_FULL, G.CLOSED, G.STAFF_BLOCKED]:
		assert_object(MarkerIcons.fill_of(glyph)).is_equal(MarkerIcons.PROBLEM_FILL)
	for glyph in [G.TRAY_TABLE, G.UNLINKED_GATE, G.WALL_GAP]:
		assert_object(MarkerIcons.fill_of(glyph)).is_equal(MarkerIcons.HINT_FILL)
	# Read back from the painted disc, at a spot no glyph draws on.
	var at := Vector2i(MarkerIcons.SIZE / 2 - 40, MarkerIcons.SIZE / 2 - 28)
	var problem := MarkerIcons.image(G.QUEUE_FULL).get_pixelv(at)
	var hint := MarkerIcons.image(G.WALL_GAP).get_pixelv(at)
	print("problem fill %s hint fill %s" % [problem, hint])
	assert_float(problem.b).is_equal_approx(MarkerIcons.PROBLEM_FILL.b, 0.02)
	assert_float(hint.b).is_equal_approx(MarkerIcons.HINT_FILL.b, 0.02)


func test_the_disc_is_round_with_clear_corners() -> void:
	var image := MarkerIcons.image(G.CLOSED)
	assert_float(image.get_pixel(2, 2).a).is_equal(0.0)
	assert_float(image.get_pixel(MarkerIcons.SIZE - 3, MarkerIcons.SIZE - 3).a).is_equal(0.0)
	var edge := image.get_pixel(MarkerIcons.SIZE / 2, 9)
	assert_float(edge.a).is_greater(0.99)
	assert_bool(_near(edge, MarkerIcons.OUTLINE)).is_true()


## image() is a fresh copy each time: repainting one leaves the next as painted.
func test_an_image_is_a_fresh_copy() -> void:
	var at := Vector2i(MarkerIcons.SIZE / 2 - 40, MarkerIcons.SIZE / 2 - 28)
	var first := MarkerIcons.image(G.QUEUE_FULL)
	var painted := first.get_pixelv(at)
	first.set_pixelv(at, Color.WHITE)
	var second := MarkerIcons.image(G.QUEUE_FULL)
	assert_bool(second.get_pixelv(at).is_equal_approx(painted)).is_true()
	assert_object(second).is_not_same(first)
	assert_object(MarkerIcons.icon(G.QUEUE_FULL)).is_same(MarkerIcons.icon(G.QUEUE_FULL))


func test_each_closed_reason_gets_its_glyph_and_words() -> void:
	var looks := [
		MissMarkers.closed_look(MissSignals.NO_STAFF_REASON, "desk"),
		MissMarkers.closed_look(MissSignals.PLAYER_CLOSED_REASON, "desk"),
		MissMarkers.closed_look(MissSignals.SPOT_BLOCKED_REASON, "scanner"),
		MissMarkers.closed_look(MissSignals.UNREACHABLE_REASON, "counter"),
	]
	print("looks %s" % [looks])
	(
		assert_array(looks)
		. is_equal(
			[
				[G.CLOSED, "Closed · no staff on duty"],
				[G.CLOSED, "Closed by you"],
				[G.STAFF_BLOCKED, "Closed · staff spot blocked"],
				[G.STAFF_BLOCKED, "Closed · staff can't reach the counter"],
			]
		)
	)
