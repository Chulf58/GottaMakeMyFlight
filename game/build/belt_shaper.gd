class_name BeltShaper
extends RefCounted
## Auto-shaping baggage belts (decision baggage-belts-are-one-auto-shaping-
## belt-tool-one-baggage-tray). The player lays plain belt cells with the Belt
## tool; each belt cell then takes the straight, corner, merge (feed) or end
## piece and its facing from its links, and BuildMode reshapes the belts next
## to every change. The grid stores the resolved piece (a BuildCatalog belt id
## and facing), so saves and the bag sim see real pieces and nothing is
## resolved on load.
##
## A cell's links are its four sides toward another belt cell, or toward a
## check-in desk whose belt outlet points into the cell, across an edge with no
## wall. By link count: none, a straight that keeps its facing; one, an end in
## a bag room (a dead end there, where bags rest) or else a straight along the
## link (a plain open end, as an unused collector end stays open); two in a
## line, a straight; two at a right angle, a corner; three, a feed whose F
## (inlet) is opposite the free side; four is refused (BELT_CROSSING). A lone
## cell in a bag room is an end too. The facing of a piece follows from its
## ports (BuildCatalog.BELT_PORTS), never from the flow: a bag may ride a belt
## either way (BuildCatalog.BELT_PATHS). Two open ends can meet across a wall
## without a link; BuildCatalog.belt_ports_join() does not see walls, so a bag
## sim follows Scene.links().
##
## What it does not do: two lines laid side by side link along their length
## and fuse into feeds (leave a cell between them), and belts laid by a debug
## layout or a direct grid edit are not shaped until something next to them
## changes. A cell with four links already (only a direct edit can make one)
## is left as it is.

const BELT := &"baggage_belt"
const CORNER := &"baggage_belt_corner"
const FEED := &"baggage_belt_feed"
const END := &"baggage_belt_end"
const DESK := &"checkin_desk"
const BAG_ROOM := &"bag_room"


## The grid as it stands, or as it would be with extra belt cells, a wall
## taken away or a desk outlet added: the inputs of a change being checked.
class Scene:
	extends RefCounted
	var grid: BuildGrid
	## Cell -> true for belt cells that are not on the grid yet.
	var added := {}
	## Edges treated as having no wall, as Vector3i(cell.x, cell.y, side).
	var open_edges := {}
	## Desk outlets not on the grid yet, as Vector3i(cell.x, cell.y, side):
	## the outlet points into `cell` from the side named.
	var outlets := {}

	func _init(on: BuildGrid) -> void:
		grid = on

	func is_belt(cell: Vector2i) -> bool:
		if added.has(cell):
			return true
		if not grid.in_bounds(cell):
			return false
		var object_id := grid.object_at(cell)
		return object_id != 0 and BuildCatalog.is_belt(grid.get_object(object_id)["def"])

	## Whether a bag can pass the edge from `cell` toward `step`.
	func open(cell: Vector2i, step: Vector2i) -> bool:
		var side := BuildGrid.SIDE_STEP.find(step)
		if not grid.in_bounds(cell) or not grid.has_wall(cell, side):
			return true
		var other := cell + step
		var back := BuildGrid.SIDE_STEP.find(-step)
		return (
			open_edges.has(Vector3i(cell.x, cell.y, side))
			or open_edges.has(Vector3i(other.x, other.y, back))
		)

	## The steps from `cell` toward each of its links.
	func links(cell: Vector2i) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for side in BuildGrid.SIDE_STEP.size():
			var step: Vector2i = BuildGrid.SIDE_STEP[side]
			var next := cell + step
			if not grid.in_bounds(next) or not open(cell, step):
				continue
			if is_belt(next) or _outlet_into(cell, next):
				out.append(step)
			elif outlets.has(Vector3i(cell.x, cell.y, side)):
				out.append(step)
		return out

	func in_bag_room(cell: Vector2i) -> bool:
		var room_id := grid.room_at(cell)
		return room_id != 0 and grid.get_room(room_id)["type"] == &"bag_room"

	## Whether the object on `next` is a desk whose belt outlet points into `cell`.
	func _outlet_into(cell: Vector2i, next: Vector2i) -> bool:
		var object_id := grid.object_at(next)
		if object_id == 0:
			return false
		var record := grid.get_object(object_id)
		for port in BuildCatalog.belt_ports(record["def"], record["anchor"], record["facing"]):
			if port["cell"] == next and next + port["side"] == cell:
				return true
		return false


## The piece and facing for a belt cell in `scene`, [def id, facing], given
## the piece it is now (`def`, `facing`); [] when it has four links.
static func shape(scene: Scene, cell: Vector2i, def: StringName, facing: int) -> Array:
	var links := scene.links(cell)
	if links.size() <= 1 and scene.in_bag_room(cell):
		if links.is_empty():
			return [END, facing]
		return [END, facing_for(END, links)]
	match links.size():
		0:
			return [BELT, facing]
		1:
			return _straight(links[0], def, facing)
		2:
			if links[0] == -links[1]:
				return _straight(links[0], def, facing)
			return [CORNER, facing_for(CORNER, links)]
		3:
			return [FEED, facing_for(FEED, links)]
	return []


## The facing at which piece `id` has a port toward exactly each of `steps`.
static func facing_for(id: StringName, steps: Array[Vector2i]) -> int:
	for turn in 4:
		var sides: Array[Vector2i] = []
		for port in BuildCatalog.belt_ports(id, Vector2i.ZERO, turn):
			sides.append(port["side"])
		if (
			sides.size() == steps.size()
			and steps.all(func(s: Vector2i) -> bool: return sides.has(s))
		):
			return turn
	push_error("BeltShaper: %s has no facing with ports %s" % [id, steps])
	return 0


## A straight along `step`: the current facing when it already runs that way.
static func _straight(step: Vector2i, def: StringName, facing: int) -> Array:
	var front := BuildObjectDef.rotate_offset(BuildCatalog.BELT_PORT_SIDES["F"], facing)
	if def == BELT and (front == step or front == -step):
		return [BELT, facing]
	return [BELT, 0 if step.x == 0 else 1]


## `cells` and their four neighbours, each once.
static func around(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in cells:
		for step in [Vector2i.ZERO] + BuildGrid.SIDE_STEP:
			var next: Vector2i = cell + step
			if not out.has(next):
				out.append(next)
	return out


## RESHAPE_BELT edits for every belt piece on `cells` whose shape no longer
## fits its links. A cell with four links is left as it is.
static func reshape_edits(grid: BuildGrid, cells: Array[Vector2i]) -> Array[BuildEdit]:
	var scene := Scene.new(grid)
	var edits: Array[BuildEdit] = []
	for cell in cells:
		if not scene.is_belt(cell):
			continue
		var record := grid.get_object(grid.object_at(cell))
		var next := shape(scene, cell, record["def"], record["facing"])
		if next.is_empty() or (next[0] == record["def"] and next[1] == record["facing"]):
			continue
		edits.append(BuildEdit.reshape_belt(cell, next[0], next[1]))
	return edits


## The cells from `from` to `to` as an L: along the longer axis first (x on a
## tie), then the other.
static func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var delta := to - from
	var corner := Vector2i(to.x, from.y)
	if absi(delta.y) > absi(delta.x):
		corner = Vector2i(from.x, to.y)
	var out: Array[Vector2i] = [from]
	var at := from
	while at != corner:
		at += (corner - at).sign()
		out.append(at)
	while at != to:
		at += (to - at).sign()
		out.append(at)
	return out


## A belt line from `from` to `to` (path()) planned against `grid`: the cells
## to buy, the edits that lay and shape them, the shapes a ghost shows and the
## refusal, if any. `turn` is the facing of a lone new cell.
class Plan:
	extends RefCounted
	var cells: Array[Vector2i] = []
	## Path cells with no belt yet: the ones the player pays for.
	var new_cells: Array[Vector2i] = []
	## PLACE_OBJECT baggage_belt for each new cell, then RESHAPE_BELT for every
	## new or neighbouring belt cell whose shape changes.
	var edits: Array[BuildEdit] = []
	## [def id, cell, facing] for each new cell and each reshaped neighbour.
	var shapes: Array = []
	var result := BuildResult.accepted()


static func plan_line(grid: BuildGrid, from: Vector2i, to: Vector2i, turn: int) -> Plan:
	var plan := Plan.new()
	plan.cells = path(from, to)
	var scene := Scene.new(grid)
	for i in range(1, plan.cells.size()):
		if not scene.open(plan.cells[i - 1], plan.cells[i] - plan.cells[i - 1]):
			plan.result = BuildResult.refused(BuildResult.Reason.BELT_WALL)
			return plan
	for cell in plan.cells:
		if scene.is_belt(cell):
			continue
		var place := BuildEdit.place_object(BELT, cell, turn)
		var check := grid.validate(place)
		if not check.ok:
			plan.result = check
			return plan
		plan.new_cells.append(cell)
		scene.added[cell] = true
		plan.edits.append(place)
	# Each cell passed alone; together they may still close a staff spot in.
	var cut_off := grid.staff_reach_problem(plan.edits)
	if cut_off != null:
		plan.result = cut_off
		return plan
	var reshapes: Array[BuildEdit] = []
	for cell in around(plan.new_cells):
		if not scene.is_belt(cell):
			continue
		var def := BELT
		var facing := turn
		if not scene.added.has(cell):
			var record := grid.get_object(grid.object_at(cell))
			def = record["def"]
			facing = record["facing"]
		var next := shape(scene, cell, def, facing)
		if next.is_empty():
			plan.result = BuildResult.refused(BuildResult.Reason.BELT_CROSSING)
			return plan
		if next[0] != def or next[1] != facing:
			reshapes.append(BuildEdit.reshape_belt(cell, next[0], next[1]))
		if scene.added.has(cell) or next[0] != def or next[1] != facing:
			plan.shapes.append([next[0], cell, next[1]])
	plan.edits.append_array(reshapes)
	return plan


## BELT_CROSSING when `edit` would give a belt cell a fourth link: a desk whose
## outlet points into a belt cell, or a wall taken away between linked cells.
## Null when it adds no link.
static func crossing_problem(grid: BuildGrid, edit: BuildEdit) -> BuildResult:
	var scene := Scene.new(grid)
	var targets: Array[Vector2i] = []
	match edit.kind:
		BuildEdit.Kind.PLACE_OBJECT:
			for port in BuildCatalog.belt_ports(edit.def_id, edit.cell, edit.facing):
				var into: Vector2i = port["cell"] + port["side"]
				var side := BuildGrid.SIDE_STEP.find(-(port["side"] as Vector2i))
				scene.outlets[Vector3i(into.x, into.y, side)] = true
				targets.append(into)
		BuildEdit.Kind.REMOVE_WALL:
			scene.open_edges[Vector3i(edit.cell.x, edit.cell.y, edit.side)] = true
			targets = [edit.cell, edit.cell + BuildGrid.SIDE_STEP[edit.side]]
	for cell in targets:
		if scene.is_belt(cell) and scene.links(cell).size() > 3:
			return BuildResult.refused(BuildResult.Reason.BELT_CROSSING)
	return null
