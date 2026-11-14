class_name BuiltSelection
extends RefCounted
## The built item the player has clicked: a grid object, a room (by its open
## floor) or a built landside spot (decision select-placed-items-design-click-
## order-gold-footprint-highlight-...). One selection at a time; PassengerHud
## clears it when a passenger or vehicle is selected and the reverse. Walls and
## plain floor are not selectable.
##
## pick() runs the grid half of the click order, after the HUD has found no
## vehicle and no passenger: the object in sight, then the room floor, then a
## built landside spot, else nothing. A wall in sight clears, like plain floor.
## It only reads; the selection is view state and is never saved.

enum Kind { NONE, OBJECT, ROOM, LANDSIDE }

var kind := Kind.NONE
## The object id or room id; unused for a landside spot.
var id := 0
## A landside spot: its LandsidePlacement kind and spot index.
var lot_kind := LandsidePlacement.Kind.CURB
var spot := -1


## Whether a build interaction owns world clicks: a tool picked, a template paste
## armed or being saved, or a room being moved. The last two run with no tool
## picked, and one click must have one owner.
static func clicks_taken(mode: BuildMode) -> bool:
	return mode.tool != BuildMode.Tool.NONE or mode.templates.is_active() or mode.room_mover.active


func clear() -> void:
	kind = Kind.NONE
	id = 0
	spot = -1


## Selects the grid object `object_id`, as a click on it would.
func select_object(object_id: int) -> void:
	clear()
	kind = Kind.OBJECT
	id = object_id


func is_selected() -> bool:
	return kind != Kind.NONE


## A key that changes whenever the selection does, for views to redraw on.
func key() -> String:
	return "%d:%d:%d:%d" % [kind, id, lot_kind, spot]


## Selects what a click at screen point `at` meets and returns whether it met
## something selectable; a miss clears. The landside half uses a ground point
## on the y = 0 plane and a spot's own footprint, not the build tools' wider
## snap margin, so the plain ground beside a car park clears.
func pick(
	grid: BuildGrid, view: BuildView, placement: LandsidePlacement, eye: Camera3D, at: Vector2
) -> bool:
	clear()
	var from := eye.project_ray_origin(at)
	var direction := eye.project_ray_normal(at)
	var point: Variant = BuildMode.ground_point(from, direction, grid.origin.y)
	if point != null:
		var cell := grid.world_to_cell(point)
		if grid.in_bounds(cell):
			return _pick_on_grid(grid, view, eye, point, cell)
	var ground: Variant = LandsidePlacement.ground_point(from, direction)
	if ground != null and placement != null:
		_pick_landside(placement, ground)
	return is_selected()


## Drops the selection when its item is gone: the object or room removed, or
## the landside spot taken back.
func prune(grid: BuildGrid, placement: LandsidePlacement) -> void:
	match kind:
		Kind.OBJECT:
			if grid.get_object(id).is_empty():
				clear()
		Kind.ROOM:
			if grid.get_room(id).is_empty():
				clear()
		Kind.LANDSIDE:
			if not is_spot_built(placement):
				clear()


## Whether the selected landside spot is still built; flags only, no scan of the
## cars, so it is cheap enough for every frame.
func is_spot_built(placement: LandsidePlacement) -> bool:
	if kind != Kind.LANDSIDE or placement == null or placement.sim == null:
		return false
	var sim := placement.sim
	var built := sim.curbs_built if lot_kind == LandsidePlacement.Kind.CURB else sim.lots_built
	return spot >= 0 and spot < built.size() and built[spot]


## The landside plan of the selected spot, or null when none is selected or the
## spot is no longer built. Its centre, footprint, capacity and cars are set.
func plan_of(placement: LandsidePlacement) -> LandsidePlacement.Plan:
	if not is_spot_built(placement):
		return null
	var centre: Vector3 = placement.sim.definition.curb_spots[spot].centre
	if lot_kind != LandsidePlacement.Kind.CURB:
		centre = placement.sim.definition.lots[spot].centre
	var plan := placement.plan_remove(centre)
	if plan == null or plan.kind != lot_kind or plan.spot != spot:
		return null
	return plan


## The floor the gold outline goes around, on the xz plane in world metres:
## an object's footprint box, a room's floor, a landside spot's footprint.
## Empty (no area) for no selection.
func outline_rect(grid: BuildGrid, placement: LandsidePlacement) -> Rect2:
	match kind:
		Kind.OBJECT:
			var record := grid.get_object(id)
			if record.is_empty():
				return Rect2()
			var def := BuildCatalog.get_def(record["def"])
			return _world_rect(grid, _bounds(def.footprint(record["anchor"], record["facing"])))
		Kind.ROOM:
			var room := grid.get_room(id)
			return _world_rect(grid, room["rect"]) if not room.is_empty() else Rect2()
		Kind.LANDSIDE:
			return _spot_rect(placement)
	return Rect2()


func _pick_on_grid(
	grid: BuildGrid, view: BuildView, eye: Camera3D, point: Vector3, cell: Vector2i
) -> bool:
	var object_id := SightPick.seen_object(grid, view, eye, point)
	var wall := SightPick.seen_wall(grid, view, eye, point)
	if object_id == 0 and wall.z < 0:
		object_id = grid.object_at(cell)
	if object_id != 0:
		kind = Kind.OBJECT
		id = object_id
		return true
	if wall.z >= 0:
		return false
	var room := grid.room_at(cell)
	if room != 0:
		kind = Kind.ROOM
		id = room
		return true
	return false


func _pick_landside(placement: LandsidePlacement, ground: Vector3) -> void:
	var plan := placement.plan_remove(ground)
	if plan == null:
		return
	var half := plan.footprint / 2.0
	if absf(ground.x - plan.centre.x) > half.x or absf(ground.z - plan.centre.z) > half.y:
		return
	kind = Kind.LANDSIDE
	lot_kind = plan.kind
	spot = plan.spot


## The selected landside spot's footprint from its definition, empty when it is
## not built.
func _spot_rect(placement: LandsidePlacement) -> Rect2:
	if not is_spot_built(placement):
		return Rect2()
	var definition := placement.sim.definition
	var centre := definition.curb_spots[spot].centre
	var footprint := definition.curb_spots[spot].footprint
	if lot_kind != LandsidePlacement.Kind.CURB:
		centre = definition.lots[spot].centre
		footprint = definition.lots[spot].footprint
	return Rect2(Vector2(centre.x, centre.z) - footprint / 2.0, footprint)


static func _bounds(cells: Array[Vector2i]) -> Rect2i:
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for cell in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	return Rect2i(low, high - low + Vector2i.ONE)


static func _world_rect(grid: BuildGrid, cells: Rect2i) -> Rect2:
	return Rect2(
		Vector2(grid.origin.x + cells.position.x, grid.origin.z + cells.position.y),
		Vector2(cells.size)
	)
