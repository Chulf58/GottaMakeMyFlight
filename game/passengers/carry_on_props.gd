class_name CarryOnProps
extends Node3D
## The carry-on bags of every drawn passenger, and the trays at security
## lanes (Security 7/8; decisions passengers-carry-their-carry-on-bags-for-
## the-whole-visit-fro and carried-bags-stay-gripped-in-the-hand-clear-body-
## contact-by). SecurityLooks says where each bag is: in a hand, in a tray or
## on the floor. sync() runs on each tick after PassengerViews has posed its
## characters: it takes or returns pooled props and turns each character's
## CarryArm on for a hand that holds a bag. draw() runs each frame after the
## characters are placed and puts every prop in place from them, so a tray
## riding the X-ray belt keeps pace with its passenger between ticks.
##
## A carried bag stands upright with its top edge in the hand, just past the
## knuckles (the Fingers bone) of the hand SecurityLooks.hand_of() names,
## its thin side to the leg and its body outward from the hand; its handle,
## on the broad face, faces the leg. A bag that changes
## home (or hand) moves there over TRANSFER_TICKS of sim time, lifted and
## kept out from the body; between side and front carry the bag stays in the
## hand and the arm turns over the same time (the clock's tick plus its
## alpha), so it stops while the game is paused and keeps pace at 2x and 3x.
## It reads the sim and the views and never writes either.

const TRAY_MOUNTS := {
	SecurityLooks.Tray.IN: [SecurityLanes.TRAY_TABLE, "Mount_TrayIn"],
	SecurityLooks.Tray.OUT: [SecurityLanes.PICKUP_TABLE, "Mount_TrayOut"],
}
const SCAN_MOUNT := [SecurityLanes.XRAY_BELT, "Mount_TrayScan"]
## A bag in a tray rests on the tray's floor, this far above its mount.
const TRAY_FLOOR_M := 0.012
## The grip sits this far past the knuckles along the hand's own axis.
const GRIP_ALONG_M := 0.03
## In front, a bag's handle sits this far under the knuckles, in the palm.
const FRONT_PALM_M := 0.04
## In front, how far from the centre line each hand holds: the hand with one
## bag, each hand with two, and the free hand (measured with the Toon walk and
## run: no body contact, the bags within 0.32 m of the centre line).
const FRONT_ONE_BAG_M := 0.10
const FRONT_TWO_BAGS_M := 0.17
const FRONT_FREE_HAND_M := 0.33
const TRANSFER_TICKS := 6.0
## How high a moving bag rises midway, so it goes over a table edge.
const TRANSFER_LIFT_M := 0.3
## A moving bag's path keeps its middle this far from the body's centre line.
const TRANSFER_CLEAR_M := 0.38
## How high a bag picked up from below rises over the walker's knee.
const KNEE_LIFT_M := 0.3
const GRIP_BONES: Array[String] = ["Fingers.R", "Fingers.L"]

## Mount name -> its transform relative to its kit piece's root.
static var _mounts := {}
static var _bag_size := Vector3.ZERO

var sim: PassengerSim
var views: PassengerViews
## Sim time for bag moves; without one a move is instant.
var clock: SimClock

## Passenger id -> {"tray": Node3D or null, "tray_at": SecurityLooks.Tray,
## "bags": Array of {"node", "home", "from", "since"}, "homes": Array,
## "lane": Dictionary, "scale": float, "floor": Array of Transform3D}.
var _held := {}
var _free_trays: Array[Node3D] = []
## Character node -> the passenger id it draws now (for _on_pose).
var _body_ids := {}
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


## The carry-on bag's size at scale 1, handle included (read once).
static func bag_size() -> Vector3:
	if _bag_size == Vector3.ZERO:
		var node := InteriorKit.instantiate("carry_on_bag")
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var b := mi.transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		node.free()
		_bag_size = box.size
	return _bag_size


## The world transform of a lane's mount on `piece`.
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


## A carried bag's transform for a grip at `grip` on a body drawn with yaw
## `yaw` at `centre`: upright (its length vertical), its handle face toward
## the body, its top edge at the grip, its body outward from the hand.
static func carried(grip: Vector3, centre: Vector3, yaw: float, scale_by: float) -> Transform3D:
	var size := bag_size()
	var lateral := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var out := lateral if (grip - centre).dot(lateral) >= 0.0 else -lateral
	var inward := -out
	var hang := Basis(inward.cross(Vector3.UP), inward, Vector3.UP).scaled(Vector3.ONE * scale_by)
	var handle := hang * Vector3(0.0, size.y, 0.0)
	return Transform3D(hang, grip - handle - Vector3.UP * (size.z * 0.5 * scale_by))


## A bag carried in front of the body (a cell closed on both sides): lying
## flat across the body, its handle on top just under the hand at `grip`
## (FRONT_PALM_M below the knuckles).
static func carried_in_front(grip: Vector3, yaw: float, scale_by: float) -> Transform3D:
	var size := bag_size()
	var flat := _flat(yaw, scale_by)
	return Transform3D(flat, grip - Vector3.UP * (size.y * scale_by + FRONT_PALM_M))


## A bag lying flat with its length across a body turned to `yaw`.
static func _flat(yaw: float, scale_by: float) -> Basis:
	var forward := Basis(Vector3.UP, yaw) * Vector3.BACK
	return Basis(forward, Vector3.UP, forward.cross(Vector3.UP)).scaled(Vector3.ONE * scale_by)


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
		var hands: Array[int] = []
		for i in homes.size():
			hands.append(SecurityLooks.hand_of(sim, p, i))
		var front := SecurityLooks.carry_front(sim, p)
		_arms(node, homes, hands)
		if homes.is_empty() and tray_at == SecurityLooks.Tray.NONE:
			continue
		seen[id] = true
		var held: Dictionary = _held.get(id, {"tray": null, "bags": []})
		_held[id] = held
		held["tray_at"] = tray_at
		held["homes"] = homes
		held["hands"] = hands
		if not held.has("front"):
			# A new record (a new passenger, or after a load) starts in the
			# carry it needs, with no turn to play.
			held["front"] = front
		elif front != held["front"]:
			# Turning between side and front carry starts from where it is now.
			held["front_from"] = _front_weight(held, _now())
			held["front_since"] = _now()
			held["front"] = front
		held["lane"] = SecurityLooks.lane_of(sim, p)
		held["scale"] = SecurityLooks.bag_scale(p)
		var spots: Array[Transform3D] = []
		for i in homes.size():
			spots.append(SecurityLooks.floor_spot(sim, p, i, homes.size()))
		held["floor"] = spots
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


## How far bag `index` of passenger `id` is through its move to its home,
## 0 to 1 (1 when it is not moving).
func transfer_progress(id: int, index: int) -> float:
	var bags: Array = _held.get(id, {}).get("bags", [])
	if index >= bags.size() or not bags[index].has("since"):
		return 1.0
	return clampf((_now() - bags[index]["since"]) / TRANSFER_TICKS, 0.0, 1.0)


## How far passenger `id` has turned to the front carry: 0 side, 1 front.
func front_weight_of(id: int) -> float:
	return _front_weight(_held.get(id, {}), _now())


## How many bag and tray nodes are drawn now.
func drawn_count() -> int:
	var count := 0
	for held: Dictionary in _held.values():
		count += (held["bags"] as Array).size() + int(held["tray"] != null)
	return count


## Places every prop for this frame. A character's carried bags are placed
## again when its skeleton has its final pose for the frame (_on_pose), so a
## bag in the hand does not trail the hand by a frame.
func draw() -> void:
	var now := _now()
	for id in _held:
		var held: Dictionary = _held[id]
		var body := views.node_for(id)
		if body == null:
			continue
		var tray_xf := _tray_transform(held, body)
		if held["tray"] != null:
			(held["tray"] as Node3D).global_transform = tray_xf
		held["weight"] = _front_weight(held, now)
		for arm: CarryArm in _rig(body)["arms"]:
			arm.front_weight = held["weight"]
		_body_ids[body] = id
		_place_bags(held, body, tray_xf, now)


## Puts the bags of one passenger in place (draw(), _on_pose()).
func _place_bags(held: Dictionary, body: Node3D, tray_xf: Transform3D, now: float) -> void:
	var bags: Array = held["bags"]
	var homes: Array = held["homes"]
	var hands: Array = held["hands"]
	for i in bags.size():
		var bag: Dictionary = bags[i]
		var want := _bag_transform(held, body, tray_xf, i, homes[i], bags.size())
		var node: Node3D = bag["node"]
		# A change of hand moves the bag across like a change of home.
		var place: int = homes[i] * 2 + hands[i]
		if bag["home"] != place:
			# The move starts where the bag is, held in the passenger's frame,
			# so a bag picked up while walking stays ahead of the legs.
			var start := want if bag["home"] == -1 else node.global_transform
			bag["from"] = body.global_transform.affine_inverse() * start
			bag["since"] = now if bag["home"] != -1 else now - TRANSFER_TICKS
			bag["home"] = place
		var k := clampf((now - bag["since"]) / TRANSFER_TICKS, 0.0, 1.0)
		var start_now := body.global_transform * (bag["from"] as Transform3D)
		var placed := start_now.interpolate_with(want, k)
		# A bag going up rises first and then comes across (picked up from
		# the floor, it clears the legs); one going down is lifted on the
		# way, over a table edge rather than through it. Either way it is
		# kept TRANSFER_CLEAR_M from the body's centre line.
		if k < 1.0:
			var arc := 4.0 * k * (1.0 - k)
			if want.origin.y > start_now.origin.y:
				var across := start_now.origin.lerp(want.origin, k * k)
				placed.origin.x = across.x
				placed.origin.z = across.z
				placed.origin.y = lerpf(start_now.origin.y, want.origin.y, 1.0 - pow(1.0 - k, 4.0))
				# Over the knee that steps forward, early in the move, and gone
				# before the bag comes in under the arm that will hold it.
				var early := 6.75 * k * (1.0 - k) * (1.0 - k) * pow(1.0 - k * k, 4.0)
				placed.origin.y += KNEE_LIFT_M * early
			else:
				placed.origin.y += TRANSFER_LIFT_M * arc
			placed.origin += _keep_out(placed.origin, body) * minf(arc * 2.0, 1.0)
		node.global_transform = placed


## How far to push a moving bag at `at` out to TRANSFER_CLEAR_M from the
## body's centre line (zero when it is already that far out).
func _keep_out(at: Vector3, body: Node3D) -> Vector3:
	var away := at - body.global_position
	away.y = 0.0
	var gap := away.length()
	if gap >= TRANSFER_CLEAR_M:
		return Vector3.ZERO
	if gap < 0.05:
		away = Basis(Vector3.UP, body.rotation.y) * Vector3.LEFT
	return away.normalized() * (TRANSFER_CLEAR_M - gap)


## How far passenger `held` has turned to the front carry at sim time `now`,
## 0 (side) to 1 (front), over TRANSFER_TICKS.
func _front_weight(held: Dictionary, now: float) -> float:
	var target := 1.0 if held.get("front", false) else 0.0
	if not held.has("front_since"):
		return target
	var k := clampf((now - held["front_since"]) / TRANSFER_TICKS, 0.0, 1.0)
	# Fast at first: a side-carried bag is the widest thing, so it comes in
	# before the passenger reaches the narrow cell.
	return lerpf(held["front_from"], target, 1.0 - (1.0 - k) * (1.0 - k))


## The skeleton of `body` has its final pose for this frame: places its bags
## from the hands as they are now.
func _on_pose(body: Node3D) -> void:
	var id: int = _body_ids.get(body, 0)
	var held: Dictionary = _held.get(id, {})
	if held.is_empty() or views.node_for(id) != body:
		return
	_place_bags(held, body, _tray_transform(held, body), _now())


## Where hand `i` (right, then left) of a character grips a bag now.
func grip_of(body: Node3D, i: int) -> Vector3:
	var grips: Array = _rig(body)["grips"]
	var grip: BoneAttachment3D = grips[i % grips.size()]
	return grip.global_position + grip.global_basis.y.normalized() * GRIP_ALONG_M


func _now() -> float:
	return clock.tick + clock.alpha if clock != null else 0.0


## Turns each arm's CarryArm on while its hand holds a bag.
func _arms(body: Node3D, homes: Array[SecurityLooks.Home], hands: Array[int]) -> void:
	var holding := [false, false]
	var carried := 0
	for i in homes.size():
		if homes[i] == SecurityLooks.Home.HAND:
			holding[hands[i]] = true
			carried += 1
	var arms: Array = _rig(body)["arms"]
	for side in arms.size():
		var arm := arms[side] as CarryArm
		arm.holds = holding[side]
		# A free arm is only posed when it comes forward for a front carry
		# (draw() sets the weight); a holding arm always.
		arm.active = holding[side] or carried > 0
		if not holding[side]:
			arm.front_half_width = FRONT_FREE_HAND_M
		else:
			arm.front_half_width = FRONT_ONE_BAG_M if carried < 2 else FRONT_TWO_BAGS_M
		if carried == 0:
			arm.front_weight = 0.0


## A character's grip attachments and CarryArm modifiers, one per hand, made
## the first time and kept on the pooled character.
func _rig(body: Node3D) -> Dictionary:
	if body.has_meta(&"carry_rig"):
		return body.get_meta(&"carry_rig")
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var rig := {"grips": [], "arms": []}
	for side in GRIP_BONES.size():
		var grip := BoneAttachment3D.new()
		grip.name = "Grip%d" % side
		grip.bone_name = GRIP_BONES[side]
		skeleton.add_child(grip)
		rig["grips"].append(grip)
		var arm := CarryArm.new()
		arm.name = "CarryArm%d" % side
		arm.side = side
		arm.active = false
		skeleton.add_child(arm)
		rig["arms"].append(arm)
	# After the grip attachments (connected when added), so they are current.
	skeleton.skeleton_updated.connect(_on_pose.bind(body))
	body.set_meta(&"carry_rig", rig)
	return rig


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
	var yaw := Basis(Vector3.UP, body.rotation.y)
	match home:
		SecurityLooks.Home.TRAY:
			var at := SecurityLooks.in_tray(i, count, bag_size().z)
			at.y += TRAY_FLOOR_M
			return Transform3D(tray_xf.basis.scaled(Vector3.ONE * scale_by), tray_xf * at)
		SecurityLooks.Home.FLOOR:
			var spot: Transform3D = held["floor"][i]
			var placed := Transform3D(yaw, body.global_position) * spot
			placed.origin.y = sim.grid.origin.y
			return Transform3D(placed.basis.scaled(Vector3.ONE * scale_by), placed.origin)
	# Between side and front carry the bag stays in the hand, turning with
	# the arm (front weight).
	var grip := grip_of(body, held["hands"][i])
	var side := carried(grip, body.global_position, body.rotation.y, scale_by)
	var weight: float = held.get("weight", 0.0)
	if weight <= 0.0:
		return side
	var ahead := carried_in_front(grip, body.rotation.y, scale_by)
	if weight >= 1.0:
		return ahead
	# Turned about the grip: the bag's point held in the hand moves across its
	# surface from the side carry's to the front carry's, and stays at the hand.
	var held_side := side.affine_inverse() * grip
	var held_ahead := ahead.affine_inverse() * grip
	var turn := side.basis.get_rotation_quaternion().slerp(
		ahead.basis.get_rotation_quaternion(), weight
	)
	var basis := Basis(turn).scaled(Vector3.ONE * scale_by)
	return Transform3D(basis, grip - basis * held_side.lerp(held_ahead, weight))


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
