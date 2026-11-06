class_name PassengerViews
extends Node3D
## Draws the passengers with pooled Toon characters. Each tick it records
## every visible passenger's position for the tick before and the tick now,
## keyed by stable passenger id; each frame it draws between the two with the
## clock's alpha. A node is taken from the pool for a passenger's whole visit
## and returned when the passenger boards or a while after missing the flight.
## It reads the sim and never writes to it; animation never drives the sim.
## Each node carries its thought bubble, its need icons (NeedIcons) and its
## shopping wish icon (WishIconView), set each tick and laid out each frame.

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

@export var clock: SimClock
@export var sim: PassengerSim
## When set, a finished load snaps every view to the loaded world.
@export var save_game: SaveGame

## Moves with the selected passenger, for a camera to follow.
var follow_anchor := Node3D.new()
## False shows every speech bubble, overlapping or not (plate probes compare).
var declutter_bubbles := true
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
## True while snap() syncs: the step from the pre-load position is no heading.
var _snapping := false
## Working array of _declutter_bubbles, reused each frame.
var _bubble_entries: Array[Dictionary] = []


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
## (ActivityPoses) and by its drawn offset at security (SecurityLooks).
func draw_position(p: Passenger) -> Vector3:
	return (
		sim.world_position(p)
		+ GateChairs.offset(sim, p)
		+ CafeChairs.offset(sim, p)
		+ _seats.get(p.id, Vector3.ZERO)
		+ _offsets.get(p.id, Vector3.ZERO)
	)


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
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if not _visible(p):
			continue
		seen[id] = true
		_chase(p)
		_chase_seat(p)
		var now := draw_position(p)
		if not _nodes.has(id):
			_nodes[id] = _take(p)
			_cur[id] = now
		now += SitHold.offset(_props, sim, p, now)
		_sit_off[id] = now - draw_position(p)
		_prev[id] = _cur[id]
		_cur[id] = now
		_turn(_nodes[id], p, _pose(_nodes[id], p))
	for id in _nodes.keys():
		if not seen.has(id):
			_release(id)
	_props.sync()
	_markers.sync()


## Draws every view at the sim's current state now, with no tick to run: a
## load while paused brings no tick, and a view drawn between its two pre-load
## positions would stay there. Syncs poses and the node set (passengers the
## load removed lose their view, new ones get one), then makes the previous and
## current positions the same so the frame draws the current one. With no
## interval to take a heading from, a walker faces along its current path or
## apron leg. Every turn and clip starts over, with no ease or blend from
## before the load.
func snap() -> void:
	_turns.clear()
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
		var heading := walk_heading(sim.get_passenger(id))
		if heading != Vector2.ZERO and not _turn_locked(node):
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
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var before: Vector3 = _prev[id]
		var after: Vector3 = _cur[id]
		node.position = before.lerp(after, alpha)
		if _turns.has(id):
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
	for id in _nodes:
		var node: Node3D = _nodes[id]
		NeedIcons.layout(node, node.get_node("Bubble") as Label3D, camera, unit, icons_shown)
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


func _on_ticked(_tick: int) -> void:
	sync()


func _on_loaded(ok: bool) -> void:
	if ok:
		snap()


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
	_pool[node.get_meta(&"body")].append(node)
	_nodes.erase(id)
	_offsets.erase(id)
	_seats.erase(id)
	_sit_off.erase(id)
	ActivityPoses.dress(node, 0.0, 0.0)
	_props.release(id)
	_turns.release(id)
	_prev.erase(id)
	_cur.erase(id)


## Sets the clip, dress, bubble and icons for this tick and returns the yaw
## the passenger faces on this tick (NAN where it faces its walk or keeps its
## turn).
func _pose(node: Node3D, p: Passenger) -> float:
	var face := NAN
	var clip := "idle"
	var base := 1.0
	var outside := p.stage == Passenger.Stage.APRON or p.stage == Passenger.Stage.SPAWNED
	var moving := (outside and p.apron_mm < p.apron_total_mm()) or p.is_moving()
	var mm := PassengerSim.RUN_MM if p.late else PassengerSim.WALK_MM
	var activity := ActivityPoses.kind(sim, p)
	var showering := activity == ActivityPoses.Kind.SHOWER
	var drawn_step := _at_security(p) or _stepping_in_stall(p) or showering
	if drawn_step or sim.files.holds(p.id) or _up_with_roller(p, activity):
		# The drawn step, so a held-back queue front or boarding-file waiter
		# (its path still open) does not walk in place and a step to the
		# table, into or out of a toilet stall or into or out of a shower, or
		# a roller passenger's step off its seat after its pick-up, is not an
		# idle slide.
		mm = roundi((_cur[p.id] - _prev[p.id]).length() * 1000.0)
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
	NeedIcons.show_needs(node, NeedIcons.shown(p, wish[1] != WishTable.State.NONE))
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
## (test_carry_in_stall).
func _turn(node: Node3D, p: Passenger, face: float) -> void:
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
	node.rotation.y = _turns.drawn(p.id, clock.alpha if clock != null else 1.0)


## Moves a passenger's drawn offset at security one tick's walk toward its
## target (SecurityLooks.target_offset).
func _chase(p: Passenger) -> void:
	var target := SecurityLooks.target_offset(sim, p)
	var now: Vector3 = _offsets.get(p.id, Vector3.ZERO)
	now = now.move_toward(target, PassengerSim.WALK_MM / 1000.0)
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
## STAND_UP_TICKS (the pick-up, then the shuffle out, CafeSim.up_ticks()). Its
## drawn step picks the clip, so it holds still and then walks off. A booth
## guest has stepped out by then and only holds; a guest with no roller steps
## out while it rises, under the stand_up clip.
func _up_with_roller(p: Passenger, activity: ActivityPoses.Kind) -> bool:
	if not ParkRecovery.has_roller(p):
		return false
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
