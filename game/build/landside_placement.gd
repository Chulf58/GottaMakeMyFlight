class_name LandsidePlacement
extends RefCounted
## The landside build tools' rules (Landside 3/4), the off-grid counterpart of
## DoorPlacement: the curb bay, surface lot and multi-storey tools snap to the
## nearest free authored spot of their kind in the LandsideDefinition, the
## Remove tool takes a built spot back, and the Close tool opens or closes a
## built car park. The BuildGrid covers only the terminal interior, so a spot
## is picked on the y = 0 ground plane (PLANE_Y), not at the grid's height.
##
## A build is paid from the wallet (PriceTable.price_of_landside()) and the
## price is kept on the built spot (LandsideSim.lots_paid, curbs_paid), so a
## removal refunds PriceTable.refund_of() that saved price and a spot placed
## for free refunds nothing. With no wallet the tools build for free. A
## removal is refused while any car is in the spot (decision landside-
## technical-design-arrival-bookings-landsidesim-vehic, point 7): close a car
## park first, and it drains.
##
## Undo: each action is kept here, and BuildMode undoes the newest of the grid's
## actions and these (has_undo_for()). Undoing a build gives back the whole
## price and is refused while a car is in the spot; undoing a removal takes
## the refund back; undoing a close opens it again.

enum Kind { CURB, SURFACE_LOT, MULTI_STOREY }
enum Action { BUILD, REMOVE, TOGGLE }

## The ground plane the tools pick on.
const PLANE_Y := 0.0
## How far outside a spot's footprint, in metres, a pointer still snaps to it.
const SNAP_MARGIN_M := 6.0
const PRICE_IDS := {
	Kind.CURB: &"curb_bay",
	Kind.SURFACE_LOT: &"surface_lot",
	Kind.MULTI_STOREY: &"multi_storey",
}
const NAMES := {
	Kind.CURB: "Curb bay",
	Kind.SURFACE_LOT: "Surface lot",
	Kind.MULTI_STOREY: "Multi-storey car park",
}
## The slab a ghost draws over a spot's footprint: its thickness and height.
const SLAB_THICKNESS := 0.1
const SLAB_HEIGHT := 0.15
const MAX_UNDO := UndoStack.CAPACITY


## What a tool would do at a point, worked out for the ghost and the status
## line and applied by apply().
class Plan:
	extends RefCounted
	var action := Action.BUILD
	var kind := Kind.CURB
	## The curb spot or lot spot index, -1 when the pointer is on none.
	var spot := -1
	var result := BuildResult.accepted()
	var centre := Vector3.ZERO
	var footprint := Vector2.ZERO
	## Berths for a curb bay, parking spaces for a car park.
	var capacity := 0
	## The mean walk from the spot to the nearest landside door, in metres; -1
	## when there is no shell door to measure to.
	var walk_m := -1.0
	## BUILD: the price. REMOVE: the refund. 0 with no wallet.
	var price := 0
	## Cars in the spot now.
	var cars := 0
	## TOGGLE: whether the car park is closed after the action.
	var closes := false
	var text := ""


var sim: LandsideSim
var shell: ShellDefinition
var wallet: Wallet

var _undo: Array[Dictionary] = []


## Whether `kind` is a car park kind (a lot spot) rather than a curb bay.
static func is_lot(kind: Kind) -> bool:
	return kind != Kind.CURB


## The ground point under a ray, on the y = 0 plane the landside tools pick on.
static func ground_point(from: Vector3, direction: Vector3) -> Variant:
	return Plane(Vector3.UP, PLANE_Y).intersects_ray(from, direction)


## The mean walk, in metres, from a spot's drop-off points to the nearest of
## `doors` (world points of the landside doorways): a curb bay's get-out
## points straight to the door; a car park's slots to its gate, along the
## crossing and on to the door. -1 with no door.
static func walk_to_door_m(
	definition: LandsideDefinition, kind: Kind, spot: int, doors: Array[Vector3]
) -> float:
	if doors.is_empty():
		return -1.0
	if kind == Kind.CURB:
		var bay := definition.curb_spots[spot]
		var total := 0.0
		for point in bay.get_out:
			total += _nearest_flat(point, doors)
		return total / bay.get_out.size()
	var lot := definition.lots[spot]
	var gate := lot.access[lot.access.size() - 1]
	var on_foot := (
		_length(lot.crossing) + _nearest_flat(lot.crossing[lot.crossing.size() - 1], doors)
	)
	var inside := 0.0
	for slot in lot.slots:
		inside += slot.distance_to(gate)
	return inside / lot.slots.size() + on_foot


## The world points of the shell's landside doorways.
static func landside_doors(shell_def: ShellDefinition) -> Array[Vector3]:
	var doors: Array[Vector3] = []
	if shell_def == null:
		return doors
	for connection in shell_def.connections:
		if connection.kind == ShellDoorConnection.Kind.LANDSIDE and not connection.route.is_empty():
			doors.append(connection.route[connection.route.size() - 1])
	return doors


## Draws the spots the tool could build on (`free_spots`, in the marker
## material) and the one the pointer is on (`plan`, valid or invalid), as flat
## slabs under `parent`. Frees nothing: the caller clears its ghost first.
static func draw(
	parent: Node3D,
	spots: Array[Plan],
	plan: Plan,
	valid: Material,
	invalid: Material,
	marker: Material
) -> void:
	for other in spots:
		if plan == null or other.spot != plan.spot:
			_slab(parent, other, marker)
	if plan != null and plan.spot >= 0:
		_slab(parent, plan, valid if plan.result.ok else invalid)


static func _slab(parent: Node3D, plan: Plan, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(plan.footprint.x, SLAB_THICKNESS, plan.footprint.y)
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = material
	box.position = Vector3(plan.centre.x, SLAB_HEIGHT, plan.centre.z)
	parent.add_child(box)


static func _length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


static func _nearest_flat(point: Vector3, doors: Array[Vector3]) -> float:
	var best := INF
	for door in doors:
		best = minf(best, Vector2(point.x - door.x, point.z - door.z).length())
	return best


## The distance in metres from a flat point to a footprint: 0 inside it.
static func _outside_m(point: Vector3, centre: Vector3, footprint: Vector2) -> float:
	var dx := maxf(absf(point.x - centre.x) - footprint.x / 2.0, 0.0)
	var dz := maxf(absf(point.z - centre.z) - footprint.y / 2.0, 0.0)
	return Vector2(dx, dz).length()


## What building `kind` at the pointer would do: onto the nearest free spot of
## the kind within SNAP_MARGIN_M, else a refusal (a built spot is in reach, or
## none is). Null with no landside sim.
func plan_build(kind: Kind, point: Vector3) -> Plan:
	if sim == null or sim.definition == null:
		return null
	var plan := Plan.new()
	plan.kind = kind
	plan.spot = _nearest(kind, point, false)
	if plan.spot < 0:
		var taken := _nearest(kind, point, true)
		plan.spot = taken
		var why := BuildResult.Reason.LANDSIDE_NOT_ON_SPOT
		if taken >= 0:
			why = BuildResult.Reason.LANDSIDE_SPOT_TAKEN
		plan.result = BuildResult.refused(why)
		_describe(plan)
		return plan
	var price := PriceTable.price_of_landside(PRICE_IDS[kind])
	if wallet != null:
		plan.price = price
		if price == PriceTable.NO_PRICE:
			plan.result = BuildResult.refused(BuildResult.Reason.UNPRICED)
		elif not wallet.can_afford(price):
			plan.result = BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	_describe(plan)
	return plan


## What Remove would do at the pointer: take back the built spot under it, or
## null when none is within SNAP_MARGIN_M. Refused while a car is in it.
func plan_remove(point: Vector3) -> Plan:
	var plan := _plan_built(point, false)
	if plan == null:
		return null
	plan.action = Action.REMOVE
	if plan.cars > 0:
		plan.result = BuildResult.refused(BuildResult.Reason.LANDSIDE_OCCUPIED)
	else:
		plan.price = _refund(plan.kind, plan.spot)
		if wallet != null and not wallet.can_credit(plan.price, Wallet.Category.BUILD):
			plan.result = BuildResult.refused(BuildResult.Reason.WALLET_FULL)
	_describe(plan)
	return plan


## What the Close tool would do at the pointer: close the open car park under
## it or open the closed one, or null when none is within SNAP_MARGIN_M.
func plan_toggle(point: Vector3) -> Plan:
	var plan := _plan_built(point, true)
	if plan == null:
		return null
	plan.action = Action.TOGGLE
	plan.closes = not sim.lots_closed[plan.spot]
	_describe(plan)
	return plan


## Carries out an accepted plan, paid through the wallet. `grid_top` is the
## newest grid undo receipt now (UndoStack.peek()), which orders this action
## among the grid's for undo. Returns a refusal with nothing changed when the
## plan was refused, the money fell short or the spot changed since.
func apply(plan: Plan, grid_top: BuildReceipt) -> BuildResult:
	if plan == null:
		return null
	if not plan.result.ok:
		return plan.result
	var done := {"action": plan.action, "kind": plan.kind, "spot": plan.spot, "top": grid_top}
	var result := BuildResult.accepted()
	match plan.action:
		Action.BUILD:
			result = _build(plan.kind, plan.spot, plan.price)
			done["paid"] = plan.price
		Action.REMOVE:
			done["paid"] = _paid(plan.kind, plan.spot)
			done["closed"] = plan.kind != Kind.CURB and sim.lots_closed[plan.spot]
			result = _remove(plan.kind, plan.spot, plan.price)
		Action.TOGGLE:
			sim.set_lot_closed(plan.spot, plan.closes)
			done["closed"] = plan.closes
	if result.ok:
		_undo.append(done)
		if _undo.size() > MAX_UNDO:
			_undo.pop_front()
	return result


## Whether the newest landside action came after the grid action `grid_top`
## and before any later one, so an undo takes it first.
func has_undo_for(grid_top: BuildReceipt) -> bool:
	return not _undo.is_empty() and _undo.back()["top"] == grid_top


func undo_size() -> int:
	return _undo.size()


func clear_undo() -> void:
	_undo.clear()


## Undoes the newest landside action and its money; a refusal (a car in the
## spot, money short) changes nothing and keeps it. Null with nothing to undo.
func undo() -> BuildResult:
	if _undo.is_empty():
		return null
	var done: Dictionary = _undo.back()
	var kind: Kind = done["kind"]
	var spot: int = done["spot"]
	var result := BuildResult.accepted()
	match done["action"]:
		Action.BUILD:
			result = _remove(kind, spot, done["paid"])
		Action.REMOVE:
			result = _rebuild(kind, spot, done)
		Action.TOGGLE:
			sim.set_lot_closed(spot, not done["closed"])
	if result.ok:
		_undo.pop_back()
	return result


## The free spots of `kind` as plans, for the marker slabs the ghost draws.
func free_spot_plans(kind: Kind) -> Array[Plan]:
	var plans: Array[Plan] = []
	if sim == null or sim.definition == null:
		return plans
	for spot in _spot_count(kind):
		if _matches(kind, spot) and not _built(kind, spot):
			var plan := Plan.new()
			plan.kind = kind
			plan.spot = spot
			_describe(plan)
			plans.append(plan)
	return plans


## The nearest spot of `kind` within SNAP_MARGIN_M whose built state is
## `built`, or -1.
func _nearest(kind: Kind, point: Vector3, built: bool) -> int:
	var best := -1
	var best_m := SNAP_MARGIN_M
	for spot in _spot_count(kind):
		if not _matches(kind, spot) or _built(kind, spot) != built:
			continue
		var m := _outside_m(point, _centre(kind, spot), _footprint(kind, spot))
		var tie := m == best_m and best >= 0
		if (
			m < best_m
			or (tie and _flat(point, _centre(kind, spot)) < _flat(point, _centre(kind, best)))
		):
			best = spot
			best_m = m
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A plan for the nearest built spot under the pointer: of any kind, or with
## `lots_only` of the car parks.
func _plan_built(point: Vector3, lots_only: bool) -> Plan:
	if sim == null or sim.definition == null:
		return null
	var best: Plan = null
	var best_m := SNAP_MARGIN_M
	for kind in [Kind.CURB, Kind.SURFACE_LOT, Kind.MULTI_STOREY]:
		if lots_only and kind == Kind.CURB:
			continue
		for spot in _spot_count(kind):
			if not _matches(kind, spot) or not _built(kind, spot):
				continue
			var m := _outside_m(point, _centre(kind, spot), _footprint(kind, spot))
			if m < best_m or (best == null and m <= best_m):
				best = Plan.new()
				best.kind = kind
				best.spot = spot
				best_m = m
	if best != null:
		best.cars = sim.curb_cars(best.spot) if best.kind == Kind.CURB else sim.lot_cars(best.spot)
	return best


func _describe(plan: Plan) -> void:
	if plan.spot < 0:
		plan.text = _with_reason(NAMES[plan.kind], plan)
		return
	plan.centre = _centre(plan.kind, plan.spot)
	plan.footprint = _footprint(plan.kind, plan.spot)
	var definition := sim.definition
	if plan.kind == Kind.CURB:
		plan.capacity = definition.curb_spots[plan.spot].berths.size()
	else:
		plan.capacity = definition.lots[plan.spot].slots.size()
	plan.walk_m = walk_to_door_m(definition, plan.kind, plan.spot, landside_doors(shell))
	var text := "%s: %s" % [NAMES[plan.kind], _capacity_text(plan)]
	if plan.walk_m >= 0.0:
		text += ", %d m walk to the nearest landside door" % roundi(plan.walk_m)
	match plan.action:
		Action.REMOVE:
			text = "Remove %s" % text.to_lower() if plan.result.ok else text
			if plan.result.ok and plan.price > 0:
				text += ". Refunds %d" % plan.price
		Action.TOGGLE:
			var state := "closed" if sim.lots_closed[plan.spot] else "open"
			var verb := "close" if plan.closes else "open"
			text = "%s (%s, %s): click to %s it" % [NAMES[plan.kind], state, _cars(plan), verb]
	plan.text = _with_reason(text, plan)


func _with_reason(text: String, plan: Plan) -> String:
	if plan.result.ok:
		return text
	var reason := plan.result.reason_text()
	if plan.result.reason == BuildResult.Reason.LANDSIDE_OCCUPIED:
		var are := "is" if plan.cars == 1 else "are"
		reason = "%s %s still in it. Close it and wait until it is empty" % [_cars(plan), are]
	return "%s  %s" % [text, reason]


static func _cars(plan: Plan) -> String:
	return "1 car" if plan.cars == 1 else "%d cars" % plan.cars


func _capacity_text(plan: Plan) -> String:
	return "%d berths" % plan.capacity if plan.kind == Kind.CURB else "%d spaces" % plan.capacity


func _spot_count(kind: Kind) -> int:
	if kind == Kind.CURB:
		return sim.definition.curb_spots.size()
	return sim.definition.lots.size()


## Whether lot spot `spot` is of `kind` (always true for a curb spot).
func _matches(kind: Kind, spot: int) -> bool:
	if kind == Kind.CURB:
		return true
	var wanted := LandsideLotSpot.Kind.SURFACE
	if kind == Kind.MULTI_STOREY:
		wanted = LandsideLotSpot.Kind.MULTI_STOREY
	return sim.definition.lots[spot].kind == wanted


func _built(kind: Kind, spot: int) -> bool:
	return sim.curbs_built[spot] if kind == Kind.CURB else sim.lots_built[spot]


func _paid(kind: Kind, spot: int) -> int:
	return sim.curbs_paid[spot] if kind == Kind.CURB else sim.lots_paid[spot]


func _refund(kind: Kind, spot: int) -> int:
	return PriceTable.refund_of(_paid(kind, spot))


func _centre(kind: Kind, spot: int) -> Vector3:
	if kind == Kind.CURB:
		return sim.definition.curb_spots[spot].centre
	return sim.definition.lots[spot].centre


func _footprint(kind: Kind, spot: int) -> Vector2:
	if kind == Kind.CURB:
		return sim.definition.curb_spots[spot].footprint
	return sim.definition.lots[spot].footprint


## Pays `price` and builds, or refuses with nothing changed.
func _build(kind: Kind, spot: int, price: int) -> BuildResult:
	if _built(kind, spot):
		return BuildResult.refused(BuildResult.Reason.LANDSIDE_SPOT_TAKEN)
	if wallet != null and not wallet.spend(price, Wallet.Category.BUILD):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	var built := sim.build_curb(spot, price) if kind == Kind.CURB else sim.build_lot(spot, price)
	if not built:
		return BuildResult.refused(BuildResult.Reason.LANDSIDE_SPOT_TAKEN)
	return BuildResult.accepted()


## Takes the spot back and credits `credit`, or refuses with nothing changed:
## a car is in it, or the wallet cannot take the credit.
func _remove(kind: Kind, spot: int, credit: int) -> BuildResult:
	if wallet != null and not wallet.can_credit(credit, Wallet.Category.BUILD):
		return BuildResult.refused(BuildResult.Reason.WALLET_FULL)
	var removed := sim.remove_curb(spot) if kind == Kind.CURB else sim.remove_lot(spot)
	if not removed:
		return BuildResult.refused(BuildResult.Reason.LANDSIDE_OCCUPIED)
	if wallet != null and not wallet.credit(credit, Wallet.Category.BUILD):
		push_error("LandsidePlacement: the wallet refused a credit it had accepted")
	return BuildResult.accepted()


## Undoes a removal: builds the spot again at its old price, taking back the
## refund, and restores whether it was closed.
func _rebuild(kind: Kind, spot: int, done: Dictionary) -> BuildResult:
	var refund := PriceTable.refund_of(done["paid"])
	if wallet != null and not wallet.can_afford(refund):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	if _built(kind, spot):
		return BuildResult.refused(BuildResult.Reason.LANDSIDE_SPOT_TAKEN)
	if wallet != null and not wallet.spend(refund, Wallet.Category.BUILD):
		return BuildResult.refused(BuildResult.Reason.CANT_AFFORD)
	var built := (
		sim.build_curb(spot, done["paid"])
		if kind == Kind.CURB
		else sim.build_lot(spot, done["paid"])
	)
	if built and kind != Kind.CURB:
		sim.set_lot_closed(spot, done["closed"])
	return (
		BuildResult.accepted()
		if built
		else BuildResult.refused(BuildResult.Reason.LANDSIDE_SPOT_TAKEN)
	)
