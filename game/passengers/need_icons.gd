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
## and lays them out each frame (layout()): they keep ICON_PX on screen at every
## zoom, like the station signs, and stand side by side along the screen's x
## through their offsets in the billboard plane. The row stands HEAD_GAP_PX on
## screen over the top of the head as drawn, at every camera angle, standing,
## seated, reclined and in between (row_anchor(), decision need-icons-and-wish-
## bubbles-sit-a-fixed-screen-gap-above-the). While the passenger's thought
## bubble shows, the row sits on top of the bubble instead of over the head.
## A bored passenger with a shopping wish shows its wish bubble (WishIconView)
## at the end of the row instead of the hourglass (user ruling shopping-wish-
## icon-replaces-the-boredom-hourglass-for-wishers); one with no wish keeps the
## hourglass.
##
## Close icons of one kind merge into one bigger icon with a count (NeedCluster,
## drawn by PassengerViews); layout()'s mask hides the members' own icons.

enum Need { HUNGER, TOILET, BOREDOM }
## Where a passenger standing up came from (node meta &"icon_rise", set by
## PassengerViews._pose() while its RISE_CLIP plays, board 3a5e1d0d). Its
## anchor and head top go from the seat's (or the pod's) to the standing ones
## by rise_weight(). Measured through the stand_up clip from a gate chair
## (game/spike/standup_icon_anchor_probe.gd): the Head bone goes from 1.28 m
## up and 0.55 m behind the root to 1.68 m up and 0.06 m behind it, its
## height within 0.01 m of a smoothstep of the clip's progress at every
## twelfth. The standing anchor, taken at once, sat 25 px under the head top
## seen from the front at 10 m. The sit_down clip (SINK_CLIP) is the same path
## played backwards, sample for sample, so a passenger sitting down (after any
## SitHold set-down, which it stands through) is marked the same way and
## goes from the standing values to the seat's.
enum Rise { NONE, SEAT, RECLINE }

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
## The same for a seated passenger (node meta &"icon_seated", board bd08ed8e, user
## ruling "Lift icons for seated"), and SEATED_BACK_M the anchor's shift toward
## the seat's back. A seated body is drawn about 0.54 m behind its root (the
## chair's front edge), its head top near 1.46 m. The game camera starts at
## 70 degrees (TycoonCamera TOP_DOWN), where that head lands 0.3 m higher on
## screen than a 2.0 m anchor over the root, so the row sat over the torso and
## face. A lift alone never fixes it (0.4 m of lift moves the row 0.14 m on
## screen at 70 degrees), so the anchor stands over the head, 0.2 m higher.
const SEATED_LIFT_M := 2.2
const SEATED_BACK_M := 0.54
## The same for a passenger reclined in a nap pod (node meta &"icon_reclined",
## board 4773e61e). Measured in the full recline (PodRecline at 1) through the
## game camera (game/spike/nap_pod_icon_plates_probe.gd): the Head bone stands
## 1.28 m up and 0.55 m behind the root, 0.03 m to the side, its head top near
## 1.40 m and under the pod's hood (1.82 m). The standing anchor put the row on
## the face seen from the front and in the air beside the pod seen from the
## side. The anchor stands over the head, 0.75 m over its top as the seated
## one does, so it clears the hood.
const RECLINE_LIFT_M := 2.15
const RECLINE_BACK_M := 0.55
## The top of the head over the root, standing, seated and reclined (the
## measurements above; a standing body is about 1.7 m tall), for a node
## PassengerViews did not make (no Head bone found by find_head()); a body's
## own head top is read off its Head bone (head_top()).
const HEAD_TOP_M := 1.7
const SEATED_HEAD_TOP_M := 1.46
const RECLINE_HEAD_TOP_M := 1.40
## The bone a body's head top is read off, and how far the top of the head
## stands over it. The bone moves with the body's clip: standing it stands
## 1.68 m up on a female body and 1.81 m on a male one (PassengerLooks'
## bodies of one gender share one skeleton), walking 1.65 and 1.72 m, about
## 0.1 m further forward, and seated 1.28 and 1.34 m
## (test_need_icon_head_gap.gd), so no one height per pose fits every body.
const HEAD_BONE := "Head"
const HEAD_OVER_BONE_M := 0.27
## The head drawn as a ball HEAD_RADIUS_M round a centre that far under
## head_top() (0.07 m over the bone): its top on screen is the centre moved
## HEAD_RADIUS_M along the camera's up, at every angle. Fitted to the twelve
## bodies' meshes, hair and buns included, in the rest pose: the furthest any
## vertex reaches from the Head bone along the camera's up, over 24 yaws, is
## 0.240 m at the 38 degree step, 0.226 m at 54 and 0.208 m at 70 (female
## character 11's bun and male character 02's hair; the plainest heads reach
## 0.165 m and 0.119 m). The ball reaches 0.255, 0.241 and 0.224 m, so the
## row clears the tallest head by HEAD_GAP_PX and a lower one by up to about
## 11 px more at 10 m.
const HEAD_RADIUS_M := 0.20
## Screen pixels between the top of the head as drawn and the bottom of the
## icon row and wish bubble (decision need-icons-and-wish-bubbles-sit-a-fixed-
## screen-gap-above-the): the same at every angle step, zoom and pose.
const HEAD_GAP_PX := 6.0
## The clips a passenger stands up from and sits down on a seat in (Rise,
## rise_weight()).
const RISE_CLIP := "stand_up"
const SINK_CLIP := "sit_down"
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
## The clips clip_weight() has reported broken (clip name -> true).
static var _clip_errors: Dictionary = {}


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


## The anchor over a passenger node's head, in the node's space: LIFT_M over
## the root, SEATED_LIFT_M high and SEATED_BACK_M behind it while the node is
## seated, or RECLINE_LIFT_M high and RECLINE_BACK_M behind it while it is
## reclined in a nap pod, and between the two while it stands up or sits down
## (Rise). The
## VIP crown anchors here too.
static func head_anchor(node: Node3D) -> Vector3:
	return _posed(
		node,
		Vector3(0.0, LIFT_M, 0.0),
		Vector3(0.0, SEATED_LIFT_M, -SEATED_BACK_M),
		Vector3(0.0, RECLINE_LIFT_M, -RECLINE_BACK_M)
	)


## The top of a node's head, in the node's space: standing over the root, or
## SEATED_BACK_M or RECLINE_BACK_M behind it while seated or reclined, as
## head_anchor() places the row over it (standing up and sitting down
## included). A node find_head() has run on reads it off its Head bone as the
## body is posed now: HEAD_OVER_BONE_M over the bone, so it follows every
## body, clip and blend, the stand-up and sit-down included.
static func head_top(node: Node3D) -> Vector3:
	var skeleton: Skeleton3D = node.get_meta(&"head_skeleton", null)
	if skeleton != null:
		var to_node: Transform3D = node.get_meta(&"head_to_node")
		var bone := skeleton.get_bone_global_pose(node.get_meta(&"head_bone"))
		return to_node * bone.origin + Vector3(0.0, HEAD_OVER_BONE_M, 0.0)
	return _posed(
		node,
		Vector3(0.0, HEAD_TOP_M, 0.0),
		Vector3(0.0, SEATED_HEAD_TOP_M, -SEATED_BACK_M),
		Vector3(0.0, RECLINE_HEAD_TOP_M, -RECLINE_BACK_M)
	)


## Keeps on a passenger node its body's Head bone for head_top(): the
## skeleton (&"head_skeleton"), the bone (&"head_bone") and the skeleton's
## transform in the node's space (&"head_to_node"). PassengerViews calls it
## once per node it makes; a node keeps its body for life. A body with no Head
## bone is reported and keeps the fixed heights.
static func find_head(node: Node3D) -> void:
	for child in node.find_children("*", "Skeleton3D", true, false):
		var skeleton := child as Skeleton3D
		var bone := skeleton.find_bone(HEAD_BONE)
		if bone < 0:
			continue
		var to_node := Transform3D.IDENTITY
		var at: Node = skeleton
		while at != node and at is Node3D:
			to_node = (at as Node3D).transform * to_node
			at = at.get_parent()
		node.set_meta(&"head_skeleton", skeleton)
		node.set_meta(&"head_bone", bone)
		node.set_meta(&"head_to_node", to_node)
		return
	push_error("NeedIcons.find_head: %s has no %s bone" % [node.name, HEAD_BONE])


## `standing`, `seated` or `reclined` as the node is posed now, and while it
## stands up or sits down (meta &"icon_rise") between the seat's or the pod's
## value and `standing` by rise_weight().
static func _posed(node: Node3D, standing: Vector3, seated: Vector3, reclined: Vector3) -> Vector3:
	if node.get_meta(&"icon_reclined", false):
		return reclined
	if node.get_meta(&"icon_seated", false):
		return seated
	match node.get_meta(&"icon_rise", Rise.NONE):
		Rise.SEAT:
			return seated.lerp(standing, rise_weight(node))
		Rise.RECLINE:
			return reclined.lerp(standing, rise_weight(node))
	return standing


## How far (0 seated, 1 standing) a node standing up or sitting down stands:
## a smoothstep of its RISE_CLIP's progress, or one minus it for SINK_CLIP
## (the measured head paths), read off its AnimationPlayer each frame so the
## icons move with the drawn body, not tick by tick. The assigned clip and its
## position outlast the clip's end, so an ended stand-up stays standing and an
## ended sit-down seated; 1 for any other clip.
static func rise_weight(node: Node3D) -> float:
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var clip := player.assigned_animation
	if clip != RISE_CLIP and clip != SINK_CLIP:
		return 1.0
	var animation: Animation = player.get_animation(clip) if player.has_animation(clip) else null
	return clip_weight(clip, animation, player.current_animation_position)


## rise_weight() for `clip` (RISE_CLIP or SINK_CLIP) played `at` seconds into
## `animation`. A missing or zero-length animation reports once per clip
## (push_error) and gives the clip's start pose, seated for a stand-up and
## standing for a sit-down, never a NaN that would carry into the icons, the
## crown and the badges' head rects.
static func clip_weight(clip: String, animation: Animation, at: float) -> float:
	if animation == null or animation.length <= 0.0:
		if not _clip_errors.has(clip):
			_clip_errors[clip] = true
			push_error("NeedIcons.clip_weight: the %s clip is missing or has no length" % clip)
		return 0.0 if clip == RISE_CLIP else 1.0
	var t := smoothstep(0.0, 1.0, at / animation.length)
	return t if clip == RISE_CLIP else 1.0 - t


## Where a node's icon row stands this frame: [the anchor in the node's space,
## the screen pixels the row's bottom edge is lifted over it]. Over the head
## the anchor is the head's centre (head_centre()) and the lift reaches
## HEAD_GAP_PX over the head's top as drawn (HEAD_RADIUS_M along the camera's
## up), so the gap on screen is the same at every angle (decision need-icons-
## and-wish-bubbles-sit-a-fixed-screen-gap-above-the). While the bubble shows
## the anchor is the bubble's position and the lift reaches GAP_PX over its
## top.
static func row_anchor(node: Node3D, bubble: Label3D, camera: Camera3D, unit: float) -> Array:
	var anchor := head_centre(node)
	var over_m := HEAD_RADIUS_M
	var gap := HEAD_GAP_PX
	if bubble.text != "" and bubble.visible:
		anchor = bubble.position
		over_m = bubble_top_m(bubble)
		gap = GAP_PX
	var at := node.global_transform * anchor
	var depth := (at - camera.global_position).dot(-camera.global_basis.z)
	var lift_px := gap
	if depth > 0.0:
		lift_px += over_m / (depth * unit)
	return [anchor, lift_px]


## The centre of the head drawn as a ball (HEAD_RADIUS_M under head_top()), in
## the node's space, standing, seated, reclined or in between.
static func head_centre(node: Node3D) -> Vector3:
	return head_top(node) - Vector3(0.0, HEAD_RADIUS_M, 0.0)


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
