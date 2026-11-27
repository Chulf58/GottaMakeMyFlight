class_name StaffChatBubbles
extends RefCounted
## Low-noise Toon speech-bubble icons above resting Break Room coworkers
## (Lively Staff 2/3, 4d7e3912). Two or more resting staff near each other
## turn gently toward a coworker and alternate subtle coffee/smile/music bubbles;
## solo resting staff emit no chat bubble.

enum IconKind { COFFEE, SMILE, MUSIC }

const SIZE := 128
const OUTLINE_PX := 8.5
const OUTLINE := MarkerIcons.OUTLINE
const CARD := WishIconView.CARD
const GLYPH := MarkerIcons.OUTLINE
const BODY_CENTRE := Vector2(-4.0, -10.0)
const BODY_HALF := Vector2(46.0, 38.0)
const BODY_ROUND := 20.0
const TAIL: Array[Vector2] = [Vector2(-24.0, 22.0), Vector2(-4.0, 22.0), Vector2(-22.0, 52.0)]
const ICON_PX := 48.0
const SPRITE := "StaffChatBubble"
const CHAT_RADIUS_M := 3.8
const CHAT_PERIOD_TICKS := 100
const CHAT_SHOW_TICKS := 40
const CHAT_HALF_TICKS := 50
const HEAD_GAP_M := 0.10

static var _textures: Dictionary = {}


static func texture(kind: IconKind) -> Texture2D:
	if not _textures.has(kind):
		_textures[kind] = _paint(kind)
	return _textures[kind]


static func ensure(node: Node3D) -> Sprite3D:
	var existing := node.get_node_or_null(SPRITE) as Sprite3D
	if existing != null:
		return existing
	var sprite := Sprite3D.new()
	sprite.name = SPRITE
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.fixed_size = true
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.render_priority = 10
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.position = Vector3(0.0, NeedIcons.LIFT_M, 0.0)
	sprite.offset = Vector2(0.0, float(SIZE) * 0.5)
	sprite.visible = false
	node.add_child(sprite)
	return sprite


static func hide(node: Node3D) -> void:
	if node == null:
		return
	var sprite := node.get_node_or_null(SPRITE) as Sprite3D
	if sprite != null:
		sprite.visible = false


## Returns {member_id: {"coworker_id", "coworker_eye", "show_icon", "icon_kind"}}
## for Break Room coworkers near each other; solo resting staff are omitted.
static func pairs_for(staff: StaffSim, resting_pos: Dictionary, tick_now: float) -> Dictionary:
	var out := {}
	if staff == null or resting_pos.size() < 2:
		return out
	var ids: Array[int] = []
	for raw_id in resting_pos:
		ids.append(int(raw_id))
	ids.sort()
	var t := maxf(tick_now, 0.0)
	var cycle := int(floor(t / float(CHAT_PERIOD_TICKS)))
	var phase := fposmod(t, float(CHAT_PERIOD_TICKS))
	for id in ids:
		var m := staff.get_member(id)
		if m == null or m.break_room <= 0:
			continue
		var my_pos: Vector3 = resting_pos[id]
		var best_id := 0
		var best_d := CHAT_RADIUS_M
		for other_id in ids:
			if other_id == id:
				continue
			var other := staff.get_member(other_id)
			if other == null or other.break_room != m.break_room:
				continue
			var d := my_pos.distance_to(resting_pos[other_id] as Vector3)
			if d <= best_d:
				best_d = d
				best_id = other_id
		if best_id == 0:
			continue
		var peer_pos: Vector3 = resting_pos[best_id]
		var pair_seed := mini(id, best_id) * 97 + maxi(id, best_id) * 31
		var is_first := id < best_id
		var show := (
			(is_first and phase < float(CHAT_SHOW_TICKS))
			or (
				not is_first
				and phase >= float(CHAT_HALF_TICKS)
				and phase < float(CHAT_HALF_TICKS + CHAT_SHOW_TICKS)
			)
		)
		var kind_idx := posmod(pair_seed + cycle + (0 if is_first else 1), 3)
		out[id] = {
			"coworker_id": best_id,
			"coworker_eye": peer_pos + Vector3(0.0, StaffStationPose.STAFF_EYE_M, 0.0),
			"show_icon": show,
			"icon_kind": kind_idx as IconKind,
		}
	return out


static func layout(
	node: Node3D,
	visible_bubble: bool,
	icon_kind: IconKind,
	camera: Camera3D,
	unit: float,
) -> void:
	if node == null:
		return
	if not visible_bubble:
		hide(node)
		return
	var sprite := ensure(node)
	var alpha := 1.0
	if camera != null and unit > 0.0:
		if not NeedIcons.shown_at(camera):
			sprite.visible = false
			return
		alpha = NeedIcons.near_alpha(camera.global_position.distance_to(node.global_position))
		if alpha <= 0.0:
			sprite.visible = false
			return
		sprite.pixel_size = ICON_PX * unit / float(SIZE)
		sprite.offset = Vector2(0.0, float(SIZE) * 0.5 + 8.0 * float(SIZE) / ICON_PX)
	else:
		sprite.pixel_size = 0.0049
		sprite.offset = Vector2(0.0, float(SIZE) * 0.5)
	if not node.has_meta(&"head_skeleton"):
		NeedIcons.find_head(node)
	var head_anchor := NeedIcons.head_top(node) + Vector3(0.0, HEAD_GAP_M, 0.0)
	sprite.position = head_anchor
	sprite.modulate.a = alpha
	sprite.texture = texture(icon_kind)
	sprite.visible = true


static func _paint(kind: IconKind) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			img.set_pixel(x, y, _bubble(kind, p))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _bubble(kind: IconKind, p: Vector2) -> Color:
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


static func _glyph(kind: IconKind, q: Vector2) -> float:
	match kind:
		IconKind.COFFEE:
			return _coffee_glyph(q)
		IconKind.SMILE:
			return _smile_glyph(q)
	return _music_glyph(q)


static func _coffee_glyph(q: Vector2) -> float:
	var cup := _box(q, Vector2(-3.0, 8.0), Vector2(13.0, 13.0), 4.0)
	var ring_d := q.distance_to(Vector2(11.0, 8.0))
	var handle := maxf(ring_d - 8.5, 4.0 - ring_d)
	handle = maxf(handle, -q.x + 8.0)
	var steam_l := _segment(q, Vector2(-7.0, -10.0), Vector2(-5.0, -20.0)) - 2.4
	var steam_r := _segment(q, Vector2(3.0, -10.0), Vector2(5.0, -20.0)) - 2.4
	return minf(minf(cup, handle), minf(steam_l, steam_r))


static func _smile_glyph(q: Vector2) -> float:
	var eye_l := q.distance_to(Vector2(-10.0, -7.0)) - 4.0
	var eye_r := q.distance_to(Vector2(10.0, -7.0)) - 4.0
	var arc_a := _segment(q, Vector2(-14.0, 4.0), Vector2(-6.0, 12.0)) - 3.2
	var arc_b := _segment(q, Vector2(-6.0, 12.0), Vector2(6.0, 12.0)) - 3.2
	var arc_c := _segment(q, Vector2(6.0, 12.0), Vector2(14.0, 4.0)) - 3.2
	return minf(minf(eye_l, eye_r), minf(arc_a, minf(arc_b, arc_c)))


static func _music_glyph(q: Vector2) -> float:
	var head_l := q.distance_to(Vector2(-11.0, 12.0)) - 6.2
	var head_r := q.distance_to(Vector2(10.0, 8.0)) - 6.2
	var stem_l := _segment(q, Vector2(-6.5, 11.0), Vector2(-6.5, -15.0)) - 2.6
	var stem_r := _segment(q, Vector2(14.5, 7.0), Vector2(14.5, -19.0)) - 2.6
	var beam := _segment(q, Vector2(-6.5, -15.0), Vector2(14.5, -19.0)) - 3.8
	return minf(minf(head_l, head_r), minf(stem_l, minf(stem_r, beam)))


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


static func _box(p: Vector2, centre: Vector2, half: Vector2, round_px: float) -> float:
	var q := (p - centre).abs() - half + Vector2.ONE * round_px
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - round_px
