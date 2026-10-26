class_name MissMarkers
extends Node3D
## Shows why passengers miss: a red "!" sign, captioned "Queue full" above it,
## over every full desk or scanner (MissSignals.full_stations), and an amber
## clock badge over the head of every late passenger (MissSignals.late_ids).
## PassengerViews creates it as a child, calls sync() after each tick and
## draw() after placing its passengers, so a badge rides the drawn,
## interpolated passenger. It reads the sim and never writes to it.
##
## Both markers are billboards drawn over the world (no depth test), like the
## thought bubbles. The sign keeps one screen size; a badge is LATE_WORLD_M
## tall in the world, held between LATE_MIN_PX and LATE_MAX_PX on screen, so
## it stays visible at the widest zoom without covering the queue near in. The
## caption sits above the sign so it does not cover the lane it describes.
## Sizes are for the camera's field of view and the view's height in pixels.

const HEAD_M := 2.0
const SIGN_LIFT_M := 0.6
const SIGN_PX := 56.0
const CAPTION_FONT := 22
const CAPTION_GAP_PX := 4.0
const LATE_WORLD_M := 0.6
const LATE_MIN_PX := 18.0
const LATE_MAX_PX := 30.0
const FALLBACK_FOV := 55.0
const FALLBACK_HEIGHT := 1080.0

var sim: PassengerSim
var views: PassengerViews

## Station id -> sign; passenger id -> badge.
var _signs: Dictionary = {}
var _badges: Dictionary = {}
var _free_signs: Array[Sprite3D] = []
var _free_badges: Array[Sprite3D] = []


## On-screen height in pixels of a late badge at `depth` metres from a camera
## with a vertical field of view of `fov_deg` on a view `viewport_h` pixels high.
static func badge_px(depth: float, fov_deg: float, viewport_h: float) -> float:
	if depth <= 0.0:
		return LATE_MAX_PX
	var px := LATE_WORLD_M * viewport_h / (2.0 * tan(deg_to_rad(fov_deg) / 2.0) * depth)
	return clampf(px, LATE_MIN_PX, LATE_MAX_PX)


func sign_for(station: int) -> Node3D:
	return _signs.get(station)


func sign_text(station: int) -> String:
	if not _signs.has(station):
		return ""
	return ((_signs[station] as Node).get_node("Caption") as Label3D).text


func badge_for(id: int) -> Sprite3D:
	return _badges.get(id)


func free_badge_count() -> int:
	return _free_badges.size()


func sync() -> void:
	if sim == null:
		return
	var full := MissSignals.full_stations(sim)
	for station: int in _signs.keys():
		if not full.has(station):
			_drop_sign(station)
	for station: int in full:
		if not _signs.has(station):
			_signs[station] = _take_sign()
		var sign: Sprite3D = _signs[station]
		sign.position = _sign_point(station)
		var held: int = full[station]
		var caption := "Queue full"
		if held > 0:
			caption += " · +" + str(held) + " waiting"
		(sign.get_node("Caption") as Label3D).text = caption
	var late := {}
	for id in MissSignals.late_ids(sim):
		if views != null and views.node_for(id) != null:
			late[id] = true
	for id: int in _badges.keys():
		if not late.has(id):
			_free_badges.append(_put_away(_badges[id]))
			_badges.erase(id)
	for id: int in late:
		if not _badges.has(id):
			_badges[id] = _take_badge()
		(_badges[id] as Sprite3D).position = _head(id)


func draw() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var fov := camera.fov if camera != null else FALLBACK_FOV
	var height := FALLBACK_HEIGHT
	if is_inside_tree():
		height = get_viewport().get_visible_rect().size.y
	## World units per screen pixel at one metre: a fixed-size sprite is drawn
	## as if it stood one metre from the camera.
	var unit := 2.0 * tan(deg_to_rad(fov) / 2.0) / height
	# The layout follows an edit at once, the queues only on the next tick, so
	# a station removed while paused loses its sign here.
	for station: int in _signs.keys():
		if sim == null or not sim.layout.lanes.has(station):
			_drop_sign(station)
	for station: int in _signs:
		var sign: Sprite3D = _signs[station]
		sign.pixel_size = SIGN_PX * unit / MarkerIcons.SIZE
		(sign.get_node("Caption") as Label3D).pixel_size = unit
	var view := camera.global_transform.affine_inverse() if camera != null else Transform3D()
	for id: int in _badges:
		var badge: Sprite3D = _badges[id]
		badge.position = _head(id)
		var px := LATE_MAX_PX
		if camera != null:
			px = badge_px(-(view * badge.global_position).z, fov, height)
		badge.pixel_size = px * unit / MarkerIcons.SIZE


func _head(id: int) -> Vector3:
	var node := views.node_for(id) if views != null else null
	if node == null:
		return Vector3.ZERO
	return node.position + Vector3(0.0, HEAD_M, 0.0)


## Above the middle of the station's footprint, clear of its top.
func _sign_point(station: int) -> Vector3:
	var record := sim.grid.get_object(station)
	var def := BuildCatalog.get_def(StringName(record["def"]))
	var cells := def.footprint(record["anchor"], record["facing"])
	var centre := BuildView.object_transform(sim.grid, cells, record["facing"]).origin
	return centre + Vector3(0.0, def.height + SIGN_LIFT_M, 0.0)


func _take_sign() -> Sprite3D:
	if not _free_signs.is_empty():
		var reused: Sprite3D = _free_signs.pop_back()
		reused.visible = true
		return reused
	var sign := _sprite(MarkerIcons.Icon.QUEUE_FULL, 11)
	sign.name = "QueueFullSign"
	var caption := Label3D.new()
	caption.name = "Caption"
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.fixed_size = true
	caption.no_depth_test = true
	caption.render_priority = 12
	caption.outline_render_priority = 11
	caption.font_size = CAPTION_FONT
	caption.outline_size = 8
	caption.outline_modulate = MarkerIcons.OUTLINE
	caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	caption.offset = Vector2(0.0, SIGN_PX + CAPTION_GAP_PX)
	sign.add_child(caption)
	return sign


func _take_badge() -> Sprite3D:
	if not _free_badges.is_empty():
		var reused: Sprite3D = _free_badges.pop_back()
		reused.visible = true
		return reused
	var badge := _sprite(MarkerIcons.Icon.LATE, 10)
	badge.name = "LateBadge"
	return badge


## A billboard drawn over the world whose bottom edge sits on its position.
func _sprite(icon: MarkerIcons.Icon, priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = MarkerIcons.texture(icon)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.fixed_size = true
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.render_priority = priority
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	sprite.pixel_size = LATE_MAX_PX / FALLBACK_HEIGHT / MarkerIcons.SIZE
	add_child(sprite)
	return sprite


func _drop_sign(station: int) -> void:
	_free_signs.append(_put_away(_signs[station]))
	_signs.erase(station)


func _put_away(sprite: Sprite3D) -> Sprite3D:
	sprite.visible = false
	return sprite
