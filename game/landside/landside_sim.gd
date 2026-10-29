class_name LandsideSim
extends Node
## Cars and taxis on the fixed road past the terminal (decision
## landside-technical-design-arrival-bookings-landsidesim-vehic), as plain
## vehicle records on the authored 1-D lanes of a LandsideDefinition, in
## whole mm with a fixed gap between cars. It does not listen to the clock:
## PassengerSim's ArrivalBookings steps it once a tick, hands it new vehicles
## and takes the release events it returns.
##
## Each step, in order: leaving cars drive on (and are gone at their lane's
## end); parked cars whose stay is over pull out onto their lot's exit; cars
## in a curb berth let held passengers out, and pull out onto road_out once
## they have stood DWELL_TICKS since; cars on a lot's access lane drive to
## the gate and park in their reserved slot (the parking fee is credited
## then, once); cars on road_in drive front first, each held back by the car
## ahead and by its stop. A car that means to park stops at its lot's turn
## and takes a free slot there, or, the lot being full, drives on to the
## curb (decision landside-congestion-a-jammed-curb-or-full-car-park-delays-pa).
## A car at the curb's stop takes the lowest free berth or queues. A lane is
## entered at its start only once the car last in it is a gap away, except
## road_in, whose queue runs on off the map (negative positions).
##
## Passengers get out only when the terminal has an entrance; until then
## they stay aboard in the berth or the parked car. A car whose passengers
## all missed their flight while it drove pulls through a berth at once and
## never turns into a lot. Parked cars stay 1 to 3 game days (decision
## landside-parking-stay-a-parked-car-stays-1-3-game-days-while), drawn from
## the sim RNG when they park.

## A car parked and its fee was credited.
signal parked(vehicle_id: int, lot: int)
## A car that meant to park found its lot full and drives on to the curb.
signal diverted(vehicle_id: int)

## 10 m/s along a lane.
const SPEED_MM := 500
## Front to front: a 5 m car and 2 m between cars.
const GAP_MM := 7000
## How long a car stands in a curb berth once its passengers got out.
const DWELL_TICKS := 60
## Tuning placeholder: the fee per car a surface lot earns when the car parks
## (decision landside-parking-houses-earn-a-parking-fee-per-car-paid-when).
const SURFACE_LOT_FEE := 20
const STAY_MIN_TICKS := GameCalendar.TICKS_PER_DAY
const STAY_MAX_TICKS := 3 * GameCalendar.TICKS_PER_DAY
## Further ahead than any car can be.
const FAR_MM := 1 << 40

@export var definition: LandsideDefinition
## In a scene the parking fees go to its wallet; tests set `wallet`.
@export var finances: Finances

var wallet: Wallet
## The tick of the last step.
var tick := 0
## Per lot spot: whether a car park stands there. A new game has none.
var lots_built: Array[bool] = []

var _vehicles: Array[LandsideVehicle] = []
var _by_id := {}
var _next_id := 1
## Derived from the vehicles: the vehicle in each curb berth, or 0.
var _berths: Array[int] = []
## Derived: per lot spot, the vehicle holding each slot (driving to it or
## parked in it), or 0.
var _slots: Array = []
var _road_in_mm := 0
var _road_out_mm := 0
var _access_mm: Array[int] = []
var _exit_mm: Array[int] = []


func _ready() -> void:
	if finances != null:
		wallet = finances.wallet
	if definition == null:
		push_error("LandsideSim: no definition is set, so no car can arrive")
		return
	if lots_built.is_empty():
		use_definition(definition)


## Takes `with_definition` and starts empty: no vehicles and no lot built.
## Returns false (with an error) when the definition cannot be driven.
func use_definition(with_definition: LandsideDefinition) -> bool:
	var problem := with_definition.problem()
	if problem != "":
		push_error("LandsideSim: %s" % problem)
		return false
	definition = with_definition
	_road_in_mm = LandsideDefinition.length_mm(definition.road_in)
	_road_out_mm = LandsideDefinition.length_mm(definition.road_out)
	_access_mm.clear()
	_exit_mm.clear()
	for spot in definition.lots:
		_access_mm.append(LandsideDefinition.length_mm(spot.access))
		_exit_mm.append(LandsideDefinition.length_mm(spot.exit))
	lots_built.clear()
	lots_built.resize(definition.lots.size())
	lots_built.fill(false)
	_vehicles.clear()
	_by_id.clear()
	_next_id = 1
	_rederive()
	return true


## Puts a surface lot on spot `spot`. False (with an error) for an unknown
## spot or one already built. The build tool (Landside 3/4) will call this.
func build_lot(spot: int) -> bool:
	if spot < 0 or spot >= lots_built.size() or lots_built[spot]:
		push_error("LandsideSim.build_lot: spot %d is unknown or built" % spot)
		return false
	lots_built[spot] = true
	return true


## The free slots of lot spot `spot`: neither reserved nor parked in.
func free_slots(spot: int) -> int:
	return (_slots[spot] as Array).count(0) if lots_built[spot] else 0


## What a car of `intent` will do: PARK only while some car park stands.
func resolve_intent(intent: LandsideVehicle.Intent) -> LandsideVehicle.Intent:
	if intent == LandsideVehicle.Intent.PARK and _first_built_lot() < 0:
		return LandsideVehicle.Intent.DROP
	return intent


## Ticks from entering road_in to letting the passengers out, on a free road:
## to the curb's stop, or to the first built lot's turn and along its access
## lane. A car handed over that long before its unload tick gets out on it.
func lead_ticks(intent: LandsideVehicle.Intent) -> int:
	var spot := _first_built_lot()
	if resolve_intent(intent) == LandsideVehicle.Intent.PARK:
		return (
			ceili(float(definition.lots[spot].branch_mm) / SPEED_MM)
			+ ceili(float(_access_mm[spot]) / SPEED_MM)
		)
	return ceili(float(definition.curb.stop_mm) / SPEED_MM)


## A new vehicle carrying `bookings` enters road_in behind the last car
## there (off the map while the queue reaches the start). Returns its id.
func add_vehicle(
	kind: LandsideVehicle.Kind, intent: LandsideVehicle.Intent, bookings: Array[int]
) -> int:
	var v := LandsideVehicle.new()
	v.id = _next_id
	_next_id += 1
	v.kind = kind
	v.intent = resolve_intent(intent)
	v.bookings = bookings.duplicate()
	v.lane = LandsideVehicle.Lane.ROAD_IN
	v.pos_mm = 0
	for other in _members(LandsideVehicle.Lane.ROAD_IN, -1):
		v.pos_mm = mini(v.pos_mm, other.pos_mm - GAP_MM)
	v.stage = LandsideVehicle.Stage.DRIVE
	v.stage_tick = tick
	_vehicles.append(v)
	_by_id[v.id] = v
	return v.id


## A booking that left the vehicle without getting out (its flight closed).
## A car emptied on road_in no longer means to park: it never turns into a
## lot, so it reserves no slot and pays nothing.
func drop_booking(vehicle_id: int, booking_id: int) -> void:
	var v: LandsideVehicle = _by_id.get(vehicle_id)
	if v == null or not v.bookings.has(booking_id):
		push_error("LandsideSim: vehicle %d does not carry booking %d" % [vehicle_id, booking_id])
		return
	v.bookings.erase(booking_id)
	if v.bookings.is_empty() and v.lane == LandsideVehicle.Lane.ROAD_IN:
		v.intent = LandsideVehicle.Intent.DROP


func vehicle_ids() -> Array[int]:
	var ids: Array[int] = []
	for v in _vehicles:
		ids.append(v.id)
	return ids


func get_vehicle(id: int) -> LandsideVehicle:
	return _by_id.get(id)


## One tick at `now`. Returns the release events in order, each
## {"vehicle": id, "bookings": Array[int], "walk": Array[Vector3]}: the
## bookings whose passengers got out and the walk from where they stepped out.
## With `can_release` false nobody gets out. `rng` draws parked stays.
func step(now: int, can_release: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	tick = now
	var released: Array[Dictionary] = []
	_step_leaving()
	_step_parked(can_release, released)
	_step_dwelling(can_release, released)
	for spot in definition.lots.size():
		_step_access(spot, can_release, released, rng)
	_step_road_in(can_release, released)
	return released


## Where the vehicle stands, in world space.
func world_position(v: LandsideVehicle) -> Vector3:
	match v.lane:
		LandsideVehicle.Lane.BERTH:
			return definition.curb.berths[v.stop]
		LandsideVehicle.Lane.SLOT:
			return definition.lots[v.lot].slots[v.stop]
	return LandsideDefinition.point_at(_lane_points(v.lane, v.lot), v.pos_mm)


## The flat direction the vehicle faces.
func heading(v: LandsideVehicle) -> Vector3:
	match v.lane:
		LandsideVehicle.Lane.BERTH:
			return LandsideDefinition.heading_at(definition.road_in, definition.curb.stop_mm)
		LandsideVehicle.Lane.SLOT:
			return LandsideDefinition.heading_at(definition.lots[v.lot].access, _access_mm[v.lot])
	return LandsideDefinition.heading_at(_lane_points(v.lane, v.lot), v.pos_mm)


## JSON-safe state, with the bookings PassengerSim keeps (`bookings`) and
## the passengers' tick. Reads only.
func to_snapshot(bookings: ArrivalBookings, at_tick: int) -> Dictionary:
	return LandsideSnapshot.save(self, _vehicles, _next_id, bookings, at_tick)


## Restores a to_snapshot() dictionary into this sim and `bookings`. Pushes an
## error and returns false, changing neither, when it is refused.
func from_snapshot(data: Dictionary, bookings: ArrivalBookings) -> bool:
	var loaded := LandsideSnapshot.load(data, definition)
	if loaded.has("error"):
		push_error("LandsideSim.from_snapshot: %s" % loaded["error"])
		return false
	tick = loaded["tick"]
	lots_built = loaded["lots_built"]
	_vehicles = loaded["vehicles"]
	_next_id = loaded["next_vehicle_id"]
	_by_id.clear()
	for v in _vehicles:
		_by_id[v.id] = v
	_rederive()
	bookings.restore(loaded)
	return true


func _step_leaving() -> void:
	var lanes := [[LandsideVehicle.Lane.ROAD_OUT, -1, _road_out_mm]]
	for spot in definition.lots.size():
		lanes.append([LandsideVehicle.Lane.LOT_EXIT, spot, _exit_mm[spot]])
	for entry in lanes:
		var leader := FAR_MM
		for v in _members(entry[0], entry[1]):
			v.pos_mm = maxi(v.pos_mm, mini(v.pos_mm + SPEED_MM, leader - GAP_MM))
			if v.pos_mm >= entry[2]:
				_remove(v)
				leader = FAR_MM
			else:
				leader = v.pos_mm


func _step_parked(can_release: bool, released: Array[Dictionary]) -> void:
	for v in _vehicles:
		if v.stage != LandsideVehicle.Stage.PARKED:
			continue
		if not v.bookings.is_empty():
			if can_release:
				_release(v, _lot_walk(v), released)
			continue
		if tick >= v.leave_tick and _lane_clear(LandsideVehicle.Lane.LOT_EXIT, v.lot):
			_slots[v.lot][v.stop] = 0
			v.leave_tick = 0
			_enter(v, LandsideVehicle.Lane.LOT_EXIT, LandsideVehicle.Stage.LEAVE)


func _step_dwelling(can_release: bool, released: Array[Dictionary]) -> void:
	for v in _vehicles:
		if v.stage != LandsideVehicle.Stage.DWELL:
			continue
		if not v.bookings.is_empty():
			if can_release:
				_release(v, [definition.curb.get_out[v.stop]], released)
				v.stage_tick = tick
			continue
		if tick - v.stage_tick >= DWELL_TICKS and _lane_clear(LandsideVehicle.Lane.ROAD_OUT, -1):
			_berths[v.stop] = 0
			_enter(v, LandsideVehicle.Lane.ROAD_OUT, LandsideVehicle.Stage.LEAVE)


func _step_access(
	spot: int, can_release: bool, released: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	var end := _access_mm[spot]
	var leader := FAR_MM
	for v in _members(LandsideVehicle.Lane.ACCESS, spot):
		var held := _drive(v, leader, end)
		leader = v.pos_mm
		if v.pos_mm < end:
			_set_moving(v, held)
			continue
		if v.bookings.is_empty():
			# Its passengers missed their flight on the way: it turns round.
			_set_moving(v, true)
			if _lane_clear(LandsideVehicle.Lane.LOT_EXIT, spot):
				_slots[spot][v.stop] = 0
				_enter(v, LandsideVehicle.Lane.LOT_EXIT, LandsideVehicle.Stage.LEAVE)
				leader = FAR_MM
			continue
		_park(v, rng)
		leader = FAR_MM
		if can_release:
			_release(v, _lot_walk(v), released)


func _step_road_in(can_release: bool, released: Array[Dictionary]) -> void:
	var leader := FAR_MM
	for v in _members(LandsideVehicle.Lane.ROAD_IN, -1):
		# An empty car never parks, however it got here (a save included).
		if v.bookings.is_empty():
			v.intent = LandsideVehicle.Intent.DROP
		var spot := _lot_ahead(v)
		var stop := definition.curb.stop_mm
		if spot >= 0:
			stop = definition.lots[spot].branch_mm
		var held := _drive(v, leader, stop)
		leader = v.pos_mm
		if v.pos_mm < stop:
			_set_moving(v, held)
			continue
		if spot >= 0:
			if _turn_into_lot(v, spot):
				leader = FAR_MM
			else:
				_set_moving(v, false)
			continue
		var berth := _berths.find(0)
		if berth < 0:
			_set_moving(v, true)
			continue
		_berths[berth] = v.id
		v.lane = LandsideVehicle.Lane.BERTH
		v.stop = berth
		v.pos_mm = 0
		_set_stage(v, LandsideVehicle.Stage.DWELL)
		leader = FAR_MM
		if v.bookings.is_empty():
			# Nobody to let out: it pulls through at once.
			v.stage_tick = tick - DWELL_TICKS
		elif can_release:
			_release(v, [definition.curb.get_out[berth]], released)


## At its lot's turn: reserve the lowest free slot and turn onto the access
## lane, or (the lot full) give up parking. True when it turned.
func _turn_into_lot(v: LandsideVehicle, spot: int) -> bool:
	var slot := (_slots[spot] as Array).find(0)
	if slot < 0:
		v.intent = LandsideVehicle.Intent.DROP
		diverted.emit(v.id)
		return false
	_slots[spot][slot] = v.id
	v.lot = spot
	v.stop = slot
	_enter(v, LandsideVehicle.Lane.ACCESS, LandsideVehicle.Stage.DRIVE)
	return true


## Moves `v` a step toward its `stop` (never back), no closer than a gap
## behind the car ahead at `leader`. True when that car held it back.
func _drive(v: LandsideVehicle, leader: int, stop: int) -> bool:
	var reach := mini(v.pos_mm + SPEED_MM, stop)
	v.pos_mm = maxi(v.pos_mm, mini(reach, leader - GAP_MM))
	return leader - GAP_MM < reach


## DRIVE or QUEUE; the stage tick moves only when the stage does.
func _set_moving(v: LandsideVehicle, queued: bool) -> void:
	var stage := LandsideVehicle.Stage.QUEUE if queued else LandsideVehicle.Stage.DRIVE
	if v.stage != stage:
		_set_stage(v, stage)


## Parks `v` in its reserved slot. The fee is settled the way shop income is
## (CafeSim and ShopSim._settle()): credited first, and `parked` is emitted
## only once the credit landed. Without a wallet, or when the wallet refuses
## (Wallet.MAX_BALANCE), an error says so and no fee is taken; the car
## still parks, so its passengers are not held up by the balance.
func _park(v: LandsideVehicle, rng: RandomNumberGenerator) -> void:
	v.lane = LandsideVehicle.Lane.SLOT
	v.pos_mm = 0
	v.leave_tick = tick + rng.randi_range(STAY_MIN_TICKS, STAY_MAX_TICKS)
	_set_stage(v, LandsideVehicle.Stage.PARKED)
	if wallet == null:
		push_error("LandsideSim: no wallet to pay vehicle %d's parking fee into" % v.id)
		return
	if not wallet.credit(SURFACE_LOT_FEE, Wallet.Category.PARKING):
		push_error("LandsideSim: the wallet refused vehicle %d's parking fee" % v.id)
		return
	parked.emit(v.id, v.lot)


## The walk from a parked car: its slot, the lot gate, then the crossing.
func _lot_walk(v: LandsideVehicle) -> Array[Vector3]:
	var spot := definition.lots[v.lot]
	var walk: Array[Vector3] = [spot.slots[v.stop], spot.access[spot.access.size() - 1]]
	walk.append_array(Array(spot.crossing))
	return walk


func _release(v: LandsideVehicle, walk: Array, released: Array[Dictionary]) -> void:
	var points: Array[Vector3] = []
	points.assign(walk)
	released.append({"vehicle": v.id, "bookings": v.bookings.duplicate(), "walk": points})
	v.bookings.clear()


func _enter(v: LandsideVehicle, lane: LandsideVehicle.Lane, stage: LandsideVehicle.Stage) -> void:
	if lane != LandsideVehicle.Lane.ACCESS:
		v.stop = -1
	if lane == LandsideVehicle.Lane.ROAD_OUT:
		v.lot = -1
	v.lane = lane
	v.pos_mm = 0
	_set_stage(v, stage)


func _set_stage(v: LandsideVehicle, stage: LandsideVehicle.Stage) -> void:
	v.stage = stage
	v.stage_tick = tick


func _remove(v: LandsideVehicle) -> void:
	_vehicles.erase(v)
	_by_id.erase(v.id)


## A car that means to park: the first built lot whose turn it has not
## passed, or -1 (it drops off at the curb then).
func _lot_ahead(v: LandsideVehicle) -> int:
	if v.intent != LandsideVehicle.Intent.PARK:
		return -1
	for spot in definition.lots.size():
		if lots_built[spot] and definition.lots[spot].branch_mm >= v.pos_mm:
			return spot
	v.intent = LandsideVehicle.Intent.DROP
	return -1


func _first_built_lot() -> int:
	return lots_built.find(true)


## The vehicles on a lane (and lot spot), front first, ties by id.
func _members(lane: LandsideVehicle.Lane, spot: int) -> Array[LandsideVehicle]:
	var out: Array[LandsideVehicle] = []
	for v in _vehicles:
		if v.lane == lane and (spot < 0 or v.lot == spot):
			out.append(v)
	out.sort_custom(_front_first)
	return out


static func _front_first(a: LandsideVehicle, b: LandsideVehicle) -> bool:
	if a.pos_mm != b.pos_mm:
		return a.pos_mm > b.pos_mm
	return a.id < b.id


## Whether a car may enter the lane's start: the last car there is a gap on.
func _lane_clear(lane: LandsideVehicle.Lane, spot: int) -> bool:
	for v in _members(lane, spot):
		if v.pos_mm < GAP_MM:
			return false
	return true


func _lane_points(lane: LandsideVehicle.Lane, spot: int) -> PackedVector3Array:
	match lane:
		LandsideVehicle.Lane.ROAD_OUT:
			return definition.road_out
		LandsideVehicle.Lane.ACCESS:
			return definition.lots[spot].access
		LandsideVehicle.Lane.LOT_EXIT:
			return definition.lots[spot].exit
	return definition.road_in


## Berth and slot holders from the vehicle records, after a load or a reset.
func _rederive() -> void:
	_berths.resize(definition.curb.berths.size())
	_berths.fill(0)
	_slots.clear()
	for spot in definition.lots:
		var holders: Array[int] = []
		holders.resize(spot.slots.size())
		holders.fill(0)
		_slots.append(holders)
	for v in _vehicles:
		if v.lane == LandsideVehicle.Lane.BERTH:
			_berths[v.stop] = v.id
		elif v.lane in [LandsideVehicle.Lane.ACCESS, LandsideVehicle.Lane.SLOT]:
			_slots[v.lot][v.stop] = v.id
