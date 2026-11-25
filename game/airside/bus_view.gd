class_name BusView
extends Node3D
## Renders one tp_bus_01a.glb shuttle per Bus Gate driven smoothly from
## BusShuttleSim.pose_at() (decisions 6d69da79, 710a78b4).

const BUS_SCENE := preload("res://assets/airside/landmarks/tp_bus_01a.glb")

@export var clock: SimClock
@export var sim: BusShuttleSim
@export var save_game: SaveGame

var _nodes: Dictionary = {}


func _ready() -> void:
	if clock != null:
		clock.ticked.connect(_on_ticked)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	draw()


func _process(_delta: float) -> void:
	draw()


func node_for(gate: String) -> Node3D:
	return _nodes.get(gate)


func active_count() -> int:
	return _nodes.size()


func draw() -> void:
	var fallback := float(sim.tick) if sim != null else 0.0
	var time := float(clock.tick) + clock.alpha if clock != null else fallback
	_draw_at(time)


func _draw_at(time: float) -> void:
	if sim == null:
		return
	var gates := sim.bus_gates()
	for gate: String in _nodes.keys():
		if not gates.has(gate):
			(_nodes[gate] as Node3D).queue_free()
			_nodes.erase(gate)
	for gate in gates:
		var node := _ensure_node(gate)
		var pose := sim.pose_at(gate, time)
		node.visible = bool(pose.get("visible", false))
		if node.visible:
			var origin: Vector3 = pose["origin"]
			var yaw := float(pose["yaw"])
			node.transform = Transform3D(Basis(Vector3.UP, yaw), origin)


func _ensure_node(gate: String) -> Node3D:
	if _nodes.has(gate):
		return _nodes[gate]
	var node := BUS_SCENE.instantiate() as Node3D
	node.name = "ShuttleBus_%s" % gate
	add_child(node)
	_nodes[gate] = node
	return node


func _on_ticked(tick_now: int) -> void:
	_draw_at(float(tick_now))


func _on_loaded(_ok: bool) -> void:
	draw()
