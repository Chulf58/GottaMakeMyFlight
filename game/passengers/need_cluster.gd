class_name NeedCluster
extends RefCounted
## Count clusters of need icons (user ruling crowd-need-display-mood-overlay-
## gains-hunger-toilet-and-bore, point 2: in normal view, need icons of the
## same kind that sit close together on screen merge into one bigger icon with
## a count; decision need-icon-count-clusters-technical-design-screen-space-
## clust). Pure logic on screen points, no scene: PassengerViews projects each
## shown icon and calls update() once a frame, then hides the members' icons
## (mask()) and draws one badge per cluster where place() puts it.
##
## Clusters are per need kind and keep a view-only id, a representative
## passenger and a member set from frame to frame, so a moving crowd keeps its
## badge. A free icon joins a cluster within ADMIT_PX of its representative; a
## member stays until it is past RETAIN_PX, so an icon at the edge does not
## flicker in and out. A new cluster needs FORM_MIN members and lives down to
## KEEP_MIN. A member leaves at once when its icon stops showing. Two clusters
## whose representatives come within ADMIT_PX merge under the bigger one's id;
## on a split the group around the representative keeps the id. Every tie is
## broken by the lower passenger id, so the input order never matters.
##
## The settling is spatial (the two radii), never a frame or time count: the
## state holds no tick and is cleared on a load and when the icons hide.

## A free icon joins a cluster within this distance of its representative.
## Tuned on the need-clusters plates at mid zoom (0.7 of the home distance):
## queue icons stand 35 to 45 px apart and the kinds interleave, so icons of one
## kind are often 80 to 120 px apart; 34 and then 60 px left the queues
## carpeted with icons.
const ADMIT_PX := 90.0
## A member stays in its cluster within this distance of the representative
## (at least 12 px past ADMIT_PX, so an icon at the edge does not flicker).
const RETAIN_PX := 110.0
## Members a new cluster needs.
const FORM_MIN := 3
## Members an existing cluster keeps living with.
const KEEP_MIN := 2
## The furthest place() moves a badge from its anchor along x and y: a
## badge's size and a bit, so three badges on one crowd can stand apart.
const MAX_SHIFT_PX := 72.0
## The step between the spots place() tries.
const SHIFT_STEP_PX := 12.0

## A badge's icon on screen, in output pixels: 1.6 times a need icon.
const BADGE_PX := NeedIcons.ICON_PX * 1.6
## The count's font size on screen (one em), in output pixels: its digits stand
## about 20 px tall in the HUD's rounded bold font.
const COUNT_EM_PX := 28.0
## The count sits on a cream pill with the navy outline (decision hud-look-warm-
## cozy-cream-cards-with-a-dark-outline-toon-pale): its height, the space each
## side of the text and the outline width, in screen pixels.
const PILL_H_PX := 30.0
const PILL_PAD_PX := 8.0
const PILL_OUTLINE_PX := 3.0
## Pill texels per screen pixel.
const PILL_TEXELS := 2.0
## The pill's centre from the badge icon's centre, screen pixels (y down): over
## the icon's lower right corner, like a notification count.
const COUNT_AT := Vector2(22.0, 18.0)
## The count label's font size; its pixel_size sets COUNT_EM_PX on screen.
const COUNT_FONT := 56
## The HUD theme, for its font.
const HUD_THEME := "res://ui/hud_theme.tres"
## The badge pool's node name under PassengerViews and a badge's count label
## and pill.
const ROOT := "NeedBadges"
const COUNT := "Count"
const PILL := "Pill"

static var _font: Font
## Pill width in screen pixels -> its texture.
static var _pills: Dictionary = {}
## Count text -> its width on screen, in pixels.
static var _text_px: Dictionary = {}

## Each cluster: {"id": int, "kind": int, "rep": passenger id, "members":
## Array[int] sorted}.
var _clusters: Array[Dictionary] = []
var _next_id := 1
## Cluster id -> the shift place() gave its badge last time.
var _shifts: Dictionary = {}
## place()'s broad phase, reused.
var _bins: Dictionary = {}
var _placed: Array[Rect2] = []
## The badges alone, for a badge with no spot clear of everything.
var _badge_bins: Dictionary = {}
var _badge_rects: Array[Rect2] = []


func clear() -> void:
	_clusters.clear()
	_shifts.clear()


## Drops passenger `id` from every cluster (its view went back to the pool).
func forget(id: int) -> void:
	for cluster in _clusters:
		(cluster["members"] as Array).erase(id)


## The clusters now, in id order.
func clusters() -> Array[Dictionary]:
	return _clusters


## Passenger id -> a bit mask of the need kinds (1 << kind) whose icon is
## drawn by a cluster badge instead of over the passenger.
func mask() -> Dictionary:
	var out := {}
	for cluster in _clusters:
		var bit: int = 1 << int(cluster["kind"])
		for id: int in cluster["members"]:
			out[id] = out.get(id, 0) | bit
	return out


## Moves the clusters on to this frame's icons: `points` maps a need kind to
## a Dictionary of passenger id -> the icon's screen point, holding only the
## icons that show.
func update(points: Dictionary) -> void:
	var kept: Array[Dictionary] = []
	for kind: int in points:
		kept.append_array(_update_kind(kind, points[kind]))
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	_clusters = kept


## The member nearest the members' centroid, ties to the lower id.
static func anchor_member(members: Array, pts: Dictionary) -> int:
	var centre := Vector2.ZERO
	for id: int in members:
		centre += pts[id]
	centre /= maxf(members.size(), 1.0)
	var best := -1
	var best_d := INF
	for id: int in members:
		var d := centre.distance_squared_to(pts[id])
		if d < best_d or (d == best_d and id < best):
			best = id
			best_d = d
	return best


## Places badge rectangles clear of each other and of `obstacles`, in the
## order given: a badge keeps the shift it had last time while that still
## fits, else takes its anchor, else the nearest free spot within
## MAX_SHIFT_PX. Where no spot within reach is clear of everything, it takes
## the first one clear of the other badges, so badges never hide each other
## while a spot for that exists. One with no such spot either is drawn at its
## anchor anyway, never hidden. `ids` are the badges' cluster ids. Returns the
## placed rectangles.
func place(wanted: Array[Rect2], ids: Array, obstacles: Array[Rect2]) -> Array[Rect2]:
	_bins.clear()
	_placed.clear()
	_badge_bins.clear()
	_badge_rects.clear()
	for rect in obstacles:
		RectBins.file(_bins, rect, _placed.size())
		_placed.append(rect)
	var out: Array[Rect2] = []
	var shifts := {}
	for i in wanted.size():
		var rect := wanted[i]
		var tries: Array[Vector2] = []
		if _shifts.has(ids[i]):
			tries.append(_shifts[ids[i]])
		tries.append_array(_offsets())
		var chosen := _first_clear(rect, tries, _bins, _placed)
		if is_nan(chosen.x):
			chosen = _first_clear(rect, tries, _badge_bins, _badge_rects)
		if is_nan(chosen.x):
			chosen = Vector2.ZERO
		shifts[ids[i]] = chosen
		var at := Rect2(rect.position + chosen, rect.size)
		RectBins.file(_bins, at, _placed.size())
		_placed.append(at)
		RectBins.file(_badge_bins, at, _badge_rects.size())
		_badge_rects.append(at)
		out.append(at)
	_shifts = shifts
	return out


## The first of `tries` that moves `rect` clear of the rectangles in `bins`,
## or a NAN vector when none does.
static func _first_clear(
	rect: Rect2, tries: Array[Vector2], bins: Dictionary, rects: Array[Rect2]
) -> Vector2:
	for shift in tries:
		if not RectBins.hits(Rect2(rect.position + shift, rect.size), bins, rects):
			return shift
	return Vector2(NAN, NAN)


## The shifts place() tries after the kept one: none, then rings out to
## MAX_SHIFT_PX, up first.
static func _offsets() -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2.ZERO]
	var r := SHIFT_STEP_PX
	while r <= MAX_SHIFT_PX:
		for dir: Vector2 in [
			Vector2(0, -1),
			Vector2(1, 0),
			Vector2(-1, 0),
			Vector2(1, -1),
			Vector2(-1, -1),
			Vector2(0, 1),
			Vector2(1, 1),
			Vector2(-1, 1),
		]:
			out.append(dir * r)
		r += SHIFT_STEP_PX
	return out


func _update_kind(kind: int, pts: Dictionary) -> Array[Dictionary]:
	var mine: Array[Dictionary] = []
	for cluster in _clusters:
		if cluster["kind"] == kind:
			mine.append(cluster)
	# Members whose icon stopped showing leave; a lost representative is
	# replaced by the member nearest the centre; members past RETAIN_PX leave.
	for cluster in mine:
		var members: Array = (cluster["members"] as Array).filter(
			func(id: int) -> bool: return pts.has(id)
		)
		if members.is_empty():
			cluster["members"] = members
			continue
		if not pts.has(cluster["rep"]) or _wandered(cluster["rep"], members, pts):
			cluster["rep"] = anchor_member(members, pts)
		var at: Vector2 = pts[cluster["rep"]]
		cluster["members"] = members.filter(
			func(id: int) -> bool: return at.distance_to(pts[id]) <= RETAIN_PX
		)
	_merge(mine, pts)
	var owned := {}
	for cluster in mine:
		for id: int in cluster["members"]:
			owned[id] = true
	var ids: Array = pts.keys()
	ids.sort()
	_admit(mine, ids, pts, owned)
	var out: Array[Dictionary] = []
	for cluster in mine:
		if (cluster["members"] as Array).size() >= KEEP_MIN:
			(cluster["members"] as Array).sort()
			out.append(cluster)
		else:
			for id: int in cluster["members"]:
				owned.erase(id)
	out.append_array(_form(kind, ids, pts, owned))
	return out


## True when representative `rep` stands more than ADMIT_PX from its
## members' centroid: it walked off from its group, which would otherwise lose
## the id to the one walker. A group split in two keeps its representative,
## since its halves leave RETAIN_PX before the centroid is that far.
static func _wandered(rep: int, members: Array, pts: Dictionary) -> bool:
	var centre := Vector2.ZERO
	for id: int in members:
		centre += pts[id]
	centre /= members.size()
	return centre.distance_to(pts[rep]) > ADMIT_PX


## Two clusters whose representatives are within ADMIT_PX become one, under
## the id of the one with more members (ties to the lower id); the other's
## members within RETAIN_PX of the kept representative move over.
func _merge(mine: Array[Dictionary], pts: Dictionary) -> void:
	mine.sort_custom(placed_before)
	for i in mine.size():
		var keep := mine[i]
		if (keep["members"] as Array).is_empty():
			continue
		var at: Vector2 = pts[keep["rep"]]
		for j in range(i + 1, mine.size()):
			var other := mine[j]
			if (other["members"] as Array).is_empty():
				continue
			if at.distance_to(pts[other["rep"]]) > ADMIT_PX:
				continue
			for id: int in other["members"]:
				if at.distance_to(pts[id]) <= RETAIN_PX:
					(keep["members"] as Array).append(id)
			other["members"] = []


## Each free icon joins the cluster whose representative is nearest, within
## ADMIT_PX (ties to the representative with the lower id).
func _admit(mine: Array[Dictionary], ids: Array, pts: Dictionary, owned: Dictionary) -> void:
	var reps := {}
	var at_rep := {}
	for cluster in mine:
		if not (cluster["members"] as Array).is_empty():
			reps[cluster["rep"]] = pts[cluster["rep"]]
			at_rep[cluster["rep"]] = cluster
	if reps.is_empty():
		return
	var bins := _bin(reps)
	for id: int in ids:
		if owned.has(id):
			continue
		var p: Vector2 = pts[id]
		var best := -1
		var best_d := INF
		for rep: int in _near(bins, p):
			var d := p.distance_to(reps[rep])
			if d <= ADMIT_PX and (d < best_d or (d == best_d and rep < best)):
				best = rep
				best_d = d
		if best >= 0:
			(at_rep[best]["members"] as Array).append(id)
			owned[id] = true


## New clusters from the free icons: the icon with the most free neighbours
## within ADMIT_PX (ties to the lower id) becomes a representative when it and
## its neighbours number FORM_MIN or more, and takes them all.
func _form(kind: int, ids: Array, pts: Dictionary, owned: Dictionary) -> Array[Dictionary]:
	var free := {}
	for id: int in ids:
		if not owned.has(id):
			free[id] = pts[id]
	var out: Array[Dictionary] = []
	if free.size() < FORM_MIN:
		return out
	var bins := _bin(free)
	var near := {}
	var order: Array = []
	for id: int in ids:
		if not free.has(id):
			continue
		var p: Vector2 = free[id]
		near[id] = _near(bins, p).filter(
			func(other: int) -> bool: return p.distance_to(free[other]) <= ADMIT_PX
		)
		order.append(id)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			var na: int = (near[a] as Array).size()
			var nb: int = (near[b] as Array).size()
			return na > nb or (na == nb and a < b)
	)
	for id: int in order:
		if owned.has(id):
			continue
		var members: Array = (near[id] as Array).filter(
			func(other: int) -> bool: return not owned.has(other)
		)
		if members.size() < FORM_MIN:
			continue
		members.sort()
		for member: int in members:
			owned[member] = true
		out.append({"id": _next_id, "kind": kind, "rep": id, "members": members})
		_next_id += 1
	return out


## Points (id -> Vector2) filed by ADMIT_PX cell.
static func _bin(pts: Dictionary) -> Dictionary:
	var bins := {}
	for id: int in pts:
		var cell := Vector2i(((pts[id] as Vector2) / ADMIT_PX).floor())
		if not bins.has(cell):
			bins[cell] = []
		(bins[cell] as Array).append(id)
	return bins


## The ids filed in the cells around `p`, `p`'s own included.
static func _near(bins: Dictionary, p: Vector2) -> Array:
	var cell := Vector2i((p / ADMIT_PX).floor())
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var key := cell + Vector2i(dx, dy)
			if bins.has(key):
				out.append_array(bins[key])
	return out


## Clusters with more members first, ties to the lower id: the merge order
## and the badge placement order.
static func placed_before(a: Dictionary, b: Dictionary) -> bool:
	var na: int = (a["members"] as Array).size()
	var nb: int = (b["members"] as Array).size()
	return na > nb or (na == nb and a["id"] < b["id"])


## The screen box (output pixels) of a badge centred at `centre` showing
## `count`: the icon and its count pill.
static func badge_rect(centre: Vector2, count: int) -> Rect2:
	var icon := Rect2(centre - Vector2.ONE * BADGE_PX / 2.0, Vector2.ONE * BADGE_PX)
	var pill := Vector2(pill_width(str(count)), PILL_H_PX)
	return icon.merge(Rect2(centre + COUNT_AT - pill / 2.0, pill))


## The pill's width on screen for `text`, in whole pixels: the text in the HUD
## font plus PILL_PAD_PX each side, never narrower than it is tall.
static func pill_width(text: String) -> float:
	if not _text_px.has(text):
		var measured := font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, COUNT_FONT)
		_text_px[text] = measured.x * COUNT_EM_PX / COUNT_FONT
	return maxf(ceilf(_text_px[text] + 2.0 * PILL_PAD_PX), PILL_H_PX)


## The HUD theme's font (a rounded bold Nunito), or the default font.
static func font() -> Font:
	if _font == null:
		var theme := load(HUD_THEME) as Theme
		_font = theme.default_font if theme != null else null
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


## A pooled badge: a billboard need icon over the world with its count pill and
## count as children, drawn with no depth test like the need icons but over
## them (11, with the station signs; a badge with no clear spot is not hidden
## under icons), the pill and count over it and under the speech bubbles.
static func make_badge() -> Sprite3D:
	var badge := _billboard(MissMarkers.SIGN_PRIORITY)
	badge.visible = false
	var pill := _billboard(MissMarkers.CAPTION_PRIORITY)
	pill.name = PILL
	badge.add_child(pill)
	var label := Label3D.new()
	label.name = COUNT
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.font = font()
	label.font_size = COUNT_FONT
	label.outline_size = 0
	label.modulate = MarkerIcons.OUTLINE
	label.render_priority = MissMarkers.CAPTION_PRIORITY + 1
	badge.add_child(label)
	return badge


static func _billboard(priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.fixed_size = true
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.render_priority = priority
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sprite


## Draws `badge` for a cluster of `kind` with `count` members at `anchor`
## (PassengerViews space), its icon centred `centre_px` screen pixels from
## the anchor's projection (y down); `unit` from NeedIcons.unit_of(). Sets
## the count's text and pill only when the count changes.
static func show_badge(
	badge: Sprite3D,
	kind: int,
	count: int,
	anchor: Vector3,
	centre_px: Vector2,
	unit: float,
	alpha: float
) -> void:
	badge.visible = true
	badge.texture = NeedIcons.texture(kind)
	badge.position = anchor
	badge.pixel_size = BADGE_PX * unit / NeedIcons.SIZE
	badge.offset = Vector2(centre_px.x, -centre_px.y) * NeedIcons.SIZE / BADGE_PX
	badge.modulate.a = alpha
	var label := badge.get_node(COUNT) as Label3D
	var pill := badge.get_node(PILL) as Sprite3D
	if badge.get_meta(&"count", -1) != count:
		badge.set_meta(&"count", count)
		label.text = str(count)
		pill.texture = pill_texture(pill_width(label.text))
	var at := centre_px + COUNT_AT
	label.pixel_size = COUNT_EM_PX * unit / COUNT_FONT
	label.offset = Vector2(at.x, -at.y) * COUNT_FONT / COUNT_EM_PX
	label.modulate.a = alpha
	pill.pixel_size = unit / PILL_TEXELS
	pill.offset = Vector2(at.x, -at.y) * PILL_TEXELS
	pill.modulate.a = alpha


## A cream pill `width_px` by PILL_H_PX screen pixels with the navy outline,
## PILL_TEXELS texels per pixel, painted once per width.
static func pill_texture(width_px: float) -> Texture2D:
	if _pills.has(width_px):
		return _pills[width_px]
	var size := Vector2i(roundi(width_px * PILL_TEXELS), roundi(PILL_H_PX * PILL_TEXELS))
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var radius := size.y / 2.0
	var half := Vector2(size) / 2.0
	var outline := PILL_OUTLINE_PX * PILL_TEXELS
	for y in size.y:
		for x in size.x:
			var p := (Vector2(x + 0.5, y + 0.5) - half).abs()
			var q := p - (half - Vector2.ONE * radius)
			var edge := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() - radius
			var cover := clampf(0.5 - edge, 0.0, 1.0)
			var inside := clampf(0.5 - (edge + outline), 0.0, 1.0)
			var colour := MarkerIcons.OUTLINE.lerp(WishIconView.CARD, inside)
			colour.a = cover
			img.set_pixel(x, y, colour)
	img.generate_mipmaps()
	var texture := ImageTexture.create_from_image(img)
	_pills[width_px] = texture
	return texture
