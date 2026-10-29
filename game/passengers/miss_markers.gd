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
## An arch without a whole security lane (MissSignals.incomplete_arches) gets
## a grey sign too, captioned with what it
## lacks first ("Needs a tray table", MissSignals.lane_hint). It is an
## ordinary caption in the layout below: the player is looking at their own
## half-built lane, the icon always stays, and the build status line says the
## same words while the pointer is over the arch, so it hides when it overlaps
## and is never lifted. It is kept readable, though: inside the view by
## VIEW_MARGIN_PX and clear of everything the HUD draws (the money card, the
## Offers button, the bottom bar, a passive hint card), moving toward the
## screen's middle when it has to, so it stays by its station: first along that
## line by at most MAX_HINT_TRAVEL_PX, then on rings around its own place. With
## no clear spot anywhere in the view it is hidden for that layout
## (hint_no_spot_hides counts it); the icon stays. It also hides while its sign
## is more than one caption width outside the view (user-ruled 2026-10-29: only
## near the view), uncounted.
## A whole lane is one station and gets the queue-full and Closed signs like a
## scanner.
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
## of view), the view size, the signs or (while a lane hint shows) the HUD
## controls' rectangles changed.
##
## A caption is a Label3D, culled by its bounding box around its world anchor, and
## a fixed-size label's box is tiny. A caption placed inside the view therefore
## gets an anchor inside the view too (its sign can be off-screen), with the pixel
## offset making up the difference.

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
## A lane-hint caption keeps this far inside the view, clear of every HUD
## control, and moves toward the screen's middle in HINT_STEP_PX steps, at most
## MAX_HINT_TRAVEL_PX, to get there.
const VIEW_MARGIN_PX := 8.0
const HINT_STEP_PX := 6.0
const MAX_HINT_TRAVEL_PX := 260.0
## Past that, spots are tried on rings this far apart, each with a point every
## HINT_RING_STEP_PX along it (at least this many), so no pocket a caption fits in
## falls between two points.
const HINT_RING_STEP_PX := 32.0
const HINT_RING_POINTS := 16
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
## How many staff-spot captions found no valid spot (one error pushed each).
var no_spot_errors := 0
## How many lane-hint captions were hidden because no spot in the view was clear
## of the HUD, summed over the layouts run.
var hint_no_spot_hides := 0

## Station id -> sign, for the queue-full signs and the closed signs.
var _signs: Dictionary = {}
var _closed_signs: Dictionary = {}
## Arch id -> sign, for the arches without a whole lane.
var _hint_signs: Dictionary = {}
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
## The HUD control rectangles (screen pixels) the last layout kept clear of.
var _view_hud: Array[Rect2] = []
## Reused by the caption layout: the captions in play, their rectangles and
## whether each is a staff-spot reason, the order they are placed in, the
## rectangles placed so far, and a grid of them by cell.
var _labels: Array[Label3D] = []
var _points: Array[Vector2] = []
var _rects: Array[Rect2] = []
var _mandatory: Array[bool] = []
var _hints: Array[bool] = []
var _stations: Array[int] = []
## The icons in play, for a moved caption to keep off, and a grid of them.
var _icons: Array[Rect2] = []
var _icon_bins: Dictionary = {}
## Stations whose staff-spot caption found no valid spot, so the error is
## pushed once per station, not on every layout; an entry lasts until the
## station's sign is removed.
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


## The lane-incomplete sign over an arch without a whole lane, or null.
func hint_sign_for(arch: int) -> Node3D:
	return _hint_signs.get(arch)


func hint_text(arch: int) -> String:
	if not _hint_signs.has(arch):
		return ""
	return ((_hint_signs[arch] as Node).get_node("Caption") as Label3D).text


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
	var incomplete := MissSignals.incomplete_arches(sim)
	for arch: int in _hint_signs.keys():
		if not incomplete.has(arch):
			_drop_sign(_hint_signs, arch)
	for arch in incomplete:
		var sign := _show_sign(_hint_signs, arch, "LaneHintSign", _closed_icon())
		_set_caption(sign, MissSignals.lane_hint(sim, arch))


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
	var hud := _hud_rects(to_output) if not _hint_signs.is_empty() else ([] as Array[Rect2])
	if (
		not _dirty
		and camera_id == _view_camera
		and xform == _view_transform
		and is_equal_approx(fov, _view_fov)
		and is_equal_approx(height, _view_height)
		and is_equal_approx(width, _view_width)
		and hud == _view_hud
	):
		return
	_dirty = false
	_view_hud = hud
	_view_camera = camera_id
	_view_transform = xform
	_view_fov = fov
	_view_height = height
	_view_width = width
	## World units per screen pixel at one metre: a fixed-size sprite is drawn
	## as if it stood one metre from the camera.
	var unit := 2.0 * tan(deg_to_rad(fov) / 2.0) / height
	for signs: Dictionary in [_signs, _closed_signs, _hint_signs]:
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
	_hints.clear()
	_stations.clear()
	_icons.clear()
	_icon_bins.clear()
	_placed.clear()
	_bins.clear()
	for signs: Dictionary in [_signs, _closed_signs, _hint_signs]:
		for station: int in signs:
			var sign: Sprite3D = signs[station]
			var caption := sign.get_node("Caption") as Label3D
			caption.visible = true
			caption.position = Vector3.ZERO
			caption.offset = Vector2(0.0, SIGN_PX + CAPTION_GAP_PX)
			if camera == null or camera.is_position_behind(sign.global_position):
				continue
			var point := camera.unproject_position(sign.global_position) * to_output
			if is_same(signs, _hint_signs) and _far_from_view(point, caption.text, view_size):
				caption.visible = false
				continue
			_labels.append(caption)
			_points.append(point)
			_rects.append(caption_rect(point, caption.text))
			_mandatory.append(is_staff_spot_caption(caption.text))
			_hints.append(is_same(signs, _hint_signs))
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
	for i in _labels.size():
		_anchor_in_view(i, camera, to_output, view_size)


## True when a lane hint's sign point is more than one caption width outside the
## view. The caption is hidden then (not counted as a missing spot) and shows
## again as the sign comes within that distance.
static func _far_from_view(point: Vector2, text: String, view_size: Vector2) -> bool:
	return not Rect2(Vector2.ZERO, view_size).grow(caption_size(text).x).has_point(point)


## Moves the Label3D of caption `i` to a world point that projects inside the
## view by VIEW_MARGIN_PX when its sign's point does not, and shifts the pixel
## offset back so the caption is drawn where the layout put it.
func _anchor_in_view(i: int, camera: Camera3D, to_output: float, view_size: Vector2) -> void:
	var caption := _labels[i]
	if not caption.visible:
		return
	var inner := Rect2(Vector2.ZERO, view_size).grow(-VIEW_MARGIN_PX)
	var point := _points[i]
	var anchor := point.clamp(inner.position, inner.end)
	if anchor.is_equal_approx(point):
		return
	var depth := -(camera.global_transform.affine_inverse() * caption.global_position).z
	caption.global_position = camera.project_position(anchor / to_output, depth)
	caption.offset += Vector2(point.x - anchor.x, anchor.y - point.y)


func _place_caption(i: int, view_size: Vector2) -> void:
	var caption := _labels[i]
	var rect := _rects[i]
	if _mandatory[i]:
		rect = _clear_spot(i, view_size)
		caption.offset += Vector2(
			rect.position.x - _rects[i].position.x, _rects[i].end.y - rect.end.y
		)
	else:
		if _hints[i]:
			rect = _hint_spot(i, view_size)
			if rect.size == Vector2.ZERO:
				hint_no_spot_hides += 1
				caption.visible = false
				caption.offset = Vector2(0.0, SIGN_PX + CAPTION_GAP_PX)
				return
			caption.offset += Vector2(
				rect.position.x - _rects[i].position.x, _rects[i].end.y - rect.end.y
			)
		if _hits_in(rect.grow(CAPTION_MARGIN_PX), _bins, _placed):
			caption.visible = false
			caption.offset = Vector2(0.0, SIGN_PX + CAPTION_GAP_PX)
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
				return rect
			if not best_found:
				best = rect
				best_found = true
	if not _no_spot.has(_stations[i]):
		_no_spot[_stations[i]] = true
		no_spot_errors += 1
		push_error(
			(
				"MissMarkers: no clear spot inside the view for the caption of station %d"
				% _stations[i]
			)
		)
	return best


## Where lane-hint caption `i` goes: its own spot when that is inside the view
## by VIEW_MARGIN_PX and clear of the HUD, else the nearest spot toward the
## screen's middle (at most MAX_HINT_TRAVEL_PX away) that is also off every
## icon, else the nearest such spot on rings of growing radius around its own
## place, tried from the direction of the middle first. A zero-size rectangle
## means no spot is clear anywhere in the view.
func _hint_spot(i: int, view_size: Vector2) -> Rect2:
	var own := _rects[i]
	var inner := Rect2(Vector2.ZERO, view_size).grow(-VIEW_MARGIN_PX)
	if _hint_spot_clear(own, inner):
		return own
	var toward := view_size / 2.0 - own.get_center()
	var heading := toward.angle() if not toward.is_zero_approx() else 0.0
	if not toward.is_zero_approx():
		var step := toward.normalized() * HINT_STEP_PX
		for k in range(1, int(MAX_HINT_TRAVEL_PX / HINT_STEP_PX) + 1):
			var rect := Rect2(own.position + step * k, own.size)
			if _hint_spot_usable(rect, inner):
				return rect
	var radius := HINT_RING_STEP_PX
	var longest := view_size.length()
	while radius <= longest:
		var points := maxi(HINT_RING_POINTS, ceili(TAU * radius / HINT_RING_STEP_PX))
		for n in points:
			## 0, then one step either side of the heading, then two, and so on.
			var turn := ceili(n / 2.0) * (1.0 if n % 2 == 1 else -1.0)
			var angle := heading + TAU * turn / points
			var rect := Rect2(own.position + Vector2.from_angle(angle) * radius, own.size)
			if _hint_spot_usable(rect, inner):
				return rect
		radius += HINT_RING_STEP_PX
	return Rect2()


func _hint_spot_usable(rect: Rect2, inner: Rect2) -> bool:
	return _hint_spot_clear(rect, inner) and not _hits_in(rect, _icon_bins, _icons)


## True when `rect` is inside `inner` and off every HUD rectangle (by the margin).
func _hint_spot_clear(rect: Rect2, inner: Rect2) -> bool:
	if not inner.encloses(rect):
		return false
	var padded := rect.grow(CAPTION_MARGIN_PX)
	for hud in _view_hud:
		if padded.intersects(hud):
			return false
	return true


## The rectangles (screen pixels) of what the HUD draws: the Controls under
## every canvas layer beside this node or beside an ancestor of it, found by
## draws_something(). Invisible ones and layout containers that draw nothing are
## not counted, however large; a drawn control is, also one spanning the view. A
## counted panel or button is not walked into: its children lie inside it.
func _hud_rects(to_output: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var scale := Transform2D().scaled(Vector2(to_output, to_output))
	var node: Node = self
	while node != null and node.get_parent() != null:
		node = node.get_parent()
		for child in node.get_children():
			if child is CanvasLayer and (child as CanvasLayer).visible:
				_collect_hud(child, scale, rects)
	return rects


func _collect_hud(parent: Node, scale: Transform2D, rects: Array[Rect2]) -> void:
	for child in parent.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control:
			var control := child as Control
			if draws_something(control) and control.size.x * control.size.y > 0.0:
				var rect := (
					scale
					* control.get_global_transform_with_canvas()
					* Rect2(Vector2.ZERO, control.size)
				)
				rects.append(rect)
				if _is_box(control):
					continue
		_collect_hud(child, scale, rects)


## True for a Control that puts something on the screen: a panel, a button, a
## label with text, a picture, a colour fill, or any control with a panel style.
static func draws_something(control: Control) -> bool:
	if _is_box(control) or control is ColorRect:
		return true
	if control is Label:
		return not (control as Label).text.is_empty()
	if control is RichTextLabel:
		return not (control as RichTextLabel).text.is_empty()
	if control is TextureRect:
		return (control as TextureRect).texture != null
	return control.has_theme_stylebox_override("panel")


## A panel or a button: it draws a box and its children lie inside it.
static func _is_box(control: Control) -> bool:
	return control is Panel or control is PanelContainer or control is BaseButton


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
	_no_spot.erase(station)
	_dirty = true
