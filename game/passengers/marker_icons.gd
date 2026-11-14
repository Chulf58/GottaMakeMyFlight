class_name MarkerIcons
extends RefCounted
## The flat toon icons of the station signs, painted once each into a texture:
## a soft warm disc inside a dark outline with a dark navy glyph that says what
## is wrong (decision calm-view-technical-design-shared-hover-target-reusing-
## click, part 4: new meaningful glyphs on a soft warm disc, no "!" and no red).
## A station problem (a full queue, a closed station, a staff spot staff cannot
## use) is drawn on a honey disc; a build hint (a missing tray table, an
## unlinked gate desk, a wall gap) on a cream one. The text goes in the hover
## tooltip, never on the icon.

enum Glyph { QUEUE_FULL, CLOSED, STAFF_BLOCKED, TRAY_TABLE, UNLINKED_GATE, WALL_GAP }

const SIZE := 128
const OUTLINE_PX := 8.0
const DISC_RADIUS := 58.0
const OUTLINE := Color(0.165, 0.165, 0.2)
## A station problem: soft honey, the HUD's sunny attention accent, softened.
const PROBLEM_FILL := Color(0.98, 0.8, 0.47)
## A build hint: the HUD cards' cream.
const HINT_FILL := Color(0.98, 0.93, 0.8)
const GLYPH := OUTLINE

static var _textures: Dictionary = {}
## The painted images, kept apart from the textures. Under the headless dummy
## renderer a texture's get_image() hands back the texture's own stored Image,
## so a caller that repainted one would change every later read of it.
static var _images: Dictionary = {}


static func icon(glyph: Glyph) -> Texture2D:
	if not _textures.has(glyph):
		_images[glyph] = _paint(glyph)
		_textures[glyph] = ImageTexture.create_from_image((_images[glyph] as Image).duplicate())
	return _textures[glyph]


## A fresh copy of `glyph`'s icon as painted.
static func image(glyph: Glyph) -> Image:
	icon(glyph)
	return (_images[glyph] as Image).duplicate()


## The disc colour of `glyph`: PROBLEM_FILL for a station problem, HINT_FILL for
## a build hint.
static func fill_of(glyph: Glyph) -> Color:
	match glyph:
		Glyph.TRAY_TABLE, Glyph.UNLINKED_GATE, Glyph.WALL_GAP:
			return HINT_FILL
	return PROBLEM_FILL


static func _paint(glyph: Glyph) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	var fill := fill_of(glyph)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var edge := shape_distance(p)
			var cover := clampf(0.5 - edge, 0.0, 1.0)
			if cover <= 0.0:
				img.set_pixel(x, y, Color(OUTLINE, 0.0))
				continue
			var inside := clampf(0.5 - (edge + OUTLINE_PX), 0.0, 1.0)
			var colour := OUTLINE.lerp(fill, inside)
			colour = colour.lerp(GLYPH, clampf(0.5 - glyph_distance(glyph, p), 0.0, 1.0) * inside)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	return img


## Signed distance in pixels to the disc's edge, negative inside.
static func shape_distance(p: Vector2) -> float:
	return p.length() - DISC_RADIUS


## Signed distance in pixels to `glyph`'s shape, negative inside. Image y runs
## down. Strokes are at least 14 px wide, 3.5 px on a 32 px sign.
static func glyph_distance(glyph: Glyph, p: Vector2) -> float:
	match glyph:
		Glyph.QUEUE_FULL:
			return _queue(p)
		Glyph.CLOSED:
			return _padlock(p)
		Glyph.STAFF_BLOCKED:
			return _blocked_staff(p)
		Glyph.TRAY_TABLE:
			return _table_plus(p)
		Glyph.UNLINKED_GATE:
			return _broken_link(p)
	return _broken_wall(p)


## Three people in a row: a queue.
static func _queue(p: Vector2) -> float:
	var best := INF
	for x in [-25.0, 0.0, 25.0]:
		best = minf(best, _person(p, Vector2(x, 0.0), 8.5, 10.0))
	return best


## A head over rounded shoulders, centred on `at`.
static func _person(p: Vector2, at: Vector2, head: float, body: float) -> float:
	var head_d := p.distance_to(at + Vector2(0.0, -17.0)) - head
	var body_d := segment_distance(p, at + Vector2(0.0, 8.0), at + Vector2(0.0, 30.0)) - body
	return minf(head_d, body_d)


## A padlock: a rounded body and a shackle arch over it.
static func _padlock(p: Vector2) -> float:
	var q := (p - Vector2(0.0, 12.0)).abs() - Vector2(20.0, 14.0)
	var body := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 6.0
	var arch_centre := Vector2(0.0, -10.0)
	var ring := absf(p.distance_to(arch_centre) - 15.0) - 7.0
	# Only the arch's upper half, with straight legs down into the body.
	if p.y > arch_centre.y:
		ring = minf(
			segment_distance(p, Vector2(-15.0, -10.0), Vector2(-15.0, 0.0)),
			segment_distance(p, Vector2(15.0, -10.0), Vector2(15.0, 0.0))
		)
		ring -= 7.0
	return minf(body, ring)


## A staff member stopped by a wall: a person on the left, a bar on the right.
static func _blocked_staff(p: Vector2) -> float:
	var person := _person(p, Vector2(-15.0, 2.0), 9.0, 11.0)
	var bar := segment_distance(p, Vector2(22.0, -32.0), Vector2(22.0, 32.0)) - 7.0
	return minf(person, bar)


## A small table with a plus over it: a table to add.
static func _table_plus(p: Vector2) -> float:
	var top := segment_distance(p, Vector2(-32.0, 4.0), Vector2(32.0, 4.0)) - 7.0
	var legs := minf(
		segment_distance(p, Vector2(-22.0, 4.0), Vector2(-22.0, 32.0)),
		segment_distance(p, Vector2(22.0, 4.0), Vector2(22.0, 32.0))
	)
	var plus := minf(
		segment_distance(p, Vector2(0.0, -38.0), Vector2(0.0, -12.0)),
		segment_distance(p, Vector2(-13.0, -25.0), Vector2(13.0, -25.0))
	)
	return minf(top, minf(legs, plus) - 7.0)


## Two chain links on a diagonal with a gap between them, and a short spark
## either side of the gap.
static func _broken_link(p: Vector2) -> float:
	var ring_r := 11.0
	var left := absf(segment_distance(p, Vector2(-30.0, 22.0), Vector2(-14.0, 6.0)) - ring_r)
	var right := absf(segment_distance(p, Vector2(14.0, -6.0), Vector2(30.0, -22.0)) - ring_r)
	var links := minf(left, right) - 7.0
	var sparks := minf(
		segment_distance(p, Vector2(-12.0, -14.0), Vector2(-21.0, -26.0)),
		segment_distance(p, Vector2(12.0, 14.0), Vector2(21.0, 26.0))
	)
	return minf(links, sparks - 6.0)


## A thick wall line broken in the middle and an arrow passing down through the
## opening.
static func _broken_wall(p: Vector2) -> float:
	var wall := minf(
		segment_distance(p, Vector2(-36.0, -4.0), Vector2(-19.0, -4.0)),
		segment_distance(p, Vector2(19.0, -4.0), Vector2(36.0, -4.0))
	)
	var shaft := segment_distance(p, Vector2(0.0, -34.0), Vector2(0.0, 22.0))
	var head := minf(
		segment_distance(p, Vector2(0.0, 32.0), Vector2(-15.0, 15.0)),
		segment_distance(p, Vector2(0.0, 32.0), Vector2(15.0, 15.0))
	)
	return minf(wall - 9.0, minf(shaft, head) - 7.0)


static func segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
