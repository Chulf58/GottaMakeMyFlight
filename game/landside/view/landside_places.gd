class_name LandsidePlaces
extends Node3D
## The curb bays and car parks of the landside, drawn where the sim's
## LandsideDefinition puts them (Landside 4/4): the starter curb's paint bays
## always, a bay on each built curb spot, a surface lot (tp_parking_01a) or a
## multi-storey (tc_parking_2a) on each built lot spot, and over the gate of a
## closed car park the grey "!" sign captioned "Closed" that closed desks and
## scanners carry (MissMarkers). LandsideViews refreshes it every frame; it
## compares the sim's build state with what it drew and adds or removes only
## what changed, so a build, a removal, a close and a load all show at once.
## Read-only.
##
## Where each asset stands follows the authored geometry (test_landside_
## geometry.gd checks it against the .glb files): a bay's origin is on the
## kerb line, its Mount_Berth markers on its two berths (the starter curb's
## berths pair up 6.5 m apart); a surface lot is turned so its entrance faces
## the road, its barrier line on the gate and its axis on the spot's centre;
## a multi-storey stands in vendor heading with its origin on the spot's
## centre. A parked car faces into its stall, away from the lot's middle
## aisle (parked_heading()).

const BAY := preload("res://assets/landside/tp_curb_bay_01a.glb")
const SURFACE := preload("res://assets/landside/tp_parking_01a.glb")
const MULTI := preload("res://assets/landside/tc_parking_2a.glb")
## The bay's two berths, centre to centre, and the berths' distance from the
## kerb line into the road (tools/blender/landside/curb_bay.py).
const BAY_PITCH := 6.5
const BAY_BERTH_Z := 1.5
const PITCH_TOLERANCE := 0.05
## Turned so the surface lot's entrance side (local -x) faces the road (-z).
const LOT_YAW := -PI / 2.0
## The surface lot's barrier line, local x -7: it stands on the gate.
const LOT_BARRIER_X := -7.0
## The Closed sign floats this high over the gate.
const SIGN_HEIGHT := 4.0
const BADGE_LIFT := 1.2
const MULTI_FALLBACK_TOP := 28.5
const SURFACE_FALLBACK_TOP := 3.1

@export var landside: LandsideSim
## The road carriageway top, unified at y 0.10 across site road, extensions, and aprons.
@export var road_top := 0.10

## The starter curb's bays, drawn once.
var _starter_bays: Array[Node3D] = []
## Curb spot -> its drawn bay.
var _bays := {}
## Lot spot -> its drawn car park.
var _lots := {}
## Lot spot -> its occupancy badge.
var _badges := {}
## Lot spot -> its Closed sign.
var _signs := {}
## Road extensions, highway portals, and forecourt/boulevard street dressing.
var _street_dressing: LandsideStreetDressing


func _ready() -> void:
	if _street_dressing == null:
		_street_dressing = LandsideStreetDressing.new()
		add_child(_street_dressing)


## Returns the mounted LandsideStreetDressing node.
func street_dressing() -> LandsideStreetDressing:
	return _street_dressing


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate_signs()


func _retranslate_signs() -> void:
	var text := MissMarkers.closed_caption()
	for sign: Sprite3D in _signs.values():
		var caption := sign.get_node_or_null("Caption") as Label3D
		if caption != null:
			caption.text = text


## Adds and removes bays, car parks and Closed signs to match the sim now.
func refresh() -> void:
	if landside == null or landside.definition == null:
		return
	var definition := landside.definition
	if _starter_bays.is_empty():
		for origin in bay_origins(definition, road_top):
			var bay: Node3D = BAY.instantiate()
			bay.name = "CurbBay%d" % _starter_bays.size()
			bay.position = origin
			add_child(bay)
			_starter_bays.append(bay)
	for spot in landside.curbs_built.size():
		_match(_bays, spot, landside.curbs_built[spot], _new_bay.bind(definition, spot))
	for spot in landside.lots_built.size():
		if (
			landside.lots_built[spot]
			and _lots.has(spot)
			and int((_lots[spot] as Node).get_meta(&"lot_kind", -1)) != int(landside.lot_kind(spot))
		):
			_drop_lot_nodes(spot)
		_match(_lots, spot, landside.lots_built[spot], _new_lot.bind(spot))
		_match(_badges, spot, landside.lots_built[spot], _new_badge.bind(spot))
		if landside.lots_built[spot] and _badges.has(spot):
			var badge: Label3D = _badges[spot]
			var lot_spot := landside.lot_spot(spot)
			var capacity := lot_spot.slots.size()
			badge.text = "%d/%d" % [landside.lot_occupied(spot), capacity]
			badge.position = Vector3(
				lot_spot.centre.x, lot_top_y(spot) + BADGE_LIFT, lot_spot.centre.z
			)
		var closed: bool = landside.lots_built[spot] and landside.lots_closed[spot]
		_match(_signs, spot, closed, _new_sign.bind(spot))
	if not _signs.is_empty():
		_size_signs()


## Keeps the Closed signs one screen size and clear of HUD rects (sliding
## clear or hiding if no clear spot exists, matching RoomLabelLayout / GateLinksView).
func _size_signs() -> void:
	var in_tree := is_inside_tree()
	var camera := get_viewport().get_camera_3d() if in_tree else null
	var fov := camera.fov if camera != null else MissMarkers.FALLBACK_FOV
	var height := MissMarkers.FALLBACK_HEIGHT
	var to_output := 1.0
	var view_size := Vector2.ZERO
	if in_tree:
		var view := get_viewport()
		to_output = view.get_stretch_transform().get_scale().y
		view_size = view.get_visible_rect().size * to_output
		height = view_size.y
	var unit := 2.0 * tan(deg_to_rad(fov) / 2.0) / height
	var hud: Array[Rect2] = []
	if camera != null:
		hud = HudRects.collect(self, to_output)
	var placed: Array[Rect2] = []
	var spots := _signs.keys()
	spots.sort()
	for spot: int in spots:
		var sign: Sprite3D = _signs[spot]
		var caption := sign.get_node("Caption") as Label3D
		sign.pixel_size = MissMarkers.SIGN_PX * unit / MarkerIcons.SIZE
		caption.pixel_size = unit
		sign.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
		caption.offset = Vector2(0.0, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX)
		sign.visible = true
		if camera == null or camera.is_position_behind(sign.global_position):
			continue
		var depth := (sign.global_position - camera.global_position).dot(-camera.global_basis.z)
		if depth <= camera.near:
			continue
		var point := camera.unproject_position(sign.global_position) * to_output
		var cap_size := MissMarkers.caption_size(caption.text)
		var total_w := maxf(MissMarkers.SIGN_PX, cap_size.x)
		var total_h := MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX + cap_size.y
		var home := Rect2(point.x - total_w / 2.0, point.y - total_h, total_w, total_h)
		if not Rect2(Vector2.ZERO, view_size).intersects(home):
			continue
		var padded := home.grow(RoomLabelLayout.GAP_PX)
		if (placed + hud).any(func(other: Rect2) -> bool: return padded.intersects(other)):
			var clear := RoomLabelLayout.slide_clear(home, placed + hud, view_size)
			if clear.size == Vector2.ZERO:
				sign.visible = false
				continue
			var delta_px := clear.position - home.position
			var icon_per_px := MarkerIcons.SIZE / MissMarkers.SIGN_PX
			sign.offset = Vector2(
				delta_px.x * icon_per_px, MarkerIcons.SIZE / 2.0 - delta_px.y * icon_per_px
			)
			caption.offset = Vector2(
				delta_px.x, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX - delta_px.y
			)
			placed.append(clear)
		else:
			placed.append(home)


## The number of curb bays drawn: the starter curb's and the built spots'.
func bay_count() -> int:
	return _starter_bays.size() + _bays.size()


## The starter curb's bay `i`.
func starter_bay(i: int) -> Node3D:
	return _starter_bays[i]


## The drawn bay of curb spot `spot`, or null.
func bay_node(spot: int) -> Node3D:
	return _bays.get(spot)


## The drawn car park of lot spot `spot`, or null.
func lot_node(spot: int) -> Node3D:
	return _lots.get(spot)


## The Closed sign over lot spot `spot`'s gate, or null while it is open.
func closed_sign(spot: int) -> Sprite3D:
	return _signs.get(spot)


## The occupancy badge over lot spot `spot`, or null while unbuilt.
func occupancy_badge(spot: int) -> Label3D:
	return _badges.get(spot)


## Highest world y across the drawn meshes of lot spot `spot` (or asset fallback).
func lot_top_y(spot: int) -> float:
	var lot := _lots.get(spot) as Node3D
	if lot != null:
		var top := -INF
		for mi: MeshInstance3D in lot.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = (
				(lot.transform * LandsideViews._to_model(lot, mi)) * mi.get_aabb()
				if not lot.is_inside_tree()
				else mi.global_transform * mi.get_aabb()
			)
			top = maxf(top, box.end.y)
		if not is_inf(top):
			return top
	if (
		landside != null
		and landside.definition != null
		and spot >= 0
		and spot < landside.definition.lots.size()
		and landside.lot_kind(spot) == LandsideLotSpot.Kind.MULTI_STOREY
	):
		return MULTI_FALLBACK_TOP
	return SURFACE_FALLBACK_TOP


## Where the starter curb's bays stand: one per pair of berths 6.5 m apart
## along the kerb, paired from the berth nearest the curb's stop on, each
## origin on the kerb line (BAY_BERTH_Z behind its berths).
static func bay_origins(definition: LandsideDefinition, at_height: float) -> Array[Vector3]:
	var stop := LandsideDefinition.point_at(definition.road_in, definition.curb.stop_mm)
	var berths: Array = Array(definition.curb.berths)
	berths.sort_custom(
		func(a: Vector3, b: Vector3) -> bool: return absf(a.x - stop.x) < absf(b.x - stop.x)
	)
	var out: Array[Vector3] = []
	var i := 0
	while i + 1 < berths.size():
		var a: Vector3 = berths[i]
		var b: Vector3 = berths[i + 1]
		if absf(absf(a.x - b.x) - BAY_PITCH) <= PITCH_TOLERANCE and is_equal_approx(a.z, b.z):
			out.append(Vector3((a.x + b.x) * 0.5, at_height, a.z - BAY_BERTH_Z))
			i += 2
		else:
			i += 1
	return out


## Where a curb spot's bay stands: its centre, moved back to the kerb line.
static func bay_origin(spot: LandsideCurbSpot, at_height: float) -> Vector3:
	return Vector3(spot.centre.x, at_height, spot.centre.z - BAY_BERTH_Z)


## Where a lot spot's car park stands. A surface lot faces the road, its
## barrier line on the gate and its axis on the spot's centre; a multi-storey
## stands in vendor heading on the spot's centre.
static func lot_transform(spot: LandsideLotSpot) -> Transform3D:
	if spot.kind == LandsideLotSpot.Kind.MULTI_STOREY:
		return Transform3D(Basis(), spot.centre)
	var gate := spot.access[spot.access.size() - 1]
	var origin := Vector3(spot.centre.x, spot.centre.y, gate.z - LOT_BARRIER_X)
	return Transform3D(Basis(Vector3.UP, LOT_YAW), origin)


## The way a car parked in `slot` of lot spot `spot` faces: into its stall,
## away from the lot's middle aisle along x (the stalls of both car parks are
## rows along z with the aisle down the middle).
static func parked_heading(spot: LandsideLotSpot, slot: Vector3) -> Vector3:
	return Vector3(1.0 if slot.x > spot.centre.x else -1.0, 0.0, 0.0)


## Adds or removes the node of `key` in `drawn` so it exists exactly while
## `wanted`; `make` builds a new one.
func _match(drawn: Dictionary, key: int, wanted: bool, make: Callable) -> void:
	if wanted and not drawn.has(key):
		var node: Node3D = make.call()
		add_child(node)
		drawn[key] = node
	elif not wanted and drawn.has(key):
		(drawn[key] as Node).queue_free()
		drawn.erase(key)


func _new_bay(definition: LandsideDefinition, spot: int) -> Node3D:
	var bay: Node3D = BAY.instantiate()
	bay.name = "BuiltCurbBay%d" % spot
	bay.position = bay_origin(definition.curb_spots[spot], road_top)
	return bay


func _drop_lot_nodes(spot: int) -> void:
	for drawn in [_lots, _badges, _signs]:
		if drawn.has(spot):
			(drawn[spot] as Node).queue_free()
			drawn.erase(spot)


func _new_lot(spot: int) -> Node3D:
	var lot_spot := landside.lot_spot(spot)
	var multi := lot_spot.kind == LandsideLotSpot.Kind.MULTI_STOREY
	var lot: Node3D = (MULTI if multi else SURFACE).instantiate()
	lot.name = "Lot%d" % spot
	lot.set_meta(&"lot_kind", int(lot_spot.kind))
	lot.transform = lot_transform(lot_spot)
	return lot


func _new_badge(spot: int) -> Label3D:
	var lot_spot := landside.lot_spot(spot)
	var badge := CaptionFont.apply(Label3D.new())
	badge.name = "OccupancyBadge%d" % spot
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.fixed_size = true
	badge.no_depth_test = true
	badge.shaded = false
	badge.render_priority = 11
	badge.outline_render_priority = 10
	badge.font_size = 24
	badge.outline_size = 6
	badge.outline_modulate = MarkerIcons.OUTLINE
	badge.modulate = Color(1.0, 0.96, 0.85)
	badge.pixel_size = 1.0 / MissMarkers.FALLBACK_HEIGHT
	badge.position = Vector3(lot_spot.centre.x, lot_top_y(spot) + BADGE_LIFT, lot_spot.centre.z)
	return badge


## The closed-station sign family (MissMarkers): the grey "!" billboard at one
## screen size, drawn over the world, with "Closed" above it.
func _new_sign(spot: int) -> Node3D:
	var lot_spot := landside.lot_spot(spot)
	var gate := lot_spot.access[lot_spot.access.size() - 1]
	var sign := Sprite3D.new()
	sign.name = "ClosedSign%d" % spot
	sign.texture = MissMarkers._closed_icon()
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.fixed_size = true
	sign.no_depth_test = true
	sign.shaded = false
	sign.render_priority = 11
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sign.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	sign.pixel_size = MissMarkers.SIGN_PX / MissMarkers.FALLBACK_HEIGHT / MarkerIcons.SIZE
	sign.position = Vector3(gate.x, road_top + SIGN_HEIGHT, gate.z)
	var caption := CaptionFont.apply(Label3D.new())
	caption.name = "Caption"
	caption.text = MissMarkers.closed_caption()
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.fixed_size = true
	caption.no_depth_test = true
	caption.render_priority = 12
	caption.outline_render_priority = 11
	caption.font_size = MissMarkers.CAPTION_FONT
	caption.outline_size = MissMarkers.CAPTION_OUTLINE
	caption.outline_modulate = MarkerIcons.OUTLINE
	caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	caption.pixel_size = 1.0 / MissMarkers.FALLBACK_HEIGHT
	caption.offset = Vector2(0.0, MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX)
	sign.add_child(caption)
	return sign
