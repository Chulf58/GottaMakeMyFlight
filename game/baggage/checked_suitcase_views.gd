class_name CheckedSuitcaseViews
extends Node3D
## Renders each pre-checkin passenger's color-matched checked suitcase beside
## them until check-in handoff (or missed-passenger retirement). Reads the sim
## and grid only; pooled independently from character skeletons.

const SCENE := preload("res://assets/interior/baggage_bag.glb")
const OFFSET := Vector3(-0.34, 0.275, -0.35)
const SCALE := 0.85
const BAG_GRIP_LOCAL := Vector3(0.0, 0.215, 0.240)
const BAG_SIZE := Vector3(0.392, 0.256, 0.550)
const HANDOFF_DELAY_TICKS := 6.0
const HANDOFF_TICKS := 16.0

var _nodes := {}
var _pool: Array[Node3D] = []
var _prev := {}
var _cur := {}


func node_for(id: int) -> Node3D:
	return _nodes.get(id)


func active_count() -> int:
	return _nodes.size()


func sync(sim: PassengerSim, bodies: Dictionary, positions: Dictionary) -> void:
	for id: int in bodies:
		var p := sim.get_passenger(id)
		if not wants_suitcase(sim, p):
			release(id)
			continue
		var bag_node: Node3D = _nodes.get(id)
		if bag_node == null:
			bag_node = _take(p.checked_bag_color)
			_nodes[id] = bag_node
			_prev[id] = positions[id]
		else:
			_prev[id] = _cur.get(id, positions[id])
			if (
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


func draw(
	bodies: Dictionary,
	turns: PassengerTurns,
	alpha: float,
	sim: PassengerSim = null,
	props: CarryOnProps = null,
	now := 0.0
) -> void:
	var upright := Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP).scaled(Vector3.ONE * SCALE)
	for id: int in _nodes:
		var bag_node: Node3D = _nodes[id]
		var body: Node3D = bodies.get(id)
		if sim != null and props != null and body != null:
			var held: Dictionary = props._held.get(id, {})
			if int(held.get("checked_hand", -1)) >= 0:
				place_for_passenger(sim, id, body, props, held, now)
				continue
		var yaw: float = body.rotation.y if body != null else turns.drawn(id, alpha)
		var before: Vector3 = _prev.get(id, _cur[id])
		var after: Vector3 = _cur[id]
		var rot := Basis(Vector3.UP, yaw)
		bag_node.transform = Transform3D(rot * upright, before.lerp(after, alpha) + rot * OFFSET)


func place_for_passenger(
	sim: PassengerSim, id: int, body: Node3D, props: CarryOnProps, held: Dictionary, now: float
) -> void:
	var bag_node: Node3D = _nodes.get(id)
	if bag_node == null or body == null or sim == null:
		return
	var p := sim.get_passenger(id)
	var hand := int(held.get("checked_hand", -1))
	if p == null or hand < 0:
		return
	var pose := handoff_pose(sim, p, now)
	var u: float = pose["u"]
	if u >= 0.65 and pose.has("desk_xf"):
		bag_node.global_transform = pose["desk_xf"]
		return
	var grip := props.grip_of(body, hand)
	var carry_xf := held_transform(
		grip, body.global_position, body.rotation.y, SCALE, float(held.get("bag_weight", 0.0))
	)
	if u <= 0.0 or not pose.has("desk_xf"):
		bag_node.global_transform = carry_xf
		return
	var t := u / 0.65
	var s := t * t * (3.0 - 2.0 * t)
	var desk_xf: Transform3D = pose["desk_xf"]
	var rot := carry_xf.basis.orthonormalized().slerp(desk_xf.basis.orthonormalized(), s).scaled(
		Vector3.ONE * lerpf(SCALE, 1.0, s)
	)
	var at := carry_xf.origin.lerp(desk_xf.origin, s) + Vector3.UP * (0.10 * sin(PI * t))
	bag_node.global_transform = Transform3D(rot, at)


static func held_transform(
	grip: Vector3, centre: Vector3, yaw: float, scale_by: float, bag_weight := 0.0
) -> Transform3D:
	var turn := Basis(Vector3.UP, yaw)
	var lateral := turn * Vector3.RIGHT
	var out := lateral if (grip - centre).dot(lateral) >= 0.0 else -lateral
	var inward := -out
	var hang := Basis(inward.cross(Vector3.UP), inward, Vector3.UP).scaled(Vector3.ONE * scale_by)
	var side_xf := Transform3D(hang, grip - hang * BAG_GRIP_LOCAL)
	if bag_weight <= 0.0:
		return side_xf
	var forward := turn * Vector3.BACK
	var flat := Basis(forward, Vector3.UP, forward.cross(Vector3.UP)).scaled(Vector3.ONE * scale_by)
	var front_xf := Transform3D(
		flat, grip - Vector3.UP * (BAG_SIZE.y * scale_by + CarryOnProps.FRONT_PALM_M)
	)
	var basis := (
		side_xf
		. basis
		. orthonormalized()
		. slerp(front_xf.basis.orthonormalized(), bag_weight)
		. scaled(Vector3.ONE * scale_by)
	)
	return Transform3D(basis, side_xf.origin.lerp(front_xf.origin, bag_weight))


static func handoff_progress(sim: PassengerSim, p: Passenger, now: float) -> float:
	if sim == null or p == null or p.is_arriving() or p.stage != Passenger.Stage.CHECKIN:
		return 0.0
	if p.is_moving() or p.station <= 0:
		return 0.0
	if BaggageViews.desk_transform(sim.grid, p.station, 0) == null:
		return 0.0
	var total := maxf(1.0, float(p.service_end - p.stage_tick))
	var dur := minf(HANDOFF_TICKS, maxf(1.0, total - 4.0))
	var delay := minf(HANDOFF_DELAY_TICKS, maxf(0.0, total - dur - 2.0))
	return clampf((now - (float(p.stage_tick) + delay)) / dur, 0.0, 1.0)


static func handoff_pose(sim: PassengerSim, p: Passenger, now: float) -> Dictionary:
	var u := handoff_progress(sim, p, now)
	if u <= 0.0:
		return {"u": 0.0, "holds": true, "curl": 1.0, "reach": 0.0, "target": Vector3.ZERO}
	var desk_v: Variant = BaggageViews.desk_transform(sim.grid, p.station, 0)
	if desk_v == null:
		return {"u": 0.0, "holds": true, "curl": 1.0, "reach": 0.0, "target": Vector3.ZERO}
	var desk_xf: Transform3D = desk_v
	return {
		"u": u,
		"holds": u < 0.65,
		"curl": clampf((0.68 - u) / 0.18, 0.0, 1.0),
		"reach": sin(PI * clampf(u / 0.90, 0.0, 1.0)),
		"target": desk_xf.origin + Vector3(0.0, 0.16, 0.0),
		"desk_xf": desk_xf,
	}


func release(id: int) -> void:
	var bag_node: Node3D = _nodes.get(id)
	if bag_node == null:
		return
	bag_node.visible = false
	_pool.append(bag_node)
	_nodes.erase(id)
	_prev.erase(id)
	_cur.erase(id)


static func has_connected_bag_room(sim: PassengerSim) -> bool:
	if sim == null or sim.grid == null:
		return false
	var grid := sim.grid
	if not grid.has_meta(&"_bag_room_state"):
		var state := {"dirty": true, "connected": false, "route_version": -1}
		grid.set_meta(&"_bag_room_state", state)
		grid.edit_applied.connect(
			func(_a: Variant = null, _b: Variant = null) -> void: state["dirty"] = true
		)
		grid.graph_changed.connect(
			func(_a: Variant = null, _b: Variant = null) -> void: state["dirty"] = true
		)
	var state: Dictionary = grid.get_meta(&"_bag_room_state")
	var rv := grid.route_version()
	if state["dirty"] or int(state.get("route_version", -1)) != rv:
		state["connected"] = BagRoutes.build(grid).connected_desk_count() > 0
		state["dirty"] = false
		state["route_version"] = rv
	return state["connected"]


static func wants_suitcase(sim: PassengerSim, p: Passenger) -> bool:
	if p == null:
		return false
	if p.is_arriving():
		return p.has_claimed_bag and not p.arrival_done
	if not has_connected_bag_room(sim):
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
