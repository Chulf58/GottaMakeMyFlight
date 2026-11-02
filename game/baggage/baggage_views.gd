class_name BaggageViews
extends Node3D
## Draws the bags of a BaggageSim with the kit's suitcase (baggage_bag.glb,
## origin at its bottom centre, its length along +Z): a bag on a belt lies on
## the belt top, turned along the edge it rides; the newest bag to reach a
## belt end rests on that end's slide (the end piece's Mount_BagRest); a bag
## waiting at its desk, an older bag in the room and a settled bag are not
## drawn. Transforms are recorded each tick and drawn between the last two
## with the clock's alpha (the turn slerped). Never writes sim state.
##
## A drawn bag turns at most TURN_PER_TICK a tick toward where its belt points,
## so a bag that turns on a cell centre (at a merge, or off a desk outlet) turns
## over the next half cell instead of in one tick. A load (SaveGame.loaded)
## starts every bag over at its sim place; a tick that does not follow the last
## one recorded does the same when no load was seen.

const BAG_SCENE := preload("res://assets/interior/baggage_bag.glb")
const END_SCENE := preload("res://assets/interior/baggage_belt_end.glb")
## Height of every belt's top above the floor (build_baggage_kit.py BELT_TOP).
const BELT_TOP := 0.355
const REST_MOUNT := "Mount_BagRest"
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


## Records the transforms for the tick that just ran.
func sync() -> void:
	var drawn := {}
	var newest := {}
	for bag in sim.bags():
		if bag.state == Bag.State.IN_ROOM:
			var best: Bag = newest.get(bag.cell)
			if best == null or bag.rest_tick > best.rest_tick:
				newest[bag.cell] = bag
	for bag in sim.bags():
		var now: Variant = null
		if bag.on_belt():
			now = belt_transform(sim.grid, bag)
		elif bag.state == Bag.State.IN_ROOM and newest[bag.cell] == bag:
			now = rest_transform(sim.grid, bag.cell)
		if now == null:
			continue
		drawn[bag.id] = true
		var place: Transform3D = now
		if not _nodes.has(bag.id):
			_nodes[bag.id] = _take()
			_cur[bag.id] = Transform3D(turn_toward(place.basis, place.basis, 0.0), place.origin)
		var last: Transform3D = _cur[bag.id]
		_prev[bag.id] = last
		_cur[bag.id] = Transform3D(
			turn_toward(last.basis, place.basis, TURN_PER_TICK), place.origin
		)
	for id in _nodes.keys():
		if not drawn.has(id):
			_release(id)


## Starts every bag over at the sim's place now, with no tick to run: a load
## while paused, or back to the tick already showing, brings no tick for
## _on_ticked to see a gap in. Releases every record, records the loaded
## world with both ticks at its place, and draws it.
func snap() -> void:
	for id in _nodes.keys():
		_release(id)
	sync()
	_last_tick = clock.tick if clock != null else -1
	draw()


## Places every bag between its last two tick transforms.
func draw() -> void:
	var alpha := clock.alpha if clock != null else 1.0
	for id in _nodes:
		var before: Transform3D = _prev[id]
		var after: Transform3D = _cur[id]
		var node: Node3D = _nodes[id]
		node.transform = Transform3D(
			before.basis.slerp(after.basis, alpha), before.origin.lerp(after.origin, alpha)
		)


func _on_ticked(tick: int) -> void:
	if tick != _last_tick + 1:
		for id in _nodes.keys():
			_release(id)
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
