class_name MarkerIcons
extends RefCounted
## Flat toon icons for the miss markers, painted once into textures: a fill
## colour inside a thick dark outline with a white glyph, like the Toon
## Series' flat palette. QUEUE_FULL is a red rounded square with "!", LATE an
## amber disc with a clock face.

enum Icon { QUEUE_FULL, LATE }

const SIZE := 128
const OUTLINE_PX := 9.0
const OUTLINE := Color(0.165, 0.165, 0.2)
const QUEUE_FILL := Color(0.847, 0.263, 0.231)
const LATE_FILL := Color(0.949, 0.639, 0.227)
const GLYPH := Color(1.0, 1.0, 1.0)

static var _cache: Dictionary = {}


static func texture(icon: Icon) -> Texture2D:
	if not _cache.has(icon):
		_cache[icon] = _paint(icon)
	return _cache[icon]


static func _paint(icon: Icon) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var fill := QUEUE_FILL if icon == Icon.QUEUE_FULL else LATE_FILL
	var half := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var edge := _shape(icon, p)
			var cover := clampf(0.5 - edge, 0.0, 1.0)
			if cover <= 0.0:
				img.set_pixel(x, y, Color(OUTLINE, 0.0))
				continue
			var inside := clampf(0.5 - (edge + OUTLINE_PX), 0.0, 1.0)
			var colour := OUTLINE.lerp(fill, inside)
			colour = colour.lerp(GLYPH, clampf(0.5 - _glyph(icon, p), 0.0, 1.0) * inside)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Signed distance in pixels to the icon's outer edge, negative inside.
static func _shape(icon: Icon, p: Vector2) -> float:
	if icon == Icon.LATE:
		return p.length() - 60.0
	var radius := 22.0
	var q := p.abs() - Vector2.ONE * (60.0 - radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## Signed distance to the white glyph. Image y runs down.
static func _glyph(icon: Icon, p: Vector2) -> float:
	if icon == Icon.QUEUE_FULL:
		var bar := _segment(p, Vector2(0.0, -34.0), Vector2(0.0, 6.0)) - 9.0
		var dot := p.distance_to(Vector2(0.0, 28.0)) - 10.0
		return minf(bar, dot)
	var ring := absf(p.length() - 36.0) - 5.5
	var minute := _segment(p, Vector2.ZERO, Vector2(0.0, -26.0)) - 5.0
	var hour := _segment(p, Vector2.ZERO, Vector2(18.0, 0.0)) - 5.0
	return minf(ring, minf(minute, hour))


static func _segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
