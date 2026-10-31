class_name LandsideViews
extends Node3D
## Draws the landside's cars and taxis with the Toon vehicle models (Landside
## 4/4), and the curb bays and car parks through LandsidePlaces. Each tick it
## records where every vehicle on the map is (its lane, lot, berth or slot
## and position in mm) for the tick before and the tick now, keyed by vehicle
## id; each frame it draws between the two with the clock's alpha. A vehicle
## is drawn by distance along the polyline it drives (a lane, or a berth's or
## slot's path from LandsidePaths), facing the way the sim says it faces on
## the segment it is on: the direction of travel, so traffic keeps right as
## the lanes do (decision landside-traffic-drives-on-the-right-the-terminal-
## side-carri), except backing out of a stall. A parked car faces into its
## stall. The models' noses are local +Z. On a slope (a ramp, a kerb) the car
## pitches so both axles stand on the path's height under them (on_path()).
##
## A vehicle that moved from one lane onto the path that carries on from it
## (road to a berth's path, a berth's path to road_out, and so on;
## LandsidePaths.handover()) is drawn along the two, so it never jumps. Only a
## change with no path between (a load) is drawn where it is now. Vehicles
## waiting off the map (below 0 on road_in) are not drawn. Reads the sim and
## never writes to it.
##
## Clicking a vehicle (PassengerHud) selects it: a ring around it, and
## follow_anchor moves with it for the camera.

## Each kind's models; a vehicle's model is picked by its id, for looks only.
const MODELS := {
	LandsideVehicle.Kind.TAXI:
	[
		preload("res://assets/vehicles/tp_taxi_01a.glb"),
		preload("res://assets/vehicles/tp_taxi_01b.glb"),
		preload("res://assets/vehicles/tp_taxi_01c.glb"),
	],
	LandsideVehicle.Kind.CAR:
	[
		preload("res://assets/vehicles/tp_suv_01b.glb"),
		preload("res://assets/vehicles/tp_suv_01c.glb"),
		preload("res://assets/vehicles/tp_van_01a.glb"),
	],
}
const RING_RADIUS := 3.4
## How far outside a vehicle's drawn box a click still picks it.
const PICK_MARGIN_PX := 6.0

@export var landside: LandsideSim
@export var clock: SimClock
## When set, a finished load snaps every view to the loaded world.
@export var save_game: SaveGame

## Moves with the selected vehicle, for a camera to follow.
var follow_anchor := Node3D.new()
## The selected vehicle's id, or 0.
var selected_id := 0

var _places := LandsidePlaces.new()
## Vehicle id -> its drawn model.
var _nodes := {}
## Vehicle id -> where it was on the tick before and on the tick now, each
## {"place": [lane, lot, stop], "pos_mm", "dir"}.
var _prev := {}
var _cur := {}
## Model scene -> free nodes of it.
var _pool := {}
var _ring := MeshInstance3D.new()


func _ready() -> void:
	follow_anchor.name = "FollowAnchor"
	add_child(follow_anchor)
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.25
	torus.outer_radius = RING_RADIUS
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(1.0, 0.85, 0.3)
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = ring_material
	_ring.name = "SelectionRing"
	_ring.mesh = torus
	_ring.visible = false
	add_child(_ring)
	_places.name = "LandsidePlaces"
	_places.landside = landside
	add_child(_places)
	if clock != null:
		clock.ticked.connect(_on_ticked)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)
	sync()
	_settle()


func _process(_delta: float) -> void:
	draw()


## Records where every vehicle is on the tick that just ran: the tick now
## becomes the tick before. A vehicle new on the map starts with both the same.
func sync() -> void:
	if landside == null or landside.definition == null:
		return
	_places.refresh()
	var seen := {}
	for id in landside.vehicle_ids():
		var v := landside.get_vehicle(id)
		if v.lane == LandsideVehicle.Lane.ROAD_IN and v.pos_mm < 0:
			continue
		seen[id] = true
		var now := _place_of(v)
		if not _nodes.has(id):
			_nodes[id] = _take(v)
			_cur[id] = now
		_prev[id] = _cur[id]
		_cur[id] = now
	for id in _nodes.keys():
		if not seen.has(id):
			_release(id)


## Draws every vehicle at the sim's state now, with no tick to run (a load):
## the node set follows the loaded vehicles, the selection is cleared, and
## each vehicle is drawn where it stands.
func snap() -> void:
	for id in _nodes.keys():
		_release(id)
	selected_id = 0
	sync()
	_settle()
	draw()


## Places every vehicle between its last two tick positions, and the curb
## bays and car parks as the sim has them now (a lot built while paused shows
## at once).
func draw() -> void:
	_places.refresh()
	var alpha := clock.alpha if clock != null else 1.0
	for id in _nodes:
		(_nodes[id] as Node3D).transform = pose_at(id, alpha)
	if _nodes.has(selected_id):
		follow_anchor.position = (_nodes[selected_id] as Node3D).position
		_ring.position = follow_anchor.position + Vector3(0.0, 0.05, 0.0)
	_ring.visible = _nodes.has(selected_id)


## Where vehicle `id` is drawn `alpha` (0 to 1) of the way from the tick
## before to the tick now. Identity for a vehicle not drawn.
func pose_at(id: int, alpha: float) -> Transform3D:
	if not _cur.has(id):
		return Transform3D()
	var now: Dictionary = _cur[id]
	var before: Dictionary = _prev[id]
	var place: Array = now["place"]
	var mm: int = now["pos_mm"]
	var dir: Vector3 = now["dir"]
	var paths := landside.paths
	var off := paths.handover(before["place"], now["place"])
	if off >= 0 and now["pos_mm"] != before["pos_mm"] - off:
		mm = roundi(lerpf(before["pos_mm"] - off, now["pos_mm"], clampf(alpha, 0.0, 1.0)))
		if mm < 0:
			place = before["place"]
			mm += off
		dir = paths.facing(place[0], place[1], place[2], mm)
	var axles: Vector2 = (_nodes[id] as Node3D).get_meta(&"axles")
	var path := paths.path(place[0], place[1], place[2])
	return on_path(path, mm, dir, axles, paths.lead_in(place[0], place[1]))


## A car's pose `mm` along `path`, its nose the flat way `dir`: over the path
## point there, with its front and rear wheels (`axles`, their distances
## along the nose from the origin, front positive) on the path's own height
## where each wheel stands, so on a slope it pitches and neither wheel floats
## or sinks. Each wheel is looked up that far along the path, ahead of the
## car or behind it by the way the nose faces (backing out, the front wheels
## are behind on the path). A wheel before the path's start stands on `lead`,
## the way that runs into the start (LandsidePaths.lead_in(): the multi-storey's
## way-out ramp down to its exit lane), or at the start's height when there is
## none. A wheel past the path's end takes the end's height: every lane
## carries on flat from its end (the access lane's gate into the entrance, a
## slot's path into the exit lane), and carrying a last ramp segment on would
## lift a wheel off the slab at the gate.
static func on_path(
	path: PackedVector3Array, mm: int, dir: Vector3, axles: Vector2, lead := PackedVector3Array()
) -> Transform3D:
	var at := LandsideDefinition.point_at(path, mm)
	var way := 1.0 if dir.dot(LandsideDefinition.heading_at(path, mm)) >= 0.0 else -1.0
	var front := _height_on(path, lead, mm + roundi(way * axles.x * 1000.0))
	var rear := _height_on(path, lead, mm + roundi(way * axles.y * 1000.0))
	var rise := clampf((front - rear) / (axles.x - axles.y), -1.0, 1.0)
	at.y = front - axles.x * rise
	var nose := dir * sqrt(1.0 - rise * rise) + Vector3.UP * rise
	return Transform3D(Basis.looking_at(nose, Vector3.UP, true), at)


## The height `mm` along `path`, a negative `mm` back along `lead` (which ends
## where `path` starts), both clamped to their far ends.
static func _height_on(path: PackedVector3Array, lead: PackedVector3Array, mm: int) -> float:
	if mm >= 0 or lead.is_empty():
		return LandsideDefinition.point_at(path, mm).y
	var into := lead.duplicate()
	into.append(path[0])
	return LandsideDefinition.point_at(into, LandsideDefinition.length_mm(into) + mm).y


## Selects vehicle `id` (0 for none) and moves follow_anchor and the ring
## to it now, so a camera told to follow the anchor next starts from the car.
func select(id: int) -> void:
	selected_id = id if _nodes.has(id) else 0
	draw()


## The vehicle drawn under a screen point (inside its drawn box, projected,
## with a small margin), nearest the box centre when several are; 0 for none.
func pick(camera: Camera3D, screen: Vector2) -> int:
	var best := 0
	var best_px := INF
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var box: AABB = node.global_transform * (node.get_meta(&"box") as AABB)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var behind := false
		for i in 8:
			var corner := box.get_endpoint(i)
			if camera.is_position_behind(corner):
				behind = true
				break
			var at := camera.unproject_position(corner)
			lo = lo.min(at)
			hi = hi.max(at)
		if behind:
			continue
		var rect := Rect2(lo, hi - lo).grow(PICK_MARGIN_PX)
		if not rect.has_point(screen):
			continue
		var px := rect.get_center().distance_to(screen)
		if px < best_px:
			best = id
			best_px = px
	return best


## Whether vehicle `id` is drawn now.
func has_vehicle(id: int) -> bool:
	return _nodes.has(id)


func node_for(id: int) -> Node3D:
	return _nodes.get(id)


## The number of vehicles drawn.
func vehicle_count() -> int:
	return _nodes.size()


func places() -> LandsidePlaces:
	return _places


## Where a vehicle is now. A parked car faces into its stall
## (LandsidePlaces.parked_heading()), on its slot's deck in a multi-storey;
## every other car faces the way the sim says (pulling in or out of a slot,
## the way it drives, backing out of the stall included).
func _place_of(v: LandsideVehicle) -> Dictionary:
	var at := landside.world_position(v)
	var dir := landside.heading(v)
	if v.stage == LandsideVehicle.Stage.PARKED:
		dir = LandsidePlaces.parked_heading(landside.definition.lots[v.lot], at)
	return {"place": [v.lane, v.lot, v.stop], "pos_mm": v.pos_mm, "dir": dir}


## Makes the tick before the tick now, so a frame draws the tick now.
func _settle() -> void:
	for id in _cur:
		_prev[id] = _cur[id]


func _take(v: LandsideVehicle) -> Node3D:
	var models: Array = MODELS[v.kind]
	var scene: PackedScene = models[v.id % models.size()]
	var free: Array = _pool.get(scene, [])
	var node: Node3D
	if free.is_empty():
		node = scene.instantiate()
		node.set_meta(&"scene", scene)
		node.set_meta(&"box", _local_box(node))
		node.set_meta(&"axles", axles_of(node))
		add_child(node)
	else:
		node = free.pop_back()
	node.name = "Vehicle%d" % v.id
	node.transform = Transform3D()
	node.visible = true
	return node


func _release(id: int) -> void:
	var node: Node3D = _nodes[id]
	node.visible = false
	node.name = "PooledVehicle%d" % node.get_instance_id()
	var scene: PackedScene = node.get_meta(&"scene")
	if not _pool.has(scene):
		_pool[scene] = []
	(_pool[scene] as Array).append(node)
	_nodes.erase(id)
	_prev.erase(id)
	_cur.erase(id)


## How far along the nose (local +Z) from the model's origin its front and
## rear axles are: the middles of its "Wheel_F" and "Wheel_R" meshes. A
## model without both is an error; it is then drawn with its box's ends as
## its axles.
static func axles_of(model: Node3D) -> Vector2:
	var front := -INF
	var rear := INF
	for mi: MeshInstance3D in model.find_children("*Wheel_*", "MeshInstance3D", true, false):
		var z := (_to_model(model, mi) * mi.get_aabb()).get_center().z
		if mi.name.contains("Wheel_F"):
			front = maxf(front, z)
		elif mi.name.contains("Wheel_R"):
			rear = minf(rear, z)
	if is_inf(front) or is_inf(rear) or front <= rear:
		push_error("LandsideViews: %s has no front and rear wheels" % model.name)
		var box := _local_box(model)
		return Vector2(box.end.z, box.position.z)
	return Vector2(front, rear)


## The model's box in its own frame, from its meshes.
static func _local_box(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		var part: AABB = _to_model(model, mi) * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## A mesh's transform in its model's own frame (the model need not be in a tree).
static func _to_model(model: Node3D, mi: MeshInstance3D) -> Transform3D:
	var to_model := Transform3D()
	var node: Node = mi
	while node != model:
		to_model = (node as Node3D).transform * to_model
		node = node.get_parent()
	return to_model


func _on_ticked(_tick: int) -> void:
	sync()


func _on_loaded(ok: bool) -> void:
	if ok:
		snap()
