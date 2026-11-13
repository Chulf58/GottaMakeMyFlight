class_name VipMarker
extends RefCounted
## The crown over the VIP passenger (board 2348c245; decision daily-incidents-
## small-ones-just-happen-with-a-card-and-a-cau: a VIP is an ordinary passenger
## marked for that day's incident, not a new trait). While an accepted VIP
## incident has marked its passenger (IncidentMajors: plan "target"), that
## passenger wears a gold crown over the head; the mark goes when the incident
## ends (made, missed or not held).
##
## The crown is painted once into a texture in the HUD's filled toon style, like
## the need icons (NeedIcons) and station signs (MarkerIcons): a gold fill inside
## the dark navy outline, with a navy band line. Its shape sets it apart from the
## round need icons, the rounded-square station signs and the wish bubble
## (WishIconView). Two Point Hospital marks its VIP visitors the same way, with a
## crown icon over the head.
##
## Unlike the need icons, the crown shows at the home zoom and farther out:
## there is one VIP at a time, so it adds no crowding (the reason the need icons
## hide there, decision passenger-need-icons-hide-when-the-camera-is-zoomed-out-
## past), and the player needs to find the VIP at the zoom they play at. The N
## key does not hide it (it toggles the need icons only). It fades near the lens
## with the need icons (NeedIcons.near_alpha(), decision passenger-need-icons-
## fade-out-when-the-camera-is-very-close), for the same reason: it draws with no
## depth test and would land on another passenger's face.
##
## PassengerViews gives every pooled passenger node one sprite (make_sprite()),
## fills the marked ids from the director on every sync (marked_ids()), sets the
## sprite each tick (mark()) and lays it out each frame after the need icons
## (layout()): CROWN_PX on screen, over the head, or on top of the thought
## bubble and the need icon row while they show. It holds no tick: a load reads
## the marked ids again from the loaded director.

const SIZE := 128
const OUTLINE_PX := 9.0
const OUTLINE := MarkerIcons.OUTLINE
## A deeper gold than the need icons' attention yellow (NeedIcons.FILL), so the
## crown reads as gold beside them.
const FILL := Color(1.0, 0.74, 0.16)
const BAND := MarkerIcons.OUTLINE
## The crown's height on screen, in output pixels: over a need icon's
## (NeedIcons.ICON_PX) and under a station sign's (56 px).
const CROWN_PX := 40.0
## The sprite's name on a passenger node.
const SPRITE := "VipCrown"
## The crown's outline, in texture pixels around the centre (y runs down): a
## band at the bottom, three points with valleys between them.
const OUTLINE_POINTS: Array[Vector2] = [
	Vector2(-42.0, 38.0),
	Vector2(42.0, 38.0),
	Vector2(46.0, -24.0),
	Vector2(21.0, 2.0),
	Vector2(0.0, -34.0),
	Vector2(-21.0, 2.0),
	Vector2(-46.0, -24.0),
]
## A ball on each point's tip, wide enough that gold shows inside its outline
## (at 10 px the outline left 1 px of gold and the balls read as dark dots).
const BALLS: Array[Vector2] = [Vector2(-46.0, -30.0), Vector2(0.0, -42.0), Vector2(46.0, -30.0)]
const BALL_RADIUS := 15.0

static var _texture: ImageTexture


## Clears `into` and fills it with the ids of the passengers marked by an
## accepted VIP incident of `director` (IncidentDirector.vip_targets(), which
## copies no incident), as keys; empty with no director. The caller keeps one
## dictionary and passes it on every sync.
static func marked_ids(director: IncidentDirector, into: Dictionary) -> void:
	if director == null:
		into.clear()
		return
	director.vip_targets(into)


static func texture() -> Texture2D:
	if _texture == null:
		_texture = ImageTexture.create_from_image(_paint())
	return _texture


## A billboard drawn over the world, its bottom edge on its anchor, with the
## need icons' draw order (under the station signs and the speech bubbles).
static func make_sprite() -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = SPRITE
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.fixed_size = true
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.render_priority = 10
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.texture = texture()
	sprite.position = Vector3(0.0, NeedIcons.LIFT_M, 0.0)
	sprite.offset = Vector2(0.0, SIZE / 2.0)
	sprite.visible = false
	return sprite


## Marks or unmarks a passenger node for this tick.
static func mark(node: Node3D, marked: bool) -> void:
	node.set_meta(&"vip", marked)
	(node.get_node(SPRITE) as Sprite3D).visible = marked


## Lays out a marked node's crown for this frame: CROWN_PX on screen (`unit`
## from NeedIcons.unit_of()), over the head, lifted over the thought bubble and
## over the need icon row while they show. Call after NeedIcons.layout(), which
## sets the row's visibility for the frame. Fades with near_alpha(); hidden with
## no camera.
static func layout(node: Node3D, bubble: Label3D, camera: Camera3D, unit: float) -> void:
	var crown := node.get_node(SPRITE) as Sprite3D
	if not node.get_meta(&"vip", false):
		crown.visible = false
		return
	if camera == null or unit <= 0.0:
		crown.visible = false
		return
	var alpha := NeedIcons.near_alpha(camera.global_position.distance_to(node.global_position))
	crown.visible = alpha > 0.0
	crown.modulate.a = alpha
	# Where the row stands (the head gap over the head, or on the bubble), so
	# the crown stacks on the row (decision need-icons-and-wish-bubbles-sit-a-
	# fixed-screen-gap-above-the).
	var at := NeedIcons.row_anchor(node, bubble, camera, unit)
	var lift_px: float = at[1] + _row_px(node)
	crown.position = at[0]
	crown.pixel_size = CROWN_PX * unit / SIZE
	crown.offset = Vector2(0.0, SIZE / 2.0 + lift_px * SIZE / CROWN_PX)


## The screen height the node's need icon row takes this frame, with the gap
## over it, or 0 when no icon of the row is drawn.
static func _row_px(node: Node3D) -> float:
	var row := 0.0
	for sprite_name in NeedIcons.SPRITES:
		if (node.get_node(sprite_name) as Sprite3D).visible:
			row = NeedIcons.ICON_PX
	var wish := node.get_node_or_null(WishIconView.SPRITE) as Sprite3D
	if wish != null and wish.visible:
		row = WishIconView.WISH_PX
	return row + NeedIcons.GAP_PX if row > 0.0 else 0.0


static func _paint() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var edge := shape_distance(p)
			var cover := clampf(0.5 - edge, 0.0, 1.0)
			if cover <= 0.0:
				img.set_pixel(x, y, Color(OUTLINE, 0.0))
				continue
			var inside := clampf(0.5 - (edge + OUTLINE_PX), 0.0, 1.0)
			var colour := OUTLINE.lerp(FILL, inside)
			var band := MarkerIcons.segment_distance(p, Vector2(-34.0, 20.0), Vector2(34.0, 20.0))
			colour = colour.lerp(BAND, clampf(0.5 - (band - 3.5), 0.0, 1.0) * inside)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	return img


## Signed distance in texture pixels to the crown's edge, negative inside: the
## outline polygon joined with the three balls.
static func shape_distance(p: Vector2) -> float:
	var d := _polygon_distance(p, OUTLINE_POINTS)
	for ball in BALLS:
		d = minf(d, p.distance_to(ball) - BALL_RADIUS)
	return d


## Signed distance to a closed polygon, negative inside (even-odd rule).
static func _polygon_distance(p: Vector2, points: Array[Vector2]) -> float:
	var best := INF
	var inside := false
	var j := points.size() - 1
	for i in points.size():
		var a := points[i]
		var b := points[j]
		best = minf(best, MarkerIcons.segment_distance(p, a, b))
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return -best if inside else best
