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
## Two more by the user ruling of 2026-11-04 (board a48bca8d, decision
## room-labels-sit-on-a-cream-card-and-slide-clear-of-need-icons):
##
## - A cream card: every label draws on a cream rounded card with a dark
##   outline, the HUD card look (make_card(), sync_card()). The card is the
##   label's child, follows its size cap, slide and fade, and is the box every
##   slide keeps clear.
## - Clear of need icons: a label whose card a passenger's need icon covers on
##   screen is nudged a short way (its card's height, at most NUDGE_PX, plus
##   two icon widths) to a spot clear of the icons, the HUD and the cards placed
##   before it, and keeps that nudge while it stays clear. With no such spot
##   near, it keeps its HUD-clear spot and the icons draw over it (icons always
##   stay, and keep drawing over labels).
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
## The furthest a label is nudged to clear need icons.
const NUDGE_PX := 96.0
## The card: its node name, the space around the text box in font pixels, the
## corner radius and the outline width in card texels (one per font pixel), and
## the HUD panel colours (game/ui/hud_theme.tres, MarkerIcons.OUTLINE).
const CARD := "Card"
const CARD_PAD_PX := 8
const CARD_RADIUS_PX := 12.0
const CARD_BORDER_PX := 4.0
const CARD_FILL := Color(0.96, 0.93, 0.86)
const CARD_BORDER := Color(0.165, 0.165, 0.2)

## Card textures by size in texels, painted once.
static var _card_textures: Dictionary = {}

## How many ring spots _ring_spot has tried, summed over every call (a counter for
## tests: a HUD rectangle over the whole view must hide a label without any).
static var ring_candidates := 0

## How many labels were hidden because no spot was clear of the HUD, summed over
## the layouts run.
var no_spot_hides := 0
## The cards placed so far in this layout, in screen pixels.
var _placed: Array[Rect2] = []


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


## The box a label's card covers on screen: label_rect() grown by CARD_PAD_PX
## font pixels on every side.
static func card_rect(
	point: Vector2, text: String, font_size: int, outline: int, scale: float
) -> Rect2:
	return label_rect(point, text, font_size, outline, scale).grow(CARD_PAD_PX * scale)


## `rect` when it is clear of `hud` by GAP_PX, else the nearest spot toward the
## middle of a view of `view_size` that is, at most MAX_TRAVEL_PX away, else the
## nearest clear spot inside the view on rings around `rect`, tried from the
## direction of the middle first. `reach` caps both searches (the need-icon
## nudge). A zero-size rectangle means there is none, at once when one HUD
## rectangle covers the whole view inside its margin.
static func slide_clear(rect: Rect2, hud: Array[Rect2], view_size: Vector2, reach := INF) -> Rect2:
	if _is_clear(rect, hud):
		return rect
	var usable := Rect2(Vector2.ZERO, view_size).grow(-VIEW_MARGIN_PX)
	for control in hud:
		if control.encloses(usable):
			return Rect2()
	var toward := view_size / 2.0 - rect.get_center()
	if not toward.is_zero_approx():
		var travel := minf(minf(MAX_TRAVEL_PX, toward.length()), reach)
		var step := toward.normalized() * STEP_PX
		for k in range(1, int(travel / STEP_PX) + 1):
			var moved := Rect2(rect.position + step * k, rect.size)
			if _is_clear(moved, hud):
				return moved
	return _ring_spot(rect, hud, view_size, toward, reach)


## The nearest spot inside the view and clear of `hud` on rings of growing radius
## (up to `reach`) around `rect`, or a zero-size rectangle.
static func _ring_spot(
	rect: Rect2, hud: Array[Rect2], view_size: Vector2, toward: Vector2, reach := INF
) -> Rect2:
	var inner := Rect2(Vector2.ZERO, view_size).grow(-VIEW_MARGIN_PX)
	var heading := toward.angle() if not toward.is_zero_approx() else 0.0
	var radius := RING_STEP_PX
	while radius <= minf(view_size.length(), reach):
		var points := maxi(RING_POINTS, ceili(TAU * radius / RING_STEP_PX))
		for n in points:
			## 0, then one step either side of the heading, then two, and so on.
			var turn := ceili(n / 2.0) * (1.0 if n % 2 == 1 else -1.0)
			var angle := heading + TAU * turn / points
			ring_candidates += 1
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


## Sets every label's alpha, size, slide and visibility for this frame, and
## its card's to match. `to_output` converts the camera's viewport coordinates
## to screen pixels, `view_size` is the screen's size in them, `hud` the HUD
## rectangles and `icons` the need icons' (icon_rects()), all in screen pixels.
func layout(
	labels: Array[Label3D],
	camera: Camera3D,
	to_output: float,
	view_size: Vector2,
	hud: Array[Rect2],
	icons: Array[Rect2] = []
) -> void:
	var alpha := zoom_alpha(camera)
	var unit := 0.0
	if camera != null:
		unit = 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / view_size.y
	_placed.clear()
	for label in labels:
		label.pixel_size = RoomView.LABEL_PIXEL_SIZE
		label.offset = Vector2.ZERO
		label.modulate.a = alpha
		label.outline_modulate.a = alpha
		label.visible = alpha > HIDDEN_ALPHA
		if camera != null and label.visible:
			_place(label, camera, unit, to_output, view_size, hud, icons)
		sync_card(label)


func _place(
	label: Label3D,
	camera: Camera3D,
	unit: float,
	to_output: float,
	view_size: Vector2,
	hud: Array[Rect2],
	icons: Array[Rect2]
) -> void:
	if camera.is_position_behind(label.global_position):
		label.visible = false
		return
	var depth := -(camera.global_transform.affine_inverse() * label.global_position).z
	label.pixel_size = capped_pixel_size(label.pixel_size, depth, unit)
	var scale := label.pixel_size / (depth * unit)
	var point := camera.unproject_position(label.global_position) * to_output
	var rect := card_rect(point, label.text, label.font_size, label.outline_size, scale)
	if not Rect2(Vector2.ZERO, view_size).intersects(rect):
		return
	# The nudge: clear of the icons, the HUD and the cards placed before this
	# one (one card never hides another's text), within a reach that clears a
	# row of icons. The last frame's nudge is kept while it stays clear, so a
	# label does not jitter as passengers walk.
	var reach := minf(NUDGE_PX, rect.size.y) + 2.0 * NeedIcons.ICON_PX
	var near := rect.grow(reach + GAP_PX)
	var blockers: Array[Rect2] = hud.duplicate()
	for other in icons + _placed:
		if near.intersects(other):
			blockers.append(other)
	var spot := Rect2()
	if blockers.size() > hud.size():
		var kept: Vector2 = label.get_meta(&"nudge", Vector2.ZERO)
		var again := Rect2(rect.position + kept, rect.size)
		var inner := Rect2(Vector2.ZERO, view_size).grow(-VIEW_MARGIN_PX)
		if kept.length() <= reach and inner.encloses(again) and _is_clear(again, blockers):
			spot = again
		else:
			spot = slide_clear(rect, blockers, view_size, reach)
	if spot.size == Vector2.ZERO:
		spot = slide_clear(rect, hud, view_size)
	if spot.size == Vector2.ZERO:
		label.visible = false
		no_spot_hides += 1
		return
	label.set_meta(&"nudge", spot.position - rect.position)
	_placed.append(spot)
	var shift := (spot.position - rect.position) / scale
	label.offset = Vector2(shift.x, -shift.y)


## Screen boxes (screen pixels) of the need icons and wish bubbles shown over
## the passenger nodes under `views` (PassengerViews: its children with a
## &"body"), in view. Empty with no camera or while need icons are hidden at
## this zoom (NeedIcons.shown_at()).
static func icon_rects(views: Node, camera: Camera3D, to_output: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if views == null or camera == null or not NeedIcons.shown_at(camera):
		return rects
	var size := camera.get_viewport().get_visible_rect().size
	var unit := 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / size.y
	var view := Rect2(Vector2.ZERO, size)
	for child in views.get_children():
		var node := child as Node3D
		if node == null or not node.visible or not node.has_meta(&"body"):
			continue
		for sprite_name: String in NeedIcons.SPRITES + [WishIconView.SPRITE]:
			var sprite := node.get_node_or_null(NodePath(sprite_name)) as Sprite3D
			if sprite == null or not sprite.visible:
				continue
			var rect := sprite_rect(sprite, camera, unit)
			if rect.has_area() and view.intersects(rect):
				rects.append(Rect2(rect.position * to_output, rect.size * to_output))
	return rects


## The viewport-pixel box of a billboard Sprite3D through `camera` (`unit` is
## the world size of one viewport pixel at one metre), or an empty one when it
## draws nothing or is behind the camera or inside its near plane.
static func sprite_rect(sprite: Sprite3D, camera: Camera3D, unit: float) -> Rect2:
	if sprite.texture == null or sprite.modulate.a <= 0.0:
		return Rect2()
	var at := sprite.global_position
	var depth := (at - camera.global_position).dot(-camera.global_basis.z)
	if depth <= camera.near:
		return Rect2()
	var scale := sprite.pixel_size / ((1.0 if sprite.fixed_size else depth) * unit)
	var size := sprite.texture.get_size() * scale
	var centre := camera.unproject_position(at) + Vector2(sprite.offset.x, -sprite.offset.y) * scale
	return Rect2(centre - size / 2.0, size)


## The cream card for `label`, a child Sprite3D under its text (sync_card()
## sizes and places it).
static func make_card(label: Label3D) -> Sprite3D:
	var card := Sprite3D.new()
	card.name = CARD
	card.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	card.no_depth_test = true
	card.shaded = false
	card.double_sided = false
	card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	card.render_priority = label.outline_render_priority - 1
	label.add_child(card)
	sync_card(label)
	return card


## Fits a label's card to its text, size cap, slide and fade: one card texel
## per font pixel, centred on the text box (the text stands on the label's
## position, VERTICAL_ALIGNMENT_BOTTOM).
static func sync_card(label: Label3D) -> void:
	var card := label.get_node_or_null(CARD) as Sprite3D
	if card == null:
		return
	var font := label.font if label.font != null else ThemeDB.fallback_font
	var text := font.get_multiline_string_size(
		label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size
	)
	var size := Vector2i((text + Vector2.ONE * 2.0 * (label.outline_size + CARD_PAD_PX)).ceil())
	if card.texture == null or Vector2i(card.texture.get_size()) != size:
		card.texture = card_texture(size)
	card.pixel_size = label.pixel_size
	card.offset = label.offset + Vector2(0.0, text.y / 2.0)
	card.modulate.a = label.modulate.a
	# Culling bounds come from the label's own axes, not the camera-facing ones
	# its text is drawn in, so a slid label whose anchor is off screen was culled
	# (an empty card in a plate). A margin of twice the slide plus the card's
	# diagonal holds the drawn card at any turn, at any zoom.
	var margin := (
		2.0 * card.offset.length() * card.pixel_size + Vector2(size).length() * card.pixel_size
	)
	if not is_equal_approx(label.extra_cull_margin, margin):
		label.extra_cull_margin = margin
		card.extra_cull_margin = margin


## A cream rounded card `size` texels big with a CARD_BORDER_PX dark outline,
## painted once per size.
static func card_texture(size: Vector2i) -> ImageTexture:
	if _card_textures.has(size):
		return _card_textures[size]
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(CARD_BORDER)
	var border := int(CARD_BORDER_PX)
	image.fill_rect(Rect2i(Vector2i.ONE * border, size - Vector2i.ONE * 2 * border), CARD_FILL)
	# Only the corners are round: paint them texel by texel.
	var half := Vector2(size) / 2.0
	var inner := half - Vector2.ONE * CARD_RADIUS_PX
	var r := ceili(CARD_RADIUS_PX)
	for y in size.y:
		if y >= r and y < size.y - r:
			continue
		for x in [range(0, mini(r, size.x)), range(maxi(size.x - r, r), size.x)]:
			for xi: int in x:
				# Signed distance to the rounded rectangle's edge, negative inside.
				var q := (Vector2(xi + 0.5, y + 0.5) - half).abs() - inner
				var d := q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0.0) - CARD_RADIUS_PX
				var colour := CARD_BORDER if d > -CARD_BORDER_PX else CARD_FILL
				colour.a = clampf(0.5 - d, 0.0, 1.0)
				image.set_pixel(xi, y, colour)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_card_textures[size] = texture
	return texture
