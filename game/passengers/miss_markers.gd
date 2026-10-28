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
## already shown, and every icon stays; the captions return as the camera moves
## in. The two staff-spot reasons are never hidden: one that would overlap is
## moved clear instead, up first and then to either side, staying inside the
## view and off every icon; with no such spot it is reported once and kept at
## the best one found. Otherwise the widest caption wins, then the leftmost.
## The layout runs only when the camera (its presence, identity, pose and field
## of view), the view size or the signs changed.

const SIGN_LIFT_M := 0.6
const SIGN_PX := 56.0
const CAPTION_FONT := 22
const CAPTION_GAP_PX := 4.0
const CAPTION_OUTLINE := 8
## Clear space kept between two shown captions.
const CAPTION_MARGIN_PX := 6.0
## Side of a broad-phase cell for the overlap test, and the most a staff-spot
## caption is lifted looking for clear space.
const BIN_PX := 160.0
const MAX_LIFTS := 64
const FALLBACK_FOV := 55.0
const FALLBACK_HEIGHT := 1080.0
const FALLBACK_WIDTH := 1920.0
## A moved staff-spot caption tries this many side steps each way.
const MAX_SHIFTS := 8
## The closed sign is the queue-full icon with its red fill painted grey-blue.
const CLOSED_FILL := Color(0.47, 0.53, 0.62)
const FILL_TOLERANCE := 0.1
const CLOSED_CAPTION := "Closed"
const SPOT_BLOCKED_CAPTION := "Closed: staff spot blocked"
const UNREACHABLE_CAPTION := "Closed: staff can't reach"

static var _closed_texture: ImageTexture
## Caption text -> its on-screen size in pixels, measured once.
static var _caption_sizes: Dictionary = {}

var sim: PassengerSim
## How many times the caption layout ran; it skips a draw where nothing changed.
var declutter_runs := 0

## Station id -> sign, for the queue-full signs and the closed signs.
var _signs: Dictionary = {}
var _closed_signs: Dictionary = {}
var _free_signs: Array[Sprite3D] = []
## Set when a sign or caption changed; with the camera and view size it decides
## whether draw() has anything to do.
var _dirty := true
var _view_transform := Transform3D()
var _view_fov := 0.0
var _view_height := 0.0
var _view_width := 0.0
## Instance id of the camera the last layout used, 0 for none.
var _view_camera := 0
## Reused by the caption layout: the captions in play, their rectangles and
## whether each is a staff-spot reason, the order they are placed in, the
## rectangles placed so far, and a grid of them by cell.
var _labels: Array[Label3D] = []
var _points: Array[Vector2] = []
var _rects: Array[Rect2] = []
var _mandatory: Array[bool] = []
var _stations: Array[int] = []
## The icons in play, for a moved caption to keep off, and a grid of them.
var _icons: Array[Rect2] = []
var _icon_bins: Dictionary = {}
## Stations whose staff-spot caption found no valid spot, so the error is
## pushed once, not on every layout.
var _no_spot: Dictionary = {}
var _order: Array[int] = []
var _placed: Array[Rect2] = []
var _bins: Dictionary = {}


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
		_set_caption(sign, caption)
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
		_set_caption(sign, caption)


func draw() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var fov := camera.fov if camera != null else FALLBACK_FOV
	## The viewport's output height in screen pixels. The visible rect alone is the
	## layout size, which the content scale (project.godot) makes smaller than
	## the screen, so it is scaled back by the stretch transform. (The viewport
	## texture's get_size() is no help: under the content scale it reports
	## neither size.)
	var height := FALLBACK_HEIGHT
	var width := FALLBACK_WIDTH
	## Layout coordinates (the camera's) times this are screen pixels.
	var to_output := 1.0
	if is_inside_tree():
		var view := get_viewport()
		to_output = view.get_stretch_transform().get_scale().y
		height = view.get_visible_rect().size.y * to_output
		width = view.get_visible_rect().size.x * view.get_stretch_transform().get_scale().x
	var xform := camera.global_transform if camera != null else Transform3D()
	var camera_id := camera.get_instance_id() if camera != null else 0
	if (
		not _dirty
		and camera_id == _view_camera
		and xform == _view_transform
		and is_equal_approx(fov, _view_fov)
		and is_equal_approx(height, _view_height)
		and is_equal_approx(width, _view_width)
	):
		return
	_dirty = false
	_view_camera = camera_id
	_view_transform = xform
	_view_fov = fov
	_view_height = height
	_view_width = width
	## World units per screen pixel at one metre: a fixed-size sprite is drawn
	## as if it stood one metre from the camera.
	var unit := 2.0 * tan(deg_to_rad(fov) / 2.0) / height
	for signs: Dictionary in [_signs, _closed_signs]:
		for station: int in signs:
			var sign: Sprite3D = signs[station]
			sign.pixel_size = SIGN_PX * unit / MarkerIcons.SIZE
			(sign.get_node("Caption") as Label3D).pixel_size = unit
	_declutter_captions(camera, to_output, Vector2(width, height))


## Lays the captions out on the screen: each is shown only if it clears the
## captions already placed. The two staff-spot reasons go first and are never
## hidden (one that would overlap is lifted instead); then the widest, then the
## leftmost. `to_output` converts the camera's viewport coordinates to the
## screen pixels the captions are sized in; `view_size` is the screen's size in
## those pixels.
func _declutter_captions(camera: Camera3D, to_output: float, view_size: Vector2) -> void:
	declutter_runs += 1
	_labels.clear()
	_points.clear()
	_rects.clear()
	_mandatory.clear()
	_stations.clear()
	_icons.clear()
	_icon_bins.clear()
	_placed.clear()
	_bins.clear()
	for signs: Dictionary in [_signs, _closed_signs]:
		for station: int in signs:
			var sign: Sprite3D = signs[station]
			var caption := sign.get_node("Caption") as Label3D
			caption.visible = true
			caption.offset = Vector2(0.0, SIGN_PX + CAPTION_GAP_PX)
			if camera == null or camera.is_position_behind(sign.global_position):
				continue
			var point := camera.unproject_position(sign.global_position) * to_output
			_labels.append(caption)
			_points.append(point)
			_rects.append(caption_rect(point, caption.text))
			_mandatory.append(is_staff_spot_caption(caption.text))
			_stations.append(station)
			var icon := Rect2(point.x - SIGN_PX / 2.0, point.y - SIGN_PX, SIGN_PX, SIGN_PX)
			_icons.append(icon)
			_bin(_icon_bins, icon, _icons.size() - 1)
	_order.resize(_labels.size())
	for i in _order.size():
		_order[i] = i
	_order.sort_custom(_placed_before)
	for i in _order:
		_place_caption(i, view_size)


func _place_caption(i: int, view_size: Vector2) -> void:
	var caption := _labels[i]
	var rect := _rects[i]
	if _mandatory[i]:
		rect = _clear_spot(i, view_size)
		caption.offset += Vector2(
			rect.position.x - _rects[i].position.x, _rects[i].end.y - rect.end.y
		)
	elif _hits_in(rect.grow(CAPTION_MARGIN_PX), _bins, _placed):
		caption.visible = false
		return
	_placed.append(rect)
	_bin(_bins, rect, _placed.size() - 1)


## Where staff-spot caption `i` goes: its own spot if clear, else lifted
## upward, then the same lifts to either side. A spot is valid inside the view,
## off every icon and clear of the captions placed. With no valid spot the error
## is pushed once and the best spot found is used: inside the view and clear of
## the captions, else the caption's own place.
func _clear_spot(i: int, view_size: Vector2) -> Rect2:
	var view := Rect2(Vector2.ZERO, view_size)
	var text := _labels[i].text
	var step_y := _rects[i].size.y + CAPTION_MARGIN_PX
	var step_x := _rects[i].size.x / 2.0 + SIGN_PX / 2.0 + CAPTION_MARGIN_PX
	var best := _rects[i]
	var best_found := false
	for attempt in MAX_SHIFTS * 2 + 1:
		## 0, then right, left, twice right, twice left, and so on.
		var side := 0.0
		if attempt > 0:
			side = step_x * ceili(attempt / 2.0) * (1.0 if attempt % 2 == 1 else -1.0)
		for lifts in MAX_LIFTS:
			var rect := caption_rect(_points[i], text, step_y * lifts, side)
			if rect.position.y < view.position.y:
				break
			if not view.encloses(rect) or _hits_in(rect.grow(CAPTION_MARGIN_PX), _bins, _placed):
				continue
			if not _hits_in(rect, _icon_bins, _icons):
				_no_spot.erase(_stations[i])
				return rect
			if not best_found:
				best = rect
				best_found = true
	if not _no_spot.has(_stations[i]):
		_no_spot[_stations[i]] = true
		push_error(
			(
				"MissMarkers: no clear spot inside the view for the caption of station %d"
				% _stations[i]
			)
		)
	return best


## True when `rect` touches a rectangle in `rects`, found through `bins`.
func _hits_in(rect: Rect2, bins: Dictionary, rects: Array[Rect2]) -> bool:
	for cell in _bin_range(rect):
		if bins.has(cell):
			for at: int in bins[cell]:
				if rect.intersects(rects[at]):
					return true
	return false


## Files rectangle number `at` under every broad-phase cell it covers.
static func _bin(bins: Dictionary, rect: Rect2, at: int) -> void:
	for cell in _bin_range(rect):
		if not bins.has(cell):
			bins[cell] = []
		(bins[cell] as Array).append(at)


## The broad-phase cells a rectangle covers.
static func _bin_range(rect: Rect2) -> Array[Vector2i]:
	var low := Vector2i((rect.position / BIN_PX).floor())
	var high := Vector2i((rect.end / BIN_PX).floor())
	var cells: Array[Vector2i] = []
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			cells.append(Vector2i(x, y))
	return cells


func _placed_before(a: int, b: int) -> bool:
	if _mandatory[a] != _mandatory[b]:
		return _mandatory[a]
	var ra := _rects[a]
	var rb := _rects[b]
	if not is_equal_approx(ra.size.x, rb.size.x):
		return ra.size.x > rb.size.x
	if not is_equal_approx(ra.position.x, rb.position.x):
		return ra.position.x < rb.position.x
	return ra.position.y < rb.position.y


static func is_staff_spot_caption(text: String) -> bool:
	return text == SPOT_BLOCKED_CAPTION or text == UNREACHABLE_CAPTION


## What a caption covers on screen, in pixels, outline included: the text in
## the default font plus the outline on every side. Measured once per text.
static func caption_size(text: String) -> Vector2:
	if not _caption_sizes.has(text):
		var font := ThemeDB.fallback_font
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_FONT)
		size.y = font.get_height(CAPTION_FONT)
		_caption_sizes[text] = size + Vector2.ONE * 2.0 * CAPTION_OUTLINE
	return _caption_sizes[text]


## The screen rectangle (pixels) a caption covers over a sign whose bottom edge
## is at `sign_point`: centred on the sign, its bottom a gap above the icon,
## `lift` pixels higher and `shift` pixels to the right when a staff-spot
## caption was moved clear of others.
static func caption_rect(sign_point: Vector2, text: String, lift := 0.0, shift := 0.0) -> Rect2:
	var size := caption_size(text)
	var bottom := sign_point.y - SIGN_PX - CAPTION_GAP_PX - lift
	return Rect2(Vector2(sign_point.x - size.x / 2.0 + shift, bottom - size.y), size)


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
		_dirty = true
	var sign: Sprite3D = signs[station]
	sign.name = sign_name
	sign.texture = icon
	var point := _sign_point(station)
	if not sign.position.is_equal_approx(point):
		sign.position = point
		_dirty = true
	return sign


func _set_caption(sign: Sprite3D, text: String) -> void:
	var caption := sign.get_node("Caption") as Label3D
	if caption.text != text:
		caption.text = text
		_dirty = true


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
	_dirty = true
