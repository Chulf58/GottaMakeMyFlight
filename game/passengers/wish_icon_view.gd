class_name WishIconView
extends RefCounted
## The shopping wish icon over a bored passenger (ruling store-variety-
## passengers-have-a-shopping-wish-weighted-by-arrival-type-unmet-settles-for-
## less: the wish shows as a small icon over the passenger, so the player sees
## which store kinds are missing; decision shopping-wish-technical-design-id-
## hash-wish-admissible-wished-slot-then-fallback, point 5).
##
## The icon is a cream speech bubble with a dark navy outline and a navy glyph
## of the wished kind (a newspaper for the kiosk, a cross for the pharmacy, a
## bottle for duty free, a T-shirt for fashion), in the HUD's filled toon
## style (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-
## pale). While the passenger is bored and has no visit it shows the bubble
## alone (WishTable.State.WANTED). Once the planner commits a visit it adds a
## badge: a green circle with a white tick when the visit is to the wished
## kind (FULFILLED), a coral circle with a white cross when it settles for
## another shop (SUBSTITUTED). The bubble's tail and the badges set it apart
## from the round need icons and the square station signs.
##
## It reads only ShopSim.visit_wish_state() and ShopSim.wish_of(): the
## planner's result, never a plan or a path. PassengerViews gives each pooled
## passenger node one sprite (make_sprite()), sets it each tick (show_wish(),
## which changes the texture only when the wish or its state changes) and lays
## it out each frame (layout()): WISH_PX on screen, stacked over the need icon
## row and hidden with it at the home zoom or farther out (decision passenger-
## need-icons-hide-when-the-camera-is-zoomed-out-past, NeedIcons.shown_at()).

enum Badge { NONE, TICK, CROSS }

const SIZE := 128
const OUTLINE_PX := 9.0
const BADGE_OUTLINE_PX := 7.0
const OUTLINE := MarkerIcons.OUTLINE
const GLYPH := MarkerIcons.OUTLINE
## The HUD theme's card cream (hud_theme.tres, the panel card fill).
const CARD := Color(0.99, 0.97, 0.92)
## The HUD theme's green, for good news.
const GOOD := Color(0.44, 0.704, 0.396)
## The HUD theme's coral red, for problems.
const PROBLEM := Color(0.92, 0.45, 0.4)
## The tick and the cross on a badge.
const MARK := Color(1.0, 1.0, 1.0)
## The bubble's body, a rounded box, in texture pixels from the centre.
const BODY_CENTRE := Vector2(-12.0, -14.0)
const BODY_HALF := Vector2(46.0, 40.0)
const BODY_ROUND := 20.0
## The tail, a triangle under the body's left half.
const TAIL: Array[Vector2] = [Vector2(-44.0, 20.0), Vector2(-22.0, 20.0), Vector2(-42.0, 54.0)]
## The badge circle, over the body's lower right corner, large enough for its
## mark to read at WISH_PX.
const BADGE_CENTRE := Vector2(36.0, 35.0)
const BADGE_RADIUS := 27.0
## The icon's height on screen, in output pixels: over a need icon's, so the
## glyph reads about as large as a need glyph and the badge's mark reads too.
const WISH_PX := 48.0
## The sprite's name on a passenger node.
const SPRITE := "WishIcon"

static var _textures: Dictionary = {}


## The badge for `state`: none while wanted, a tick when fulfilled, a cross
## when substituted.
static func badge_of(state: WishTable.State) -> Badge:
	match state:
		WishTable.State.FULFILLED:
			return Badge.TICK
		WishTable.State.SUBSTITUTED:
			return Badge.CROSS
	return Badge.NONE


## The wish of `p` and its state, [kind, WishTable.State], from the planner's
## result: ShopSim.visit_wish_state(), and ShopSim.wish_of() only when there
## is one to show. NONE for a passenger who missed its flight or boarded.
static func read(shops: ShopSim, p: Passenger) -> Array:
	if p.stage == Passenger.Stage.MISSED or p.stage == Passenger.Stage.MADE:
		return [WishTable.NONE, WishTable.State.NONE]
	var state := shops.visit_wish_state(p.id)
	if state == WishTable.State.NONE:
		return [WishTable.NONE, state]
	return [shops.wish_of(p), state]


## A key naming the icon for `kind` in `state`, or empty when nothing shows.
static func key_of(kind: StringName, state: WishTable.State) -> String:
	if state == WishTable.State.NONE or kind == WishTable.NONE:
		return ""
	return "%s/%d" % [kind, badge_of(state)]


## The icon for `kind` in `state`, painted once and kept.
static func texture(kind: StringName, state: WishTable.State) -> Texture2D:
	var key := key_of(kind, state)
	if not _textures.has(key):
		_textures[key] = _paint(kind, badge_of(state))
	return _textures[key]


## The wish billboard, drawn over the world like a need icon.
static func make_sprite() -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = SPRITE
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.fixed_size = true
	sprite.no_depth_test = true
	sprite.shaded = false
	# With the need icons, under the station signs (11) and captions (12).
	sprite.render_priority = 10
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.position = Vector3(0.0, NeedIcons.LIFT_M, 0.0)
	sprite.offset = offset_for(0.0)
	sprite.visible = false
	return sprite


## Shows `wish` ([kind, WishTable.State] from read()) on a passenger node's
## sprite. Sets the texture only when the icon changes.
static func show_wish(node: Node3D, wish: Array) -> void:
	var key := key_of(wish[0], wish[1])
	if node.get_meta(&"wish", "") == key:
		return
	node.set_meta(&"wish", key)
	var sprite := node.get_node(SPRITE) as Sprite3D
	sprite.visible = key != ""
	if sprite.visible:
		sprite.texture = texture(wish[0], wish[1])


## The sprite's offset, in texture pixels, for its bottom edge `lift_px`
## screen pixels over its anchor.
static func offset_for(lift_px: float) -> Vector2:
	return Vector2(0.0, SIZE / 2.0 + lift_px * SIZE / WISH_PX)


## Lays out a passenger node's wish icon for this frame: WISH_PX on screen
## (`unit` from NeedIcons.unit_of()), centred over the need icon row, or where
## the row would be when no need shows; on top of the thought bubble while it
## shows. With `shown` false (NeedIcons.shown_at()) it is hidden.
static func layout(
	node: Node3D, bubble: Label3D, camera: Camera3D, unit: float, shown := true
) -> void:
	var sprite := node.get_node(SPRITE) as Sprite3D
	sprite.visible = shown and node.get_meta(&"wish", "") != ""
	if not sprite.visible or camera == null or unit <= 0.0:
		return
	var anchor := Vector3(0.0, NeedIcons.LIFT_M, 0.0)
	var lift_px := 0.0
	if bubble.text != "":
		anchor = bubble.position
		var at := node.global_transform * bubble.position
		var depth := (at - camera.global_position).dot(-camera.global_basis.z)
		if depth > 0.0:
			lift_px = NeedIcons.bubble_top_m(bubble) / (depth * unit) + NeedIcons.GAP_PX
	if node.get_meta(&"needs", 0) > 0:
		lift_px += NeedIcons.ICON_PX + NeedIcons.GAP_PX
	sprite.position = anchor
	sprite.pixel_size = WISH_PX * unit / SIZE
	sprite.offset = offset_for(lift_px)


static func _paint(kind: StringName, badge: Badge) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var under := _bubble(kind, p)
			var colour := under
			if badge != Badge.NONE:
				colour = _over(_badge(badge, p), under)
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The bubble's colour at `p`, its alpha the cover.
static func _bubble(kind: StringName, p: Vector2) -> Color:
	var edge := minf(_box(p, BODY_CENTRE, BODY_HALF, BODY_ROUND), _triangle(p, TAIL))
	var cover := clampf(0.5 - edge, 0.0, 1.0)
	if cover <= 0.0:
		return Color(OUTLINE, 0.0)
	var inside := clampf(0.5 - (edge + OUTLINE_PX), 0.0, 1.0)
	var colour := OUTLINE.lerp(CARD, inside)
	var glyph := _glyph(kind, p - BODY_CENTRE)
	colour = colour.lerp(GLYPH, clampf(0.5 - glyph, 0.0, 1.0) * inside)
	colour.a = cover
	return colour


## The badge's colour at `p`, its alpha the cover.
static func _badge(badge: Badge, p: Vector2) -> Color:
	var q := p - BADGE_CENTRE
	var edge := q.length() - BADGE_RADIUS
	var cover := clampf(0.5 - edge, 0.0, 1.0)
	if cover <= 0.0:
		return Color(OUTLINE, 0.0)
	var inside := clampf(0.5 - (edge + BADGE_OUTLINE_PX), 0.0, 1.0)
	var colour := OUTLINE.lerp(GOOD if badge == Badge.TICK else PROBLEM, inside)
	var mark := _tick(q) if badge == Badge.TICK else _cross(q)
	colour = colour.lerp(MARK, clampf(0.5 - mark, 0.0, 1.0) * inside)
	colour.a = cover
	return colour


## `top` drawn over `under`.
static func _over(top: Color, under: Color) -> Color:
	var alpha := top.a + under.a * (1.0 - top.a)
	if alpha <= 0.0:
		return Color(OUTLINE, 0.0)
	var rgb := (
		Vector3(top.r, top.g, top.b) * top.a
		+ Vector3(under.r, under.g, under.b) * under.a * (1.0 - top.a)
	)
	rgb /= alpha
	return Color(rgb.x, rgb.y, rgb.z, alpha)


## Signed distance to the glyph of `kind`, `q` from the body's centre.
static func _glyph(kind: StringName, q: Vector2) -> float:
	match kind:
		&"kiosk":
			return _newspaper(q)
		&"pharmacy":
			return _plus(q)
		&"duty_free":
			return _bottle(q)
	return _shirt(q)


## A folded newspaper: a sheet with a headline block and two lines of text
## cut out of it. Image y runs down.
static func _newspaper(q: Vector2) -> float:
	var sheet := _box(q, Vector2.ZERO, Vector2(25.0, 25.0), 3.0)
	var headline := _box(q, Vector2(0.0, -11.0), Vector2(17.0, 6.0), 1.0)
	var lines := minf(
		_segment(q, Vector2(-16.0, 5.0), Vector2(16.0, 5.0)) - 3.0,
		_segment(q, Vector2(-16.0, 15.0), Vector2(16.0, 15.0)) - 3.0
	)
	return maxf(sheet, -minf(headline, lines))


## A pharmacy cross.
static func _plus(q: Vector2) -> float:
	return minf(
		_box(q, Vector2.ZERO, Vector2(9.0, 26.0), 3.0),
		_box(q, Vector2.ZERO, Vector2(26.0, 9.0), 3.0)
	)


## A bottle with a cap and a label.
static func _bottle(q: Vector2) -> float:
	var body := _box(q, Vector2(0.0, 9.0), Vector2(16.0, 19.0), 6.0)
	var neck := _box(q, Vector2(0.0, -15.0), Vector2(6.5, 9.0), 2.0)
	var cap := _box(q, Vector2(0.0, -25.0), Vector2(9.0, 4.5), 1.5)
	var label := _box(q, Vector2(0.0, 10.0), Vector2(10.0, 7.0), 1.0)
	return maxf(minf(body, minf(neck, cap)), -label)


## A T-shirt: body, shoulders and sleeves, with a round neck cut out.
static func _shirt(q: Vector2) -> float:
	var body := _box(q, Vector2(0.0, 7.0), Vector2(15.0, 19.0), 2.0)
	var shoulders := _box(q, Vector2(0.0, -12.0), Vector2(21.0, 7.0), 3.0)
	var sleeves := minf(
		_segment(q, Vector2(-15.0, -13.0), Vector2(-27.0, 2.0)) - 7.0,
		_segment(q, Vector2(15.0, -13.0), Vector2(27.0, 2.0)) - 7.0
	)
	var neck := q.distance_to(Vector2(0.0, -19.0)) - 7.5
	return maxf(minf(body, minf(shoulders, sleeves)), -neck)


## A tick, `q` from the badge's centre.
static func _tick(q: Vector2) -> float:
	return (
		minf(
			_segment(q, Vector2(-12.0, 1.0), Vector2(-4.0, 10.0)),
			_segment(q, Vector2(-4.0, 10.0), Vector2(12.0, -9.0))
		)
		- 5.0
	)


## A cross, `q` from the badge's centre.
static func _cross(q: Vector2) -> float:
	return (
		minf(
			_segment(q, Vector2(-10.0, -10.0), Vector2(10.0, 10.0)),
			_segment(q, Vector2(10.0, -10.0), Vector2(-10.0, 10.0))
		)
		- 5.0
	)


## Signed distance to a triangle (the largest of its edges' half-plane
## distances: exact inside, close enough outside for a pixel of antialiasing).
static func _triangle(p: Vector2, corners: Array[Vector2]) -> float:
	var out := -INF
	for i in 3:
		var a := corners[i]
		var b := corners[(i + 1) % 3]
		var c := corners[(i + 2) % 3]
		var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
		if normal.dot(c - a) > 0.0:
			normal = -normal
		out = maxf(out, normal.dot(p - a))
	return out


static func _segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Signed distance to a box of half size `half` with corners rounded by `round_px`.
static func _box(p: Vector2, centre: Vector2, half: Vector2, round_px: float) -> float:
	var q := (p - centre).abs() - half + Vector2.ONE * round_px
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - round_px
