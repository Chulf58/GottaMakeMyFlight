class_name HoverTarget
extends Node
## The one thing under the pointer each frame, and the one thing a click pinned
## (decision calm-view-technical-design-shared-hover-target-reusing-click, parts
## 1-2). It shows the shown target's text in one cream AnchoredTooltip card.
##
## CONTRACT for station signs (lane A) and passenger bubbles (lane B):
## - Find it: HoverTarget.find(get_tree()) returns the scene's HoverTarget (it
##   joins GROUP on entering the tree, before any _ready runs), or null.
## - Targets: a Target is a passenger (kind PASSENGER, passenger_id) or a station
##   sign (kind SIGN, provider and key). Identity is the passenger id, or the
##   provider object plus its key; Target.same_as() compares it. rect is the
##   target's screen rect in viewport px (a sign: its hit rect without the margin;
##   a passenger: a zero-size rect at the projected top of the head) and text is
##   what the tooltip shows. A Target is a fresh snapshot each frame: keep it no
##   longer than the frame, and read the getters again next frame.
## - Getters: hovered_target(), pinned_target(), shown_target() (hovered, else
##   pinned: what the tooltip shows), and hovered_passenger()/pinned_passenger()
##   (an id, 0 for none). They are current from the start of PassengerViews.draw()
##   on, every frame (see Frame order).
## - Sign providers: register_provider(provider) and unregister_provider(provider).
##   A provider is any object with hover_signs() -> Array[Dictionary], each entry
##   {"key": Variant, "rect": Rect2, "text": String}: the sign's visible screen
##   rect this frame (viewport px, as Camera3D.unproject_position gives) and its
##   tooltip text. It is asked every frame; a sign it stops reporting is gone. A
##   freed provider is dropped.
## - Passenger text: passenger_text is a Callable (passenger id -> String) that
##   lane B sets; unset or "" shows no tooltip for a passenger.
##
## Arbitration, the same as a click: nothing while a build interaction owns world
## clicks (BuiltSelection.clicks_taken); nothing under a visible mouse-catching
## HUD Control (mouse_filter not IGNORE: the Controls that take a click before the
## world sees it); else a sign whose rect grown by SIGN_MARGIN_PX holds the pointer
## (the nearest centre of several); else the passenger PassengerHud's click would
## select there: none over a vehicle, PassengerViews.pick_body() when a built
## object is under the pointer, PassengerViews.pick() (the 40 px circle) elsewhere.
## This mirrors PassengerHud._unhandled_input and _passenger_at; a change to that
## click order must change _passenger_under() too.
##
## Pins: a left click on a sign pins that sign and takes the click, so nothing
## behind the sign is selected, and ends any passenger, vehicle or built selection
## and the camera follow through PassengerHud. Any other world click unpins the
## sign, and the passenger PassengerHud selects for that click becomes the pinned
## passenger. The
## pin lasts until a click elsewhere or Esc (a pinned sign takes the Esc; a pinned
## passenger ends with PassengerHud's selection), and is cleared when its target
## goes (the sign is no longer reported, the passenger's view is released) and on a
## successful load. The pin survives hovering something else.
##
## Frame order: PassengerViews.draw() calls resolve() first, before it lays out
## bubbles, icons and badges (PassengerViews.layout_started marks where that
## layout begins), so they can read this frame's target. PassengerViews
## runs after the AnimationPlayers (process_priority 1) and RoomView after it (2);
## resolving inside draw() keeps the target ahead of the layout whatever those
## numbers become, where a priority of its own would race them. The target reads
## the passengers where they were last drawn, the positions a click this frame was
## made against. When PassengerViews is not processing (a paused tree), this node's
## own _process resolves instead (it runs in every pause mode).

enum Kind { PASSENGER, SIGN }

const GROUP := &"hover_target"
## How far outside its rect a sign still wins, in viewport px.
const SIGN_MARGIN_PX := 6.0
## A HUD rect larger than this share of the screen (a frame or an overlay) is not
## something the tooltip steps around.
const AVOID_MAX_SHARE := 0.4
const TOOLTIP_LAYER := 3

@export var views: PassengerViews
@export var build_mode: BuildMode
@export var landside_views: LandsideViews
@export var save_game: SaveGame
## When set, a click a sign takes also ends the passenger, vehicle or built
## selection and the camera follow, as a click elsewhere would.
@export var hud: PassengerHud

## (passenger id) -> String, the tooltip text of a passenger; set by lane B.
var passenger_text: Callable
## Test and probe seam: a Vector2 read as the pointer instead of the mouse.
var pointer_override: Variant = null

var _providers: Array[Object] = []
var _layers: Array[CanvasLayer] = []
var _hovered: Target
var _pinned: Target
var _pinned_sign: Target
var _pinned_passenger := 0
## Set by a world click that met no sign: the next resolve pins the passenger
## PassengerHud selected for it.
var _pin_from_click := false
var _resolved_frame := -1
var _tip_layer: CanvasLayer
var _tip: AnchoredTooltip
var _built_probe := BuiltSelection.new()
## This resolve's HUD rects, walked at most once and only when needed.
var _hud_cache: Variant = null


## A target under the pointer or pinned, as of the frame it was resolved in.
class Target:
	extends RefCounted
	var kind := Kind.PASSENGER
	var passenger_id := 0
	var provider: Object
	var key: Variant
	var rect := Rect2()
	var text := ""

	func same_as(other: Target) -> bool:
		if other == null or other.kind != kind:
			return false
		if kind == Kind.PASSENGER:
			return other.passenger_id == passenger_id
		return other.provider == provider and other.key == key


static func find(tree: SceneTree) -> HoverTarget:
	return tree.get_first_node_in_group(GROUP) as HoverTarget if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tip_layer = CanvasLayer.new()
	_tip_layer.name = "TooltipLayer"
	_tip_layer.layer = TOOLTIP_LAYER
	add_child(_tip_layer)
	_tip = AnchoredTooltip.new()
	_tip_layer.add_child(_tip)
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		_track_layer(node)
	get_tree().node_added.connect(_track_layer)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)


func _process(_delta: float) -> void:
	if views == null or not views.can_process():
		resolve()


func register_provider(provider: Object) -> void:
	if not _providers.has(provider):
		_providers.append(provider)


func unregister_provider(provider: Object) -> void:
	_providers.erase(provider)


func hovered_target() -> Target:
	return _hovered


func pinned_target() -> Target:
	return _pinned


func shown_target() -> Target:
	return _hovered if _hovered != null else _pinned


func hovered_passenger() -> int:
	return _passenger_of(_hovered)


## The pinned passenger's id, also while they are behind the camera and
## pinned_target() is null.
func pinned_passenger() -> int:
	return _pinned_passenger


func tooltip() -> AnchoredTooltip:
	return _tip


## The process frame of the last resolve.
func resolved_frame() -> int:
	return _resolved_frame


## Resolves this frame's hovered and pinned targets and places the tooltip.
## PassengerViews.draw() calls it before its layout (see Frame order).
func resolve() -> void:
	_resolved_frame = Engine.get_process_frames()
	refresh()


## Resolves now: the work of resolve(), for a caller that changed the pointer.
func refresh() -> void:
	_hud_cache = null
	var signs := _current_signs()
	var eye := get_viewport().get_camera_3d() if is_inside_tree() else null
	var taken := build_mode != null and BuiltSelection.clicks_taken(build_mode)
	if taken:
		_pinned_sign = null
	_settle_passenger_pin()
	_hovered = null if taken else _target_at(_pointer(), signs, eye)
	_pinned = _pinned_now(signs, eye)
	var shown := shown_target()
	if shown == null or shown.text == "":
		_tip.hide_tip()
	else:
		_tip.show_at(shown.text, shown.rect, _avoid_rects(_hud_rects()))


func _unhandled_input(event: InputEvent) -> void:
	if _pinned_sign != null and event.is_action_pressed(&"build_tool_none"):
		_pinned_sign = null
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if build_mode != null and BuiltSelection.clicks_taken(build_mode):
		return
	var sign := _sign_at(click.position, _current_signs())
	if sign != null:
		_pinned_sign = sign
		_pinned_passenger = 0
		_pin_from_click = false
		# The click is the sign's: what was selected before ends as a click
		# elsewhere would end it (PassengerHud's Esc path, also used by GameMenu).
		if hud != null:
			hud._close_selection()
		get_viewport().set_input_as_handled()
		return
	_pinned_sign = null
	_pin_from_click = true


## A failed load leaves the world as it was, and the pins with it.
func _on_loaded(ok: bool) -> void:
	if not ok:
		return
	_pinned_sign = null
	_pinned_passenger = 0
	_pin_from_click = false
	_hovered = null
	_pinned = null


func _pointer() -> Vector2:
	if pointer_override != null:
		return pointer_override
	return get_viewport().get_mouse_position() if is_inside_tree() else Vector2(-1.0, -1.0)


func _target_at(at: Vector2, signs: Array[Target], eye: Camera3D) -> Target:
	var found := _sign_at(at, signs)
	if found == null and eye != null:
		found = _passenger_target(_passenger_under(eye, at), eye)
	if found == null:
		return null
	for rect in _hud_rects():
		if rect.has_point(at):
			return null
	return found


## The sign whose rect grown by SIGN_MARGIN_PX holds `at`, nearest centre first.
func _sign_at(at: Vector2, signs: Array[Target]) -> Target:
	var best: Target
	var best_px := INF
	for sign in signs:
		if not sign.rect.grow(SIGN_MARGIN_PX).has_point(at):
			continue
		var px := sign.rect.get_center().distance_to(at)
		if px < best_px:
			best = sign
			best_px = px
	return best


## The passenger a left click at `at` selects (PassengerHud's click order), or 0.
func _passenger_under(eye: Camera3D, at: Vector2) -> int:
	if views == null:
		return 0
	if landside_views != null and landside_views.pick(eye, at) != 0:
		return 0
	var view := build_mode.get_node_or_null("BuildView") as BuildView if build_mode else null
	if view != null:
		_built_probe.pick(build_mode.grid, view, build_mode.landside_placement(), eye, at)
		if _built_probe.kind == BuiltSelection.Kind.OBJECT:
			return views.pick_body(eye, at)
	return views.pick(eye, at)


func _passenger_target(id: int, eye: Camera3D) -> Target:
	var node := views.node_for(id) if views != null and id != 0 else null
	if node == null or eye == null:
		return null
	var head := node.position + Vector3(0.0, PassengerViews.BODY_HEIGHT_M, 0.0)
	if eye.is_position_behind(head):
		return null
	var target := Target.new()
	target.kind = Kind.PASSENGER
	target.passenger_id = id
	target.rect = Rect2(eye.unproject_position(head), Vector2.ZERO)
	if passenger_text.is_valid():
		target.text = passenger_text.call(id)
	return target


## Takes the passenger PassengerHud selected for the last world click, and drops
## the pinned passenger once that selection ends or their view goes.
func _settle_passenger_pin() -> void:
	if _pin_from_click:
		_pin_from_click = false
		_pinned_passenger = views.selected_id if views != null else 0
	if _pinned_passenger == 0:
		return
	if views == null or views.selected_id != _pinned_passenger:
		_pinned_passenger = 0
	elif views.node_for(_pinned_passenger) == null:
		_pinned_passenger = 0


func _pinned_now(signs: Array[Target], eye: Camera3D) -> Target:
	if _pinned_sign != null:
		for sign in signs:
			if sign.same_as(_pinned_sign):
				_pinned_sign = sign
				return sign
		_pinned_sign = null
	if _pinned_passenger != 0:
		return _passenger_target(_pinned_passenger, eye)
	return null


## Every sign the live providers report this frame.
func _current_signs() -> Array[Target]:
	var signs: Array[Target] = []
	var live: Array[Object] = []
	for provider in _providers:
		if is_instance_valid(provider):
			live.append(provider)
	_providers = live
	for provider in _providers:
		for entry: Dictionary in provider.hover_signs():
			var sign := Target.new()
			sign.kind = Kind.SIGN
			sign.provider = provider
			sign.key = entry.get("key")
			sign.rect = entry.get("rect", Rect2())
			sign.text = entry.get("text", "")
			signs.append(sign)
	return signs


func _track_layer(node: Node) -> void:
	var layer := node as CanvasLayer
	if layer != null and layer != _tip_layer and not _layers.has(layer):
		_layers.append(layer)


## The screen rect of every visible HUD Control that takes the mouse, in
## viewport px. A Control under a Viewport (a SubViewport) is not walked.
func _hud_rects() -> Array[Rect2]:
	if _hud_cache != null:
		return _hud_cache
	var rects: Array[Rect2] = []
	var live: Array[CanvasLayer] = []
	for layer in _layers:
		if is_instance_valid(layer):
			live.append(layer)
	_layers = live
	for layer in _layers:
		if not layer.is_inside_tree() or not layer.visible:
			continue
		var to_screen := layer.get_final_transform()
		for child in layer.get_children():
			_collect(child, to_screen, rects)
	_hud_cache = rects
	return rects


func _collect(node: Node, to_screen: Transform2D, rects: Array[Rect2]) -> void:
	if node is Viewport:
		return
	var item := node as CanvasItem
	if item != null and not item.visible:
		return
	var control := node as Control
	if control != null and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		rects.append(to_screen * control.get_global_rect())
	for child in node.get_children():
		_collect(child, to_screen, rects)


func _avoid_rects(hud: Array[Rect2]) -> Array[Rect2]:
	var screen := get_viewport().get_visible_rect().get_area() if is_inside_tree() else 0.0
	var avoid: Array[Rect2] = []
	for rect in hud:
		if rect.get_area() <= screen * AVOID_MAX_SHARE:
			avoid.append(rect)
	return avoid


static func _passenger_of(target: Target) -> int:
	return target.passenger_id if target != null and target.kind == Kind.PASSENGER else 0
