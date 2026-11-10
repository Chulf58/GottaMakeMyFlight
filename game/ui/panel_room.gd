class_name PanelRoom
extends Node
## Keeps the terminal out from under the HUD panels (decision camera-makes-
## room-for-open-panels-the-build-tray-banner-and). It finds which panels are
## open (the build tray with its status and cost lines, the Staff card, the
## banner at the top centre and the Offers sheet), and the right rail's drawn
## cards (alert cards and the flight result card) with its history tray
## (AlertStack.room_rect()), and the category bar across the bottom while no
## tray covers it, takes the
## largest screen rectangle they leave free, and tells the TycoonCamera, which
## puts its focus at the middle of that rectangle and, while it is still on the
## start view, refits the start area inside it.
##
## Only a panel opening or closing refits the distance; a panel that merely
## changes size moves the view a little and never zooms it (the banner is the
## exception while the tray is open: see the build stack below). The rail is
## counted the same way: a card coming or going only shifts the view. The
## camera does nothing on a build edit.
##
## The build stack (the tray, and the banner at the top centre) makes room once,
## when the tray opens (decision camera-makes-room-once-per-build-mode-open-not-on-
## every-menu-switch). REFIT_FRAMES later its rectangles are kept, and the
## tray changing size, or the banner coming or going, while the player
## switches between build menus moves and zooms nothing. They are let go when
## the tray closes. The other panels keep making room as they open and close.

## A cut that would leave less than this share of the viewport's width or
## height is not taken, so a small window never shrinks the view to nothing.
const MIN_SHARE := 0.25
## Frames after a panel opens or closes in which a size change still refits the
## distance: a card that has just appeared is not laid out until a frame later.
const REFIT_FRAMES := 4
## The least a free rectangle's edge may change to be sent to the camera again,
## as a share of the viewport.
const MIN_CHANGE := 0.004

## The camera the free rectangle goes to; null leaves the view alone.
var camera: TycoonCamera
## The node holding BuildMenu, StaffPanel and OfferPanel as children, found by
## name each time because the panels build themselves after the HUD.
var scene_root: Node
## Returns the screen rectangle of the banner slot's visible card (the status
## banner or a first-time hint), empty while none shows. PassengerHud sets it;
## without one the status banner's card alone is read.
var banner_rect := Callable()
## The right rail, held by PassengerHud; its rect is cut but never counts as
## a panel opening or closing.
var alert_stack: AlertStack

var _last_key := 0
var _refit_frames := 0
var _last_free := Rect2(0.0, 0.0, 1.0, 1.0)
## Frames the tray has been open, counted up to the frame its stack is kept.
var _tray_frames := 0
## The tray and banner rectangles kept at that frame, and the viewport size
## they were taken at; `_kept` is false while they follow the panels live.
var _kept := false
var _kept_rects: Array[Rect2] = []
var _kept_size := Vector2.ZERO


## The largest rectangle of `viewport` that `panels` leave free, in the same
## units. Each panel in turn cuts the rectangle on the side that keeps the most
## area; one that overlaps nothing, or whose every cut would leave too little,
## is skipped.
static func free_rect(viewport: Rect2, panels: Array[Rect2]) -> Rect2:
	var free := viewport
	for panel in panels:
		if not free.intersects(panel):
			continue
		var best := Rect2()
		for kept in _kept_sides(free, panel):
			var big_enough := (
				kept.size.x >= viewport.size.x * MIN_SHARE
				and kept.size.y >= viewport.size.y * MIN_SHARE
			)
			if big_enough and kept.get_area() > best.get_area():
				best = kept
		if best.has_area():
			free = best
	return free


## The four pieces of `free` beside `panel`: above, left, right, below.
static func _kept_sides(free: Rect2, panel: Rect2) -> Array[Rect2]:
	var top := free.position.y
	var left := free.position.x
	return [
		Rect2(left, top, free.size.x, panel.position.y - top),
		Rect2(left, top, panel.position.x - left, free.size.y),
		Rect2(panel.end.x, top, free.end.x - panel.end.x, free.size.y),
		Rect2(left, panel.end.y, free.size.x, free.end.y - panel.end.y),
	]


func _process(_delta: float) -> void:
	if camera == null:
		return
	_track_build_stack()
	var key := open_key()
	var free := free_fraction()
	var moved := (
		absf(free.position.x - _last_free.position.x) > MIN_CHANGE
		or absf(free.position.y - _last_free.position.y) > MIN_CHANGE
		or absf(free.end.x - _last_free.end.x) > MIN_CHANGE
		or absf(free.end.y - _last_free.end.y) > MIN_CHANGE
	)
	if key != _last_key:
		_refit_frames = REFIT_FRAMES
	var refit := _refit_frames > 0
	_refit_frames = maxi(_refit_frames - 1, 0)
	if key == _last_key and not moved:
		return
	camera.set_room(free, refit)
	_last_key = key
	_last_free = free


## Counts the frames the tray has been open and, REFIT_FRAMES after it opened,
## keeps the build stack's rectangles until the tray closes. A resized viewport
## takes them again, since they are in pixels.
func _track_build_stack() -> void:
	var menu := _menu()
	if menu == null or not menu.is_tray_open():
		_tray_frames = 0
		_kept = false
		return
	var size := get_viewport().get_visible_rect().size
	if _kept and size != _kept_size:
		_tray_frames = 0
		_kept = false
	if _kept:
		return
	_tray_frames += 1
	if _tray_frames > REFIT_FRAMES:
		_kept_rects = _build_stack(menu)
		_kept_size = size
		_kept = true


## The free screen rectangle as fractions of the viewport.
func free_fraction() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var free := free_rect(Rect2(Vector2.ZERO, size), open_rects())
	return Rect2(free.position / size, free.size / size)


## Takes the open panels and free rectangle now as the ones the camera already
## has, so the next frame sends nothing. The start view is framed with them.
func mark_sent() -> void:
	_last_key = open_key()
	_last_free = free_fraction()


## Which panels are open, one bit each, so the camera can tell a panel opening
## or closing from one changing size.
func open_key() -> int:
	var key := 0
	var bit := 1
	var menu := _menu()
	var tray_open := menu != null and menu.is_tray_open()
	for panel in _panels():
		if panel != null and panel.is_visible_in_tree():
			key |= bit
		bit <<= 1
	if not tray_open and _banner().has_area():
		key |= bit
	bit <<= 1
	if tray_open:
		key |= bit
	bit <<= 1
	if menu != null and not tray_open and menu.bar().is_visible_in_tree():
		key |= bit
	return key


## The screen rectangle of every open panel, then the right rail.
func open_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var menu := _menu()
	var tray_open := menu != null and menu.is_tray_open()
	if tray_open:
		rects.append_array(_kept_rects if _kept else _build_stack(menu))
	elif menu != null and menu.bar().is_visible_in_tree():
		rects.append(_bar_strip())
	for panel in _panels():
		if panel != null and panel.is_visible_in_tree():
			rects.append(panel.get_global_rect())
	if not tray_open and _banner().has_area():
		rects.append(_banner())
	if alert_stack != null:
		var alerts := alert_stack.room_rect()
		if alerts.has_area():
			rects.append(alerts)
	return rects


## The Staff card and the Offers sheet, in the order their rectangles are cut;
## the banner slot is `_banner()`.
func _panels() -> Array[Control]:
	var panels: Array[Control] = []
	var staff := _find("StaffPanel") as StaffPanel
	panels.append(null if staff == null else staff.card())
	var offers := _find("OfferPanel") as OfferPanel
	panels.append(null if offers == null else offers.sheet())
	return panels


## The rectangles the build stack covers now: the tray with its lines and bar,
## then the banner while it shows.
func _build_stack(menu: BuildMenu) -> Array[Rect2]:
	var rects: Array[Rect2] = [_tray_stack(menu)]
	var banner := _banner()
	if banner.has_area():
		rects.append(banner)
	return rects


## The banner slot's visible card now, the status banner or a first-time hint;
## empty while none shows.
func _banner() -> Rect2:
	if banner_rect.is_valid():
		return banner_rect.call()
	var staff := _find("StaffPanel") as StaffPanel
	if staff == null or not staff.hint_card().is_visible_in_tree():
		return Rect2()
	return staff.hint_card().get_global_rect()


## The category bar's strip across the bottom of the screen, which the start view
## keeps clear while no tray covers it. Taken from the bar's fixed height, not its
## laid-out rectangle, so the first frame, before layout, already has it.
func _bar_strip() -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var height := BuildMenu.MARGIN + BuildMenu.BAR_H
	return Rect2(0.0, size.y - height, size.x, height)


## The tray, its status and cost lines and the bar under them, from the top of
## the stack to the bottom of the screen. The status line comes and goes with
## the pointer, so the fixed height of the stack is used, not the line.
func _tray_stack(menu: BuildMenu) -> Rect2:
	var size := get_viewport().get_visible_rect().size
	var tray := menu.tray().get_global_rect()
	var half := maxf(BuildMenu.COLUMN_W, tray.size.x) / 2.0
	var top := size.y - menu.stack_top()
	return Rect2(size.x / 2.0 - half, top, half * 2.0, size.y - top)


func _menu() -> BuildMenu:
	return _find("BuildMenu") as BuildMenu


func _find(node_name: String) -> Node:
	if scene_root == null:
		return null
	var node := scene_root.get_node_or_null(node_name)
	return node if node != null and node.is_node_ready() else null
