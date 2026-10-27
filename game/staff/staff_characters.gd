class_name StaffCharacters
extends Node3D
## Draws hired staff with pooled Toon characters, one model per role, so staff
## never look like passengers: a check-in agent in a navy skirt suit and a
## security officer in a white shirt and tie. A member is drawn while it is on
## the floor (not in the pool). Each tick it records the position for the tick
## before and the tick now, keyed by member id, and each frame it draws
## between the two with the clock's alpha, as PassengerViews does.
##
## StaffSim puts a member on duty on its station's service cell, the cell the
## passenger being served stands on. So an on-duty member is drawn at its
## station's post instead (POSTS: behind a desk's counter, beside a scanner's
## arch), facing the passenger side. The move onto and off the post is a
## snap, never a glide through the counter. The post is only drawn: nothing
## reserves it, so a desk backed onto a wall draws its agent behind the wall.
##
## Edits, hires, fires and loads between ticks resync at once (snapped) on the
## next frame, so a paused game shows them. It reads the sim and never writes
## to it.

## By StaffMember.Role: CHECKIN, SECURITY.
const CHARACTERS: Array[PackedScene] = [
	preload("res://assets/people/tcp_female_character_07.glb"),
	preload("res://assets/people/tcp_male_character_07.glb"),
]
## Walk clip speeds measured by the Toon pipeline (SPEED lines), by role.
const CLIP_WALK_MPS: Array[float] = [1.922, 1.952]
const LOOPED := ["idle", "walk"]
## Where an on-duty member stands, in its station's frame (BuildView.object_transform:
## footprint centre, front +Z): behind the desk's counter cell, and beside the
## scanner's landside half, just outside its right panel (in the next cell, so
## a scanner built right beside it overlaps this officer).
const POSTS := {
	&"checkin_desk": Vector3(-0.5, 0.0, -0.85),
	&"security_scanner": Vector3(0.75, 0.0, 0.55),
}

@export var clock: SimClock
@export var staff: StaffSim

var _pool: Array[Array] = [[], []]
## Member id -> node.
var _nodes: Dictionary = {}
var _prev: Dictionary = {}
var _cur: Dictionary = {}
## Something changed between ticks: the next sync snaps instead of interpolating.
var _dirty := false


func _ready() -> void:
	for scene in CHARACTERS:
		var probe := scene.instantiate()
		var player := probe.get_node("AnimationPlayer") as AnimationPlayer
		for clip in LOOPED:
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		probe.free()
	if clock != null:
		clock.ticked.connect(_on_ticked)
	if staff != null:
		staff.staff_changed.connect(_mark_dirty)
		if staff.sim != null:
			staff.sim.grid.graph_changed.connect(_on_graph_changed)
		sync(true)


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		sync(true)
	draw()


func node_for(id: int) -> Node3D:
	return _nodes.get(id)


func active_count() -> int:
	return _nodes.size()


## A member's recorded position for the tick before (false) or now (true).
func tick_position(id: int, current: bool) -> Vector3:
	return (_cur if current else _prev).get(id, Vector3.ZERO)


## Where the member on duty at `station` is drawn, in world space.
func post_position(station: int) -> Vector3:
	var record := staff.sim.grid.get_object(station)
	return _station_frame(record) * (POSTS[StringName(record["def"])] as Vector3)


## The yaw a member on duty at `station` is drawn with: facing the station's front.
func post_yaw(station: int) -> float:
	var front := TerminalLayout.front_of(staff.sim.grid.get_object(station)["facing"])
	return atan2(front.x, front.y)


## Records positions for the members on the floor and updates their poses. With
## `snap` both recorded positions are set to now, so nothing glides.
func sync(snap: bool = false) -> void:
	var seen := {}
	for id in staff.member_ids():
		var m := staff.get_member(id)
		if m.in_pool():
			continue
		seen[id] = true
		var node: Node3D = _nodes.get(id)
		if node != null and node.get_meta(&"role") != m.role:
			_release(id)
			node = null
		var fresh := node == null
		if fresh:
			node = _take(m.role)
			_nodes[id] = node
		var on_post := m.state == StaffMember.State.ON_DUTY
		var now := post_position(m.station) if on_post else staff.world_position(m)
		if snap or fresh or node.get_meta(&"on_post") != on_post:
			_prev[id] = now
		else:
			_prev[id] = _cur[id]
		_cur[id] = now
		node.set_meta(&"on_post", on_post)
		_pose(node, m, (_cur[id] as Vector3) - (_prev[id] as Vector3))
	for id in _nodes.keys():
		if not seen.has(id):
			_release(id)


## Places every node between its last two tick positions.
func draw() -> void:
	var alpha := clock.alpha if clock != null else 1.0
	var paused := clock == null or clock.paused
	for id in _nodes:
		var node: Node3D = _nodes[id]
		node.position = (_prev[id] as Vector3).lerp(_cur[id], alpha)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		var base: float = node.get_meta(&"base_speed", 1.0)
		player.speed_scale = 0.0 if paused else base * clock.speed


func _on_ticked(_tick: int) -> void:
	var snap := _dirty
	_dirty = false
	sync(snap)


## Inside a tick the tick's own sync shows the change; between ticks the next
## frame resyncs.
func _mark_dirty() -> void:
	if clock == null or not clock.is_in_tick():
		_dirty = true


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_mark_dirty()


func _station_frame(record: Dictionary) -> Transform3D:
	var cells := BuildCatalog.get_def(record["def"]).footprint(record["anchor"], record["facing"])
	return BuildView.object_transform(staff.sim.grid, cells, record["facing"])


func _take(role: StaffMember.Role) -> Node3D:
	var free: Array = _pool[role]
	var node: Node3D
	if not free.is_empty():
		node = free.pop_back()
		node.visible = true
	else:
		node = CHARACTERS[role].instantiate() as Node3D
		node.set_meta(&"role", role)
		add_child(node)
	node.rotation.y = 0.0
	node.set_meta(&"on_post", false)
	return node


func _release(id: int) -> void:
	var node: Node3D = _nodes[id]
	node.visible = false
	(node.get_node("AnimationPlayer") as AnimationPlayer).stop()
	node.set_meta(&"clip", "")
	_pool[node.get_meta(&"role")].append(node)
	_nodes.erase(id)
	_prev.erase(id)
	_cur.erase(id)


## `moved` is the step drawn between the two recorded positions; a walker faces
## it, or its next path cell when it was just placed (no step to draw yet).
func _pose(node: Node3D, m: StaffMember, moved: Vector3) -> void:
	var clip := "idle"
	var base := 1.0
	if m.state == StaffMember.State.ON_DUTY:
		node.rotation.y = post_yaw(m.station)
	elif m.state == StaffMember.State.TO_STATION and m.is_moving():
		clip = "walk"
		base = (PassengerSim.WALK_MM * SimClock.TICK_RATE / 1000.0) / CLIP_WALK_MPS[m.role]
		if moved.length() > 0.001:
			node.rotation.y = atan2(moved.x, moved.z)
		else:
			var ahead := m.path[m.path_index + 1] - m.at
			node.rotation.y = atan2(ahead.x, ahead.y)
	node.set_meta(&"base_speed", base)
	if node.get_meta(&"clip", "") != clip:
		node.set_meta(&"clip", clip)
		(node.get_node("AnimationPlayer") as AnimationPlayer).play(clip)
