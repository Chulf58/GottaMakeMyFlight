class_name PassengerViews
extends Node3D
## Draws the passengers with pooled Toon characters. Each tick it records
## every visible passenger's position for the tick before and the tick now,
## keyed by stable passenger id; each frame it draws between the two with the
## clock's alpha. A node is taken from the pool for a passenger's whole visit
## and returned when the passenger boards or a while after missing the flight.
## It reads the sim and never writes to it; animation never drives the sim.
## Each node carries its thought bubble, its need icons (NeedIcons), its
## shopping wish icon (WishIconView) and its VIP crown (VipMarker), set each
## tick and laid out each frame. Close need icons of one kind are drawn as one
## count badge instead (NeedCluster, _cluster_icons()).

## Bodies, tints, bag colours and clip speeds: PassengerLooks.
const SIT_CLIP_SECONDS := 1.2
## On an activity visit, a sit_down or stand_up clip more than this many
## ticks, plus the ticks one frame runs at the clock's speed, away from where
## the sim is in it is sought there: frames play the clip between ticks and
## may run it a frame ahead of or behind the sim.
const SEEK_SLACK_TICKS := 1.5
## A clip change blends from the pose drawn at the change over this much sim
## time (ClipCrossfade; user ruling
## passenger-turns-on-the-spot-ease-over-a-few-frames-and-anima); a view just
## taken or snapped plays its clip with no blend.
const CROSSFADE_SECONDS := 0.18
const LOOPED := ["idle", "walk", "run", "sit_idle", "shower"]
const MISSED_LINGER_TICKS := 200
const BUBBLE_HEIGHT := 2.5
## A speech bubble draws above the need icons and the station signs and
## captions (user ruling: a kept bubble's text is never covered).
const BUBBLE_PRIORITY := MissMarkers.CAPTION_PRIORITY + 2
const PICK_RADIUS_PX := 40.0
## The drawn body pick_body() reads: a capsule this wide and this tall, in metres.
const BODY_RADIUS_M := 0.35
const BODY_HEIGHT_M := 1.7
## How far along the click ray pick_body() looks, in metres.
const BODY_PICK_RANGE_M := 1000.0
## The height and width of the head a count badge keeps clear of, metres
## from the head's top, and the most screen pixels its rect may span.
const HEAD_RECT_M := 0.35
const HEAD_RECT_MAX_PX := 96.0

@export var clock: SimClock
@export var sim: PassengerSim
## When set, a finished load snaps every view to the loaded world.
@export var save_game: SaveGame
## When set, the passenger an accepted VIP incident marked wears the VIP crown
## (VipMarker).
@export var incidents: IncidentDirector

## When set, its Hunger, Toilet and Boredom modes hide every need icon (the
## tinted floor shows the need instead).
@export var mood_overlay: MoodOverlay

## Moves with the selected passenger, for a camera to follow.
var follow_anchor := Node3D.new()
## False shows every speech bubble, overlapping or not (plate probes compare).
var declutter_bubbles := true
## False draws every need icon on its own, with no count badges (plate probes
## compare).
var cluster_needs := true
## The count clusters of close need icons (NeedCluster). View state with no
## tick: snap() and the icons hiding clear it, and a released id leaves it.
var need_clusters := NeedCluster.new()
## The N key's on/off choice for the need icons (NeedIconsToggle); a test points
## its settings_path at a per-process file before the views enter the tree.
var need_icons_toggle := NeedIconsToggle.new()
var selected_id := 0
## Moved pieces still in use, drawn at their old spot (RelocationGhosts).
## Holds no tick: it compares with the sim every frame.
var ghosts := RelocationGhosts.new()

## Free nodes per body (PassengerLooks.BODIES).
var _pool: Array[Array] = []
## Passenger id -> node.
var _nodes: Dictionary = {}
var _prev: Dictionary = {}
var _cur: Dictionary = {}
## Passenger id -> its stage at the sync before this one, to tell the tick a
## cafe guest is handed back from CAFE_STANDING_UP (_up_with_roller()). Holds
## no tick; snap() and release erase it.
var _stages: Dictionary = {}
## Passenger id -> its odometer_mm at the sync before this one, to read the way
## a walker held in a boarding file walked on this tick (a drawn step across a
## corner is a chord, shorter than the way walked). Holds no tick; snap() and
## release erase it.
var _odometers: Dictionary = {}
var _ring := MeshInstance3D.new()
## Queue-full signs, drawn after the passengers.
var _markers := MissMarkers.new()
## The '+$' pops over cafe counters.
var _pops := CafePops.new()
## Carry-on bags of every passenger, and trays at security lanes.
var _props := CarryOnProps.new()
## Passenger id -> its drawn offset at security (SecurityLooks.target_offset),
## moved toward the target at walking speed once per tick.
var _offsets: Dictionary = {}
## Passenger id -> its drawn step onto a seat or into a shower on an activity
## visit, moved toward ActivityPoses.offset() by at most a walking step a tick,
## so a stay cut short or a removed piece eases the body back instead of
## jumping. Holds no tick; snap() restarts it from the loaded world.
var _seats: Dictionary = {}
## Passenger id -> the offset drawn on its last tick for a walker sitting down
## with a roller (SitHold.offset(), sit_offset()). Holds no anchor: the chair
## front is read from the seat on every sync. Started over on a snap or a release.
var _sit_off: Dictionary = {}
## The yaw each view is drawn with, eased per tick (PassengerTurns); snap()
## starts every record over.
var _turns := PassengerTurns.new()
## Passenger id -> Vector3(yaw drawn at the tick before, yaw now, yaw the turn
## started from) while a lane passenger turns to the tray table and on into the
## arch (SecurityLooks.setoff_yaw(): set from the start yaw and the sim on each
## tick, never stepped). The start is the yaw drawn when UNPACK began, or the
## way it walked in (SecurityLooks.arrival_yaw()) for a view first drawn after.
## Holds no tick; snap() and release erase it.
var _setoffs: Dictionary = {}
## Passenger ids an accepted VIP incident marked, as keys: one dictionary,
## cleared and filled again from the director on every sync
## (VipMarker.marked_ids), so a load reads the loaded ones. Holds no tick.
var _vips: Dictionary = {}
## True while snap() syncs: the step from the pre-load position is no heading.
var _snapping := false
## Working array of _declutter_bubbles, reused each frame.
var _bubble_entries: Array[Dictionary] = []
## The count badges, pooled (NeedCluster.make_badge()), under _badge_root.
var _badges: Array[Sprite3D] = []
## Made and parented in _ready(), so a views node that never enters the tree
## leaves no orphan behind.
var _badge_root: Node3D
## The badges drawn this frame: {"kind", "count", "rect"} (screen pixels).
var _badges_drawn: Array[Dictionary] = []


func _ready() -> void:
	follow_anchor.name = "FollowAnchor"
	add_child(follow_anchor)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.6
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(1.0, 0.85, 0.3)
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = ring_material
	_ring.mesh = torus
	_ring.visible = false
	add_child(_ring)
	for scene in PassengerLooks.SCENES:
		_pool.append([])
		var probe := scene.instantiate()
		var player := probe.get_node("AnimationPlayer") as AnimationPlayer
		for clip in LOOPED:
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		probe.free()
	_markers.name = "MissMarkers"
	_markers.sim = sim
	add_child(_markers)
	_pops.name = "CafePops"
	_pops.sim = sim
	add_child(_pops)
	ghosts.name = "RelocationGhosts"
	ghosts.sim = sim
	add_child(ghosts)
	_props.name = "CarryOnProps"
	_props.clock = clock
	_props.sim = sim
	_props.views = self
	add_child(_props)
	add_child(need_icons_toggle)
	_badge_root = Node3D.new()
	_badge_root.name = NeedCluster.ROOT
	add_child(_badge_root)
	if clock != null:
		clock.ticked.connect(_on_ticked)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)


func _process(_delta: float) -> void:
	draw()


func node_for(id: int) -> Node3D:
	return _nodes.get(id)


func active_count() -> int:
	return _nodes.size()


func cafe_pops() -> CafePops:
	return _pops


func carry_on_props() -> CarryOnProps:
	return _props


## A passenger's recorded position for the tick before (false) or now (true).
func tick_position(id: int, current: bool) -> Vector3:
	return (_cur if current else _prev).get(id, Vector3.ZERO)


## Where a passenger is drawn on this tick: the sim's position, moved onto
## its chair's pan at a gate seat (GateChairs), clear of its chair at a cafe
## seat (CafeChairs), onto its seat or into the shower on an activity visit
## (ActivityPoses), by its drawn offset at security (SecurityLooks) and off a
## door's axis, away from the hand pulling its roller (DoorSteer).
func draw_position(p: Passenger) -> Vector3:
	return _base_position(p) + DoorSteer.offset_of(self, p, _steer_time())


## draw_position() without the door steer.
func _base_position(p: Passenger) -> Vector3:
	return (
		sim.world_position(p)
		+ GateChairs.offset(sim, p)
		+ CafeChairs.offset(sim, p)
		+ _seats.get(p.id, Vector3.ZERO)
		+ _offsets.get(p.id, Vector3.ZERO)
	)


## The sim time DoorSteer reads a roller's move at: a tick ahead of the clock,
## since a body is drawn between its last two tick positions while its bags
## are drawn at the clock's time, so the body crosses with the roller.
func _steer_time() -> float:
	return (float(clock.tick) if clock != null else 0.0) + 1.0


## How far passenger `id` is drawn from where the sim puts it while it stands
## at the chair front setting its roller down (SitHold.offset()).
func sit_offset(id: int) -> Vector3:
	return _sit_off.get(id, Vector3.ZERO)


## A passenger's drawn offset at security now.
func security_offset(id: int) -> Vector3:
	return _offsets.get(id, Vector3.ZERO)


## Records positions for the tick that just ran and updates poses and bubbles.
func sync() -> void:
	var seen := {}
	# Passenger id -> the door steer in its tick position, from the carry state
	# before _props.sync(); true for a node made on this sync.
	var steers := {}
	var fresh := {}
	VipMarker.marked_ids(incidents, _vips)
	# Read once for the whole sync, not per passenger: every icon row asks it.
	var built := NeedIcons.provided(sim)
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if not _visible(p):
			continue
		seen[id] = true
		_chase(p)
		_chase_seat(p)
		var steer := DoorSteer.offset_of(self, p, _steer_time())
		var now := _base_position(p) + steer
		if not _nodes.has(id):
			_nodes[id] = _take(p)
			_cur[id] = now
			fresh[id] = true
		var sit := SitHold.offset(_props, sim, p, now)
		_sit_off[id] = sit
		now += sit
		_prev[id] = _cur[id]
		_cur[id] = now
		steers[id] = steer
		_turn(_nodes[id], p, _pose(_nodes[id], p, built))
		VipMarker.mark(_nodes[id], _vips.has(id))
		_stages[id] = p.stage
		_odometers[id] = p.odometer_mm
	for id in _nodes.keys():
		if not seen.has(id):
			_release(id)
	_props.sync()
	_resteer(steers, fresh)
	_markers.sync()


## Moves each tick position in `steers` (passenger id -> the door steer it was
## recorded with) onto the steer of the carry state _props.sync() has just
## made: a change of hand seen this tick, or bags made again after a load. The
## tick position and its side then come from the same state, and
## draw_position() afterwards returns the position recorded. `fresh` holds
## the nodes made this sync, whose previous position moves with it.
func _resteer(steers: Dictionary, fresh: Dictionary) -> void:
	for id: int in steers:
		var shift: Vector3 = (
			DoorSteer.offset_of(self, sim.get_passenger(id), _steer_time()) - steers[id]
		)
		if shift == Vector3.ZERO:
			continue
		_cur[id] += shift
		if fresh.has(id):
			_prev[id] += shift


## Draws every view at the sim's current state now, with no tick to run: a
## load while paused brings no tick, and a view drawn between its two pre-load
## positions would stay there. Syncs poses and the node set (passengers the
## load removed lose their view, new ones get one), then makes the previous and
## current positions the same so the frame draws the current one. With no
## interval to take a heading from, a walker faces along its current path or
## apron leg, and one standing still in a queue or at the gate faces its queue
## stand's way (ParkSide.stand_face(); drawn new it faced yaw 0, away from the
## roller stood for that way). Every turn and clip starts over, with no ease or
## blend from before the load.
func snap() -> void:
	_turns.clear()
	need_clusters.clear()
	_setoffs.clear()
	_stages.clear()
	_odometers.clear()
	for id in sim.passenger_ids():
		if _nodes.has(id):
			# A node kept through the load starts over dressed, with no foam
			# or recline (the sync below dresses it for the loaded tick), and
			# goes back to the pool when the loaded passenger of that id has
			# another body, so sync() takes one of the right body.
			var kept: Node3D = _nodes[id]
			ActivityPoses.dress(kept, 0.0, 0.0)
			var p := sim.get_passenger(id)
			if kept.get_meta(&"body") != PassengerLooks.body_of(id, p.variant):
				_release(id)
		_offsets.erase(id)
		_seats.erase(id)
		_sit_off.erase(id)
		var seat := ActivityPoses.offset(sim, sim.get_passenger(id))
		if seat != Vector3.ZERO:
			_seats[id] = seat
		# A load starts every tray and bag over, with no transfer from before.
		_props.release(id)
		var target := SecurityLooks.target_offset(sim, sim.get_passenger(id))
		if target != Vector3.ZERO:
			_offsets[id] = target
		# Every clip is played again from the loaded tick: a node kept through
		# the load still plays the clip it had, from where it was before.
		if _nodes.has(id):
			(_nodes[id] as Node3D).set_meta(&"clip", "")
	_snapping = true
	sync()
	_snapping = false
	for id in _cur:
		_prev[id] = _cur[id]
		var node: Node3D = _nodes[id]
		var p := sim.get_passenger(id)
		var heading := walk_heading(p)
		# One standing still in a queue or at the gate faces its queue stand's way
		# (ParkSide.stand_face()), the way its stood roller is placed for.
		if heading == Vector2.ZERO and RollerPark.queue_still(sim, p):
			heading = ParkSide.stand_face(sim, p)
		if heading != Vector2.ZERO and not _turn_locked(node) and not _setoffs.has(id):
			_turns.place(id, atan2(heading.x, heading.y))
	draw()


## The ground direction (x, z) a walking passenger is heading in, from the
## committed path step or apron leg it is on; zero when it is not walking.
func walk_heading(p: Passenger) -> Vector2:
	var outside := p.stage == Passenger.Stage.APRON or p.stage == Passenger.Stage.SPAWNED
	if outside and p.apron_mm < p.apron_total_mm():
		var left := p.apron_mm
		for i in range(1, p.apron.size()):
			var length := p.apron_segment_mm(i)
			if left < length:
				var leg := p.apron[i] - p.apron[i - 1]
				return Vector2(leg.x, leg.z)
			left -= length
		return Vector2.ZERO
	if p.is_moving():
		return Vector2(p.path[p.path_index + 1] - p.path[p.path_index])
	return Vector2.ZERO


## Places every node between its last two tick positions.
func draw() -> void:
	var alpha := clock.alpha if clock != null else 1.0
	var now := _now()
	var paused := clock == null or clock.paused
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var unit := NeedIcons.unit_of(get_viewport() if is_inside_tree() else null, camera)
	var icons_shown := need_icons_toggle.is_shown() and NeedIcons.shown_at(camera)
	if mood_overlay != null and mood_overlay.hides_need_icons():
		icons_shown = false
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var before: Vector3 = _prev[id]
		var after: Vector3 = _cur[id]
		node.position = before.lerp(after, alpha)
		if _setoffs.has(id):
			var yaws: Vector3 = _setoffs[id]
			node.rotation.y = lerp_angle(yaws.x, yaws.y, alpha)
		elif _turns.has(id):
			node.rotation.y = _turns.drawn(id, alpha)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		var base: float = node.get_meta(&"base_speed", 1.0)
		player.speed_scale = 0.0 if paused else base * clock.speed
		var fade: ClipCrossfade = node.get_meta(&"crossfade")
		fade.ease_to(now, CROSSFADE_SECONDS)
		fade.drawn = true
	if _nodes.has(selected_id):
		follow_anchor.position = (_nodes[selected_id] as Node3D).position
		_ring.position = follow_anchor.position + Vector3(0.0, 0.05, 0.0)
	_ring.visible = _nodes.has(selected_id)
	# The icons lift over a bubble only while it shows, so they are laid out
	# after the declutter has set each bubble's visibility for this frame.
	_declutter_bubbles(camera, unit)
	# Clustered icons are masked before the crown measures the row.
	var masks := _cluster_icons(camera, unit, icons_shown)
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var bubble := node.get_node("Bubble") as Label3D
		NeedIcons.layout(node, bubble, camera, unit, icons_shown, masks.get(id, 0))
		VipMarker.layout(node, bubble, camera, unit)
	_props.draw()
	_markers.draw()


## Shows each speech bubble, then hides the ones that overlap a bubble kept
## on screen (BubbleDeclutter: late first, then nearest the front of the
## queue). Does nothing with no camera.
func _declutter_bubbles(camera: Camera3D, unit: float) -> void:
	var entries := _bubble_entries
	entries.clear()
	var view := get_viewport() if is_inside_tree() else null
	var to_output := view.get_stretch_transform().get_scale().y if view != null else 1.0
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var bubble := node.get_node("Bubble") as Label3D
		bubble.visible = true
		if bubble.text == "" or camera == null or unit <= 0.0:
			continue
		var at := bubble.global_position
		var depth := (at - camera.global_position).dot(-camera.global_basis.z)
		if depth <= 0.0:
			continue
		var rect := BubbleDeclutter.rect_of(
			camera.unproject_position(at) * to_output,
			bubble.text,
			bubble.font_size,
			bubble.outline_size,
			bubble.pixel_size / (depth * unit)
		)
		var rank: int = node.get_meta(&"bubble_rank", BubbleDeclutter.NO_QUEUE)
		entries.append(BubbleDeclutter.entry(id, bubble.text, rank, rect))
	if not declutter_bubbles:
		return
	for id in BubbleDeclutter.hidden(entries):
		((_nodes[id] as Node3D).get_node("Bubble") as Label3D).visible = false


## The count badges drawn this frame, each {"id": cluster id, "kind":
## NeedIcons.Need, "count": int, "rect": Rect2 in screen pixels}.
func need_badges() -> Array[Dictionary]:
	return _badges_drawn


## Merges close need icons of one kind into count badges for this frame
## (NeedCluster; decision need-icon-count-clusters-technical-design-screen-
## space-clust) and returns passenger id -> the mask of kinds a badge draws, for
## NeedIcons.layout(). Each icon's screen point is its row's anchor, projected
## once per passenger, plus its place in the row as drawn with no mask. Left
## out: anchors nearer than the camera's near plane, icons off screen and
## passengers faded out near the camera. Badges are placed clear of each
## other, the kept speech bubbles, the icons still drawn and the passengers'
## heads. With the icons hidden, or cluster_needs off, it clears the clusters
## and hides every badge.
func _cluster_icons(camera: Camera3D, unit: float, icons_shown: bool) -> Dictionary:
	_badges_drawn.clear()
	if not cluster_needs or not icons_shown or camera == null or unit <= 0.0:
		need_clusters.clear()
		_hide_badges(0)
		return {}
	var view := get_viewport()
	var to_output := view.get_stretch_transform().get_scale().y
	var screen := Rect2(Vector2.ZERO, view.get_visible_rect().size * to_output)
	var half := Vector2.ONE * NeedIcons.ICON_PX / 2.0
	var points := {}
	for kind: int in NeedIcons.Need.values():
		points[kind] = {}
	# Passenger id -> [anchor in this node's space, its screen point, lift_px,
	# wishing, alpha].
	var rows := {}
	var forward := -camera.global_basis.z
	for id: int in _nodes:
		var node: Node3D = _nodes[id]
		var kinds: Array = node.get_meta(&"need_kinds", [])
		var wishing: bool = node.get_meta(&"wish", "") != ""
		if kinds.is_empty() and not wishing:
			continue
		var alpha := NeedIcons.near_alpha(camera.global_position.distance_to(node.global_position))
		if alpha <= 0.0:
			continue
		var at := NeedIcons.row_anchor(node, node.get_node("Bubble") as Label3D, camera, unit)
		var world: Vector3 = node.global_transform * (at[0] as Vector3)
		if (world - camera.global_position).dot(forward) <= camera.near:
			continue
		var base := camera.unproject_position(world) * to_output
		rows[id] = [node.transform * (at[0] as Vector3), base, at[1], wishing, alpha]
		for i in kinds.size():
			var centre := base + NeedIcons.icon_centre_px(i, kinds.size(), wishing, at[1])
			if screen.intersects(Rect2(centre - half, half * 2.0)):
				(points[kinds[i]] as Dictionary)[id] = centre
	need_clusters.update(points)
	var masks := need_clusters.mask()
	# The biggest counts are placed first, so they keep their anchors.
	var clusters := need_clusters.clusters().duplicate()
	clusters.sort_custom(NeedCluster.placed_before)
	# Per cluster: the row of the member nearest its centroid, the badge's
	# centre from that row's anchor (its bottom edge where the row's is).
	var anchors: Array[Array] = []
	var wanted: Array[Rect2] = []
	var ids: Array = []
	for cluster in clusters:
		var members: Array = cluster["members"]
		var row: Array = rows[NeedCluster.anchor_member(members, points[cluster["kind"]])]
		var centre_px := Vector2(0.0, -float(row[2]) - NeedCluster.BADGE_PX / 2.0)
		anchors.append([row, centre_px])
		wanted.append(NeedCluster.badge_rect((row[1] as Vector2) + centre_px, members.size()))
		ids.append(cluster["id"])
	var obstacles := _badge_obstacles(rows, masks, screen)
	_add_head_rects(obstacles, camera, unit, to_output, screen)
	var placed := need_clusters.place(wanted, ids, obstacles)
	for i in clusters.size():
		var kind: int = clusters[i]["kind"]
		var count: int = (clusters[i]["members"] as Array).size()
		var row: Array = anchors[i][0]
		var centre_px: Vector2 = anchors[i][1] + placed[i].position - wanted[i].position
		NeedCluster.show_badge(_badge(i), kind, count, row[0], centre_px, unit, row[4])
		_badges_drawn.append({"id": ids[i], "kind": kind, "count": count, "rect": placed[i]})
	_hide_badges(clusters.size())
	return masks


## What a badge is kept clear of: the speech bubbles kept on screen, the
## icons and wish bubbles still drawn (each row closed up past its masked
## icons, as NeedIcons.layout() draws it) and the station captions shown (as
## the last frame placed them; MissMarkers draws after this pass), in screen
## pixels.
func _badge_obstacles(rows: Dictionary, masks: Dictionary, screen: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in _markers.placed_captions():
		if screen.intersects(rect):
			out.append(rect)
	for e: Dictionary in _bubble_entries:
		var rect: Rect2 = e["rect"]
		var bubble := (_nodes[e["id"]] as Node3D).get_node("Bubble") as Label3D
		if bubble.visible and screen.intersects(rect):
			out.append(rect)
	var icon := Vector2.ONE * NeedIcons.ICON_PX
	var wish := Vector2.ONE * WishIconView.WISH_PX
	for id: int in rows:
		var row: Array = rows[id]
		var mask: int = masks.get(id, 0)
		var kept := 0
		for kind: int in (_nodes[id] as Node3D).get_meta(&"need_kinds", []):
			if mask & (1 << kind) == 0:
				kept += 1
		var wishing: bool = row[3]
		for j in kept:
			var centre: Vector2 = row[1] + NeedIcons.icon_centre_px(j, kept, wishing, row[2])
			out.append(Rect2(centre - icon / 2.0, icon))
		if wishing:
			var x := NeedIcons.row_x_px(kept, NeedIcons.row_widths(kept, true))
			var y := -float(row[2]) - WishIconView.WISH_PX / 2.0
			out.append(Rect2((row[1] as Vector2) + Vector2(x, y) - wish / 2.0, wish))
	return out


## Adds to `out` the screen rect (output pixels) of every drawn passenger's
## head, from the top of the head (NeedIcons.head_top(), standing, seated or
## reclined) HEAD_RECT_M down and as wide, so a badge's dodge does not land
## on a head (board 769f210d: a badge shifted down onto a seated row's heads).
## Heads nearer than the camera's near plane or off screen are left out, and
## a rect is never wider than HEAD_RECT_MAX_PX, since size over depth grows
## without bound near the lens (anti-pattern a-screen-rectangle-measured-from-
## a-3d-point-as-size-depth-gr).
func _add_head_rects(
	out: Array[Rect2], camera: Camera3D, unit: float, to_output: float, screen: Rect2
) -> void:
	var forward := -camera.global_basis.z
	for id: int in _nodes:
		var node: Node3D = _nodes[id]
		if not node.visible:
			continue
		var top: Vector3 = node.global_transform * NeedIcons.head_top(node)
		var depth := (top - camera.global_position).dot(forward)
		if depth <= camera.near:
			continue
		var side := minf(HEAD_RECT_M / (depth * unit), HEAD_RECT_MAX_PX)
		var at := camera.unproject_position(top) * to_output
		var rect := Rect2(at - Vector2(side / 2.0, 0.0), Vector2(side, side))
		if screen.intersects(rect):
			out.append(rect)


## Pooled badge `i`, made when the pool is short.
func _badge(i: int) -> Sprite3D:
	while _badges.size() <= i:
		var badge := NeedCluster.make_badge()
		badge.name = "NeedBadge%d" % _badges.size()
		_badge_root.add_child(badge)
		_badges.append(badge)
	return _badges[i]


## Hides the pooled badges from number `from` on.
func _hide_badges(from: int) -> void:
	for i in range(from, _badges.size()):
		_badges[i].visible = false


## The passenger drawn nearest a screen point within PICK_RADIUS_PX, or 0.
func pick(camera: Camera3D, screen: Vector2) -> int:
	var best := 0
	var best_px := PICK_RADIUS_PX
	for id in _nodes:
		var at: Vector3 = (_nodes[id] as Node3D).position + Vector3(0.0, 1.0, 0.0)
		if camera.is_position_behind(at):
			continue
		var px := camera.unproject_position(at).distance_to(screen)
		if px < best_px:
			best = id
			best_px = px
	return best


## The passenger whose drawn body the click ray at a screen point passes through,
## or 0: the nearest axis within BODY_RADIUS_M of the ray, the body being the
## capsule round the line from feet to head, in world space, so the reach is the
## same at every zoom and angle. Tighter than pick(), for a click that also
## meets a built item.
func pick_body(camera: Camera3D, screen: Vector2) -> int:
	var best := 0
	var best_m := INF
	var from := camera.project_ray_origin(screen)
	var to := from + camera.project_ray_normal(screen) * BODY_PICK_RANGE_M
	for id in _nodes:
		var feet: Vector3 = (_nodes[id] as Node3D).position
		var head := feet + Vector3(0.0, BODY_HEIGHT_M, 0.0)
		var closest := Geometry3D.get_closest_points_between_segments(from, to, feet, head)
		var gap_m := closest[0].distance_to(closest[1])
		if gap_m <= BODY_RADIUS_M and gap_m < best_m:
			best = id
			best_m = gap_m
	return best


func _on_ticked(_tick: int) -> void:
	sync()


func _on_loaded(ok: bool) -> void:
	if ok:
		snap()


## Whether passenger `p` is drawn: false once they have boarded, and once a
## missed passenger has lingered out, when their body goes back to the pool.
func shows(p: Passenger) -> bool:
	return _visible(p)


func _visible(p: Passenger) -> bool:
	if p.stage == Passenger.Stage.MADE:
		return false
	if p.stage == Passenger.Stage.MISSED:
		return sim.tick - p.outcome_tick <= MISSED_LINGER_TICKS
	return true


## A node of the passenger's body (PassengerLooks.body_of), from the pool when
## one is free, painted with the passenger's clothing tint.
func _take(p: Passenger) -> Node3D:
	var body := PassengerLooks.body_of(p.id, p.variant)
	var free: Array = _pool[body]
	if not free.is_empty():
		var reused: Node3D = free.pop_back()
		reused.visible = true
		PassengerLooks.paint_body(reused, body, PassengerLooks.tint_of(p.id))
		return reused
	var node := PassengerLooks.SCENES[body].instantiate() as Node3D
	node.set_meta(&"variant", p.variant)
	node.set_meta(&"body", body)
	PassengerLooks.paint_body(node, body, PassengerLooks.tint_of(p.id))
	var bubble := Label3D.new()
	bubble.name = "Bubble"
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.render_priority = BUBBLE_PRIORITY
	bubble.outline_render_priority = BUBBLE_PRIORITY - 1
	bubble.font_size = 56
	bubble.outline_size = 14
	bubble.pixel_size = 0.006
	bubble.position = Vector3(0.0, BUBBLE_HEIGHT, 0.0)
	node.add_child(bubble)
	for sprite_name in NeedIcons.SPRITES:
		node.add_child(NeedIcons.make_sprite(sprite_name))
	node.add_child(WishIconView.make_sprite())
	node.add_child(VipMarker.make_sprite())
	var fade := ClipCrossfade.new()
	fade.name = "ClipCrossfade"
	var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	skeleton.add_child(fade)
	skeleton.move_child(fade, 0)
	node.set_meta(&"crossfade", fade)
	add_child(node)
	return node


func _release(id: int) -> void:
	var node: Node3D = _nodes[id]
	node.visible = false
	(node.get_node("AnimationPlayer") as AnimationPlayer).stop()
	var fade: ClipCrossfade = node.get_meta(&"crossfade")
	fade.stop()
	fade.drawn = false
	node.set_meta(&"clip", "")
	node.set_meta(&"icon_seated", false)
	node.set_meta(&"icon_reclined", false)
	node.set_meta(&"icon_rise", NeedIcons.Rise.NONE)
	VipMarker.mark(node, false)
	_pool[node.get_meta(&"body")].append(node)
	_nodes.erase(id)
	_offsets.erase(id)
	_seats.erase(id)
	_sit_off.erase(id)
	ActivityPoses.dress(node, 0.0, 0.0)
	_props.release(id)
	_turns.release(id)
	_setoffs.erase(id)
	_prev.erase(id)
	_cur.erase(id)
	_stages.erase(id)
	_odometers.erase(id)
	need_clusters.forget(id)


## Sets the clip, dress, bubble and icons for this tick and returns the yaw
## the passenger faces on this tick (NAN where it faces its walk or keeps its
## turn).
func _pose(node: Node3D, p: Passenger, built: Dictionary) -> float:
	var face := NAN
	var clip := "idle"
	var base := 1.0
	var outside := p.stage == Passenger.Stage.APRON or p.stage == Passenger.Stage.SPAWNED
	var moving := (outside and p.apron_mm < p.apron_total_mm()) or p.is_moving()
	var mm := PassengerSim.RUN_MM if p.late else PassengerSim.WALK_MM
	var activity := ActivityPoses.kind(sim, p)
	var showering := activity == ActivityPoses.Kind.SHOWER
	var drawn_step := _at_security(p) or _stepping_in_stall(p) or showering
	if drawn_step or _up_with_roller(p, activity):
		# The drawn step, so a held-back queue front (its path still open)
		# does not walk in place and a step to the table, into or out of a
		# toilet stall or into or out of a shower, or a roller passenger's step
		# off its seat after its pick-up, is not an idle slide.
		mm = roundi((_cur[p.id] - _prev[p.id]).length() * 1000.0)
		moving = mm > 0
	elif sim.files.holds(p.id):
		# A boarding-file waiter (its path still open) does not walk in place
		# either. The way it walked, not the drawn step: across a corner the
		# drawn step is a chord, 0.71 of the way walked at a right angle, and
		# the clip played at that speed for the tick (board 03454587).
		mm = maxi(p.odometer_mm - _odometers.get(p.id, p.odometer_mm), 0)
		moving = mm > 0
	var held := 0
	var seat_pose := StageKinds.pose(p.stage)
	if activity != ActivityPoses.Kind.NONE:
		seat_pose = ActivityPoses.pose(sim, p)
	match seat_pose:
		StageKinds.Pose.SITTING_DOWN:
			# Standing while a pulled roller is set down (SitHold), then sitting
			# over the ticks left.
			held = SitHold.held_ticks(_props, sim, p)
			clip = "sit_down" if ActivityPoses.clip_ticks(sim, p) >= held else "idle"
			if clip == "sit_down":
				var sit_ticks := SitHold.sit_ticks(sim, p) - held
				base = SIT_CLIP_SECONDS / (sit_ticks / float(SimClock.TICK_RATE))
		StageKinds.Pose.SEATED:
			clip = "sit_idle"
		StageKinds.Pose.STANDING_UP:
			clip = "stand_up"
			base = SIT_CLIP_SECONDS / (PassengerSim.STAND_UP_TICKS / float(SimClock.TICK_RATE))
	if moving:
		var body: int = node.get_meta(&"body")
		var sim_mps := mm * SimClock.TICK_RATE / 1000.0
		clip = "run" if p.late else "walk"
		base = (
			sim_mps
			/ (PassengerLooks.CLIP_RUN_MPS[body] if p.late else PassengerLooks.CLIP_WALK_MPS[body])
		)
	# In the shower, between the step in and the step out: washing.
	var washing := showering and not moving and ActivityPoses.washing(sim, p)
	if washing:
		clip = "shower"
	var where := StageKinds.location(p.stage)
	var at_gate := where == StageKinds.Location.GATE_SEAT and p.seat_object != 0
	var at_cafe := (
		where == StageKinds.Location.FACILITY_SEAT and sim.cafes.seat_facing(p) != Vector2i.ZERO
	)
	var at_stall := (
		where == StageKinds.Location.FACILITY_SEAT and sim.toilets.use_facing(p) != Vector2i.ZERO
	)
	var staying := activity != ActivityPoses.Kind.NONE
	node.set_meta(&"seated", at_gate or at_cafe or at_stall or staying)
	# The icon row's seated anchor (NeedIcons.head_anchor): only a settled sit
	# on a chair, sofa or toilet seat, not &"seated"'s wider turn lock (standing
	# up, the upright shower, the reclined nap pod).
	node.set_meta(
		&"icon_seated",
		(
			seat_pose == StageKinds.Pose.SEATED
			and (at_gate or at_cafe or at_stall or activity == ActivityPoses.Kind.SEAT)
		)
	)
	# The nap pod's own anchor over the reclined head, for the same settled sit
	# (the lean eases in over its first ActivityPoses.EASE_TICKS).
	node.set_meta(
		&"icon_reclined",
		seat_pose == StageKinds.Pose.SEATED and activity == ActivityPoses.Kind.RECLINE
	)
	# Standing up from either (the stand_up clip playing, not yet stepping off):
	# the anchor rises with the body, from the seat's or the pod's to the
	# standing one (NeedIcons.Rise, board 3a5e1d0d).
	var rise := NeedIcons.Rise.NONE
	if seat_pose == StageKinds.Pose.STANDING_UP and clip == NeedIcons.RISE_CLIP:
		if activity == ActivityPoses.Kind.RECLINE:
			rise = NeedIcons.Rise.RECLINE
		elif at_gate or at_cafe or at_stall or activity == ActivityPoses.Kind.SEAT:
			rise = NeedIcons.Rise.SEAT
	node.set_meta(&"icon_rise", rise)
	var works := SecurityLooks.face(sim, p)
	node.set_meta(&"faces", works != Vector2.ZERO)
	if at_gate:
		var facing: int = sim.grid.get_object(p.seat_object).get("facing", 0)
		var front := TerminalLayout.front_of(facing)
		face = atan2(front.x, front.y)
	elif at_cafe:
		var looks := sim.cafes.seat_facing(p)
		face = atan2(looks.x, looks.y)
	elif at_stall:
		# Seated at Mount_Use, facing out of the stall door.
		var out := sim.toilets.use_facing(p)
		face = atan2(out.x, out.y)
	elif staying:
		# On the sofa or in the pod, or in the shower: facing out of the piece.
		var out := ActivityPoses.facing(sim, p)
		face = atan2(out.x, out.y)
	elif works != Vector2.ZERO:
		face = atan2(works.x, works.y)
	elif sim.shops.browse_facing(p) != Vector2i.ZERO:
		# Browsing at a kiosk: face the display stand.
		var shelf := sim.shops.browse_facing(p)
		face = atan2(shelf.x, shelf.y)
	elif not moving and sim.cafes.counter_facing(p) != Vector2i.ZERO:
		# Waiting in a cafe queue or ordering: face the counter.
		var ahead := sim.cafes.counter_facing(p)
		face = atan2(ahead.x, ahead.y)
	ActivityPoses.dress(
		node, ActivityPoses.recline(sim, p), ActivityPoses.foam(sim, p), ActivityPoses.bare(sim, p)
	)
	node.set_meta(&"base_speed", base)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var was: String = node.get_meta(&"clip", "")
	var changed := was != clip
	var fade: ClipCrossfade = node.get_meta(&"crossfade")
	if fade.get_index() != 0:
		# First on the skeleton (a recline added later goes in front of it).
		fade.get_parent().move_child(fade, 0)
	if changed:
		node.set_meta(&"clip", clip)
		# Blended from the pose drawn now; a view just taken or snapped has no
		# clip before it and plays the new one alone.
		if was != "":
			fade.begin(_now())
		else:
			fade.stop()
		player.play(clip)
		if washing:
			# A view made or snapped mid-wash (a load, a passenger just drawn)
			# washes from where the sim is in the loop. The sim cannot move the
			# loop on afterwards (the step in fixes its start), so the frames
			# play it from there.
			var length := player.get_animation(clip).length
			player.seek(fposmod(ActivityPoses.wash_seconds(sim, p), length), true)
	var seat_clip := seat_pose == StageKinds.Pose.SITTING_DOWN
	seat_clip = seat_clip or seat_pose == StageKinds.Pose.STANDING_UP
	if seat_clip and not moving:
		# A view made or snapped mid-way (a load, a passenger just drawn)
		# starts the clip where the sim is in it, not from its first frame.
		var at := maxi(ActivityPoses.clip_ticks(sim, p) - held, 0) * SimClock.STEP * base
		if changed:
			player.seek(at, true)
		elif activity != ActivityPoses.Kind.NONE and player.current_animation == clip:
			# Only an activity stay can move the sim on within a clip (its
			# deadline brought closer during a stand-up); a seat stage's clip
			# runs its fixed ticks and is left to the frames, which seat
			# moves such as RollerPark follow.
			var speed := clock.speed if clock != null else 1
			var slack := (SEEK_SLACK_TICKS + speed) * SimClock.STEP * base
			if absf(player.current_animation_position - at) > slack:
				player.seek(at, true)
	var bubble_text := sim.bubble_text(p)
	(node.get_node("Bubble") as Label3D).text = bubble_text
	node.set_meta(
		&"bubble_rank",
		BubbleDeclutter.rank_of(sim, p) if bubble_text != "" else BubbleDeclutter.NO_QUEUE
	)
	var wish := WishIconView.read(sim.shops, p)
	NeedIcons.show_needs(node, NeedIcons.shown(p, wish[1] != WishTable.State.NONE, built))
	WishIconView.show_wish(node, wish)
	# A boarding-file waiter on its wait spot (FileWaiters) faces its way out,
	# not back along its walk to the spot.
	var way := walk_heading(p)
	if is_nan(face) and sim.files.waiters.at_spot(p) and way != Vector2.ZERO:
		face = atan2(way.x, way.y)
	return face


## The sim time now, in ticks, as frames draw it.
func _now() -> float:
	return clock.tick + clock.alpha if clock != null else 0.0


## Turns a view one tick toward what it faces now (PassengerTurns): a seated
## passenger, or one facing its work at security, faces `face`; any other
## faces the step it was drawn over this tick, or `face` when it did not move,
## or keeps the facing it had. A view just taken, or snapped, faces it at once,
## and so does one stepping into, using or leaving a toilet stall: its bags are
## kept clear of the partitions and the door for a body facing its step
## (StallCarry), and one turning over 0.3 s swept them through a partition
## (test_carry_in_stall). A lane passenger from UNPACK until it walks into the
## arch is drawn with SecurityLooks.setoff_yaw() instead, and the turn record
## is placed on it each tick, so the turn after it starts from there.
func _turn(node: Node3D, p: Passenger, face: float) -> void:
	var alpha := clock.alpha if clock != null else 1.0
	var from := NAN
	if _setoffs.has(p.id):
		from = (_setoffs[p.id] as Vector3).z
	elif _turns.has(p.id) and not _snapping:
		# The yaw it has as the set-off starts, kept as the turn's start.
		from = _turns.drawn(p.id, 1.0)
	var setoff := SecurityLooks.setoff_yaw(sim, p, from)
	if not is_nan(setoff):
		var before := setoff
		if _turns.has(p.id) and not _snapping:
			before = _turns.drawn(p.id, 1.0)
		_turns.place(p.id, setoff)
		if is_nan(from):
			from = SecurityLooks.arrival_yaw(sim, p)
		_setoffs[p.id] = Vector3(before, setoff, from)
		node.rotation.y = lerp_angle(before, setoff, alpha)
		return
	_setoffs.erase(p.id)
	var step: Vector3 = _cur[p.id] - _prev[p.id]
	var heading := walk_heading(p)
	var keep := atan2(heading.x, heading.y) if heading != Vector2.ZERO else node.rotation.y
	var target := _turns.target(p.id, keep)
	if _turn_locked(node) and not is_nan(face):
		target = face
	elif step.length() > 0.001 and not _snapping:
		target = atan2(step.x, step.z)
	elif not is_nan(face):
		target = face
	if _snapping or not _turns.has(p.id) or _in_stall(p):
		_turns.place(p.id, target)
	else:
		_turns.step(p.id, target)
	node.rotation.y = _turns.drawn(p.id, alpha)


## Moves a passenger's drawn offset at security one tick's walk toward its
## target (SecurityLooks.target_offset), or sets it there while it sets off
## from the tray table into the arch (SecurityLooks.setting_off()): set from
## how far it has walked, so it is the same for a view first drawn then.
func _chase(p: Passenger) -> void:
	var target := SecurityLooks.target_offset(sim, p)
	var now: Vector3 = _offsets.get(p.id, Vector3.ZERO)
	now = now.move_toward(target, PassengerSim.WALK_MM / 1000.0)
	if SecurityLooks.setting_off(sim, p):
		now = target
	if now == Vector3.ZERO:
		_offsets.erase(p.id)
	else:
		_offsets[p.id] = now


## Moves a passenger's drawn activity step toward ActivityPoses.offset() by
## at most a walking step: exactly onto it while the stay eases in and out.
func _chase_seat(p: Passenger) -> void:
	var target := ActivityPoses.offset(sim, p)
	var now: Vector3 = _seats.get(p.id, Vector3.ZERO)
	now = now.move_toward(target, PassengerSim.WALK_MM / 1000.0)
	if now == Vector3.ZERO:
		_seats.erase(p.id)
	else:
		_seats[p.id] = now


func _at_security(p: Passenger) -> bool:
	return p.stage == Passenger.Stage.SECURITY or p.stage == Passenger.Stage.SECURITY_QUEUE


## Stepping between a toilet stall's approach cell and its turn spot, off the
## grid path.
func _stepping_in_stall(p: Passenger) -> bool:
	return p.stage == Passenger.Stage.TOILET_ENTER or p.stage == Passenger.Stage.TOILET_EXIT


## Up from its seat with a roller, past its stand-up clip: a sofa or nap pod
## visitor in its up_tail() (standing at the seat for the pick-up, then
## stepping off to its slot cell), or a cafe guest in CAFE_STANDING_UP after
## STAND_UP_TICKS (the pick-up, then the shuffle out, CafeSim.up_ticks()),
## and on the tick it is handed back from that stage, when the shuffle's last
## step is drawn. Its drawn step picks the clip, so it holds still and then
## walks off. A booth guest has stepped out by then and only holds; a guest
## with no roller steps out while it rises, under the stand_up clip.
func _up_with_roller(p: Passenger, activity: ActivityPoses.Kind) -> bool:
	if not ParkRecovery.has_roller(p):
		return false
	var was: int = _stages.get(p.id, -1)
	if was == Passenger.Stage.CAFE_STANDING_UP and p.stage != was:
		return true
	if p.stage == Passenger.Stage.CAFE_STANDING_UP:
		return sim.tick - p.stage_tick >= PassengerSim.STAND_UP_TICKS
	if activity != ActivityPoses.Kind.SEAT and activity != ActivityPoses.Kind.RECLINE:
		return false
	var past_door := sim.tick - p.stage_tick >= ActivityPoses.seat_door(sim, p)
	return past_door and ActivityPoses.pose(sim, p) == StageKinds.Pose.UPRIGHT


## Stepping into, sitting in, or stepping out of a toilet stall.
func _in_stall(p: Passenger) -> bool:
	return (
		StageKinds.facility(p.stage) == StageKinds.Facility.TOILET
		and StageKinds.location(p.stage) == StageKinds.Location.FACILITY_SEAT
	)


## A seated passenger, or one facing its work at security, keeps its rotation.
func _turn_locked(node: Node3D) -> bool:
	return node.get_meta(&"seated", false) or node.get_meta(&"faces", false)
