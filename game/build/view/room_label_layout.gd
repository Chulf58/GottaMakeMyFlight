class_name RoomLabelLayout
extends RefCounted
## Lays out the world labels over rooms (RoomView) each frame, by two user
## rulings of 2026-11-03 (board item 9c2b0d32):
##
## - Clear of the HUD: a label whose screen rectangle touches a HUD control (the
##   Alerts button, the Day panel) slides toward the screen's middle, in
##   STEP_PX steps and at most MAX_TRAVEL_PX, until it clears every control by
##   GAP_PX, the same rule as the station captions (MissMarkers); with no clear
##   spot it is hidden. The slide is the Label3D's pixel offset, so its world
##   position stays put and the cafe '+$' pop (CafePops) still hangs under the
##   room's column.
## - A capped size that fades when close: the label stays a world-size
##   billboard, but its text never covers more than MAX_SCALE screen pixels per
##   font pixel, and it fades out as the camera rig zooms in from FADE_FAR to
##   FADE_NEAR of its home distance (the need icons use the same reading, in the
##   other direction: NeedIcons.shown_at).
##
## Sizes are screen pixels, for the camera's field of view and the rendered
## view's height, as in MissMarkers.

## The most screen pixels one font pixel of a label covers: a 40 px font reads
## at about 22 px, as large as a station caption.
const MAX_SCALE := 0.55
## The label is fully visible at or beyond FADE_FAR times the rig's home
## distance and fully faded at or inside FADE_NEAR times it.
const FADE_FAR := 0.6
const FADE_NEAR := 0.35
## An alpha at or under this hides the label outright.
const HIDDEN_ALPHA := 0.02
## Clear space kept between a label and a HUD control.
const GAP_PX := 6.0
const STEP_PX := 6.0
const MAX_TRAVEL_PX := 360.0
## Past that, spots are tried on rings this far apart, each with a point every
## RING_STEP_PX along it (at least RING_POINTS), from the direction of the middle
## first, as the station captions do (MissMarkers); a ring spot stays inside the
## view by VIEW_MARGIN_PX.
const RING_STEP_PX := 32.0
const RING_POINTS := 16
const VIEW_MARGIN_PX := 8.0

## How many labels were hidden because no spot was clear of the HUD, summed over
## the layouts run.
var no_spot_hides := 0


## 1 at or beyond FADE_FAR of the rig's home distance, 0 at or inside FADE_NEAR,
## between them in proportion. 1 for a camera outside a TycoonCamera rig, or none.
static func zoom_alpha(camera: Camera3D) -> float:
	var rig := camera.get_parent() as TycoonCamera if camera != null else null
	if rig == null:
		return 1.0
	return clampf(
		inverse_lerp(rig.home_distance * FADE_NEAR, rig.home_distance * FADE_FAR, rig.distance),
		0.0,
		1.0
	)


## `base` (a Label3D's pixel size) unless the text would then cover more than
## MAX_SCALE screen pixels per font pixel at `depth` metres from the camera
## (`unit` is the world size of one output pixel at one metre).
static func capped_pixel_size(base: float, depth: float, unit: float) -> float:
	return minf(base, MAX_SCALE * depth * unit)


## What a label covers on screen, outline included, in pixels: its text box in
## the default font, centred over `point` with its bottom line on `point`.
## `scale` is the screen pixels one font pixel covers.
static func label_rect(
	point: Vector2, text: String, font_size: int, outline: int, scale: float
) -> Rect2:
	var font := ThemeDB.fallback_font
	var size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	size += Vector2.ONE * 2.0 * outline
	size *= scale
	return Rect2(Vector2(point.x - size.x / 2.0, point.y + outline * scale - size.y), size)


## `rect` when it is clear of `hud` by GAP_PX, else the nearest spot toward the
## middle of a view of `view_size` that is, at most MAX_TRAVEL_PX away, else the
## nearest clear spot inside the view on rings around `rect`, tried from the
## direction of the middle first. A zero-size rectangle means there is none.
static func slide_clear(rect: Rect2, hud: Array[Rect2], view_size: Vector2) -> Rect2:
	if _is_clear(rect, hud):
		return rect
	var toward := view_size / 2.0 - rect.get_center()
	if not toward.is_zero_approx():
		var reach := minf(MAX_TRAVEL_PX, toward.length())
		var step := toward.normalized() * STEP_PX
		for k in range(1, int(reach / STEP_PX) + 1):
			var moved := Rect2(rect.position + step * k, rect.size)
			if _is_clear(moved, hud):
				return moved
	return _ring_spot(rect, hud, view_size, toward)


## The nearest spot inside the view and clear of `hud` on rings of growing radius
## around `rect`, or a zero-size rectangle.
static func _ring_spot(
	rect: Rect2, hud: Array[Rect2], view_size: Vector2, toward: Vector2
) -> Rect2:
	var inner := Rect2(Vector2.ZERO, view_size).grow(-VIEW_MARGIN_PX)
	var heading := toward.angle() if not toward.is_zero_approx() else 0.0
	var radius := RING_STEP_PX
	while radius <= view_size.length():
		var points := maxi(RING_POINTS, ceili(TAU * radius / RING_STEP_PX))
		for n in points:
			## 0, then one step either side of the heading, then two, and so on.
			var turn := ceili(n / 2.0) * (1.0 if n % 2 == 1 else -1.0)
			var angle := heading + TAU * turn / points
			var moved := Rect2(rect.position + Vector2.from_angle(angle) * radius, rect.size)
			if inner.encloses(moved) and _is_clear(moved, hud):
				return moved
		radius += RING_STEP_PX
	return Rect2()


static func _is_clear(rect: Rect2, hud: Array[Rect2]) -> bool:
	var padded := rect.grow(GAP_PX)
	for control in hud:
		if padded.intersects(control):
			return false
	return true


## Sets every label's alpha, size, slide and visibility for this frame.
## `to_output` converts the camera's viewport coordinates to screen pixels,
## `view_size` is the screen's size in them and `hud` the HUD rectangles.
func layout(
	labels: Array[Label3D],
	camera: Camera3D,
	to_output: float,
	view_size: Vector2,
	hud: Array[Rect2]
) -> void:
	var alpha := zoom_alpha(camera)
	var unit := 0.0
	if camera != null:
		unit = 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / view_size.y
	var view := Rect2(Vector2.ZERO, view_size)
	for label in labels:
		label.pixel_size = RoomView.LABEL_PIXEL_SIZE
		label.offset = Vector2.ZERO
		label.modulate.a = alpha
		label.outline_modulate.a = alpha
		label.visible = alpha > HIDDEN_ALPHA
		if camera == null or not label.visible:
			continue
		if camera.is_position_behind(label.global_position):
			label.visible = false
			continue
		var depth := -(camera.global_transform.affine_inverse() * label.global_position).z
		label.pixel_size = capped_pixel_size(label.pixel_size, depth, unit)
		var scale := label.pixel_size / (depth * unit)
		var point := camera.unproject_position(label.global_position) * to_output
		var rect := label_rect(point, label.text, label.font_size, label.outline_size, scale)
		if not view.intersects(rect):
			continue
		var spot := slide_clear(rect, hud, view_size)
		if spot.size == Vector2.ZERO:
			label.visible = false
			no_spot_hides += 1
			continue
		var shift := (spot.position - rect.position) / scale
		label.offset = Vector2(shift.x, -shift.y)
