class_name PassengerViews
extends Node3D
## Draws the passengers with pooled Toon characters. Each tick it records
## every visible passenger's position for the tick before and the tick now,
## keyed by stable passenger id; each frame it draws between the two with the
## clock's alpha. A node is taken from the pool for a passenger's whole visit
## and returned when the passenger boards or a while after missing the flight.
## It reads the sim and never writes to it; animation never drives the sim.

const CHARACTERS: Array[PackedScene] = [
	preload("res://assets/people/tcp_male_character_01.glb"),
	preload("res://assets/people/tcp_female_character_01.glb"),
]
## Clip speeds measured by the Toon pipeline (SPEED lines), male then female.
const CLIP_WALK_MPS: Array[float] = [1.952, 1.922]
const CLIP_RUN_MPS: Array[float] = [5.295, 4.173]
const SIT_CLIP_SECONDS := 1.2
const LOOPED := ["idle", "walk", "run", "sit_idle"]
const MISSED_LINGER_TICKS := 200
const BUBBLE_HEIGHT := 2.5
const PICK_RADIUS_PX := 40.0

@export var clock: SimClock
@export var sim: PassengerSim

## Moves with the selected passenger, for a camera to follow.
var follow_anchor := Node3D.new()
var selected_id := 0

var _pool: Array[Array] = [[], []]
## Passenger id -> node.
var _nodes: Dictionary = {}
var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _ring := MeshInstance3D.new()
## Queue-full signs, drawn after the passengers.
var _markers := MissMarkers.new()
## The '+$' pops over cafe counters.
var _pops := CafePops.new()


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
	for scene in CHARACTERS:
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
	if clock != null:
		clock.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	draw()


func node_for(id: int) -> Node3D:
	return _nodes.get(id)


func active_count() -> int:
	return _nodes.size()


func cafe_pops() -> CafePops:
	return _pops


## A passenger's recorded position for the tick before (false) or now (true).
func tick_position(id: int, current: bool) -> Vector3:
	return (_cur if current else _prev).get(id, Vector3.ZERO)


## Where a passenger is drawn on this tick: the sim's position, moved onto
## its chair's pan at a gate seat (GateChairs).
func draw_position(p: Passenger) -> Vector3:
	return sim.world_position(p) + GateChairs.offset(sim, p)


## Records positions for the tick that just ran and updates poses and bubbles.
func sync() -> void:
	var seen := {}
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if not _visible(p):
			continue
		seen[id] = true
		var now := draw_position(p)
		if not _nodes.has(id):
			_nodes[id] = _take(p.variant)
			_cur[id] = now
		_prev[id] = _cur[id]
		_cur[id] = now
		_pose(_nodes[id], p)
	for id in _nodes.keys():
		if not seen.has(id):
			_release(id)
	_markers.sync()


## Places every node between its last two tick positions.
func draw() -> void:
	var alpha := clock.alpha if clock != null else 1.0
	var paused := clock == null or clock.paused
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var before: Vector3 = _prev[id]
		var after: Vector3 = _cur[id]
		node.position = before.lerp(after, alpha)
		var heading := after - before
		if heading.length() > 0.001 and not node.get_meta(&"seated", false):
			node.rotation.y = atan2(heading.x, heading.z)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		var base: float = node.get_meta(&"base_speed", 1.0)
		player.speed_scale = 0.0 if paused else base * clock.speed
	if _nodes.has(selected_id):
		follow_anchor.position = (_nodes[selected_id] as Node3D).position
		_ring.position = follow_anchor.position + Vector3(0.0, 0.05, 0.0)
	_ring.visible = _nodes.has(selected_id)
	_markers.draw()


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


func _visible(p: Passenger) -> bool:
	if p.stage == Passenger.Stage.MADE:
		return false
	if p.stage == Passenger.Stage.MISSED:
		return sim.tick - p.outcome_tick <= MISSED_LINGER_TICKS
	return true


func _take(variant: int) -> Node3D:
	var free: Array = _pool[variant]
	if not free.is_empty():
		var reused: Node3D = free.pop_back()
		reused.visible = true
		return reused
	var node := CHARACTERS[variant].instantiate() as Node3D
	node.set_meta(&"variant", variant)
	var bubble := Label3D.new()
	bubble.name = "Bubble"
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.font_size = 56
	bubble.outline_size = 14
	bubble.pixel_size = 0.006
	bubble.position = Vector3(0.0, BUBBLE_HEIGHT, 0.0)
	node.add_child(bubble)
	add_child(node)
	return node


func _release(id: int) -> void:
	var node: Node3D = _nodes[id]
	node.visible = false
	(node.get_node("AnimationPlayer") as AnimationPlayer).stop()
	node.set_meta(&"clip", "")
	_pool[node.get_meta(&"variant")].append(node)
	_nodes.erase(id)
	_prev.erase(id)
	_cur.erase(id)


func _pose(node: Node3D, p: Passenger) -> void:
	var clip := "idle"
	var base := 1.0
	var outside := p.stage == Passenger.Stage.APRON or p.stage == Passenger.Stage.SPAWNED
	var moving := (outside and p.apron_mm < p.apron_total_mm()) or p.is_moving()
	match p.stage:
		Passenger.Stage.SITTING_DOWN, Passenger.Stage.CAFE_SITTING_DOWN:
			clip = "sit_down"
			base = SIT_CLIP_SECONDS / (PassengerSim.SIT_DOWN_TICKS / float(SimClock.TICK_RATE))
		Passenger.Stage.SEATED, Passenger.Stage.CAFE_SEATED:
			clip = "sit_idle"
		Passenger.Stage.STANDING_UP, Passenger.Stage.CAFE_STANDING_UP:
			clip = "stand_up"
			base = SIT_CLIP_SECONDS / (PassengerSim.STAND_UP_TICKS / float(SimClock.TICK_RATE))
	if moving:
		var variant: int = node.get_meta(&"variant")
		var mm := PassengerSim.RUN_MM if p.late else PassengerSim.WALK_MM
		var sim_mps := mm * SimClock.TICK_RATE / 1000.0
		clip = "run" if p.late else "walk"
		base = sim_mps / (CLIP_RUN_MPS[variant] if p.late else CLIP_WALK_MPS[variant])
	var at_gate: bool = p.stage in PassengerSim.SEAT_STAGES and p.seat_object != 0
	var at_cafe := (
		p.stage in Passenger.CAFE_SEAT_STAGES and sim.cafes.seat_facing(p) != Vector2i.ZERO
	)
	node.set_meta(&"seated", at_gate or at_cafe)
	if at_gate:
		var facing: int = sim.grid.get_object(p.seat_object).get("facing", 0)
		var front := TerminalLayout.front_of(facing)
		node.rotation.y = atan2(front.x, front.y)
	elif at_cafe:
		var looks := sim.cafes.seat_facing(p)
		node.rotation.y = atan2(looks.x, looks.y)
	elif not moving and sim.cafes.counter_facing(p) != Vector2i.ZERO:
		# Waiting in a cafe queue or ordering: face the counter.
		var ahead := sim.cafes.counter_facing(p)
		node.rotation.y = atan2(ahead.x, ahead.y)
	node.set_meta(&"base_speed", base)
	if node.get_meta(&"clip", "") != clip:
		node.set_meta(&"clip", clip)
		(node.get_node("AnimationPlayer") as AnimationPlayer).play(clip)
	(node.get_node("Bubble") as Label3D).text = sim.bubble_text(p)
