class_name NeedIcons
extends RefCounted
## The need icons over passengers (decision passenger-needs-are-hunger-toilet-
## and-boredom-met-by-food-st: each need shows as an icon above the passenger).
## Each icon is painted once into a texture in the HUD's filled toon style
## (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-toon-pale): a
## circle in the attention yellow inside the dark navy outline, with a dark
## navy glyph: a fork and knife for hunger, a toilet for the toilet need and
## an hourglass for boredom. All use the one attention colour, told apart by
## the glyph; the circle tells them from the stations' rounded-square signs
## (MarkerIcons).
##
## A need's icon shows while the need is at or over the level its facility
## acts on (CafeSim.HUNGRY_AT, ToiletSim.NEED_AT, BoredomSim.BORED_AT), walking
## and queueing included, until the visit meets it. It is hidden while the
## passenger is at the facility meeting it (at a cafe table, inside a toilet
## stall, browsing at a kiosk) and for a passenger who missed the flight. All
## icons hide
## while the game camera is at its home zoom or farther out (shown_at()) and
## while the N key has turned them off (NeedIconsToggle, on by default, decision
## passenger-need-icons-toggle-key-n-on-by-default); the follow panel still
## lists the needs. A passenger's icons also fade out as the
## camera comes very close to that passenger (near_alpha()).
##
## No icon shows for a need while nothing built can meet it (provided(): no
## cafe, no toilet stall, no shop that relieves boredom, screen or prize car).
##
## PassengerViews gives every passenger node three Sprite3D icons (make_sprite())
## at one point over the head, so the body's turn never moves them, and lays
## them out each frame (layout()): they keep ICON_PX on screen at every zoom,
## like the station signs, and stand side by side along the screen's x through
## their offsets in the billboard plane. While the passenger's thought bubble
## shows, the row sits on top of the bubble instead of over the head.
## A bored passenger with a shopping wish shows its wish bubble (WishIconView)
## at the end of the row instead of the hourglass (user ruling shopping-wish-
## icon-replaces-the-boredom-hourglass-for-wishers); one with no wish keeps the
## hourglass.
##
## Close icons of one kind merge into one bigger icon with a count (NeedCluster,
## drawn by PassengerViews); layout()'s mask hides the members' own icons.

enum Need { HUNGER, TOILET, BOREDOM }

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
## A passenger's icons fade out as the camera comes within NEAR_FULL_M of it and
## are gone at NEAR_HIDDEN_M. Icons draw with no depth test at a 2.0 m anchor, so
## near the lens one passenger's row lands on another's face. Read off the
## need_icon_near_camera plates: at the 0.4x home zoom the seated rows stand
## 6.2 to 8.8 m from the camera and a row at 6.85 m covered a face at 7.2 m, so
## the icons are gone from 7.0 m and whole from 9.0 m (a 2 m fade).
const NEAR_HIDDEN_M := 7.0
const NEAR_FULL_M := 9.0
## The sprite names on a passenger node.
const SPRITES := ["NeedIcon0", "NeedIcon1", "NeedIcon2"]

static var _textures: Dictionary = {}


## Which needs something built can meet, as need -> bool (decision crowd-need-
## display-mood-overlay-gains-hunger-toilet-and-bore, point 3: a need icon is
## hidden while nothing built can meet that need). Hunger: a usable cafe;
## toilet: a usable stall (the same layouts HintRules.read_world() counts for
## the toilet and food hints); boredom: a ready kiosk-style shop that relieves
## it, a screen stand or a prize car, the three things BoredomSim treats as
## meeting it. Refreshes the toilet, cafe and shop layouts if an edit left them
## stale, as read_world() does.
static func provided(sim: PassengerSim) -> Dictionary:
	sim.toilets.refresh()
	sim.cafes.refresh()
	sim.shops.refresh()
	var relieving := false
	for shop in sim.shops.layout.shops:
		if RoomTypes.get_type(sim.grid.get_room(shop["room"])["type"]).relieves_boredom:
			relieving = true
			break
	return {
		Need.HUNGER: not sim.cafes.layout.cafes.is_empty(),
		Need.TOILET: not sim.toilets.layout.stalls.is_empty(),
		Need.BOREDOM:
		(
			relieving
			or not sim.boredom.screens.cells().is_empty()
			or not sim.boredom.prize.cells().is_empty()
		),
	}


## The needs whose icons show over `p`: hunger, toilet, boredom. With
## `wishing` (a shopping wish shows over `p`, WishIconView) the wish bubble
## takes the boredom icon's place in the row (user ruling shopping-wish-icon-
## replaces-the-boredom-hourglass-for-wishers), so boredom is left out. A need
## `built` (provided()) maps to false is left out too; a need it does not name
## is not gated, so the default, an empty `built`, gates nothing.
static func shown(p: Passenger, wishing := false, built := {}) -> Array[Need]:
	var out: Array[Need] = []
	if p.stage == Passenger.Stage.MISSED or p.stage == Passenger.Stage.MADE:
		return out
	var at_facility := StageKinds.location(p.stage) == StageKinds.Location.FACILITY_SEAT
	var facility := StageKinds.facility(p.stage)
	var eating := at_facility and facility == StageKinds.Facility.CAFE
	var in_stall := at_facility and facility == StageKinds.Facility.TOILET
	if p.hunger >= CafeSim.HUNGRY_AT and not eating and built.get(Need.HUNGER, true):
		out.append(Need.HUNGER)
	if p.toilet_need >= ToiletSim.NEED_AT and not in_stall and built.get(Need.TOILET, true):
		out.append(Need.TOILET)
	if (
		BoredomSim.is_bored(p)
		and p.stage != Passenger.Stage.SHOP_BROWSE
		and not wishing
		and built.get(Need.BOREDOM, true)
	):
		out.append(Need.BOREDOM)
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
## Keeps the needs on the node (&"need_kinds") for layout()'s mask and the
## count clusters (NeedCluster).
static func show_needs(node: Node3D, needs: Array[Need]) -> void:
	for i in SPRITES.size():
		var sprite := node.get_node(SPRITES[i]) as Sprite3D
		sprite.visible = i < needs.size()
		if sprite.visible:
			sprite.texture = texture(needs[i])
	node.set_meta(&"needs", needs.size())
	node.set_meta(&"need_kinds", needs)


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


## How opaque a passenger's icons are at `distance` metres from the camera (user
## ruling passenger-need-icons-fade-out-when-the-camera-is-very-close): 0 at or
## inside NEAR_HIDDEN_M, 1 at or beyond NEAR_FULL_M, linear between.
static func near_alpha(distance: float) -> float:
	return clampf(inverse_lerp(NEAR_HIDDEN_M, NEAR_FULL_M, distance), 0.0, 1.0)


## World units per output pixel at one metre from `camera` in `view`, or 0
## with no camera.
static func unit_of(view: Viewport, camera: Camera3D) -> float:
	if view == null or camera == null:
		return 0.0
	var height := view.get_visible_rect().size.y * view.get_stretch_transform().get_scale().y
	return 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / height


## Lays out a passenger node's shown icons for this frame: ICON_PX on screen
## (`unit` from unit_of()), side by side, over the head, or on top of the
## thought bubble while it shows. A shopping wish bubble the node shows
## (WishIconView.SPRITE) ends the row, WishIconView.WISH_PX on screen, in the
## place the boredom icon would take. Does nothing with no camera.
## With `shown` false (the camera at the home zoom or farther out, shown_at())
## the node's icons and wish bubble are hidden for this frame. `mask` holds a
## bit (1 << Need) for each need whose icon a count cluster badge draws
## instead (NeedCluster); those icons hide and the rest close up the row.
static func layout(
	node: Node3D, bubble: Label3D, camera: Camera3D, unit: float, shown := true, mask := 0
) -> void:
	var count: int = node.get_meta(&"needs", 0)
	var kinds: Array = node.get_meta(&"need_kinds", [])
	var alpha := 1.0
	if camera != null:
		alpha = near_alpha(camera.global_position.distance_to(node.global_position))
	var drawn := shown and alpha > 0.0
	var kept: Array[int] = []
	for i in count:
		var icon := node.get_node(SPRITES[i]) as Sprite3D
		var masked := i < kinds.size() and mask & (1 << int(kinds[i])) != 0
		icon.visible = drawn and not masked
		icon.modulate.a = alpha
		if icon.visible:
			kept.append(i)
	var wish := node.get_node_or_null(WishIconView.SPRITE) as Sprite3D
	var wishing: bool = wish != null and node.get_meta(&"wish", "") != ""
	if wish != null:
		wish.visible = drawn and wishing
		wish.modulate.a = alpha
	if (kept.is_empty() and not wishing) or not drawn or camera == null or unit <= 0.0:
		return
	var at := row_anchor(node, bubble, camera, unit)
	var anchor: Vector3 = at[0]
	var lift_px: float = at[1]
	var shown_count := kept.size()
	if not wishing:
		for j in shown_count:
			var sprite := node.get_node(SPRITES[kept[j]]) as Sprite3D
			sprite.position = anchor
			sprite.pixel_size = ICON_PX * unit / SIZE
			sprite.offset = offset_of(j, shown_count, lift_px)
		return
	var widths := row_widths(shown_count, true)
	for j in shown_count:
		var sprite := node.get_node(SPRITES[kept[j]]) as Sprite3D
		sprite.position = anchor
		sprite.pixel_size = ICON_PX * unit / SIZE
		sprite.offset = Vector2(row_x_px(j, widths) * SIZE / ICON_PX, offset_of(0, 1, lift_px).y)
	wish.position = anchor
	wish.pixel_size = WishIconView.WISH_PX * unit / WishIconView.SIZE
	var wish_x := row_x_px(shown_count, widths) * WishIconView.SIZE / WishIconView.WISH_PX
	wish.offset = Vector2(wish_x, WishIconView.offset_for(lift_px).y)


## Where a node's icon row stands this frame: [the anchor in the node's space
## (over the head, or the bubble's position while the bubble shows), the
## screen pixels the row's bottom edge is lifted over it (over the bubble's
## top while it shows, else 0)].
static func row_anchor(node: Node3D, bubble: Label3D, camera: Camera3D, unit: float) -> Array:
	var anchor := Vector3(0.0, LIFT_M, 0.0)
	var lift_px := 0.0
	if bubble.text != "" and bubble.visible:
		anchor = bubble.position
		var at := node.global_transform * bubble.position
		var depth := (at - camera.global_position).dot(-camera.global_basis.z)
		if depth > 0.0:
			lift_px = bubble_top_m(bubble) / (depth * unit) + GAP_PX
	return [anchor, lift_px]


## The widths (screen pixels) of a row of `count` icons, ended by the wish
## bubble when `wishing`.
static func row_widths(count: int, wishing: bool) -> Array[float]:
	var widths: Array[float] = []
	for i in count:
		widths.append(ICON_PX)
	if wishing:
		widths.append(WishIconView.WISH_PX)
	return widths


## The screen centre of icon `index` of a row of `count` icons (ended by the
## wish bubble when `wishing`), relative to the row's projected anchor, in
## screen pixels with y down; `lift_px` from row_anchor(). The same geometry
## layout() draws.
static func icon_centre_px(index: int, count: int, wishing: bool, lift_px: float) -> Vector2:
	if not wishing:
		return Vector2((index - (count - 1) / 2.0) * (ICON_PX + GAP_PX), -lift_px - ICON_PX / 2.0)
	return Vector2(row_x_px(index, row_widths(count, true)), -lift_px - ICON_PX / 2.0)


## The centre of item `index` of a row of items `widths` wide (screen
## pixels), GAP_PX apart and centred on the anchor, in screen pixels along x.
static func row_x_px(index: int, widths: Array[float]) -> float:
	var total := GAP_PX * (widths.size() - 1)
	for width in widths:
		total += width
	var x := -total / 2.0
	for i in index:
		x += widths[i] + GAP_PX
	return x + widths[index] / 2.0


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
			var glyph := _glyph(need, p)
			colour = colour.lerp(GLYPH, clampf(0.5 - glyph, 0.0, 1.0) * inside)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _glyph(need: Need, p: Vector2) -> float:
	match need:
		Need.HUNGER:
			return _hunger(p)
		Need.TOILET:
			return _toilet(p)
	return _hourglass(p)


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


## Signed distance to an hourglass: a cap on top and bottom, the glass drawn
## as two outlined bulbs meeting at a narrow waist, and a heap of sand in the
## lower bulb.
static func _hourglass(p: Vector2) -> float:
	var caps := minf(
		_box(p, Vector2(0.0, -33.0), Vector2(24.0, 4.0), 2.0),
		_box(p, Vector2(0.0, 33.0), Vector2(24.0, 4.0), 2.0)
	)
	# The glass: two triangles tip to tip, drawn as their outlines.
	var left := minf(
		_segment(p, Vector2(-18.0, -29.0), Vector2(-3.0, 0.0)),
		_segment(p, Vector2(-3.0, 0.0), Vector2(-18.0, 29.0))
	)
	var right := minf(
		_segment(p, Vector2(18.0, -29.0), Vector2(3.0, 0.0)),
		_segment(p, Vector2(3.0, 0.0), Vector2(18.0, 29.0))
	)
	var glass := minf(left, right) - 5.0
	# The sand heaped in the lower bulb.
	var sand := maxf(
		_box(p, Vector2(0.0, 24.0), Vector2(8.0, 5.0), 0.0), absf(p.x) * 1.6 - (p.y - 14.0)
	)
	return minf(minf(caps, glass), sand)


static func _segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Signed distance to a box of half size `half` with corners rounded by `round_px`.
static func _box(p: Vector2, centre: Vector2, half: Vector2, round_px: float) -> float:
	var q := (p - centre).abs() - half + Vector2.ONE * round_px
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - round_px
