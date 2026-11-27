class_name CheckedSuitcaseViews
extends Node3D
## Renders each pre-checkin passenger's color-matched checked suitcase beside
## them until check-in handoff (or missed-passenger retirement). Reads the sim
## and grid only; pooled independently from character skeletons.

const SCENE := preload("res://assets/interior/baggage_bag.glb")
const OFFSET := Vector3(-0.34, 0.275, -0.35)
const SCALE := 0.85

var _nodes := {}
var _pool: Array[Node3D] = []
var _prev := {}
var _cur := {}
var _bag_room_connected := false
var _bag_room_dirty := true
var _watched_grid: BuildGrid = null


func node_for(id: int) -> Node3D:
	return _nodes.get(id)


func active_count() -> int:
	return _nodes.size()


func sync(sim: PassengerSim, bodies: Dictionary, positions: Dictionary) -> void:
	for id: int in bodies:
		var p := sim.get_passenger(id)
		if not _wants_suitcase(sim, p):
			release(id)
			continue
		var bag_node: Node3D = _nodes.get(id)
		if bag_node == null:
			bag_node = _take(p.checked_bag_color)
			_nodes[id] = bag_node
			_prev[id] = positions[id]
		elif (
			not bag_node.has_meta(&"bag_color")
			or int(bag_node.get_meta(&"bag_color")) != p.checked_bag_color
		):
			Bag.paint_suitcase(bag_node, p.checked_bag_color)
			bag_node.set_meta(&"bag_color", p.checked_bag_color)
		_cur[id] = positions[id]
	for id: int in _nodes.keys():
		if not bodies.has(id):
			release(id)


func snap() -> void:
	for id in _cur:
		_prev[id] = _cur[id]


func draw(bodies: Dictionary, turns: PassengerTurns, alpha: float) -> void:
	var upright := Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP).scaled(Vector3.ONE * SCALE)
	for id: int in _nodes:
		var bag_node: Node3D = _nodes[id]
		var body: Node3D = bodies.get(id)
		var yaw: float = body.rotation.y if body != null else turns.drawn(id, alpha)
		var before: Vector3 = _prev.get(id, _cur[id])
		var after: Vector3 = _cur[id]
		var rot := Basis(Vector3.UP, yaw)
		bag_node.transform = Transform3D(rot * upright, before.lerp(after, alpha) + rot * OFFSET)


func release(id: int) -> void:
	var bag_node: Node3D = _nodes.get(id)
	if bag_node == null:
		return
	bag_node.visible = false
	_pool.append(bag_node)
	_nodes.erase(id)
	_prev.erase(id)
	_cur.erase(id)


func _mark_dirty(_arg1: Variant = null, _arg2: Variant = null) -> void:
	_bag_room_dirty = true


func _has_connected_bag_room(sim: PassengerSim) -> bool:
	if sim == null or sim.grid == null:
		return false
	if _watched_grid != sim.grid:
		_watched_grid = sim.grid
		_bag_room_dirty = true
		if not sim.grid.edit_applied.is_connected(_mark_dirty):
			sim.grid.edit_applied.connect(_mark_dirty)
		if not sim.grid.graph_changed.is_connected(_mark_dirty):
			sim.grid.graph_changed.connect(_mark_dirty)
	if _bag_room_dirty:
		_bag_room_connected = BagRoutes.build(sim.grid).connected_desk_count() > 0
		_bag_room_dirty = false
	return _bag_room_connected


func _wants_suitcase(sim: PassengerSim, p: Passenger) -> bool:
	if p == null or not _has_connected_bag_room(sim):
		return false
	if PassengerBags.BEFORE_DROP.has(p.stage):
		return true
	return p.stage == Passenger.Stage.MISSED and PassengerBags.BEFORE_DROP.has(p.missed_stage)


func _take(color_index: int) -> Node3D:
	var bag_node: Node3D = _pool.pop_back() if not _pool.is_empty() else SCENE.instantiate()
	if bag_node.get_parent() == null:
		add_child(bag_node)
	Bag.paint_suitcase(bag_node, color_index)
	bag_node.set_meta(&"bag_color", color_index)
	bag_node.visible = true
	return bag_node
