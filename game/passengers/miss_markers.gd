class_name MissMarkers
extends Node3D
## Shows why passengers miss: a red "!" sign, captioned "Queue full" above it,
## over every full desk or scanner (MissSignals.full_stations), and a grey one
## captioned "Closed" over every desk or scanner with nobody on duty
## (MissSignals.closed_stations; a closed station shows only that, since it
## serves nobody), "Closed: staff spot blocked" when an old save left the
## station's staff spot blocked, or "Closed: staff can't reach" when staff have
## no way from an entrance to it (MissSignals.closed_reason). PassengerViews
## creates it as a child and calls sync() after each tick and draw() after
## placing its passengers. It reads the sim and
## never writes to it.
##
## The sign is a billboard drawn over the world (no depth test), like the
## thought bubbles, and keeps one screen size at every zoom and UI scale. The
## caption sits above the sign so it does not cover the lane it describes.
## Sizes are screen pixels, for the camera's field of view and the rendered
## view's height. Neighbouring stations stand closer on screen than a caption
## is wide when zoomed out, so draw() hides a caption that would overlap one
## already shown (the widest first, then left to right); every icon stays and
## the captions return as the camera moves in.

const SIGN_LIFT_M := 0.6
const SIGN_PX := 56.0
const CAPTION_FONT := 22
const CAPTION_GAP_PX := 4.0
const CAPTION_OUTLINE := 8
## Clear space kept between two shown captions.
const CAPTION_MARGIN_PX := 6.0
const FALLBACK_FOV := 55.0
const FALLBACK_HEIGHT := 1080.0
## The closed sign is the queue-full icon with its red fill painted grey-blue.
const CLOSED_FILL := Color(0.47, 0.53, 0.62)
const FILL_TOLERANCE := 0.1
const CLOSED_CAPTION := "Closed"
const SPOT_BLOCKED_CAPTION := "Closed: staff spot blocked"
const UNREACHABLE_CAPTION := "Closed: staff can't reach"

static var _closed_texture: ImageTexture

var sim: PassengerSim

## Station id -> sign, for the queue-full signs and the closed signs.
var _signs: Dictionary = {}
var _closed_signs: Dictionary = {}
var _free_signs: Array[Sprite3D] = []


func sign_for(station: int) -> Node3D:
	return _signs.get(station)


func sign_text(station: int) -> String:
	if not _signs.has(station):
		return ""
	return ((_signs[station] as Node).get_node("Caption") as Label3D).text


## The queue-full icon with its red fill repainted CLOSED_FILL, once; the
## outline and the white "!" stay, so the two signs read as one family.
static func _closed_icon() -> Texture2D:
	if _closed_texture == null:
		var img := MarkerIcons.queue_full().get_image()
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if (
					c.a > 0.99
					and absf(c.r - MarkerIcons.QUEUE_FILL.r) < FILL_TOLERANCE
					and absf(c.g - MarkerIcons.QUEUE_FILL.g) < FILL_TOLERANCE
					and absf(c.b - MarkerIcons.QUEUE_FILL.b) < FILL_TOLERANCE
				):
					img.set_pixel(x, y, CLOSED_FILL)
		img.generate_mipmaps()
		_closed_texture = ImageTexture.create_from_image(img)
	return _closed_texture


## The Closed sign over a desk or scanner with nobody on duty, or null.
func closed_sign_for(station: int) -> Node3D:
	return _closed_signs.get(station)


func closed_text(station: int) -> String:
	if not _closed_signs.has(station):
		return ""
	return ((_closed_signs[station] as Node).get_node("Caption") as Label3D).text


func _ready() -> void:
	sync()


## Also called on every grid edit, so a paused edit that removes a station or
## changes its lane length updates the sign at once. The sim rebuilds its
## layout on the same signal and is connected first: bind() connects it in
## the same call that sets sim.grid, so no sync here can see the grid sooner.
func sync() -> void:
	if sim == null or sim.grid == null:
		return
	if not sim.grid.graph_changed.is_connected(_on_graph_changed):
		sim.grid.graph_changed.connect(_on_graph_changed)
	_watch_staff()
	var closed := MissSignals.closed_stations(sim)
	var full := MissSignals.full_stations(sim)
	for station: int in closed:
		full.erase(station)
	for station: int in _signs.keys():
		if not full.has(station):
			_drop_sign(_signs, station)
	for station: int in full:
		var sign := _show_sign(_signs, station, "QueueFullSign", MarkerIcons.queue_full())
		var held: int = full[station]
		var caption := "Queue full"
		if held > 0:
			caption += " · +" + str(held) + " waiting"
		(sign.get_node("Caption") as Label3D).text = caption
	for station: int in _closed_signs.keys():
		if not closed.has(station):
			_drop_sign(_closed_signs, station)
	for station in closed:
		var sign := _show_sign(_closed_signs, station, "ClosedSign", _closed_icon())
		var caption := CLOSED_CAPTION
		match MissSignals.closed_reason(sim, station):
			MissSignals.SPOT_BLOCKED_REASON:
				caption = SPOT_BLOCKED_CAPTION
			MissSignals.UNREACHABLE_REASON:
				caption = UNREACHABLE_CAPTION
		(sign.get_node("Caption") as Label3D).text = caption


func draw() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var fov := camera.fov if camera != null else FALLBACK_FOV
	## The viewport's output height in screen pixels. The visible rect alone is the
	## layout size, which the content scale (project.godot) makes smaller than
	## the screen, so it is scaled back by the stretch transform. (The viewport
	## texture's get_size() is no help: under the content scale it reports
	## neither size.)
	var height := FALLBACK_HEIGHT
	## Layout coordinates (the camera's) times this are screen pixels.
	var to_output := 1.0
	if is_inside_tree():
		var view := get_viewport()
		to_output = view.get_stretch_transform().get_scale().y
		height = view.get_visible_rect().size.y * to_output
	## World units per screen pixel at one metre: a fixed-size sprite is drawn
	## as if it stood one metre from the camera.
	var unit := 2.0 * tan(deg_to_rad(fov) / 2.0) / height
	for signs: Dictionary in [_signs, _closed_signs]:
		for station: int in signs:
			var sign: Sprite3D = signs[station]
			sign.pixel_size = SIGN_PX * unit / MarkerIcons.SIZE
			(sign.get_node("Caption") as Label3D).pixel_size = unit
	_declutter_captions(camera, to_output)


## Shows each caption only if it clears the captions already shown, taking the
## widest first and then left to right. `to_output` converts the camera's
## viewport coordinates to the screen pixels the captions are sized in.
func _declutter_captions(camera: Camera3D, to_output: float) -> void:
	var entries: Array[Dictionary] = []
	for signs: Dictionary in [_signs, _closed_signs]:
		for station: int in signs:
			var sign: Sprite3D = signs[station]
			var caption := sign.get_node("Caption") as Label3D
			caption.visible = true
			if camera == null or camera.is_position_behind(sign.global_position):
				continue
			var point := camera.unproject_position(sign.global_position) * to_output
			entries.append({"caption": caption, "rect": caption_rect(point, caption.text)})
	entries.sort_custom(_wider_then_left_first)
	var shown: Array[Rect2] = []
	for entry in entries:
		var rect: Rect2 = entry["rect"]
		var clear := true
		for other in shown:
			if rect.intersects(other):
				clear = false
				break
		(entry["caption"] as Label3D).visible = clear
		if clear:
			shown.append(rect.grow(CAPTION_MARGIN_PX / 2.0))


static func _wider_then_left_first(a: Dictionary, b: Dictionary) -> bool:
	var ra: Rect2 = a["rect"]
	var rb: Rect2 = b["rect"]
	if not is_equal_approx(ra.size.x, rb.size.x):
		return ra.size.x > rb.size.x
	if not is_equal_approx(ra.position.x, rb.position.x):
		return ra.position.x < rb.position.x
	return ra.position.y < rb.position.y


## The screen rectangle (pixels) a caption covers over a sign whose bottom edge
## is at `sign_point`: centred on the sign, its bottom a gap above the icon. The
## width is estimated from the default font, plus the outline.
static func caption_rect(sign_point: Vector2, text: String) -> Rect2:
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_FONT)
	size.x += CAPTION_OUTLINE
	size.y = font.get_height(CAPTION_FONT) + CAPTION_OUTLINE
	var bottom := sign_point.y - SIGN_PX - CAPTION_GAP_PX
	return Rect2(Vector2(sign_point.x - size.x / 2.0, bottom - size.y), size)


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	sync()


## A hire, a fire or a member going on duty changes which stations are closed,
## also while the clock is paused.
func _watch_staff() -> void:
	if sim.staff == null:
		return
	if not sim.staff.staff_changed.is_connected(sync):
		sim.staff.staff_changed.connect(sync)
	if not sim.staff.member_state_changed.is_connected(_on_member_state):
		sim.staff.member_state_changed.connect(_on_member_state)


func _on_member_state(_id: int, _state: StaffMember.State) -> void:
	sync()


## The sign of `station` in `signs`, taken from the pool when it has none,
## placed over the station and given its icon.
func _show_sign(signs: Dictionary, station: int, sign_name: String, icon: Texture2D) -> Sprite3D:
	if not signs.has(station):
		signs[station] = _take_sign()
	var sign: Sprite3D = signs[station]
	sign.name = sign_name
	sign.texture = icon
	sign.position = _sign_point(station)
	return sign


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
	caption.outline_size = CAPTION_OUTLINE
	caption.outline_modulate = MarkerIcons.OUTLINE
	caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	caption.offset = Vector2(0.0, SIGN_PX + CAPTION_GAP_PX)
	sign.add_child(caption)
	add_child(sign)
	return sign


func _drop_sign(signs: Dictionary, station: int) -> void:
	var sign: Sprite3D = signs[station]
	sign.visible = false
	_free_signs.append(sign)
	signs.erase(station)
