class_name BaggageViews
extends Node3D
## Draws the bags and active baggage_cart shuttles of a BaggageSim:
## - bags riding a belt lie on the belt top, turned along the edge;
## - waiting IN_ROOM bags at a belt end stack visibly up to MAX_ROOM_STACK;
## - waiting AT_DESK bags at a check-in desk stack visibly up to MAX_DESK_STACK;
## - active BaggageShuttle trips animate a baggage_cart (with Cart_Bags while
##   outbound/unloading) from the bag room to the parked plane stand.
## Transforms are recorded each tick and drawn between the last two with the
## clock's alpha. Never writes sim state.

const BAG_SCENE := preload("res://assets/interior/baggage_bag.glb")
const END_SCENE := preload("res://assets/interior/baggage_belt_end.glb")
const CART_SCENE := preload("res://assets/interior/baggage_cart.glb")
## Height of every belt's top above the floor (build_baggage_kit.py BELT_TOP).
const BELT_TOP := 0.355
const REST_MOUNT := "Mount_BagRest"
const CART_BAGS_NODE := "Cart_Bags"
## Visual stack caps and spacing for waiting suitcases at desks and belt ends.
## 0.26 m clears baggage_bag.glb's 0.256 m body+strap+handle height cleanly.
const MAX_DESK_STACK := 4
const MAX_ROOM_STACK := 4
const MAX_CART_BAGS := 16
const CART_DECK_Y := 0.36
const CART_LAYER_STEP_M := 0.22
const STACK_STEP_M := 0.26
const STACK_YAW_RAD := 0.07
## Claim carousel stadium track geometry (claim_carousel.glb, Arrivals A0/A3).
const CAROUSEL_TRACK_Y := 0.355
const CAROUSEL_HALF_STRAIGHT_X := 1.00
const CAROUSEL_CURVE_RADIUS := 0.61
const CAROUSEL_SPUR_Z := -1.00
const CAROUSEL_SPUR_X := 0.50
## Radius of a bag's turn on a corner piece, about the cell's inner corner.
## The belt lane runs from 0.15 to 0.85 m from it (build_baggage_kit.py); a
## 0.39 x 0.55 m bag on this turn stays between 0.30 and 0.78 m. Under 0.5 so
## the first and last 5 cm of a corner stay straight: a bag a desk drops half
## a cell into its corner lies where it would on a straight belt.
const TURN_RADIUS := 0.45
## Most a drawn bag turns in one tick, in radians: a quarter turn over half a
## cell of travel (9 degrees), so a bag that turns on a cell centre lies along
## its new edge by the time it leaves the cell. A corner turns a quarter over
## 2 * TURN_RADIUS (5 degrees a tick), under this, so on a corner the drawn
## heading is the path's.
const TURN_PER_TICK := PI / 2.0 * BaggageSim.BELT_MM / (Bag.CELL_MM / 2.0)

@export var clock: SimClock
@export var sim: BaggageSim
## When set, a finished load starts every bag over at the loaded world.
@export var save_game: SaveGame

## Bag id -> node.
var _nodes := {}
var _prev := {}
var _cur := {}
var _pool: Array[Node3D] = []
## Shuttle id -> cart node.
var _shuttle_nodes := {}
var _shuttle_prev := {}
var _shuttle_cur := {}
var _shuttle_pool: Array[Node3D] = []
## Shuttle id -> Array[Node3D] of slotted suitcase nodes on the cart.
var _shuttle_bag_nodes := {}
var _cart_bag_pool: Array[Node3D] = []
## Mount_BagRest in the end piece's own frame.
var _rest := Transform3D.IDENTITY
## The tick sync() last recorded, or -1.
var _last_tick := -1


func _ready() -> void:
	_rest = mount_transform(END_SCENE, REST_MOUNT)
	if clock != null:
		clock.ticked.connect(_on_ticked)
	if save_game != null:
		save_game.loaded.connect(_on_loaded)


func _process(_delta: float) -> void:
	draw()


func node_for(id: int) -> Node3D:
	return _nodes.get(id)


func active_count() -> int:
	return _nodes.size()


func shuttle_node_for(shuttle_id: int) -> Node3D:
	return _shuttle_nodes.get(shuttle_id)


func active_shuttle_count() -> int:
	return _shuttle_nodes.size()


func shuttle_bag_nodes(shuttle_id: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var slots: Array = _shuttle_bag_nodes.get(shuttle_id, [])
	for slot: Node3D in slots:
		out.append(slot)
	return out


func shuttle_bag_count(shuttle_id: int) -> int:
	var slots: Array = _shuttle_bag_nodes.get(shuttle_id, [])
	return slots.size()


## The transform of node `mount_name` in `scene`'s root frame, or the
## identity with an error when the scene has no such node.
static func mount_transform(scene: PackedScene, mount_name: String) -> Transform3D:
	var root := scene.instantiate() as Node3D
	var mount := root.find_child(mount_name, true, false) as Node3D
	var out := Transform3D.IDENTITY
	if mount == null:
		push_error("BaggageViews: %s has no %s" % [scene.resource_path, mount_name])
	else:
		out = mount.transform
		var parent := mount.get_parent() as Node3D
		while parent != null and parent != root:
			out = parent.transform * out
			parent = parent.get_parent() as Node3D
	root.free()
	return out


## `from` turned toward `to` by at most `max_angle` radians, about the axis
## between them, as a pure rotation (any scale dropped).
static func turn_toward(from: Basis, to: Basis, max_angle: float) -> Basis:
	var a := from.get_rotation_quaternion()
	var b := to.get_rotation_quaternion()
	var angle := a.angle_to(b)
	if angle <= max_angle:
		return Basis(b)
	return Basis(a.slerp(b, max_angle / angle))


## Where a bag on a belt lies: `remain_mm` back from its cell's centre toward
## the cell it came from, on the belt top, its length along its edge. On a
## corner piece it follows the turn instead (turn_transform()), because the
## sim's straight path through the corner's centre runs the bag through the
## outer rail.
static func belt_transform(grid: BuildGrid, bag: Bag) -> Transform3D:
	var turn := _corner_turn(grid, bag)
	if not turn.is_empty():
		return turn_transform(grid.cell_to_world(turn[0]), turn[1], turn[2], turn[3])
	var heading := Vector3(bag.from_step.x, 0.0, bag.from_step.y)
	var at := grid.cell_to_world(bag.cell) - heading * (bag.remain_mm / float(Bag.CELL_MM))
	at.y += BELT_TOP
	return Transform3D(Basis(Vector3.UP, atan2(heading.x, heading.z)), at)


## A bag `d` metres (0 to 1) along the sim's straight path through a corner
## whose centre is `centre`, entered through side `entry` and left through
## side `exit` (unit grid steps from the centre, at right angles): straight
## from the entry edge to TURN_RADIUS from the centre, a quarter turn of that
## radius, straight to the exit edge. The straight parts keep the sim's
## distance; the 2 * TURN_RADIUS between them is spread evenly over the
## turn. Heading is the path's direction.
static func turn_transform(
	centre: Vector3, entry: Vector2i, exit: Vector2i, d: float
) -> Transform3D:
	var e := Vector3(entry.x, 0.0, entry.y)
	var x := Vector3(exit.x, 0.0, exit.y)
	var lead := 0.5 - TURN_RADIUS
	var at: Vector3
	var heading: Vector3
	if d <= lead:
		at = centre + e * (0.5 - d)
		heading = -e
	elif d >= 1.0 - lead:
		at = centre + x * (d - 0.5)
		heading = x
	else:
		var theta := (d - lead) / (2.0 * TURN_RADIUS) * PI / 2.0
		at = centre + (e + x) * TURN_RADIUS - (x * cos(theta) + e * sin(theta)) * TURN_RADIUS
		heading = x * sin(theta) - e * cos(theta)
	at.y += BELT_TOP
	return Transform3D(Basis(Vector3.UP, atan2(heading.x, heading.z)), at)


## [corner cell, entry side, exit side, metres along the sim's path through
## it] when the bag's body is on a corner piece whose two ports are the sides
## it travels through, else []. Entering, the bag owns the corner (within half
## a cell of its centre); leaving, it owns the next cell but more than half a
## cell remains, so its body is still on the corner. Leaving, the entry side
## is taken to be the corner's other port: the bag does not keep the side it
## came in by, so after a reshape the bag follows the piece now under it.
static func _corner_turn(grid: BuildGrid, bag: Bag) -> Array:
	var remain := bag.remain_mm / float(Bag.CELL_MM)
	if remain <= 0.5:
		var sides := _corner_sides(grid, bag.cell)
		if sides.has(-bag.from_step):
			sides.erase(-bag.from_step)
			return [bag.cell, -bag.from_step, sides[0], 0.5 - remain]
	else:
		var corner := bag.cell - bag.from_step
		var sides := _corner_sides(grid, corner)
		if sides.has(bag.from_step):
			sides.erase(bag.from_step)
			return [corner, sides[0], bag.from_step, 1.5 - remain]
	return []


## The two port sides of the corner piece on `cell`, or [] when none is there.
static func _corner_sides(grid: BuildGrid, cell: Vector2i) -> Array[Vector2i]:
	var sides: Array[Vector2i] = []
	var record := grid.get_object(grid.object_at(cell))
	if record.is_empty() or record["def"] != BeltShaper.CORNER:
		return sides
	for port in BuildCatalog.belt_ports(record["def"], record["anchor"], record["facing"]):
		sides.append(port["side"])
	return sides


## Where a bag rests on the end piece at `cell`, or null when no end is there.
func rest_transform(grid: BuildGrid, cell: Vector2i) -> Variant:
	var record := grid.get_object(grid.object_at(cell))
	if record.is_empty() or record["def"] != BeltShaper.END:
		return null
	var piece := Transform3D(
		Basis(Vector3.UP, -record["facing"] * PI / 2.0), grid.cell_to_world(cell)
	)
	return piece * _rest


## Where the `stack_index`-th waiting IN_ROOM bag sits on the end piece at `cell`.
func room_stack_transform(grid: BuildGrid, cell: Vector2i, stack_index := 0) -> Variant:
	var base: Variant = rest_transform(grid, cell)
	if base == null:
		return null
	var rest: Transform3D = base
	if stack_index <= 0:
		return rest
	var basis := rest.basis * Basis(Vector3.UP, _stack_yaw(stack_index))
	var origin := rest.origin + rest.basis.y * (stack_index * STACK_STEP_M)
	return Transform3D(basis, origin)


## Where the `stack_index`-th waiting AT_DESK bag sits on check-in desk `desk_id`'s
## bag-drop belt, or null when the desk is gone.
static func desk_transform(grid: BuildGrid, desk_id: int, stack_index := 0) -> Variant:
	var record := grid.get_object(desk_id)
	if record.is_empty() or StringName(record["def"]) != BeltShaper.DESK:
		return null
	var ports := BuildCatalog.belt_ports(record["def"], record["anchor"], record["facing"])
	if ports.is_empty():
		return null
	var port: Dictionary = ports[0]
	var heading := Vector3(port["side"].x, 0.0, port["side"].y)
	var at := grid.cell_to_world(port["cell"])
	at.y += BELT_TOP + stack_index * STACK_STEP_M
	var yaw := atan2(heading.x, heading.z) + _stack_yaw(stack_index)
	return Transform3D(Basis(Vector3.UP, yaw), at)


static func _stack_yaw(stack_index: int) -> float:
	if stack_index <= 0:
		return 0.0
	return STACK_YAW_RAD if stack_index % 2 == 1 else -STACK_YAW_RAD


## World transform of an ON_CAROUSEL bag orbiting the 4x2 claim_carousel stadium
## track at `at_tick`, or null when the carousel is gone.
static func carousel_transform(grid: BuildGrid, bag: Bag, at_tick: int) -> Variant:
	if grid == null or bag.carousel <= 0:
		return null
	var record := grid.get_object(bag.carousel)
	if record.is_empty() or StringName(record["def"]) != BeltShaper.CLAIM_CAROUSEL:
		return null
	var def := BuildCatalog.get_def(BeltShaper.CLAIM_CAROUSEL)
	var piece_xf := BuildView.object_transform(
		grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
	)
	var dist_m := float(maxi(0, at_tick - bag.rest_tick)) * (BaggageSim.BELT_MM / 1000.0)
	var spur_len := -CAROUSEL_CURVE_RADIUS - CAROUSEL_SPUR_Z
	var local_pos: Vector3
	var heading: Vector3
	if dist_m < spur_len:
		local_pos = Vector3(CAROUSEL_SPUR_X, CAROUSEL_TRACK_Y, CAROUSEL_SPUR_Z + dist_m)
		heading = Vector3(0.0, 0.0, 1.0)
	else:
		var back_first := CAROUSEL_SPUR_X + CAROUSEL_HALF_STRAIGHT_X
		var curve_len := PI * CAROUSEL_CURVE_RADIUS
		var front_len := 2.0 * CAROUSEL_HALF_STRAIGHT_X
		var back_last := CAROUSEL_HALF_STRAIGHT_X - CAROUSEL_SPUR_X
		var loop_len := back_first + curve_len + front_len + curve_len + back_last
		var s := fposmod(dist_m - spur_len, loop_len)
		if s < back_first:
			local_pos = Vector3(CAROUSEL_SPUR_X - s, CAROUSEL_TRACK_Y, -CAROUSEL_CURVE_RADIUS)
			heading = Vector3(-1.0, 0.0, 0.0)
		elif s < back_first + curve_len:
			var angle := (s - back_first) / CAROUSEL_CURVE_RADIUS
			local_pos = Vector3(
				-CAROUSEL_HALF_STRAIGHT_X - CAROUSEL_CURVE_RADIUS * sin(angle),
				CAROUSEL_TRACK_Y,
				-CAROUSEL_CURVE_RADIUS * cos(angle)
			)
			heading = Vector3(-cos(angle), 0.0, sin(angle))
		elif s < back_first + curve_len + front_len:
			var u := s - (back_first + curve_len)
			local_pos = Vector3(
				-CAROUSEL_HALF_STRAIGHT_X + u, CAROUSEL_TRACK_Y, CAROUSEL_CURVE_RADIUS
			)
			heading = Vector3(1.0, 0.0, 0.0)
		elif s < back_first + curve_len + front_len + curve_len:
			var angle := (s - (back_first + curve_len + front_len)) / CAROUSEL_CURVE_RADIUS
			local_pos = Vector3(
				CAROUSEL_HALF_STRAIGHT_X + CAROUSEL_CURVE_RADIUS * sin(angle),
				CAROUSEL_TRACK_Y,
				CAROUSEL_CURVE_RADIUS * cos(angle)
			)
			heading = Vector3(cos(angle), 0.0, -sin(angle))
		else:
			var u := s - (back_first + curve_len + front_len + curve_len)
			local_pos = Vector3(
				CAROUSEL_HALF_STRAIGHT_X - u, CAROUSEL_TRACK_Y, -CAROUSEL_CURVE_RADIUS
			)
			heading = Vector3(-1.0, 0.0, 0.0)
	var local_xf := Transform3D(Basis(Vector3.UP, atan2(heading.x, heading.z)), local_pos)
	return piece_xf * local_xf


## Records the transforms for the tick that just ran.
func sync() -> void:
	var drawn := {}
	var desk_stacks := _desk_stack_indices()
	var room_stacks := _room_stack_indices()
	for bag in sim.bags():
		var now: Variant = null
		if bag.on_belt():
			now = belt_transform(sim.grid, bag)
		elif bag.state == Bag.State.ON_CAROUSEL:
			now = carousel_transform(sim.grid, bag, sim.tick)
		elif bag.state == Bag.State.AT_DESK and desk_stacks.has(bag.id):
			now = desk_transform(sim.grid, bag.desk, desk_stacks[bag.id])
		elif bag.state == Bag.State.IN_ROOM and room_stacks.has(bag.id):
			now = room_stack_transform(sim.grid, bag.cell, room_stacks[bag.id])
		if now == null:
			continue
		drawn[bag.id] = true
		var place: Transform3D = now
		if not _nodes.has(bag.id):
			_nodes[bag.id] = _take()
			_cur[bag.id] = Transform3D(turn_toward(place.basis, place.basis, 0.0), place.origin)
		var bag_node: Node3D = _nodes[bag.id]
		if not bag_node.has_meta(&"bag_color") or int(bag_node.get_meta(&"bag_color")) != bag.color:
			Bag.paint_suitcase(bag_node, bag.color)
			bag_node.set_meta(&"bag_color", bag.color)
		var last: Transform3D = _cur[bag.id]
		_prev[bag.id] = last
		_cur[bag.id] = Transform3D(
			turn_toward(last.basis, place.basis, TURN_PER_TICK), place.origin
		)
	for id in _nodes.keys():
		if not drawn.has(id):
			_release(id)
	_sync_shuttles()


func _desk_stack_indices() -> Dictionary:
	var by_desk := {}
	for bag in sim.bags():
		if bag.state == Bag.State.AT_DESK:
			var list: Array[Bag] = by_desk.get(bag.desk, [] as Array[Bag])
			list.append(bag)
			by_desk[bag.desk] = list
	var indices := {}
	for desk_id in by_desk:
		var list: Array[Bag] = by_desk[desk_id]
		list.sort_custom(
			func(a: Bag, b: Bag) -> bool:
				return a.wait_tick < b.wait_tick if a.wait_tick != b.wait_tick else a.id < b.id
		)
		for i in mini(list.size(), MAX_DESK_STACK):
			indices[list[i].id] = i
	return indices


func _room_stack_indices() -> Dictionary:
	var by_cell := {}
	for bag in sim.bags():
		if bag.state == Bag.State.IN_ROOM and bag.shuttle_id == 0:
			var list: Array[Bag] = by_cell.get(bag.cell, [] as Array[Bag])
			list.append(bag)
			by_cell[bag.cell] = list
	var indices := {}
	for cell in by_cell:
		var list: Array[Bag] = by_cell[cell]
		list.sort_custom(
			func(a: Bag, b: Bag) -> bool:
				return a.rest_tick < b.rest_tick if a.rest_tick != b.rest_tick else a.id < b.id
		)
		for i in mini(list.size(), MAX_ROOM_STACK):
			indices[list[i].id] = i
	return indices


func _sync_shuttles() -> void:
	var active := {}
	for shuttle in sim.shuttles():
		active[shuttle.id] = true
		var place := shuttle.pose_at(sim.tick, sim.grid)
		if not _shuttle_nodes.has(shuttle.id):
			_shuttle_nodes[shuttle.id] = _take_shuttle()
			_shuttle_cur[shuttle.id] = place
		_shuttle_prev[shuttle.id] = _shuttle_cur[shuttle.id]
		_shuttle_cur[shuttle.id] = place
		var cart_node: Node3D = _shuttle_nodes[shuttle.id]
		var bags_node := cart_node.find_child(CART_BAGS_NODE, true, false) as Node3D
		if bags_node != null:
			bags_node.visible = shuttle.carrying_bags()
			_sync_shuttle_bags(shuttle, bags_node)
	for id in _shuttle_nodes.keys():
		if not active.has(id):
			_release_shuttle(id)


func _sync_shuttle_bags(shuttle: BaggageShuttle, bags_node: Node3D) -> void:
	var slots: Array = _shuttle_bag_nodes.get(shuttle.id, [])
	var count := mini(shuttle.bag_ids.size(), MAX_CART_BAGS) if shuttle.carrying_bags() else 0
	while slots.size() > count:
		var extra: Node3D = slots.pop_back()
		_release_cart_bag(extra)
	while slots.size() < count:
		var slot: Node3D = _take_cart_bag(bags_node)
		slots.append(slot)
	for i in count:
		var slot: Node3D = slots[i]
		var bag := sim.get_bag(shuttle.bag_ids[i])
		var color_idx := bag.color if bag != null else 0
		if not slot.has_meta(&"bag_color") or int(slot.get_meta(&"bag_color")) != color_idx:
			Bag.paint_suitcase(slot, color_idx)
			slot.set_meta(&"bag_color", color_idx)
		slot.transform = _cart_slot_transform(i)
		slot.visible = true
	if slots.is_empty():
		_shuttle_bag_nodes.erase(shuttle.id)
	else:
		_shuttle_bag_nodes[shuttle.id] = slots


static func _cart_slot_transform(slot_index: int) -> Transform3D:
	var layer := slot_index / 4
	var cell := slot_index % 4
	var col := cell % 2
	var row := cell / 2
	var x := -0.175 if col == 0 else 0.175
	var z := -0.35 if row == 0 else 0.35
	var y := CART_DECK_Y + float(layer) * CART_LAYER_STEP_M
	var yaw := 0.06 if (layer % 2) == 1 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 0.85), Vector3(x, y, z))


func _take_cart_bag(bags_node: Node3D) -> Node3D:
	var slot: Node3D = (
		_cart_bag_pool.pop_back() if not _cart_bag_pool.is_empty() else BAG_SCENE.instantiate()
	)
	if slot.get_parent() != bags_node:
		if slot.get_parent() != null:
			slot.get_parent().remove_child(slot)
		bags_node.add_child(slot)
	slot.visible = true
	return slot


func _release_cart_bag(slot: Node3D) -> void:
	slot.visible = false
	if slot.get_parent() != self:
		if slot.get_parent() != null:
			slot.get_parent().remove_child(slot)
		add_child(slot)
	_cart_bag_pool.append(slot)


## Starts every bag over at the sim's place now, with no tick to run: a load
## while paused, or back to the tick already showing, brings no tick for
## _on_ticked to see a gap in. Releases every record, records the loaded
## world with both ticks at its place, and draws it.
func snap() -> void:
	for id in _nodes.keys():
		_release(id)
	for id in _shuttle_nodes.keys():
		_release_shuttle(id)
	sync()
	_last_tick = clock.tick if clock != null else -1
	draw()


## Places every bag and active shuttle between its last two tick transforms.
func draw() -> void:
	var alpha := clock.alpha if clock != null else 1.0
	for id in _nodes:
		var before: Transform3D = _prev[id]
		var after: Transform3D = _cur[id]
		var node: Node3D = _nodes[id]
		node.transform = Transform3D(
			before.basis.slerp(after.basis, alpha), before.origin.lerp(after.origin, alpha)
		)
	for id in _shuttle_nodes:
		var before: Transform3D = _shuttle_prev[id]
		var after: Transform3D = _shuttle_cur[id]
		var node: Node3D = _shuttle_nodes[id]
		node.transform = Transform3D(
			before.basis.slerp(after.basis, alpha), before.origin.lerp(after.origin, alpha)
		)
	_sync_parked_carts()


func _sync_parked_carts() -> void:
	if sim == null or sim.build_mode == null or sim.grid == null:
		return
	var build_view := sim.build_mode.get_node_or_null("BuildView") as BuildView
	if build_view == null:
		return
	var busy := {}
	for cart_id in sim.active_cart_ids():
		busy[cart_id] = true
	for object_id in sim.grid.object_ids():
		var record := sim.grid.get_object(object_id)
		if StringName(record["def"]) != BaggageSim.CART_DEF:
			continue
		var parked := build_view.object_node(object_id)
		if parked == null:
			continue
		var out := busy.has(object_id)
		parked.visible = not out
		if not out:
			var bags_node := parked.find_child(CART_BAGS_NODE, true, false) as Node3D
			if bags_node != null:
				bags_node.visible = false


func _on_ticked(tick: int) -> void:
	if tick != _last_tick + 1:
		for id in _nodes.keys():
			_release(id)
		for id in _shuttle_nodes.keys():
			_release_shuttle(id)
	_last_tick = tick
	sync()


func _on_loaded(ok: bool) -> void:
	if ok:
		snap()


func _take() -> Node3D:
	if not _pool.is_empty():
		var reused: Node3D = _pool.pop_back()
		reused.visible = true
		return reused
	var node := BAG_SCENE.instantiate() as Node3D
	add_child(node)
	return node


func _release(id: int) -> void:
	var node: Node3D = _nodes[id]
	node.visible = false
	_pool.append(node)
	_nodes.erase(id)
	_prev.erase(id)
	_cur.erase(id)


func _take_shuttle() -> Node3D:
	if not _shuttle_pool.is_empty():
		var reused: Node3D = _shuttle_pool.pop_back()
		reused.visible = true
		return reused
	var node := CART_SCENE.instantiate() as Node3D
	var static_bags := node.find_child("Cart_Bags_Mesh", true, false) as Node3D
	if static_bags != null:
		static_bags.visible = false
	add_child(node)
	return node


func _release_shuttle(id: int) -> void:
	if _shuttle_bag_nodes.has(id):
		var slots: Array = _shuttle_bag_nodes[id]
		for slot: Node3D in slots:
			_release_cart_bag(slot)
		_shuttle_bag_nodes.erase(id)
	var node: Node3D = _shuttle_nodes[id]
	node.visible = false
	_shuttle_pool.append(node)
	_shuttle_nodes.erase(id)
	_shuttle_prev.erase(id)
	_shuttle_cur.erase(id)
