class_name NeedIcons
extends RefCounted
## The need icons over passengers (decision passenger-needs-are-hunger-toilet-
## and-boredom-met-by-food-st: each need shows as an icon above the passenger).
## Each icon is painted once into a texture in the HUD's filled toon style
## (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale): a
## circle in the attention yellow inside the dark navy outline, with a dark
## navy glyph, a fork and knife for hunger and a toilet for the toilet need.
## Both use the one attention colour, told apart by the glyph; the circle tells
## them from the stations' rounded-square signs (MarkerIcons).
##
## A need's icon shows while the need is at or over the level its facility
## acts on (CafeSim.HUNGRY_AT, ToiletSim.NEED_AT), walking and queueing
## included, until the visit meets it. It is hidden while the passenger is at
## the facility meeting it (at a cafe table, inside a toilet stall) and for a
## passenger who missed the flight. All icons hide while the game camera is at
## its home zoom or farther out (shown_at()); the follow panel still lists the
## needs.
##
## PassengerViews gives every passenger node two Sprite3D icons (make_sprite())
## at one point over the head, so the body's turn never moves them, and lays
## them out each frame (layout()): they keep ICON_PX on screen at every zoom,
## like the station signs, and stand side by side along the screen's x through
## their offsets in the billboard plane. While the passenger's thought bubble
## shows, the row sits on top of the bubble instead of over the head.

enum Need { HUNGER, TOILET }

const SIZE := 128
const OUTLINE_PX := 9.0
const OUTLINE := MarkerIcons.OUTLINE
## The HUD theme's attention yellow (hud_theme.tres, the attention card fill).
const FILL := Color(1.0, 0.8, 0.3)
const GLYPH := MarkerIcons.OUTLINE
const RADIUS := 60.0
## One icon's height on screen, in output pixels: about half the station sign.
const ICON_PX := 30.0
## Screen pixels between two icons, and between the row and a bubble under it.
const GAP_PX := 4.0
## Height over the passenger's root of the icons' anchor, just over the head.
const LIFT_M := 2.0
## The sprite names on a passenger node.
const SPRITES := ["NeedIcon0", "NeedIcon1"]

static var _textures: Dictionary = {}


## The needs whose icons show over `p`, hunger first.
static func shown(p: Passenger) -> Array[Need]:
	var out: Array[Need] = []
	if p.stage == Passenger.Stage.MISSED or p.stage == Passenger.Stage.MADE:
		return out
	var at_facility := StageKinds.location(p.stage) == StageKinds.Location.FACILITY_SEAT
	var facility := StageKinds.facility(p.stage)
	var eating := at_facility and facility == StageKinds.Facility.CAFE
	var in_stall := at_facility and facility == StageKinds.Facility.TOILET
	if p.hunger >= CafeSim.HUNGRY_AT and not eating:
		out.append(Need.HUNGER)
	if p.toilet_need >= ToiletSim.NEED_AT and not in_stall:
		out.append(Need.TOILET)
	return out


static func texture(need: Need) -> Texture2D:
	if not _textures.has(need):
		_textures[need] = _paint(need)
	return _textures[need]


## A billboard drawn over the world, its bottom edge on its anchor.
static func make_sprite(sprite_name: String) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = sprite_name
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.fixed_size = true
	sprite.no_depth_test = true
	sprite.shaded = false
	# Under the station signs (11) and their captions (12).
	sprite.render_priority = 10
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.position = Vector3(0.0, LIFT_M, 0.0)
	sprite.offset = offset_of(0, 1)
	sprite.visible = false
	return sprite


## Shows `needs` on a passenger node's sprites, in order, and hides the rest.
static func show_needs(node: Node3D, needs: Array[Need]) -> void:
	for i in SPRITES.size():
		var sprite := node.get_node(SPRITES[i]) as Sprite3D
		sprite.visible = i < needs.size()
		if sprite.visible:
			sprite.texture = texture(needs[i])
	node.set_meta(&"needs", needs.size())


## The offset, in texture pixels, of icon `index` of a row of `count`: centred
## along the screen's x with GAP_PX between them, the bottom edge `lift_px`
## screen pixels over the anchor.
static func offset_of(index: int, count: int, lift_px := 0.0) -> Vector2:
	var to_texture := SIZE / ICON_PX
	var step := SIZE + GAP_PX * to_texture
	var x := (index - (count - 1) / 2.0) * step
	return Vector2(x, SIZE / 2.0 + lift_px * to_texture)


## Whether need icons show through `camera` (user ruling: need icons hide when
## the camera is zoomed out past the home zoom). Under a TycoonCamera rig they
## show only while it is closer than its home distance (TycoonCamera.
## home_distance, which frame_start_view() sets); at the home zoom or farther
## out they are hidden. Any other camera, or none, shows them.
static func shown_at(camera: Camera3D) -> bool:
	var rig := camera.get_parent() as TycoonCamera if camera != null else null
	return rig == null or rig.distance < rig.home_distance


## World units per output pixel at one metre from `camera` in `view`, or 0
## with no camera.
static func unit_of(view: Viewport, camera: Camera3D) -> float:
	if view == null or camera == null:
		return 0.0
	var height := view.get_visible_rect().size.y * view.get_stretch_transform().get_scale().y
	return 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / height


## Lays out a passenger node's shown icons for this frame: ICON_PX on screen
## (`unit` from unit_of()), side by side, over the head, or on top of the
## thought bubble while it shows. Does nothing with no camera.
## With `shown` false (the camera at the home zoom or farther out, shown_at())
## the node's icons are hidden for this frame.
static func layout(
	node: Node3D, bubble: Label3D, camera: Camera3D, unit: float, shown := true
) -> void:
	var count: int = node.get_meta(&"needs", 0)
	for i in count:
		(node.get_node(SPRITES[i]) as Sprite3D).visible = shown
	if count == 0 or not shown or camera == null or unit <= 0.0:
		return
	var anchor := Vector3(0.0, LIFT_M, 0.0)
	var lift_px := 0.0
	if bubble.text != "":
		anchor = bubble.position
		var at := node.global_transform * bubble.position
		var depth := (at - camera.global_position).dot(-camera.global_basis.z)
		if depth > 0.0:
			lift_px = bubble_top_m(bubble) / (depth * unit) + GAP_PX
	for i in count:
		var sprite := node.get_node(SPRITES[i]) as Sprite3D
		sprite.position = anchor
		sprite.pixel_size = ICON_PX * unit / SIZE
		sprite.offset = offset_of(i, count, lift_px)


## How far the top of a one-line bubble reaches over its centre, in metres:
## half the font plus half its outline. Taken from the label's settings, not
## its bounds: a label's bounds are empty until the frame after its text
## changes, and then much taller than the line drawn (0.65 m for 0.21 m).
static func bubble_top_m(bubble: Label3D) -> float:
	return (bubble.font_size + bubble.outline_size) * bubble.pixel_size / 2.0


static func _paint(need: Need) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := SIZE / 2.0
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var edge := p.length() - RADIUS
			var cover := clampf(0.5 - edge, 0.0, 1.0)
			if cover <= 0.0:
				img.set_pixel(x, y, Color(OUTLINE, 0.0))
				continue
			var inside := clampf(0.5 - (edge + OUTLINE_PX), 0.0, 1.0)
			var colour := OUTLINE.lerp(FILL, inside)
			var glyph := _hunger(p) if need == Need.HUNGER else _toilet(p)
			colour = colour.lerp(GLYPH, clampf(0.5 - glyph, 0.0, 1.0) * inside)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Signed distance to a fork (left) and a knife (right). Image y runs down.
static func _hunger(p: Vector2) -> float:
	var tines := minf(
		_segment(p, Vector2(-25.0, -36.0), Vector2(-25.0, -14.0)) - 3.5,
		minf(
			_segment(p, Vector2(-16.0, -36.0), Vector2(-16.0, -14.0)) - 3.5,
			_segment(p, Vector2(-7.0, -36.0), Vector2(-7.0, -14.0)) - 3.5
		)
	)
	var bridge := _box(p, Vector2(-16.0, -12.0), Vector2(12.5, 6.0), 5.0)
	var fork_handle := _segment(p, Vector2(-16.0, -8.0), Vector2(-16.0, 36.0)) - 5.5
	var blade := _segment(p, Vector2(15.0, -32.0), Vector2(15.0, 2.0)) - 8.0
	var knife_handle := _segment(p, Vector2(15.0, 2.0), Vector2(15.0, 36.0)) - 5.5
	return minf(minf(tines, bridge), minf(fork_handle, minf(blade, knife_handle)))


## Signed distance to a toilet seen from the side, facing right: the tank,
## the seat over a round bowl, and the pedestal.
static func _toilet(p: Vector2) -> float:
	var tank := _box(p, Vector2(-20.0, -14.0), Vector2(10.0, 20.0), 3.0)
	var seat := _box(p, Vector2(4.0, 0.0), Vector2(26.0, 5.0), 4.0)
	var bowl := maxf(p.distance_to(Vector2(4.0, 2.0)) - 24.0, 2.0 - p.y)
	var pedestal := _box(p, Vector2(2.0, 30.0), Vector2(10.0, 9.0), 2.0)
	return minf(minf(tank, seat), minf(bowl, pedestal))


static func _segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Signed distance to a box of half size `half` with corners rounded by `round_px`.
static func _box(p: Vector2, centre: Vector2, half: Vector2, round_px: float) -> float:
	var q := (p - centre).abs() - half + Vector2.ONE * round_px
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - round_px
