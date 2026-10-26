class_name MarkerIcons
extends RefCounted
## The flat toon icon for the queue-full sign, painted once into a texture:
## a red rounded square inside a thick dark outline with a white "!", like the
## Toon Series' flat palette.

const SIZE := 128
const OUTLINE_PX := 9.0
const OUTLINE := Color(0.165, 0.165, 0.2)
const QUEUE_FILL := Color(0.847, 0.263, 0.231)
const GLYPH := Color(1.0, 1.0, 1.0)

static var _queue_full: ImageTexture


static func queue_full() -> Texture2D:
	if _queue_full == null:
		_queue_full = _paint()
	return _queue_full


static func _paint() -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var edge := _shape(p)
			var cover := clampf(0.5 - edge, 0.0, 1.0)
			if cover <= 0.0:
				img.set_pixel(x, y, Color(OUTLINE, 0.0))
				continue
			var inside := clampf(0.5 - (edge + OUTLINE_PX), 0.0, 1.0)
			var colour := OUTLINE.lerp(QUEUE_FILL, inside)
			colour = colour.lerp(GLYPH, clampf(0.5 - _glyph(p), 0.0, 1.0) * inside)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Signed distance in pixels to the rounded square's edge, negative inside.
static func _shape(p: Vector2) -> float:
	var radius := 22.0
	var q := p.abs() - Vector2.ONE * (60.0 - radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## Signed distance to the white "!". Image y runs down.
static func _glyph(p: Vector2) -> float:
	var bar := _segment(p, Vector2(0.0, -34.0), Vector2(0.0, 6.0)) - 9.0
	var dot := p.distance_to(Vector2(0.0, 28.0)) - 10.0
	return minf(bar, dot)


static func _segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
