class_name LotBarriers
extends RefCounted
## The barrier arms of the drawn car parks: an arm lifts as a car comes close on
## its way through it and drops after the car has passed (board 00291df0, user
## ruling 2026-11-03 "Animate near cars"). The arms are the lot model's nodes
## named "*_Barrier" (TP_Parking_01A's Entry and Exit Barrier, each hinged at its
## post); a car park with none (the multi-storey) has nothing to lift. View only:
## it reads the sim and never writes to it, and nothing of it is saved.
##
## step() runs once per sim tick (LandsideViews.sync, from SimClock.ticked), never
## on a real-time timer, so at any game speed a car cannot get past an arm between
## two checks (anti-pattern a-view-that-reacts-to-moving-sim-objects-must-check-
## them-on). An arm wants to be up while a car that is not parked is within
## AHEAD_MM before the point where its path crosses the arm, or within BEHIND_MM
## past it, along that path and the way the car faces. Each tick the arm's lift
## (0 closed, 1 up) moves toward what it wants by a fixed step; draw() places the
## arm between its last two ticks with the clock's alpha. restart() (a load)
## forgets every arm, so the next step() puts each one straight where its cars
## want it (anti-pattern a-per-id-view-record-holding-a-sim-tick-must-start-over-
## on-l).

## How far a raised arm turns up about its hinge.
const OPEN_ANGLE := PI * 0.46
## Ticks from closed to up, and from up to closed.
const OPEN_TICKS := 16
const CLOSE_TICKS := 24
## A car's nose is at most 3 m ahead of its origin, and it drives
## LandsideSim.SPEED_MM a tick: from this far before the arm, the arm is fully up
## before the nose reaches it.
const AHEAD_MM := 3000 + OPEN_TICKS * LandsideSim.SPEED_MM + 500
## Its tail is at most 3 m behind its origin: the arm starts down once the tail
## is half a metre past.
const BEHIND_MM := 3500
## A path crosses an arm within this of the arm's ends.
const END_SLACK := 0.3
const ARM_NAMES := "*_Barrier"

## Lot spot -> {"node": the drawn car park, "arms": [arm records]}.
var _lots := {}


## Follows the sim on the tick that just ran: binds the arms of each car park
## `places` draws (a new or rebuilt one starts with its arms where its cars want
## them), forgets car parks no longer drawn, and moves each arm a step toward up
## or closed.
func step(places: LandsidePlaces, landside: LandsideSim) -> void:
	for spot: int in _lots.keys():
		if places.lot_node(spot) != (_lots[spot] as Dictionary)["node"]:
			_lots.erase(spot)
	for spot in landside.lots_built.size():
		var node := places.lot_node(spot)
		if node == null:
			continue
		var fresh := not _lots.has(spot)
		if fresh:
			_lots[spot] = {"node": node, "arms": _bind(node)}
		for arm: Dictionary in (_lots[spot] as Dictionary)["arms"]:
			var want := 1.0 if _wanted(arm, spot, landside) else 0.0
			var now: float = arm["now"]
			var rate := 1.0 / (OPEN_TICKS if want > now else CLOSE_TICKS)
			arm["prev"] = want if fresh else now
			arm["now"] = want if fresh else move_toward(now, want, rate)


## Places every arm `alpha` (0 to 1) of the way from its lift on the tick before
## to its lift on the tick now.
func draw(alpha: float) -> void:
	for spot: int in _lots:
		var lot: Dictionary = _lots[spot]
		if not is_instance_valid(lot["node"]):
			continue
		for arm: Dictionary in lot["arms"]:
			var lift := lerpf(arm["prev"], arm["now"], clampf(alpha, 0.0, 1.0))
			var turn := Basis(arm["axis"], OPEN_ANGLE * smoothstep(0.0, 1.0, lift))
			var pivot: Vector3 = arm["pivot"]
			var about := Transform3D(turn, pivot - turn * pivot)
			(arm["node"] as Node3D).transform = arm["to_parent"] * about * arm["rest"]


## Puts every arm back at rest and forgets it (a load): the next step() binds
## it again from its rest pose and puts it straight where the loaded cars want it.
func restart() -> void:
	for spot: int in _lots:
		var lot: Dictionary = _lots[spot]
		if not is_instance_valid(lot["node"]):
			continue
		for arm: Dictionary in lot["arms"]:
			(arm["node"] as Node3D).transform = arm["to_parent"] * arm["rest"]
	_lots.clear()


## The lift of the arm named `arm_name` of lot spot `spot` on the tick now (0
## closed, 1 up), or -1 when there is no such arm.
func lift(spot: int, arm_name: String) -> float:
	var lot: Dictionary = _lots.get(spot, {})
	for arm: Dictionary in lot.get("arms", []):
		if (arm["node"] as Node).name == arm_name:
			return arm["now"]
	return -1.0


## The arm records of a car park node, everything in the frame of the node's
## parent (LandsidePlaces, the landside's own frame): the arm's transform there
## at rest, its hinge, its flat direction from the hinge, its length that way,
## the level axis that turns it up, and the way back to its own parent's frame.
static func _bind(lot: Node3D) -> Array[Dictionary]:
	var arms: Array[Dictionary] = []
	for found: Node in lot.find_children(ARM_NAMES, "Node3D", true, false):
		var node := found as Node3D
		var parent := lot.transform * _to_lot(lot, node.get_parent())
		var rest := parent * node.transform
		var pivot := rest.origin
		var corners: Array[Vector3] = []
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		for mi: MeshInstance3D in meshes:
			var box: AABB = lot.transform * _to_lot(lot, mi) * mi.get_aabb()
			for i in 8:
				corners.append(box.get_endpoint(i))
		if corners.is_empty():
			push_error("LotBarriers: %s has no mesh" % node.name)
			continue
		var middle := Vector3.ZERO
		for c in corners:
			middle += c
		middle /= corners.size()
		var along := Vector3(middle.x - pivot.x, 0.0, middle.z - pivot.z).normalized()
		var length := 0.0
		for c in corners:
			length = maxf(length, (c - pivot).dot(along))
		(
			arms
			. append(
				{
					"node": node,
					"rest": rest,
					"to_parent": parent.affine_inverse(),
					"pivot": pivot,
					"along": along,
					"length": length,
					"axis": along.cross(Vector3.UP).normalized(),
					"prev": 0.0,
					"now": 0.0,
					"crossings": {},
				}
			)
		)
	return arms


## Whether a car of lot spot `spot` that is not parked is close to `arm` along its
## path: within AHEAD_MM before a crossing or BEHIND_MM past it, the way it faces.
static func _wanted(arm: Dictionary, spot: int, landside: LandsideSim) -> bool:
	for id in landside.vehicle_ids():
		var v := landside.get_vehicle(id)
		if v.lot != spot or v.stage == LandsideVehicle.Stage.PARKED:
			continue
		var path := landside.paths.path(v.lane, v.lot, v.stop)
		var key := Vector3i(v.lane, v.lot, v.stop)
		var cache: Dictionary = arm["crossings"]
		if not cache.has(key):
			cache[key] = _crossings(arm, path)
		var drives := LandsideDefinition.heading_at(path, v.pos_mm)
		var way := 1 if landside.heading(v).dot(drives) >= 0.0 else -1
		for at: int in cache[key]:
			var ahead := (at - v.pos_mm) * way
			if ahead <= AHEAD_MM and ahead >= -BEHIND_MM:
				return true
	return false


## Where along `path` (mm, as LandsideDefinition measures it) it crosses `arm`'s
## line between the hinge and the tip.
static func _crossings(arm: Dictionary, path: PackedVector3Array) -> Array[int]:
	var out: Array[int] = []
	var pivot: Vector3 = arm["pivot"]
	var normal: Vector3 = arm["axis"]
	var along: Vector3 = arm["along"]
	var mm := 0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var segment := roundi(a.distance_to(b) * 1000.0)
		var sa := Vector3(a.x - pivot.x, 0.0, a.z - pivot.z).dot(normal)
		var sb := Vector3(b.x - pivot.x, 0.0, b.z - pivot.z).dot(normal)
		if sa * sb <= 0.0 and not (is_zero_approx(sa) and is_zero_approx(sb)):
			var t := sa / (sa - sb)
			var q := a.lerp(b, t)
			var u := Vector3(q.x - pivot.x, 0.0, q.z - pivot.z).dot(along)
			var at := mm + roundi(segment * t)
			if u >= -END_SLACK and u <= arm["length"] + END_SLACK:
				if out.is_empty() or absi(at - out[out.size() - 1]) > 100:
					out.append(at)
		mm += segment
	return out


## `node`'s transform relative to `lot` (the chain of local transforms between).
static func _to_lot(lot: Node3D, node: Node) -> Transform3D:
	var t := Transform3D()
	var n := node
	while n != null and n != lot:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
