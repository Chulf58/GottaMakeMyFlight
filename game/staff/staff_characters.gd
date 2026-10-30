class_name StaffCharacters
extends Node3D
## Draws hired staff with pooled Toon characters, one model per role, so staff
## never look like passengers: a check-in agent in a navy skirt suit and a
## security officer in a white shirt and tie. A shop server wears the check-in
## agent's suit until it has a model of its own. A member is drawn while it is on
## the floor (not in the pool). Each tick it records the position for the tick
## before and the tick now, keyed by member id, and each frame it draws
## between the two with the clock's alpha, as PassengerViews does.
##
## StaffSim walks a member onto its station's staff spot (StaffSpots: behind
## a desk's counter, beside a scanner's landside half) and puts it on duty
## there, so a member is always drawn where it stands: walking onto the spot
## and off it again is an ordinary walk, with no jump. On duty it faces its
## station's front, the passenger side; a security lane's officer faces its
## work instead (post_yaw()). A fired member walking out to the
## entrance is drawn walking until it is gone.
##
## Walking through a security lane's arch, a member tucks its arms in toward
## the body, eased in and out, so its hands stay clear of the narrow posts
## (StaffArchTuck): the passage state is taken each tick, the weight drawn
## each frame. A snapped sync starts each member's tuck over, settled.
##
## Edits, hires, fires and loads between ticks resync at once (snapped) on the
## next frame, so a paused game shows them. It reads the sim and never writes
## to it.

const AGENT_SUIT := preload("res://assets/people/tcp_female_character_07.glb")
## By StaffMember.Role: CHECKIN, SECURITY, SHOP.
const CHARACTERS: Array[PackedScene] = [
	AGENT_SUIT,
	preload("res://assets/people/tcp_male_character_07.glb"),
	AGENT_SUIT,
]
## Walk clip speeds measured by the Toon pipeline (SPEED lines), by role.
const CLIP_WALK_MPS: Array[float] = [1.922, 1.952, 1.922]
const LOOPED := ["idle", "walk"]

@export var clock: SimClock
@export var staff: StaffSim

var _pool: Array[Array] = [[], [], []]
## Member id -> node.
var _nodes: Dictionary = {}
var _prev: Dictionary = {}
var _cur: Dictionary = {}
## Member id -> its arch tuck record (StaffArchTuck).
var _tucks: Dictionary = {}
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


## How far member `id` has tucked its arms in for an arch now: 0 swinging, 1
## tucked (StaffArchTuck.weight()).
func tuck_of(id: int) -> float:
	return StaffArchTuck.weight(_tucks.get(id, {}), _now())


## Where the member on duty at `station` is drawn, in world space: the
## centre of its staff spot.
func post_position(station: int) -> Vector3:
	return staff.sim.grid.cell_to_world(staff.spot_of(station))


## The yaw a member on duty at `station` in `slot` is drawn with: at a whole
## security lane, looking at its work (the primary officer at the X-ray belt,
## the helper at the repack berth, each beside it); elsewhere facing the
## station's front.
func post_yaw(station: int, slot: StaffMember.Slot = StaffMember.Slot.PRIMARY) -> float:
	var lane := staff.sim.layout.security_lanes.lane(station)
	if not lane.is_empty():
		var work: Vector2i = lane["berth" if slot == StaffMember.Slot.HELPER else "xray_belt"]
		var ahead := work - staff.spot_of(station, slot)
		return atan2(ahead.x, ahead.y)
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
		var now := staff.world_position(m)
		if snap or fresh:
			_prev[id] = now
		else:
			_prev[id] = _cur[id]
		_cur[id] = now
		_pose(node, m, (_cur[id] as Vector3) - (_prev[id] as Vector3))
		# A snapped sync (a load among them: member ids survive it) starts the
		# tuck over, settled where the member stands, with no turn from before.
		if snap:
			_tucks.erase(id)
		var inside := StaffArchTuck.in_arch_passage(staff.sim.grid, m)
		StaffArchTuck.update(_tucks.get_or_add(id, {}), inside, _tick())
	for id in _nodes.keys():
		if not seen.has(id):
			_release(id)


## Places every node between its last two tick positions.
func draw() -> void:
	var alpha := clock.alpha if clock != null else 1.0
	var paused := clock == null or clock.paused
	var now := _now()
	for id in _nodes:
		var node: Node3D = _nodes[id]
		node.position = (_prev[id] as Vector3).lerp(_cur[id], alpha)
		StaffArchTuck.pose(node, StaffArchTuck.weight(_tucks.get(id, {}), now))
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
	return node


func _release(id: int) -> void:
	var node: Node3D = _nodes[id]
	node.visible = false
	(node.get_node("AnimationPlayer") as AnimationPlayer).stop()
	node.set_meta(&"clip", "")
	StaffArchTuck.pose(node, 0.0)
	_pool[node.get_meta(&"role")].append(node)
	_nodes.erase(id)
	_prev.erase(id)
	_cur.erase(id)
	_tucks.erase(id)


## Sim time now, between ticks: the tick and the clock's alpha.
func _now() -> float:
	return clock.tick + clock.alpha if clock != null else 0.0


func _tick() -> float:
	return float(clock.tick) if clock != null else 0.0


## `moved` is the step drawn between the two recorded positions; a walker faces
## it, or its next path cell when it was just placed (no step to draw yet).
func _pose(node: Node3D, m: StaffMember, moved: Vector3) -> void:
	var clip := "idle"
	var base := 1.0
	if m.state == StaffMember.State.ON_DUTY:
		node.rotation.y = post_yaw(m.station, m.slot)
	elif m.is_moving():
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
