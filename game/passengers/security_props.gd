class_name SecurityProps
extends Node3D
## The trays and carry-on bags of passengers at security (Security 7/8),
## drawn where SecurityLooks says they are. sync() runs on each tick after
## PassengerViews has posed its characters and takes or returns pooled
## props; draw() runs each frame after the characters are placed and puts
## every prop in place from the drawn characters, so a tray riding the X-ray
## belt keeps pace with its passenger between ticks. A bag that changes home
## (hand, tray, floor) moves there over TRANSFER_MS instead of jumping. It
## reads the sim and the views and never writes either.

const TRAY_MOUNTS := {
	SecurityLooks.Tray.IN: [SecurityLanes.TRAY_TABLE, "Mount_TrayIn"],
	SecurityLooks.Tray.OUT: [SecurityLanes.PICKUP_TABLE, "Mount_TrayOut"],
}
const SCAN_MOUNT := [SecurityLanes.XRAY_BELT, "Mount_TrayScan"]
## A bag in a tray rests on the tray's floor, this far above its mount.
const TRAY_FLOOR_M := 0.012
## A carried bag hangs this far under the hand that holds it.
const GRIP_DROP_M := 0.02
## A carried bag's inner face stays at least this far from the body's centre
## line (the Toon characters' hips and thighs reach about 0.2 m).
const CARRY_CLEAR_M := 0.22
const TRANSFER_MS := 300.0
const HANDS: Array[String] = ["Hand.R", "Hand.L"]

## Mount name -> its transform relative to its kit piece's root.
static var _mounts := {}
static var _bag_size := Vector3.ZERO

var sim: PassengerSim
var views: PassengerViews

## Passenger id -> {"tray": Node3D or null, "tray_at": SecurityLooks.Tray,
## "bags": Array of {"node", "home", "from", "since"}, "homes": Array}.
var _held := {}
var _free_trays: Array[Node3D] = []
var _free_bags: Array[Node3D] = []


## A mount's transform relative to its piece (read once from the kit scene).
static func mount_local(piece: StringName, mount: String) -> Transform3D:
	if not _mounts.has(mount):
		var node := InteriorKit.instantiate(piece)
		var found := node.find_child(mount, true, false) as Node3D
		var xf := Transform3D.IDENTITY
		var at: Node = found
		while at != null and at != node:
			xf = (at as Node3D).transform * xf
			at = at.get_parent()
		node.free()
		_mounts[mount] = xf
	return _mounts[mount]


## The carry-on bag's size at scale 1 (read once from the kit scene).
static func bag_size() -> Vector3:
	if _bag_size == Vector3.ZERO:
		var node := InteriorKit.instantiate("carry_on_bag")
		var box := AABB()
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			box = (
				box.merge(mi.transform * mi.get_aabb())
				if box.size != Vector3.ZERO
				else (mi.transform * mi.get_aabb())
			)
		node.free()
		_bag_size = box.size
	return _bag_size


## The world transform of a lane's tray mount (`at` IN or OUT, or the scan
## mount for RIDE's middle).
static func mount_world(
	grid: BuildGrid, lane: Dictionary, piece: StringName, mount: String
) -> Transform3D:
	var cells: Array[Vector2i] = [lane[piece]]
	return BuildView.object_transform(grid, cells, lane["facing"]) * mount_local(piece, mount)


## Where a riding tray is when its passenger is drawn at `body`: from the tray
## table over the belt to the pickup table, by the body's progress along the
## passage from the unpack cell to the pickup cell.
static func ride(grid: BuildGrid, lane: Dictionary, body: Vector3) -> Transform3D:
	var unpack := grid.cell_to_world(lane["unpack"])
	var pickup := grid.cell_to_world(lane["pickup"])
	var along := pickup - unpack
	var t := clampf((body - unpack).dot(along) / along.length_squared(), 0.0, 1.0)
	var start := mount_world(grid, lane, SecurityLanes.TRAY_TABLE, "Mount_TrayIn")
	var mid := mount_world(grid, lane, SCAN_MOUNT[0], SCAN_MOUNT[1])
	var end := mount_world(grid, lane, SecurityLanes.PICKUP_TABLE, "Mount_TrayOut")
	if t < 0.5:
		return start.interpolate_with(mid, t * 2.0)
	return mid.interpolate_with(end, (t - 0.5) * 2.0)


## Takes and returns props to match each drawn passenger's look on this tick.
func sync() -> void:
	var seen := {}
	for id in sim.passenger_ids():
		var node := views.node_for(id)
		if node == null:
			continue
		var p := sim.get_passenger(id)
		var homes := SecurityLooks.bag_homes(sim, p)
		var tray_at := SecurityLooks.tray(sim, p)
		if homes.is_empty() and tray_at == SecurityLooks.Tray.NONE:
			continue
		seen[id] = true
		var held: Dictionary = _held.get(id, {"tray": null, "bags": []})
		_held[id] = held
		held["tray_at"] = tray_at
		held["homes"] = homes
		held["lane"] = SecurityLooks.lane_of(sim, p)
		held["scale"] = SecurityLooks.bag_scale(p)
		if tray_at != SecurityLooks.Tray.NONE and held["tray"] == null:
			held["tray"] = _take(_free_trays, "security_tray")
		elif tray_at == SecurityLooks.Tray.NONE and held["tray"] != null:
			_give(_free_trays, held["tray"])
			held["tray"] = null
		var bags: Array = held["bags"]
		while bags.size() < homes.size():
			bags.append({"node": _take(_free_bags, "carry_on_bag"), "home": -1})
		while bags.size() > homes.size():
			_give(_free_bags, bags.pop_back()["node"])
	for id in _held.keys():
		if not seen.has(id):
			release(id)


## Returns every prop of passenger `id` to the pool.
func release(id: int) -> void:
	var held: Dictionary = _held.get(id, {})
	if held.is_empty():
		return
	if held["tray"] != null:
		_give(_free_trays, held["tray"])
	for bag: Dictionary in held["bags"]:
		_give(_free_bags, bag["node"])
	_held.erase(id)


## Props of passenger `id`: {"tray": Node3D or null, "bags": Array[Node3D]}.
func props_of(id: int) -> Dictionary:
	var held: Dictionary = _held.get(id, {})
	var bags: Array[Node3D] = []
	for bag: Dictionary in held.get("bags", []):
		bags.append(bag["node"])
	return {"tray": held.get("tray"), "bags": bags}


## Places every prop for this frame.
func draw() -> void:
	var now := float(Time.get_ticks_msec())
	for id in _held:
		var held: Dictionary = _held[id]
		var body := views.node_for(id)
		if body == null:
			continue
		var tray_xf := _tray_transform(held, body)
		if held["tray"] != null:
			(held["tray"] as Node3D).global_transform = tray_xf
		var bags: Array = held["bags"]
		var homes: Array = held["homes"]
		for i in bags.size():
			var bag: Dictionary = bags[i]
			var want := _bag_transform(held, body, tray_xf, i, homes[i], bags.size())
			var node: Node3D = bag["node"]
			if bag["home"] != homes[i]:
				bag["from"] = want if bag["home"] == -1 else node.global_transform
				bag["since"] = now
				bag["home"] = homes[i]
			var k := clampf((now - bag["since"]) / TRANSFER_MS, 0.0, 1.0)
			node.global_transform = (bag["from"] as Transform3D).interpolate_with(want, k)


func _tray_transform(held: Dictionary, body: Node3D) -> Transform3D:
	var lane: Dictionary = held["lane"]
	match held["tray_at"]:
		SecurityLooks.Tray.RIDE:
			return ride(sim.grid, lane, body.global_position)
		SecurityLooks.Tray.IN, SecurityLooks.Tray.OUT:
			var mount: Array = TRAY_MOUNTS[held["tray_at"]]
			return mount_world(sim.grid, lane, mount[0], mount[1])
	return Transform3D.IDENTITY


func _bag_transform(
	held: Dictionary, body: Node3D, tray_xf: Transform3D, i: int, home: int, count: int
) -> Transform3D:
	var scale_by: float = held["scale"]
	var size := bag_size() * scale_by
	var yaw := Basis(Vector3.UP, body.rotation.y)
	match home:
		SecurityLooks.Home.TRAY:
			var at := SecurityLooks.in_tray(i, count, bag_size().z)
			at.y += TRAY_FLOOR_M
			return Transform3D(tray_xf.basis.scaled(Vector3.ONE * scale_by), tray_xf * at)
		SecurityLooks.Home.FLOOR:
			var turn := yaw if count > 1 else yaw * Basis(Vector3.UP, PI / 2.0)
			var spot := body.global_position + yaw * SecurityLooks.on_floor(i, count)
			return Transform3D(turn.scaled(Vector3.ONE * scale_by), spot)
	# Carried on its side: its thickness points out from the body, its inner
	# face hangs from the hand and its length runs along the walk, so the
	# swinging hand does not take the bag through a thigh.
	var grip := grip_of(body, i)
	# The bag stays square to the walk: "out" is the body's side the hand is on,
	# and the inner face sits at the hand, or at CARRY_CLEAR_M from the body's
	# centre line when the swinging hand comes nearer than that.
	var forward := yaw * Vector3.BACK
	var lateral := yaw * Vector3.RIGHT
	var beside := (grip - body.global_position).dot(lateral)
	var out := lateral if beside >= 0.0 else -lateral
	var hang := Basis(out.cross(forward), out, forward)
	var push := out * maxf(CARRY_CLEAR_M - absf(beside), 0.0)
	var drop := Vector3(0.0, GRIP_DROP_M + size.x * 0.5, 0.0)
	return Transform3D(hang.scaled(Vector3.ONE * scale_by), grip - drop + push)


## Where hand `i` (right, then left) of a character is now, from a bone
## attachment added to its skeleton the first time.
func grip_of(body: Node3D, i: int) -> Vector3:
	var name := "Grip%d" % i
	var grip := body.find_child(name, true, false) as BoneAttachment3D
	if grip == null:
		var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		grip = BoneAttachment3D.new()
		grip.name = name
		grip.bone_name = HANDS[i % HANDS.size()]
		skeleton.add_child(grip)
	return grip.global_position


func _take(pool: Array[Node3D], piece: String) -> Node3D:
	if not pool.is_empty():
		var reused: Node3D = pool.pop_back()
		reused.visible = true
		return reused
	var node := InteriorKit.instantiate(piece)
	add_child(node)
	return node


func _give(pool: Array[Node3D], node: Node3D) -> void:
	node.visible = false
	pool.append(node)
