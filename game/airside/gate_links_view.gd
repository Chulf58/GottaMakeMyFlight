class_name GateLinksView
extends Node3D
## Shows which exit and stand each gate desk is linked to (Gates 2/4, board
## 51bcad8a), so the automatic link is never hidden (user ruling gates-are-
## placed-gate-desks-each-desk-links-automatically-to: "shown with a visible
## connection, never a manual hook-up").
##
## While build mode lasts (as the guard area and the buildable outline, decision
## plane-guard-area-shows-only-in-build-mode-the-site-paving-ex), every gate
## gets a sky-blue line on the ground from the edge of its desk to its exit and
## on out to where its plane's door will stand (StandPlacement.door_point()), a
## disc at that end and a "Gate A" caption over the desk. The line keeps
## WIDTH_PX on screen at every zoom: a vertex shader pushes each segment's
## corners apart in screen space, a dark rim pass drawn under the fill pass.
## Where the terminal's north wall hides the part out past the exit, a faint
## pass of that part drawn through everything (THROUGH_ALPHA) keeps the link
## readable; the part inside is depth tested only, so it comes out from behind
## its own desk instead of being drawn across it.
##
## A gate desk with no gate (GateDesks.unlinked(), decision gates-1b-as-built-
## gatedesks-link-desks-to-north-exits-as-sti, residual) gets no line and, at
## all times, an unlinked sign over it: the queue-full sign's form (decision
## queue-full-marker-a-red-sign-with-a-queue-full-n-waiting-cap: MarkerIcons'
## rounded square and outline, 56 px on screen, over walls and roof) in the
## closed-station slate, with its own broken-link glyph so the "!" keeps its
## meanings, and a two-line caption naming why (sign_text(): "Unlinked" over
## the short reason, the gate caption's two-line form). The signs are not part
## of MissMarkers' declutter layout, like the wall-gap signs. The sign stands on
## its desk, so its caption sits over the sign, not under it: every frame
## layout_signs() puts each one there, lifted MissMarkers' way clear of its own
## desk, of the seat pieces within GateReach.NEAR_CELLS of it, of every sign and
## of the captions already placed (smoke playtest 11, board f0fbae3c (g): the
## old one-line caption under the sign was drawn across the desk and its seats).
## A sign that meets a wall-gap sign (GapMarkers) slides sideways off it
## instead, its caption still right over it (round 2, user ruling "Separate the
## two signs").
##
## Each gate's stand envelope for its biggest plane (GateDesks.max_class,
## StandEnvelope; decision runway-and-taxi-technical-design-movement-plan-
## analytic-bookings-planned-pauses, section 3) is outlined on the ground in the
## same sky blue, thinner (ENVELOPE_PX), from the stand out along the way north
## to the taxi lane, and the class is the second line of the gate's caption over
## its desk ("Gate A" / "up to large planes"; a third line "N min walk" gives
## the longest walk from security, GateWalk, once bind_walk() has the sim), the
## gate ribbon's form (decision
## gates-2-4-as-built-toon-gate-desk-model-sky-blue-link-line-f). Both show only
## while build mode lasts, with the links. Gates can stand 19 m apart, closer on
## screen than a caption is wide when zoomed out, so every frame in build mode
## layout_captions() lifts each gate caption, in desk order, clear of the gate
## captions already placed and of every sign and caption of `markers` (the
## desks' Closed and "!" signs), the way MissMarkers lifts its staff-spot
## captions (MissMarkers.CAPTION_MARGIN_PX, MAX_LIFTS).
##
## Redrawn on every GateDesks.changed (each graph change). Draws in world space,
## so it sits at the world origin. View only.

const LIFT_M := 0.07
const WIDTH_PX := 8.0
const RIM_PX := 2.0
const LINE_FILL := Color(0.38, 0.68, 0.98)
## The fill's opacity where something stands between the camera and the line.
const THROUGH_ALPHA := 0.6
const END_RADIUS_M := 0.7
const ENVELOPE_PX := 3.0
## The gate caption's second line: its max_class, or no room.
const CLASS_LINE := "up to %s planes"
const NO_CLASS_LINE := "no room for a plane"
## The "Gate A" caption stands this far over the desk's top.
const CAPTION_LIFT_M := 0.5
const UNLINKED_PREFIX := "Unlinked: "
## The unlinked sign's first caption line; the reason is the second.
const UNLINKED_LINE := "Unlinked"
## The gate seats piece, whose seats the unlinked sign's caption keeps off.
const SEAT_ROW := &"seat_row"
## The unlinked sign's caption bottom, in pixels over the sign's point: the
## sign, then CAPTION_GAP_PX.
const SIGN_OVER_PX := MissMarkers.SIGN_PX + MissMarkers.CAPTION_GAP_PX
## The steps an unlinked sign slides sideways off a wall-gap sign by.
const SHIFT_STEP_PX := 14.0
const MAX_SHIFT_STEPS := 16
const FALLBACK_FOV := 55.0
const FALLBACK_HEIGHT := 1080.0
const LINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled%s;
uniform vec4 colour : source_color = vec4(1.0);
uniform float width_px = 8.0;
// CUSTOM0.xyz is the segment's other end, CUSTOM0.w the side (+1 or -1). The
// corner moves half the width to its side and half the width past its own end
// (a square cap, so the bends close), measured in screen pixels.
void vertex() {
	vec4 here = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec4 there = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0));
	vec2 a = here.xy / here.w * VIEWPORT_SIZE;
	vec2 b = there.xy / there.w * VIEWPORT_SIZE;
	vec2 along = normalize(b - a);
	vec2 side = vec2(-along.y, along.x) * CUSTOM0.w;
	vec2 offset_px = (side - along) * width_px * 0.5;
	POSITION = here + vec4(offset_px * 2.0 / VIEWPORT_SIZE * here.w, 0.0, 0.0);
}
void fragment() {
	ALBEDO = colour.rgb;
	ALPHA = colour.a;
}
"""

static var _icon: ImageTexture
## The line shader with the depth test, and without it (the faint pass).
static var _shaders: Dictionary = {}
## Text -> its caption_size(), measured once.
static var _caption_sizes: Dictionary = {}

## The MissMarkers whose signs and captions the gate captions keep clear of.
## Unset, the first MissMarkers in the tree is taken, looked for once.
var markers: Node3D
## The GapMarkers whose wall-gap signs and captions the unlinked signs'
## captions keep clear of (taking a gate's exit away leaves a gap by its
## desk). Unset, the first GapMarkers in the tree is taken, looked for once.
var gaps: Node3D
## The gates' walks from security, for the captions' third line; reads nothing
## until bind_walk() gives it the sim.
var walk := GateWalk.new()
## How many times layout_signs() ran its layout rather than answering from the
## cache (tests read it).
var sign_layouts := 0
var _markers_looked := false
var _walk_queued := false

var _grid: BuildGrid
var _gates: GateDesks
## Lines, end discs and gate captions: shown only while build mode lasts.
var _links := Node3D.new()
var _through := MeshInstance3D.new()
var _rim := MeshInstance3D.new()
var _fill := MeshInstance3D.new()
var _envelope := MeshInstance3D.new()
var _envelope_paths: Array[PackedVector3Array] = []
var _ends: Array[MeshInstance3D] = []
var _captions: Array[Label3D] = []
var _signs: Array[Sprite3D] = []
## Per entry of _signs: the boxes (8 world corners each) its caption keeps
## clear of, its own desk first.
var _sign_boxes: Array = []
## The screen rectangles of the shown signs and their captions, from the last
## layout_signs(); the gate captions keep clear of them.
var _sign_rects: Array[Rect2] = []
## What the cached layout_signs() layout was made from, and its result: while
## the key is the same the layout is too. Bumped by rebuild() (signs, texts,
## obstacle boxes).
var _layout_key: Array = []
var _layout_placed: Array[Rect2] = []
var _signs_revision := 0
var _paths: Array[PackedVector3Array] = []
var _unit := 0.0


func _init() -> void:
	_links.name = "Links"
	_links.visible = false
	add_child(_links)
	_through.name = "LineThrough"
	_rim.name = "LineRim"
	_fill.name = "LineFill"
	var faint := Color(LINE_FILL, THROUGH_ALPHA)
	_through.material_override = _line_material(faint, WIDTH_PX, 0, false)
	_rim.material_override = _line_material(MarkerIcons.OUTLINE, WIDTH_PX + 2.0 * RIM_PX, 1)
	_fill.material_override = _line_material(LINE_FILL, WIDTH_PX, 2)
	_envelope.name = "Envelopes"
	_envelope.material_override = _line_material(LINE_FILL, ENVELOPE_PX, 2)
	for line in [_through, _rim, _fill, _envelope]:
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.extra_cull_margin = 4.0
		_links.add_child(line)


## Follows `on_gates`' links on `on_grid`.
func bind(on_grid: BuildGrid, on_gates: GateDesks) -> void:
	if _gates != null and _gates.changed.is_connected(rebuild):
		_gates.changed.disconnect(rebuild)
	_grid = on_grid
	_gates = on_gates
	_gates.changed.connect(rebuild)
	rebuild()


## Shows the lines, end discs and gate captions while build mode lasts.
func set_building(on: bool) -> void:
	_links.visible = on


func is_building() -> bool:
	return _links.visible


## The ground path of `binding`'s link on `grid`: where the way from the desk's
## footprint centre to the exit's cell centre leaves the footprint (the desk's
## edge), the exit's cell centre, and where the plane's door stands at its
## stand, each LIFT_M over the grid's floor.
static func link_points(grid: BuildGrid, binding: Dictionary) -> PackedVector3Array:
	var cells := GateDesks.desk_footprint(grid, binding["desk"])
	var area := Rect2(Vector2(cells[0]), Vector2.ONE)
	for cell in cells:
		area = area.merge(Rect2(Vector2(cell), Vector2.ONE))
	var origin := Vector2(grid.origin.x, grid.origin.z)
	var centre := area.get_center() + origin
	var exit_3d := grid.cell_to_world(grid.get_object(binding["exit"])["anchor"])
	var exit := Vector2(exit_3d.x, exit_3d.z)
	var edge := (
		centre + (exit - centre) * _leave_t(Rect2(area.position + origin, area.size), centre, exit)
	)
	var door := StandPlacement.door_point(StandPlacement.for_exit(grid, binding["exit"]))
	var y := grid.origin.y + LIFT_M
	return PackedVector3Array(
		[Vector3(edge.x, y, edge.y), Vector3(exit.x, y, exit.y), Vector3(door.x, y, door.z)]
	)


## The fraction of the way from `from` (inside `box`) to `to` at which it
## leaves `box`, at most 1.
static func _leave_t(box: Rect2, from: Vector2, to: Vector2) -> float:
	var t := 1.0
	var d := to - from
	for axis in 2:
		if d[axis] > 0.0:
			t = minf(t, (box.end[axis] - from[axis]) / d[axis])
		elif d[axis] < 0.0:
			t = minf(t, (box.position[axis] - from[axis]) / d[axis])
	return t


## Why a desk is unlinked, short, from a GateDesks.unlinked() entry.
static func reason_text(reason: Dictionary) -> String:
	match reason["why"]:
		GateDesks.Unlinked.NO_EXIT:
			return "no north exit in %d cells" % GateDesks.LINK_CELLS
		GateDesks.Unlinked.EXIT_TAKEN:
			return "Gate %s uses the exit" % reason["gate"]
		GateDesks.Unlinked.STAND_OVERLAP:
			return "stand would overlap Gate %s" % reason["gate"]
		GateDesks.Unlinked.NO_ROOM:
			return "no room for a plane"
		GateDesks.Unlinked.ROUTE_BLOCKED:
			return "way to the lane blocked"
	return "every gate letter in use"


## The reason on one line ("Unlinked: ..."), as the desk card's status shows it.
static func caption_for(reason: Dictionary) -> String:
	return UNLINKED_PREFIX + reason_text(reason)


## What the sign over an unlinked desk says: "Unlinked", then the reason.
static func sign_text(reason: Dictionary) -> String:
	return "%s\n%s" % [UNLINKED_LINE, reason_text(reason)]


## Draws the links and the unlinked signs again from the gates.
func rebuild() -> void:
	_paths.clear()
	_signs_revision += 1
	var gate_texts: Array[String] = []
	var desk_tops: Array[Vector3] = []
	if _grid != null and _gates != null:
		for binding in _gates.bindings:
			var path := link_points(_grid, binding)
			_paths.append(path)
			gate_texts.append(_caption_for(binding["gate"]))
			desk_tops.append(_desk_top(binding["desk"]))
	_draw_lines()
	_draw_ends()
	_draw_envelopes()
	while _captions.size() < gate_texts.size():
		_captions.append(_make_caption("GateCaption", VERTICAL_ALIGNMENT_BOTTOM, 0.0))
		_links.add_child(_captions[-1])
	for i in _captions.size():
		_captions[i].visible = i < gate_texts.size()
		if i < gate_texts.size():
			_captions[i].text = gate_texts[i]
			_captions[i].position = desk_tops[i] + Vector3.UP * CAPTION_LIFT_M
	var unlinked: Dictionary = _gates.unlinked() if _gates != null else {}
	var desks: Array = unlinked.keys()
	desks.sort()
	while _signs.size() < desks.size():
		_signs.append(_make_sign())
	_sign_boxes.clear()
	for i in _signs.size():
		_signs[i].visible = i < desks.size()
		_sign_boxes.append(sign_obstacles(_grid, desks[i]) if i < desks.size() else [])
		if i < desks.size():
			_signs[i].position = _desk_top(desks[i]) + Vector3.UP * MissMarkers.SIGN_LIFT_M
			_signs[i].set_meta("desk", desks[i])
			caption_of(_signs[i]).text = sign_text(unlinked[desks[i]])
	update_sizes(true)


## The outline of the `plane_class` envelope at `stand` (StandEnvelope.rects():
## the swing square and the way north to the lane, as one shape) at height `y`,
## a closed loop.
static func envelope_outline(
	stand: Dictionary, plane_class: String, y: float
) -> PackedVector3Array:
	var parts := StandEnvelope.rects(stand, plane_class)
	var swing: Rect2 = parts[0]
	var way: Rect2 = parts[1]
	var corners: Array[Vector2] = [
		Vector2(swing.position.x, swing.end.y),
		swing.position,
		Vector2(way.position.x, swing.position.y),
		way.position,
		Vector2(way.end.x, way.position.y),
		Vector2(way.end.x, swing.position.y),
		Vector2(swing.end.x, swing.position.y),
		swing.end,
		Vector2(swing.position.x, swing.end.y),
	]
	var out := PackedVector3Array()
	for corner in corners:
		out.append(Vector3(corner.x, y, corner.y))
	return out


## The envelope outlines drawn, one per gate that holds a plane, in desk order.
func envelope_paths() -> Array[PackedVector3Array]:
	return _envelope_paths.duplicate()


## The caption over gate `gate`'s desk: "Gate A", then its biggest plane
## (GateDesks.max_class, "" for none) on a second line, then its walk from
## security ("12 min walk") on a third when `walk_minutes` is one (GateWalk).
static func caption_text(
	gate: String, plane_class: String, walk_minutes := GateWalk.NO_ROUTE
) -> String:
	var second := CLASS_LINE % plane_class if plane_class != "" else NO_CLASS_LINE
	var text := "Gate %s\n%s" % [gate, second]
	var third := GateWalk.caption_line(walk_minutes)
	return text if third == "" else "%s\n%s" % [text, third]


## Reads the gates' walks from security off `sim` for the captions' third line.
func bind_walk(sim: PassengerSim) -> void:
	walk.bind(sim, _gates)
	if not walk.changed.is_connected(_queue_walk):
		walk.changed.connect(_queue_walk)
	refresh_walk()


## Sets each gate caption's text again from the gate's class and walk. Event
## driven (GateWalk.changed, through _queue_walk()), never called per frame.
func refresh_walk() -> void:
	_walk_queued = false
	if _gates == null:
		return
	for i in mini(_captions.size(), _gates.bindings.size()):
		var text := _caption_for(_gates.bindings[i]["gate"])
		if _captions[i].text != text:
			_captions[i].text = text


## One refresh on the next idle frame, however many changes came, so the sim
## has settled the whole edit (layout, gate links) before the figures are read.
func _queue_walk() -> void:
	if not _walk_queued:
		_walk_queued = true
		refresh_walk.call_deferred()


func _caption_for(gate: String) -> String:
	return caption_text(gate, _gates.max_class(gate), walk.minutes(gate))


func envelope_node() -> MeshInstance3D:
	return _envelope


## Each gate's max_class envelope outline.
func _draw_envelopes() -> void:
	_envelope_paths.clear()
	if _grid != null and _gates != null:
		var y := _grid.origin.y + LIFT_M
		for binding in _gates.bindings:
			var plane_class := _gates.max_class(binding["gate"])
			if plane_class != "":
				var stand := StandPlacement.for_exit(_grid, binding["exit"])
				_envelope_paths.append(envelope_outline(stand, plane_class, y))
	_envelope.mesh = segments_mesh(_envelope_paths)


## The link paths drawn, one per gate in desk order (for probes and tests).
func paths() -> Array[PackedVector3Array]:
	return _paths.duplicate()


## The shown "Gate X" captions.
func gate_captions() -> Array[Label3D]:
	var out: Array[Label3D] = []
	for caption in _captions:
		if caption.visible:
			out.append(caption)
	return out


## The shown unlinked signs, in desk id order; each has meta "desk".
func signs() -> Array[Sprite3D]:
	var out: Array[Sprite3D] = []
	for marker in _signs:
		if marker.visible:
			out.append(marker)
	return out


func caption_of(marker: Sprite3D) -> Label3D:
	return marker.get_node("Caption") as Label3D


## The end discs shown, one per gate.
func ends() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for disc in _ends:
		if disc.visible:
			out.append(disc)
	return out


func line_node() -> MeshInstance3D:
	return _fill


## The faint pass drawn through walls (the part out past each exit).
func through_node() -> MeshInstance3D:
	return _through


func _process(_delta: float) -> void:
	update_sizes()
	layout_signs()
	if _links.visible:
		layout_captions()


## The screen size in pixels of a caption saying `text` at
## MissMarkers.CAPTION_FONT, every line, outline included, as
## MissMarkers.caption_size() measures its own one-line captions.
static func caption_size(text: String) -> Vector2:
	if not _caption_sizes.has(text):
		var font := ThemeDB.fallback_font
		var lines := text.split("\n")
		var width := 0.0
		for line in lines:
			var line_size := font.get_string_size(
				line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, MissMarkers.CAPTION_FONT
			)
			width = maxf(width, line_size.x)
		var size := Vector2(width, font.get_height(MissMarkers.CAPTION_FONT) * lines.size())
		_caption_sizes[text] = size + Vector2.ONE * 2.0 * MissMarkers.CAPTION_OUTLINE
	return _caption_sizes[text]


## Lifts each shown gate caption, in desk order, by the fewest steps (its height
## plus MissMarkers.CAPTION_MARGIN_PX, at most MissMarkers.MAX_LIFTS) at which,
## grown by that margin, it meets none of the gate captions already placed and
## none of the shown signs and captions of `markers` and none of the HUD's
## rectangles (HudRects), and still on screen. With no clear lift it stays on
## its desk; a caption that then touches the HUD (the sign near the top of the
## screen, under the top row) slides clear of it toward the middle of the view,
## as the room labels do (RoomLabelLayout.slide_clear, decision
## status-banner-fades-under-the-build-ghost-room-labels-slide). Returns the
## screen rectangles (pixels) placed, in desk order.
func layout_captions() -> Array[Rect2]:
	var placed: Array[Rect2] = []
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return placed
	_find_markers()
	var to_output := get_viewport().get_stretch_transform().get_scale().y
	var view_size := get_viewport().get_visible_rect().size * to_output
	var hud := HudRects.collect(self, to_output)
	var blocked := marker_rects(markers, camera, to_output) + _sign_rects + hud
	for caption in gate_captions():
		caption.offset = Vector2.ZERO
		if camera.is_position_behind(caption.global_position):
			continue
		var point := camera.unproject_position(caption.global_position) * to_output
		var size := caption_size(caption.text)
		var step := size.y + MissMarkers.CAPTION_MARGIN_PX
		var home := Rect2(point.x - size.x / 2.0, point.y - size.y, size.x, size.y)
		var chosen := home
		for lifts in MissMarkers.MAX_LIFTS:
			var rect := Rect2(home.position - Vector2(0.0, step * lifts), size)
			var padded := rect.grow(MissMarkers.CAPTION_MARGIN_PX)
			if (
				rect.position.y >= 0.0
				and not (placed + blocked).any(
					func(other: Rect2) -> bool: return padded.intersects(other)
				)
			):
				chosen = rect
				break
		var spot := RoomLabelLayout.slide_clear(chosen, hud, view_size)
		if spot.size != Vector2.ZERO:
			chosen = spot
		caption.offset = Vector2(
			chosen.position.x - home.position.x, home.position.y - chosen.position.y
		)
		placed.append(chosen)
	return placed


## Takes the first MissMarkers and GapMarkers in the tree as `markers` and
## `gaps` when they are unset, looked for once.
func _find_markers() -> void:
	if _markers_looked:
		return
	_markers_looked = true
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if markers == null and node is MissMarkers:
			markers = node
		elif gaps == null and node is GapMarkers:
			gaps = node


## Places each shown unlinked sign and its caption, in desk order. The caption
## stands over its sign (bottom-aligned CAPTION_GAP_PX over the sign's top).
## Where the sign meets a wall-gap sign or caption of `gaps` on screen (taking
## a gate's exit away leaves one by its desk), the sign slides sideways off it
## (user ruling, board f0fbae3c (g) round 2: "Separate the two signs"), first
## away from the wall-gap mark, by the fewest SHIFT_STEP_PX steps (at most
## MAX_SHIFT_STEPS each way) at which the sign, grown by
## MissMarkers.CAPTION_MARGIN_PX, meets no mark of `gaps` or `markers`, no other
## sign and no seat row, and its caption, right over it and grown the same,
## meets none of those, none of its sign_obstacles() boxes and none of the
## captions already placed. Otherwise the sign stays and its caption is lifted
## by the fewest steps (its height plus the margin, at most
## MissMarkers.MAX_LIFTS) at which it meets none of them; with no clear lift it
## stays right over its sign, so the reason always shows. Returns the caption
## rectangles (pixels) placed, in desk order, and keeps them with the signs'
## own for layout_captions(). The layout is kept (as MissMarkers.draw() keeps
## its own) while its inputs are the same: the camera (identity, transform,
## field of view), the viewport, the signs (rebuild(), their places and
## visibility) and the rectangles of the marks of `markers` and `gaps`, which
## can appear, move or vanish with the camera still. The returned array is the
## kept one, so a caller must not change it.
func layout_signs() -> Array[Rect2]:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or signs().is_empty():
		_sign_rects.clear()
		_layout_key = []
		_layout_placed = []
		return _layout_placed
	_find_markers()
	var view := get_viewport()
	var to_output := view.get_stretch_transform().get_scale().y
	var gap_marks := marker_rects(gaps, camera, to_output)
	var shown_markers := marker_rects(markers, camera, to_output) + gap_marks
	var key := [
		camera.get_instance_id(),
		camera.global_transform,
		camera.fov,
		to_output,
		view.get_visible_rect().size,
		_signs_revision,
		_sign_state(),
		gap_marks,
		shown_markers,
	]
	if key == _layout_key:
		return _layout_placed
	_layout_key = key
	sign_layouts += 1
	var placed: Array[Rect2] = []
	_sign_rects.clear()
	# Each shown sign's icon, by _signs index, where it stands unshifted.
	var icons := {}
	for i in _signs.size():
		var marker := _signs[i]
		marker.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
		caption_of(marker).offset = Vector2(0.0, SIGN_OVER_PX)
		if marker.visible and not camera.is_position_behind(marker.global_position):
			var foot := camera.unproject_position(marker.global_position) * to_output
			var side := MissMarkers.SIGN_PX
			icons[i] = Rect2(foot.x - side / 2.0, foot.y - side, side, side)
	for i in _signs.size():
		if not icons.has(i):
			continue
		var caption := caption_of(_signs[i])
		var blocked: Array[Rect2] = shown_markers.duplicate()
		for other: int in icons:
			if other != i:
				blocked.append(icons[other])
		var boxes: Array[Rect2] = []
		for corners: PackedVector3Array in _sign_boxes[i]:
			var box := screen_box(camera, corners, to_output)
			if box.has_area():
				boxes.append(box)
		var size := caption_size(caption.text)
		var icon: Rect2 = icons[i]
		var shift := sign_shift(icon, size, gap_marks, placed + blocked, boxes)
		var chosen := sign_caption_home(icon, size, shift)
		if shift == 0.0:
			# Not moved: the caption is lifted, MissMarkers' way, when its home
			# over the sign is taken.
			var step := size.y + MissMarkers.CAPTION_MARGIN_PX
			var home := chosen
			for lifts in MissMarkers.MAX_LIFTS:
				var rect := Rect2(home.position - Vector2(0.0, step * lifts), size)
				if not _meets_any(
					rect.grow(MissMarkers.CAPTION_MARGIN_PX), placed + blocked + boxes
				):
					chosen = rect
					break
			caption.offset.y = SIGN_OVER_PX + home.position.y - chosen.position.y
		else:
			_signs[i].offset.x = shift * MarkerIcons.SIZE / MissMarkers.SIGN_PX
			caption.offset.x = shift
			icons[i] = Rect2(icon.position + Vector2(shift, 0.0), icon.size)
		placed.append(chosen)
	_sign_rects.assign(icons.values())
	_sign_rects.append_array(placed)
	_layout_placed = placed
	return _layout_placed


## Where each sign stands in the world, INF while it is hidden: what the
## layout_signs() cache needs of the signs beyond rebuild().
func _sign_state() -> PackedVector3Array:
	var out := PackedVector3Array()
	for marker in _signs:
		out.append(marker.global_position if marker.visible else Vector3.INF)
	return out


## How far (pixels, + right) an unlinked sign at `icon` slides sideways off the
## wall-gap marks `gap_marks`, its caption of `size` right over it: 0 when the
## sign meets none of them, else the fewest SHIFT_STEP_PX steps, away from the
## first mark it meets before toward it, at which the sign grown by the margin
## meets no mark, nothing in `blocked` and none of `boxes` but the first (its
## own desk, which the sign stands over), and the caption grown the same meets
## none of those nor its own desk. 0 when no shift up to MAX_SHIFT_STEPS clears.
static func sign_shift(
	icon: Rect2, size: Vector2, gap_marks: Array[Rect2], blocked: Array[Rect2], boxes: Array[Rect2]
) -> float:
	var margin := MissMarkers.CAPTION_MARGIN_PX
	var met := gap_marks.filter(
		func(mark: Rect2) -> bool: return icon.grow(margin).intersects(mark)
	)
	if met.is_empty():
		return 0.0
	var away := 1.0 if icon.get_center().x >= (met[0] as Rect2).get_center().x else -1.0
	var others: Array[Rect2] = gap_marks + blocked
	for steps in range(1, MAX_SHIFT_STEPS + 1):
		for side in [away, -away]:
			var shift: float = side * steps * SHIFT_STEP_PX
			var moved := Rect2(icon.position + Vector2(shift, 0.0), icon.size)
			var home := sign_caption_home(icon, size, shift)
			if _meets_any(moved.grow(margin), others + boxes.slice(1)):
				continue
			if not _meets_any(home.grow(margin), others + boxes):
				return shift
	return 0.0


## The caption rectangle of `size` right over a sign at `icon` slid `shift`
## pixels sideways: centred over it, its bottom CAPTION_GAP_PX over its top.
static func sign_caption_home(icon: Rect2, size: Vector2, shift: float) -> Rect2:
	var centre := icon.get_center().x + shift
	var bottom := icon.position.y - MissMarkers.CAPTION_GAP_PX
	return Rect2(centre - size.x / 2.0, bottom - size.y, size.x, size.y)


static func _meets_any(rect: Rect2, others: Array[Rect2]) -> bool:
	return others.any(func(other: Rect2) -> bool: return rect.intersects(other))


## The boxes (8 world corners each) the caption of unlinked desk `desk`'s sign
## keeps clear of on `grid`: the desk itself, then every gate seat row
## (SEAT_ROW) and other piece with seats that has a cell within
## GateReach.NEAR_CELLS of the desk's footprint, each from the floor up to its
## catalog height.
static func sign_obstacles(grid: BuildGrid, desk: int) -> Array[PackedVector3Array]:
	var footprint := GateDesks.desk_footprint(grid, desk)
	var near := _cells_rect(footprint).grow(GateReach.NEAR_CELLS)
	var out: Array[PackedVector3Array] = [
		_box(grid, footprint, BuildCatalog.get_def(GateDesks.DESK).height)
	]
	for id in grid.object_ids():
		var record := grid.get_object(id)
		var def := BuildCatalog.get_def(record["def"])
		if id == desk or def == null or (def.id != SEAT_ROW and def.seats.is_empty()):
			continue
		var cells := def.footprint(record["anchor"], record["facing"])
		if near.intersects(_cells_rect(cells)):
			out.append(_box(grid, cells, def.height))
	return out


static func _cells_rect(cells: Array[Vector2i]) -> Rect2i:
	var area := Rect2i(cells[0], Vector2i.ONE)
	for cell in cells:
		area = area.merge(Rect2i(cell, Vector2i.ONE))
	return area


## The 8 world corners of `cells` on `grid`, from the floor up to `height`.
static func _box(grid: BuildGrid, cells: Array[Vector2i], height: float) -> PackedVector3Array:
	var area := _cells_rect(cells)
	var out := PackedVector3Array()
	for y in [0.0, height]:
		for x in [area.position.x, area.end.x]:
			for z in [area.position.y, area.end.y]:
				out.append(grid.origin + Vector3(x, y, z))
	return out


## The screen rectangle (pixels, `to_output` per camera unit) around `corners`
## seen by `camera`; empty when any corner is behind the camera.
static func screen_box(camera: Camera3D, corners: PackedVector3Array, to_output: float) -> Rect2:
	var box := Rect2()
	for i in corners.size():
		if camera.is_position_behind(corners[i]):
			return Rect2()
		var point := camera.unproject_position(corners[i]) * to_output
		box = Rect2(point, Vector2.ZERO) if i == 0 else box.expand(point)
	return box


## The screen rectangles (pixels, `to_output` per camera unit) of every shown
## fixed-size sign (Sprite3D) and caption (Label3D, MissMarkers.CAPTION_FONT)
## under `root` seen by `camera`: what MissMarkers draws. Empty for no root.
static func marker_rects(root: Node, camera: Camera3D, to_output: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if root == null:
		return out
	var height := camera.get_viewport().get_visible_rect().size.y * to_output
	var unit := 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / height
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var shown := node as Node3D
		if not shown.is_visible_in_tree() or camera.is_position_behind(shown.global_position):
			continue
		var point := camera.unproject_position(shown.global_position) * to_output
		if shown is Sprite3D and (shown as Sprite3D).fixed_size:
			var sprite := shown as Sprite3D
			if sprite.texture == null:
				continue
			var scale := sprite.pixel_size / unit
			var size := sprite.texture.get_size() * scale
			var centre := point + Vector2(sprite.offset.x, -sprite.offset.y) * scale
			out.append(Rect2(centre - size / 2.0, size))
		elif shown is Label3D and (shown as Label3D).fixed_size:
			var label := shown as Label3D
			var size := caption_size(label.text)
			var shift := label.offset * label.pixel_size / unit
			var bottom := point.y - shift.y
			match label.vertical_alignment:
				VERTICAL_ALIGNMENT_TOP:
					bottom += size.y
				VERTICAL_ALIGNMENT_CENTER:
					bottom += size.y / 2.0
			var left := point.x + shift.x - size.x / 2.0
			out.append(Rect2(left, bottom - size.y, size.x, size.y))
	return out


## Keeps the signs MissMarkers.SIGN_PX tall and the captions at their font
## size on screen, as GapMarkers sizes its signs; resizes only when the screen
## unit changed, or when `force`.
func update_sizes(force := false) -> void:
	var fov := FALLBACK_FOV
	var height := FALLBACK_HEIGHT
	if is_inside_tree():
		var view := get_viewport()
		var camera := view.get_camera_3d()
		if camera != null:
			fov = camera.fov
		height = view.get_visible_rect().size.y * view.get_stretch_transform().get_scale().y
	if height <= 0.0:
		return
	var unit := 2.0 * tan(deg_to_rad(fov) / 2.0) / height
	if not force and unit == _unit:
		return
	_unit = unit
	for marker in _signs:
		marker.pixel_size = MissMarkers.SIGN_PX * unit / MarkerIcons.SIZE
		caption_of(marker).pixel_size = unit
	for caption in _captions:
		caption.pixel_size = unit


## The top centre of gate desk `desk`: its footprint centre at the catalog
## height.
func _desk_top(desk: int) -> Vector3:
	var cells := GateDesks.desk_footprint(_grid, desk)
	var at := Vector3.ZERO
	for cell in cells:
		at += _grid.cell_to_world(cell)
	at /= cells.size()
	at.y = _grid.origin.y + BuildCatalog.get_def(GateDesks.DESK).height
	return at


## The whole paths for the rim and fill passes; for the faint pass only the
## part outside, from the exit's wall line (half a cell out from its centre)
## to the plane door, so nothing inside is drawn over.
func _draw_lines() -> void:
	var mesh := segments_mesh(_paths)
	_rim.mesh = mesh
	_fill.mesh = mesh
	var outside: Array[PackedVector3Array] = []
	for path in _paths:
		outside.append(PackedVector3Array([path[1].move_toward(path[2], 0.5), path[2]]))
	_through.mesh = segments_mesh(outside)


## One quad per segment of each of `paths`; every vertex carries the segment's
## other end and its side in CUSTOM0 for the line shader.
static func segments_mesh(paths: Array[PackedVector3Array]) -> ArrayMesh:
	var verts := PackedVector3Array()
	var custom := PackedFloat32Array()
	var index := PackedInt32Array()
	for path in paths:
		for i in path.size() - 1:
			var a := path[i]
			var b := path[i + 1]
			var base := verts.size()
			# Seen along a -> b: a's +1 corner and b's -1 corner are on one side.
			for corner in [[a, b, 1.0], [a, b, -1.0], [b, a, 1.0], [b, a, -1.0]]:
				verts.append(corner[0])
				var other: Vector3 = corner[1]
				custom.append_array(PackedFloat32Array([other.x, other.y, other.z, corner[2]]))
			index.append_array(
				PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3])
			)
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_INDEX] = index
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


## A disc at each path's far end (the plane door's place), rim under fill.
func _draw_ends() -> void:
	while _ends.size() < _paths.size():
		var disc := MeshInstance3D.new()
		disc.name = "LinkEnd%d" % _ends.size()
		var rim := CylinderMesh.new()
		rim.top_radius = END_RADIUS_M + 0.15
		rim.bottom_radius = rim.top_radius
		rim.height = 0.02
		rim.material = _flat(MarkerIcons.OUTLINE)
		disc.mesh = rim
		var fill := MeshInstance3D.new()
		var top := CylinderMesh.new()
		top.top_radius = END_RADIUS_M
		top.bottom_radius = END_RADIUS_M
		top.height = 0.02
		top.material = _flat(LINE_FILL)
		fill.mesh = top
		fill.position.y = 0.01
		disc.add_child(fill)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_links.add_child(disc)
		_ends.append(disc)
	for i in _ends.size():
		_ends[i].visible = i < _paths.size()
		if i < _paths.size():
			_ends[i].position = _paths[i][-1]


static func _flat(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	return material


## A line pass: `colour` at `width_px` on screen, drawn in `priority` order,
## hidden behind what stands in front of it when `depth_test`.
static func _line_material(
	colour: Color, width_px: float, priority: int, depth_test := true
) -> ShaderMaterial:
	if not _shaders.has(depth_test):
		var shader := Shader.new()
		shader.code = LINE_SHADER % ("" if depth_test else ", depth_test_disabled")
		_shaders[depth_test] = shader
	var material := ShaderMaterial.new()
	material.shader = _shaders[depth_test]
	material.set_shader_parameter("colour", colour)
	material.set_shader_parameter("width_px", width_px)
	material.render_priority = priority
	return material


func _make_caption(node_name: String, align: VerticalAlignment, gap_px: float) -> Label3D:
	var caption := Label3D.new()
	caption.name = node_name
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.fixed_size = true
	caption.no_depth_test = true
	caption.render_priority = 12
	caption.outline_render_priority = 11
	caption.font_size = MissMarkers.CAPTION_FONT
	caption.outline_size = MissMarkers.CAPTION_OUTLINE
	caption.outline_modulate = MarkerIcons.OUTLINE
	caption.vertical_alignment = align
	caption.offset = Vector2(0.0, gap_px)
	return caption


func _make_sign() -> Sprite3D:
	var marker := Sprite3D.new()
	marker.name = "UnlinkedSign"
	marker.texture = unlinked_icon()
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.fixed_size = true
	marker.no_depth_test = true
	marker.shaded = false
	marker.render_priority = 11
	marker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	marker.offset = Vector2(0.0, MarkerIcons.SIZE / 2.0)
	# Over the sign: its bottom edge a gap over the sign's top (layout_signs()
	# lifts it further when something is in the way).
	var caption := _make_caption("Caption", VERTICAL_ALIGNMENT_BOTTOM, SIGN_OVER_PX)
	marker.add_child(caption)
	add_child(marker)
	return marker


## The unlinked icon, painted once: MarkerIcons' rounded square and outline in
## the closed-station slate (MissMarkers.CLOSED_FILL), with a white broken chain
## link, drawn with MarkerIcons.shape_distance and segment_distance.
static func unlinked_icon() -> Texture2D:
	if _icon != null:
		return _icon
	var size := MarkerIcons.SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size / 2.0
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5 - half, y + 0.5 - half)
			var edge := MarkerIcons.shape_distance(p)
			var cover := clampf(0.5 - edge, 0.0, 1.0)
			if cover <= 0.0:
				img.set_pixel(x, y, Color(MarkerIcons.OUTLINE, 0.0))
				continue
			var inside := clampf(0.5 - (edge + MarkerIcons.OUTLINE_PX), 0.0, 1.0)
			var colour := MarkerIcons.OUTLINE.lerp(MissMarkers.CLOSED_FILL, inside)
			var glyph := clampf(0.5 - _broken_link(p), 0.0, 1.0) * inside
			colour = colour.lerp(MarkerIcons.GLYPH, glyph)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	_icon = ImageTexture.create_from_image(img)
	return _icon


## Signed distance in pixels to the white broken link: two chain links on a
## diagonal with a gap between them, and a short spark either side of the gap.
## Image y runs down.
static func _broken_link(p: Vector2) -> float:
	var ring_r := 12.0
	var stroke := 5.0
	var left := absf(
		MarkerIcons.segment_distance(p, Vector2(-32.0, 22.0), Vector2(-14.0, 4.0)) - ring_r
	)
	var right := absf(
		MarkerIcons.segment_distance(p, Vector2(14.0, -4.0), Vector2(32.0, -22.0)) - ring_r
	)
	var links := minf(left, right) - stroke
	var sparks := minf(
		MarkerIcons.segment_distance(p, Vector2(-14.0, -14.0), Vector2(-24.0, -26.0)),
		MarkerIcons.segment_distance(p, Vector2(14.0, 14.0), Vector2(24.0, 26.0))
	)
	return minf(links, sparks - 4.0)
