class_name MissMarkers
extends Node3D
## Shows why passengers miss: a red "!" sign, captioned "Queue full" above it,
## over every full desk or scanner (MissSignals.full_stations). PassengerViews
## creates it as a child and calls sync() after each tick and draw() after
## placing its passengers. It reads the sim and never writes to it.
##
## The sign is a billboard drawn over the world (no depth test), like the
## thought bubbles, and keeps one screen size at every zoom. The caption sits
## above the sign so it does not cover the lane it describes. Sizes are for
## the camera's field of view and the view's height in pixels.

const SIGN_LIFT_M := 0.6
const SIGN_PX := 56.0
const CAPTION_FONT := 22
const CAPTION_GAP_PX := 4.0
const FALLBACK_FOV := 55.0
const FALLBACK_HEIGHT := 1080.0

var sim: PassengerSim

## Station id -> sign.
var _signs: Dictionary = {}
var _free_signs: Array[Sprite3D] = []


func sign_for(station: int) -> Node3D:
	return _signs.get(station)


func sign_text(station: int) -> String:
	if not _signs.has(station):
		return ""
	return ((_signs[station] as Node).get_node("Caption") as Label3D).text


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


## Above the middle of the station's footprint, clear of its top.
func _sign_point(station: int) -> Vector3:
	var record := sim.grid.get_object(station)
	var def := BuildCatalog.get_def(StringName(record["def"]))
	var cells := def.footprint(record["anchor"], record["facing"])
	var centre := BuildView.object_transform(sim.grid, cells, record["facing"]).origin
	return centre + Vector3(0.0, def.height + SIGN_LIFT_M, 0.0)


## A billboard drawn over the world whose bottom edge sits on its position,
## with its caption above it.
func _take_sign() -> Sprite3D:
	if not _free_signs.is_empty():
		var reused: Sprite3D = _free_signs.pop_back()
		reused.visible = true
		return reused
	var sign := Sprite3D.new()
	sign.name = "QueueFullSign"
	sign.texture = MarkerIcons.queue_full()
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.fixed_size = true
	sign.no_depth_test = true
	sign.shaded = false
	sign.render_priority = 11
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sign.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	sign.pixel_size = SIGN_PX / FALLBACK_HEIGHT / MarkerIcons.SIZE
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
	add_child(sign)
	return sign


func _drop_sign(station: int) -> void:
	var sign: Sprite3D = _signs[station]
	sign.visible = false
	_free_signs.append(sign)
	_signs.erase(station)
