class_name MissMarkers
extends Node3D
## One small soft sign over each station with a problem (decision calm-cozy-
## default-view-quiet-world-detail-on-ask-soft-statio, part 2, and its technical
## design calm-view-technical-design-shared-hover-target-reusing-click, parts 2
## and 4): a MarkerIcons disc whose glyph says what is wrong, with no caption.
## Its words show in the HoverTarget tooltip while the pointer is over the sign
## or a click pinned it; hover_signs() gives HoverTarget each sign's screen rect
## and text.
## - A full desk or scanner (MissSignals.full_stations) gets the queue glyph:
##   "Queue full · 6 waiting".
## - A desk or scanner with nobody on duty (MissSignals.closed_stations), and a
##   cafe or kiosk counter with no server (ShopCounters.closed), gets the padlock
##   glyph, "Closed · no staff on duty" or "Closed by you". A closed station shows
##   only that sign, since it serves nobody. When its staff spot is blocked (only
##   an old save can hold one) or staff have no way from an entrance to it
##   (MissSignals.closed_reason), it gets the blocked-staff glyph instead: "Closed
##   · staff spot blocked" or "Closed · staff can't reach the desk". AlertSources
##   raises a card for the closed and staff-spot stations as well, so a problem
##   whose words moved off the world still reaches the player (part 3).
## - An arch without a whole security lane (MissSignals.incomplete_arches) gets
##   the build-hint table glyph. Its words ("Needs a tray table",
##   MissSignals.lane_hint) are a build hint: they show on hover only in build
##   mode, while the sign itself stays (the ruling keeps a missing tray table in
##   the list of station problems that show an icon). A whole lane is one station
##   and gets the queue-full and Closed signs like a scanner.
## PassengerViews creates it as a child and calls sync() after each tick and
## draw() after placing its passengers. It reads the sim and never writes to it.
##
## The sign is a billboard drawn over the world (no depth test), like the
## thought bubbles, and keeps one screen size (SIGN_PX) at every zoom and UI
## scale: sizes are screen pixels, for the camera's field of view and the
## rendered view's height.

const SIGN_LIFT_M := 0.6
const SIGN_PX := 32.0
## Caption metrics other station-sign families still use for their own captions
## (LandsidePlaces' Closed caption, GateLinksView's build-mode gate captions,
## GapMarkers' sizes); this node draws no caption.
const CAPTION_FONT := 22
const CAPTION_GAP_PX := 4.0
const CAPTION_OUTLINE := 8
const CAPTION_MARGIN_PX := 6.0
const MAX_LIFTS := 64
## Draw order of the sign sprites among the no-depth-test sprites; the
## passenger speech bubbles draw above them (PassengerViews).
const SIGN_PRIORITY := 11
const CAPTION_PRIORITY := 12
const FALLBACK_FOV := 55.0
const FALLBACK_HEIGHT := 1080.0
## The closed sign's disc, for the families that match it (GateLinksView).
const CLOSED_FILL := MarkerIcons.PROBLEM_FILL
const CLOSED_CAPTION := "Closed"
const CLOSED_TEXT := "Closed · no staff on duty"
const PLAYER_CLOSED_TEXT := "Closed by you"
const SPOT_BLOCKED_TEXT := "Closed · staff spot blocked"
const UNREACHABLE_TEXT := "Closed · staff can't reach the %s"
const QUEUE_TEXT := "Queue full · %d waiting"

## Caption text -> its on-screen size in pixels, measured once.
static var _caption_sizes: Dictionary = {}

var sim: PassengerSim
## Unset, the first BuildSession in the tree is taken, looked for until found: the
## lane hints' words show only while it is active.
var build_session: BuildSession
## How many times draw() resized the signs; it skips a draw where nothing changed.
var size_runs := 0

## Station id -> sign, for the queue-full signs and the closed signs.
var _signs: Dictionary = {}
var _closed_signs: Dictionary = {}
## Arch id -> sign, for the arches without a whole lane.
var _hint_signs: Dictionary = {}
var _free_signs: Array[Sprite3D] = []
## A deferred refresh after a room edit is queued.
var _room_sync_pending := false
## Set when a sign was shown; with the camera and view size it decides whether
## draw() has anything to do.
var _dirty := true
var _view_fov := 0.0
var _view_height := 0.0
var _no_captions: Array[Rect2] = []


## Station captions no longer exist, so the need icon count badges
## (NeedCluster.place()) have none to keep clear of. Kept for PassengerViews.
func placed_captions() -> Array[Rect2]:
	return _no_captions


func sign_for(station: int) -> Node3D:
	return _signs.get(station)


## The hover text of `station`'s queue-full sign, or "".
func sign_text(station: int) -> String:
	return _text_of(_signs, station)


## The Closed sign over a desk or scanner with nobody on duty, or null.
func closed_sign_for(station: int) -> Node3D:
	return _closed_signs.get(station)


func closed_text(station: int) -> String:
	return _text_of(_closed_signs, station)


## The lane-incomplete sign over an arch without a whole lane, or null.
func hint_sign_for(arch: int) -> Node3D:
	return _hint_signs.get(arch)


func hint_text(arch: int) -> String:
	return _text_of(_hint_signs, arch)


## The glyph a sign shows (MarkerIcons.Glyph), or -1 for no sign.
static func glyph_of(sign: Node3D) -> int:
	return sign.get_meta(&"glyph", -1) if sign != null else -1


## The closed station `station`'s glyph and words for the closed `reason`
## (a MissSignals reason); `noun` names the station ("desk").
static func closed_look(reason: String, noun: String) -> Array:
	match reason:
		MissSignals.PLAYER_CLOSED_REASON:
			return [MarkerIcons.Glyph.CLOSED, PLAYER_CLOSED_TEXT]
		MissSignals.SPOT_BLOCKED_REASON:
			return [MarkerIcons.Glyph.STAFF_BLOCKED, SPOT_BLOCKED_TEXT]
		MissSignals.UNREACHABLE_REASON:
			return [MarkerIcons.Glyph.STAFF_BLOCKED, UNREACHABLE_TEXT % noun]
	return [MarkerIcons.Glyph.CLOSED, CLOSED_TEXT]


## The closed sign's icon, for the families that match it (LandsidePlaces).
static func _closed_icon() -> Texture2D:
	return MarkerIcons.icon(MarkerIcons.Glyph.CLOSED)


## What `station` is called in its hover text: a "desk", "scanner" or "counter".
static func station_noun(on_sim: PassengerSim, station: int) -> String:
	if on_sim.layout.desks.has(station):
		return "desk"
	if on_sim.layout.scanners.has(station):
		return "scanner"
	return "counter"


func _ready() -> void:
	sync()
	var hover := HoverTarget.find(get_tree())
	if hover != null:
		hover.register_provider(self)


## Also called on every grid edit (graph_changed, or edit_applied for a room
## edit), so a paused edit that removes a station or changes its lane length
## updates the sign at once. The sim rebuilds its
## layout on the same signal and is connected first: bind() connects it in
## the same call that sets sim.grid, so no sync here can see the grid sooner.
func sync() -> void:
	if sim == null or sim.grid == null:
		return
	if not sim.grid.graph_changed.is_connected(_on_graph_changed):
		sim.grid.graph_changed.connect(_on_graph_changed)
	if not sim.grid.edit_applied.is_connected(_on_edit_applied):
		sim.grid.edit_applied.connect(_on_edit_applied)
	_watch_staff()
	var closed := MissSignals.closed_stations(sim)
	var counters := ShopCounters.closed(sim)
	closed.append_array(counters)
	var full := MissSignals.full_stations(sim)
	for station: int in closed:
		full.erase(station)
	for station: int in _signs.keys():
		if not full.has(station):
			_drop_sign(_signs, station)
	for station: int in full:
		var waiting: int = sim.queue_of(station).size() + int(full[station])
		_show_sign(
			_signs, station, "QueueFullSign", MarkerIcons.Glyph.QUEUE_FULL, QUEUE_TEXT % waiting
		)
	for station: int in _closed_signs.keys():
		if not closed.has(station):
			_drop_sign(_closed_signs, station)
	for station in closed:
		var look := closed_look(_closed_reason(station, counters), station_noun(sim, station))
		_show_sign(_closed_signs, station, "ClosedSign", look[0], look[1])
	var incomplete := MissSignals.incomplete_arches(sim)
	for arch: int in _hint_signs.keys():
		if not incomplete.has(arch):
			_drop_sign(_hint_signs, arch)
	for arch in incomplete:
		_show_sign(
			_hint_signs,
			arch,
			"LaneHintSign",
			MarkerIcons.Glyph.TRAY_TABLE,
			MissSignals.lane_hint(sim, arch)
		)


## Keeps every sign SIGN_PX tall on screen; does nothing while the camera's
## field of view, the view's height and the signs are as they were.
func draw() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var fov := camera.fov if camera != null else FALLBACK_FOV
	## The viewport's output height in screen pixels: the visible rect is the
	## layout size, which the content scale (project.godot) makes smaller than
	## the screen, so it is scaled back by the stretch transform.
	var height := FALLBACK_HEIGHT
	if is_inside_tree():
		var view := get_viewport()
		height = view.get_visible_rect().size.y * view.get_stretch_transform().get_scale().y
	if not _dirty and is_equal_approx(fov, _view_fov) and is_equal_approx(height, _view_height):
		return
	_dirty = false
	_view_fov = fov
	_view_height = height
	size_runs += 1
	## World units per screen pixel at one metre: a fixed-size sprite is drawn
	## as if it stood one metre from the camera.
	var unit := 2.0 * tan(deg_to_rad(fov) / 2.0) / height
	for signs: Dictionary in [_signs, _closed_signs, _hint_signs]:
		for station: int in signs:
			(signs[station] as Sprite3D).pixel_size = SIGN_PX * unit / MarkerIcons.SIZE


## The HoverTarget provider contract: every shown sign's screen rect this frame
## (viewport px, as Camera3D.unproject_position gives) and its words. The lane
## hints are reported only in build mode.
func hover_signs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return out
	var side := SIGN_PX / get_viewport().get_stretch_transform().get_scale().y
	var groups := [[_signs, &"queue"], [_closed_signs, &"closed"]]
	if is_building():
		groups.append([_hint_signs, &"hint"])
	for group: Array in groups:
		var signs: Dictionary = group[0]
		for station: int in signs:
			var sign: Sprite3D = signs[station]
			if camera.is_position_behind(sign.global_position):
				continue
			var foot := camera.unproject_position(sign.global_position)
			(
				out
				. append(
					{
						"key": "%s:%d" % [group[1], station],
						"rect": Rect2(foot.x - side / 2.0, foot.y - side, side, side),
						"text": sign.get_meta(&"text", ""),
						"select": station,
					}
				)
			)
	return out


## True while build mode lasts (build_session, else the first BuildSession in
## the tree, looked for until one is found).
func is_building() -> bool:
	if build_session == null and is_inside_tree():
		build_session = find_session(get_tree())
	return build_session != null and build_session.active


## The first BuildSession in `tree`, or null.
static func find_session(tree: SceneTree) -> BuildSession:
	if tree == null:
		return null
	for node in tree.root.find_children("*", "Node", true, false):
		if node is BuildSession:
			return node
	return null


## What a caption covers on screen, in pixels, outline included: the text in
## the default font plus the outline on every side. Measured once per text.
## For the sign families that still draw a caption of their own.
static func caption_size(text: String) -> Vector2:
	if not _caption_sizes.has(text):
		var font := ThemeDB.fallback_font
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAPTION_FONT)
		size.y = font.get_height(CAPTION_FONT)
		_caption_sizes[text] = size + Vector2.ONE * 2.0 * CAPTION_OUTLINE
	return _caption_sizes[text]


## True for a Control that puts something on the screen: a panel, a button, a
## label with text, a picture, a colour fill, or any control with a panel style.
static func draws_something(control: Control) -> bool:
	if is_box(control) or control is ColorRect:
		return true
	if control is Label:
		return not (control as Label).text.is_empty()
	if control is RichTextLabel:
		return not (control as RichTextLabel).text.is_empty()
	if control is TextureRect:
		return (control as TextureRect).texture != null
	return control.has_theme_stylebox_override("panel")


## A panel or a button: it draws a box and its children lie inside it.
static func is_box(control: Control) -> bool:
	return control is Panel or control is PanelContainer or control is BaseButton


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	sync()


## A room edit changes no walk graph, so graph_changed never follows it, and
## with no one hired staff_changed does not either. edit_applied comes before
## the graph_changed of an edit with dirty cells, while the sim layout is still
## the old one, so only a room edit is taken here. A held batch (AreaDrag.clear
## removes objects, rooms and floor together) runs its callbacks before that
## final graph_changed, so the refresh waits for the end of the frame, one run
## however many room edits the batch held.
func _on_edit_applied(_edit: BuildEdit, result: BuildResult) -> void:
	if result.dirty_cells.is_empty() and not _room_sync_pending:
		_room_sync_pending = true
		_sync_after_edit.call_deferred()


func _sync_after_edit() -> void:
	_room_sync_pending = false
	sync()


## Why `station` is closed (a MissSignals reason): for a counter in
## `counters` as for a desk or scanner (MissSignals.staff_reason()).
func _closed_reason(station: int, counters: Array[int]) -> String:
	if not counters.has(station):
		return MissSignals.closed_reason(sim, station)
	return MissSignals.staff_reason(sim, station)


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


static func _text_of(signs: Dictionary, station: int) -> String:
	if not signs.has(station):
		return ""
	return (signs[station] as Node).get_meta(&"text", "")


## The sign of `station` in `signs`, taken from the pool when it has none,
## placed over the station and given its glyph and hover text.
func _show_sign(
	signs: Dictionary, station: int, sign_name: String, glyph: MarkerIcons.Glyph, text: String
) -> void:
	if not signs.has(station):
		signs[station] = _take_sign()
		_dirty = true
	var sign: Sprite3D = signs[station]
	sign.name = sign_name
	sign.texture = MarkerIcons.icon(glyph)
	sign.set_meta(&"glyph", glyph)
	sign.set_meta(&"text", text)
	var point := _sign_point(station)
	if not sign.position.is_equal_approx(point):
		sign.position = point


## Above the middle of the station's footprint, clear of its top.
func _sign_point(station: int) -> Vector3:
	var record := sim.grid.get_object(station)
	var def := BuildCatalog.get_def(StringName(record["def"]))
	var cells := def.footprint(record["anchor"], record["facing"])
	var centre := BuildView.object_transform(sim.grid, cells, record["facing"]).origin
	return centre + Vector3(0.0, def.height + SIGN_LIFT_M, 0.0)


## A billboard drawn over the world whose bottom edge sits on its position.
func _take_sign() -> Sprite3D:
	if not _free_signs.is_empty():
		var reused: Sprite3D = _free_signs.pop_back()
		reused.visible = true
		return reused
	var sign := Sprite3D.new()
	sign.name = "QueueFullSign"
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.fixed_size = true
	sign.no_depth_test = true
	sign.shaded = false
	sign.render_priority = SIGN_PRIORITY
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sign.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	sign.pixel_size = SIGN_PX / FALLBACK_HEIGHT / MarkerIcons.SIZE
	add_child(sign)
	return sign


func _drop_sign(signs: Dictionary, station: int) -> void:
	var sign: Sprite3D = signs[station]
	sign.visible = false
	_free_signs.append(sign)
	signs.erase(station)
	_dirty = true
