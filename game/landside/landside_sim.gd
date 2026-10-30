# gdlint:disable = max-public-methods
# LandsideSim is the one owner of the road, the curb and the car parks; the
# build tools' calls (build_*, remove_*, set_lot_closed and their counts) took
# it past the 20-method cap.
class_name LandsideSim
extends Node
## Cars and taxis on the fixed road past the terminal (decision
## landside-technical-design-arrival-bookings-landsidesim-vehic), as plain
## vehicle records on the authored 1-D lanes of a LandsideDefinition, in
## whole mm with a fixed gap between cars. It does not listen to the clock:
## PassengerSim's ArrivalBookings steps it once a tick, hands it new vehicles
## and takes the release events it returns.
##
## A car never jumps: between a lane and a curb berth or a parking slot it
## drives the berth's or slot's path (LandsidePaths), at most SPEED_MM a tick,
## in and out again. It lets its passengers out when it has pulled in, and a
## parked car pays the parking fee then, once.
##
## Each step, in order: leaving cars drive on (and are gone at their lane's
## end); in each car park, cars on their slot paths drive on (a car that has
## pulled in parks and lets its passengers out; one that has pulled out joins
## the lot's exit lane when it is clear), cars on the access lane drive to the
## gate, and when no car moves in the lot the oldest request goes next: the car
## at the gate pulls in (or, empty, turns round), or a parked car whose stay is
## over pulls out. Then the curb and road_in: a car in a berth lets held
## passengers out and, DWELL_TICKS after, pulls out when its way back onto the
## road is clear (_merge_clear()); then road_in and the berth paths drive as one
## road, front first, each car no closer than a gap behind the car ahead on the
## road line, whichever lane it is on. A car that means to park stops at its
## lot's turn and takes a free slot there, or, the lot being full, drives on to
## the curb (decision landside-congestion-a-jammed-curb-or-full-car-park-delays-pa).
## A car at the curb's stop takes the nearest free berth or queues. A lane is
## entered at its start only once the car last in it is a gap away, except
## road_in, whose queue runs on off the map (negative positions).
##
## Passengers get out only when the terminal has an entrance; until then
## they stay aboard in the berth or the parked car. A car whose passengers
## all missed their flight while it drove pulls through a berth at once,
## turns round at a car park's gate, or, already in the car park, pulls out
## of its slot without paying. Parked cars stay 1 to 3 game days (decision
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
## Ticks between two passengers of one party stepping out. At the walking pace
## (PassengerSim.WALK_MM, 98 mm a tick) that is about 0.69 m, so they do not stand
## on one another (decision passenger-spacing-fixed-per-cause-standing-spots-
## staggered-unloading-ordered-files, part 2).
const RELEASE_GAP_TICKS := 7
## Tuning placeholder: the fee per car a surface lot earns when the car parks
## (decision landside-parking-houses-earn-a-parking-fee-per-car-paid-when).
const SURFACE_LOT_FEE := 20
const STAY_MIN_TICKS := GameCalendar.TICKS_PER_DAY
const STAY_MAX_TICKS := 3 * GameCalendar.TICKS_PER_DAY
## Further ahead than any car can be.
const FAR_MM := 1 << 40
## How far before its first berth a curb's queue head stands: the starter
## curb's stop (LandsideCurb.stop_mm) is this far before its first berth, and a
## built curb bay's stop is as far before its own. A berth's path leaves the
## road line there.
const BERTH_APPROACH_MM := LandsidePaths.BERTH_APPROACH_MM

@export var definition: LandsideDefinition
## In a scene the parking fees go to its wallet; tests set `wallet`.
@export var finances: Finances

var wallet: Wallet
## The berth and slot paths of the definition.
var paths: LandsidePaths
## The tick of the last step.
var tick := 0
## Per lot spot: whether a car park stands there. A new game has none.
var lots_built: Array[bool] = []
## Per lot spot: whether the car park takes no new arrivals, so it drains
## (decision landside-technical-design-arrival-bookings-landsidesim-vehic,
## point 7). Cars already on its lanes park and leave as usual.
var lots_closed: Array[bool] = []
## Per lot spot: the price it was built for, 0 when free or not built; what a
## removal refunds a share of.
var lots_paid: Array[int] = []
## Per curb spot: whether a curb bay stands there, and its price as above.
var curbs_built: Array[bool] = []
var curbs_paid: Array[int] = []

var _vehicles: Array[LandsideVehicle] = []
## The doors-close tick of each booking aboard's flight, as step() was given.
var _closes := {}
var _by_id := {}
var _next_id := 1
## Derived from the vehicles: the vehicle holding each curb berth (pulling in,
## standing, or pulling out until it is back on the road line), or 0.
var _berths: Array[int] = []
## Derived: where along road_in each berth stands, in mm.
var _berth_mm: Array[int] = []
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
	paths = LandsidePaths.new(definition)
	_road_in_mm = LandsideDefinition.length_mm(definition.road_in)
	_road_out_mm = LandsideDefinition.length_mm(definition.road_out)
	_access_mm.clear()
	_exit_mm.clear()
	for spot in definition.lots:
		_access_mm.append(LandsideDefinition.length_mm(spot.access))
		_exit_mm.append(LandsideDefinition.length_mm(spot.exit))
	lots_built.assign(_filled(definition.lots.size(), false))
	lots_closed.assign(_filled(definition.lots.size(), false))
	lots_paid.assign(_filled(definition.lots.size(), 0))
	curbs_built.assign(_filled(definition.curb_spots.size(), false))
	curbs_paid.assign(_filled(definition.curb_spots.size(), 0))
	_vehicles.clear()
	_by_id.clear()
	_next_id = 1
	_rederive()
	return true


## Puts a car park on lot spot `spot`, bought for `paid`. False (with an
## error) for an unknown spot or one already built.
func build_lot(spot: int, paid := 0) -> bool:
	if spot < 0 or spot >= lots_built.size() or lots_built[spot]:
		push_error("LandsideSim.build_lot: spot %d is unknown or built" % spot)
		return false
	lots_built[spot] = true
	lots_paid[spot] = paid
	return true


## Takes the car park off lot spot `spot`. Refused (false, nothing changed)
## while any car is on its lanes or parked, or when none stands there.
func remove_lot(spot: int) -> bool:
	if spot < 0 or spot >= lots_built.size() or not lots_built[spot] or lot_cars(spot) > 0:
		return false
	lots_built[spot] = false
	lots_closed[spot] = false
	lots_paid[spot] = 0
	return true


## Closes the built car park `spot` to new arrivals, or opens it again. False
## for an unknown or unbuilt spot.
func set_lot_closed(spot: int, closed: bool) -> bool:
	if spot < 0 or spot >= lots_built.size() or not lots_built[spot]:
		return false
	lots_closed[spot] = closed
	return true


## How many cars are on lot spot `spot`'s lanes or parked in it.
func lot_cars(spot: int) -> int:
	var count := 0
	for v in _vehicles:
		if v.lot == spot:
			count += 1
	return count


## Whether lot spot `spot` takes new arrivals: built and not closed.
func lot_open(spot: int) -> bool:
	return lots_built[spot] and not lots_closed[spot]


## Puts a curb bay on curb spot `spot`, bought for `paid`; its berths join the
## curb. False (with an error) for an unknown spot or one already built.
func build_curb(spot: int, paid := 0) -> bool:
	if spot < 0 or spot >= curbs_built.size() or curbs_built[spot]:
		push_error("LandsideSim.build_curb: spot %d is unknown or built" % spot)
		return false
	curbs_built[spot] = true
	curbs_paid[spot] = paid
	return true


## Takes the curb bay off curb spot `spot`. Refused (false, nothing changed)
## while a car is on the path of one of its berths, or when none stands there.
func remove_curb(spot: int) -> bool:
	if spot < 0 or spot >= curbs_built.size() or not curbs_built[spot] or curb_cars(spot) > 0:
		return false
	curbs_built[spot] = false
	curbs_paid[spot] = 0
	return true


## How many cars are on the paths of curb spot `spot`'s berths: pulling in,
## standing or pulling out.
func curb_cars(spot: int) -> int:
	var count := 0
	for v in _vehicles:
		if v.lane == LandsideVehicle.Lane.BERTH and definition.berth_spot(v.stop) == spot:
			count += 1
	return count


## The free slots of lot spot `spot`: neither reserved nor parked in.
func free_slots(spot: int) -> int:
	return (_slots[spot] as Array).count(0) if lots_built[spot] else 0


## What a car of `intent` will do: PARK only while some car park is open.
func resolve_intent(intent: LandsideVehicle.Intent) -> LandsideVehicle.Intent:
	if intent == LandsideVehicle.Intent.PARK and _lot_for(0) < 0:
		return LandsideVehicle.Intent.DROP
	return intent


## Ticks from entering road_in to letting the passengers out, on a free road
## and with the berths and slots as they are now: to the curb's stop and in
## along the path of the berth a car there takes (the nearest free one, or
## the nearest when all are taken), or to the turn of the lot a new car would
## take (_lot_for(): the first open lot with a free slot), along its access
## lane and in along its lowest free slot's path. Each leg ends on a tick of
## its own, as the car changes lane there. A car handed over that long before
## its unload tick gets out on it.
func lead_ticks(intent: LandsideVehicle.Intent) -> int:
	var spot := _lot_for(0)
	if resolve_intent(intent) == LandsideVehicle.Intent.PARK:
		var slot := maxi((_slots[spot] as Array).find(0), 0)
		return (
			_ticks(definition.lots[spot].branch_mm)
			+ _ticks(_access_mm[spot])
			+ _ticks(paths.slot_stand[spot][slot] - _access_mm[spot])
		)
	var stop := curb_stop_mm()
	var berth := _free_berth(stop, FAR_MM)
	if berth < 0:
		berth = _nearest_berth(stop)
	if berth < 0:
		return _ticks(stop)
	return _ticks(stop) + _ticks(paths.berth_stand[berth] - stop)


## Where the curb's queue head waits, in mm along road_in: the starter curb's
## stop, or, once a curb bay stands upstream of it, just before that bay's first
## berth. A car never reverses, so the stop is upstream of every berth a car
## takes there.
func curb_stop_mm() -> int:
	var stop := definition.curb.stop_mm
	for i in _berths.size():
		var spot := definition.berth_spot(i)
		if spot >= 0 and curbs_built[spot]:
			stop = mini(stop, _berth_mm[i] - BERTH_APPROACH_MM)
	return maxi(stop, 0)


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
	if v.bookings.is_empty():
		v.release_wait = 0
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
## With `can_release` false nobody gets out. A party gets out one passenger at
## a time, RELEASE_GAP_TICKS apart, and the rest stay aboard, unless the stagger
## would run to the doors-close tick of their flight (`closes`: booking id to
## that tick, for the bookings aboard), when they all get out at once. `rng` draws
## parked stays.
func step(
	now: int, can_release: bool, rng: RandomNumberGenerator, closes := {}
) -> Array[Dictionary]:
	tick = now
	_closes = closes
	var released: Array[Dictionary] = []
	for v in _vehicles:
		v.release_wait = maxi(v.release_wait - 1, 0)
	_step_leaving()
	for spot in definition.lots.size():
		_step_lot(spot, can_release, released, rng)
	_step_curb(can_release, released)
	return released


## Where the vehicle stands, in world space.
func world_position(v: LandsideVehicle) -> Vector3:
	return LandsideDefinition.point_at(paths.path(v.lane, v.lot, v.stop), v.pos_mm)


## The flat direction the vehicle faces.
func heading(v: LandsideVehicle) -> Vector3:
	return paths.facing(v.lane, v.lot, v.stop, v.pos_mm)


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
	lots_closed = loaded["lots_closed"]
	lots_paid = loaded["lots_paid"]
	curbs_built = loaded["curbs_built"]
	curbs_paid = loaded["curbs_paid"]
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


## One car park: its slot paths, its access lane, then the requests to move.
## In- and outbound cars share the aisle and the ramps, so they never move at
## once, and one car pulls out at a time; cars pulling in follow each other a
## gap apart from the gate and never stop on the way, so several may.
func _step_lot(
	spot: int, can_release: bool, released: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	var moving_in := false
	var moving_out := false
	for v in _members(LandsideVehicle.Lane.SLOT, spot):
		match v.stage:
			LandsideVehicle.Stage.PARKED:
				if not v.bookings.is_empty() and can_release and v.release_wait == 0:
					_release(v, paths.lot_walk(spot, v.stop), released)
			LandsideVehicle.Stage.DRIVE:
				var stand := paths.slot_stand[spot][v.stop] as int
				v.pos_mm = mini(v.pos_mm + SPEED_MM, stand)
				if v.pos_mm < stand:
					moving_in = true
				else:
					_arrive_in_slot(v, can_release, released, rng)
			LandsideVehicle.Stage.LEAVE:
				var end := paths.end_of(v.lane, spot, v.stop)
				v.pos_mm = mini(v.pos_mm + SPEED_MM, end)
				if v.pos_mm == end and _lane_clear(LandsideVehicle.Lane.LOT_EXIT, spot):
					_enter(v, LandsideVehicle.Lane.LOT_EXIT, LandsideVehicle.Stage.LEAVE)
				else:
					moving_out = true
	var gate := _step_access(spot)
	if not moving_out:
		_grant(spot, gate, moving_in)


## Drives the access lane to the gate; returns the car waiting there, or null.
func _step_access(spot: int) -> LandsideVehicle:
	var end := _access_mm[spot]
	var leader := FAR_MM
	var waiting: LandsideVehicle = null
	for v in _members(LandsideVehicle.Lane.ACCESS, spot):
		var held := _drive(v, leader, end)
		leader = v.pos_mm
		if v.pos_mm < end:
			_set_moving(v, held)
			continue
		# At the gate it waits until it may go in (its request is its stage tick).
		_set_moving(v, true)
		waiting = v
	return waiting


## Lets the oldest request in car park `spot` move, while no car pulls out
## there: the car at the gate (`gate`, or null) since it reached it, or a
## parked car since its stay ended; ties by vehicle id. A car that would pull
## out waits for the cars `moving_in` to arrive, and so does a newer car at the
## gate, so a stream of arrivals cannot keep it in forever.
func _grant(spot: int, gate: LandsideVehicle, moving_in: bool) -> void:
	var best := gate
	var best_tick := gate.stage_tick if gate != null else FAR_MM
	for v in _members(LandsideVehicle.Lane.SLOT, spot):
		var due := (
			v.stage == LandsideVehicle.Stage.PARKED
			and v.bookings.is_empty()
			and tick >= v.leave_tick
		)
		if due and (v.leave_tick < best_tick or (v.leave_tick == best_tick and v.id < best.id)):
			best = v
			best_tick = v.leave_tick
	if best == null:
		return
	# A car turning round at the gate leaves the way it came in: it waits too.
	var outbound := best.lane == LandsideVehicle.Lane.SLOT or best.bookings.is_empty()
	if outbound and moving_in:
		return
	if best.lane == LandsideVehicle.Lane.ACCESS:
		best.lane = LandsideVehicle.Lane.SLOT
		if best.bookings.is_empty():
			# Its passengers missed their flight on the way: it turns round.
			_slots[spot][best.stop] = 0
			best.stop = -1
			_set_stage(best, LandsideVehicle.Stage.LEAVE)
		else:
			_set_stage(best, LandsideVehicle.Stage.DRIVE)
		return
	_slots[spot][best.stop] = 0
	best.leave_tick = 0
	_set_stage(best, LandsideVehicle.Stage.LEAVE)


## A car that has pulled into its slot parks (the fee once) and lets its
## passengers out; an empty one is due to leave at once and pays nothing.
func _arrive_in_slot(
	v: LandsideVehicle, can_release: bool, released: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	if v.bookings.is_empty():
		v.leave_tick = maxi(tick, 1)
		_set_stage(v, LandsideVehicle.Stage.PARKED)
		return
	_park(v, rng)
	if can_release:
		_release(v, paths.lot_walk(v.lot, v.stop), released)


## The curb and road_in. First every car standing in a berth lets held
## passengers out or starts pulling out; then road_in and the berth paths
## drive as one road (_drive_road()).
func _step_curb(can_release: bool, released: Array[Dictionary]) -> void:
	var waiting := FAR_MM
	for v in _members(LandsideVehicle.Lane.BERTH, -1):
		if v.stage != LandsideVehicle.Stage.DWELL:
			continue
		if not v.bookings.is_empty():
			if can_release and v.release_wait == 0:
				_release(v, [definition.berth_get_out(v.stop)], released)
				v.stage_tick = tick
			continue
		if tick - v.stage_tick < DWELL_TICKS:
			continue
		if _merge_clear(v):
			_set_stage(v, LandsideVehicle.Stage.LEAVE)
		else:
			waiting = mini(waiting, _berth_mm[v.stop])
	_drive_road(waiting, can_release, released)


## Road_in and every car pulling into or out of a berth, front first along the
## road line: each is held a gap behind the car ahead on that line, whichever
## lane it is on (a car tapering into its berth has left the line; one tapering
## out counts at the road point its way out is level with). No car at the stop
## takes a berth past one whose car `waiting` to pull out stands at.
func _drive_road(waiting: int, can_release: bool, released: Array[Dictionary]) -> void:
	var road: Array[LandsideVehicle] = []
	for v in _vehicles:
		if v.lane == LandsideVehicle.Lane.ROAD_IN:
			road.append(v)
		elif v.lane == LandsideVehicle.Lane.BERTH and v.stage != LandsideVehicle.Stage.DWELL:
			road.append(v)
	road.sort_custom(
		func(a: LandsideVehicle, b: LandsideVehicle) -> bool:
			var by_axis := _axis(a) - _axis(b)
			return a.id < b.id if by_axis == 0 else by_axis > 0
	)
	var leader := FAR_MM
	for v in road:
		if v.lane == LandsideVehicle.Lane.ROAD_IN:
			leader = _drive_road_in(v, leader, waiting)
		elif v.stage == LandsideVehicle.Stage.DRIVE:
			leader = _pull_in(v, leader, can_release, released)
		else:
			leader = _pull_out(v, leader)


## One car on road_in: to its stop, then into its lot's access lane, or into
## the berth path of the nearest free berth. Returns the road position it
## holds the car behind to.
func _drive_road_in(v: LandsideVehicle, leader: int, waiting: int) -> int:
	# An empty car never parks, however it got here (a save included).
	if v.bookings.is_empty():
		v.intent = LandsideVehicle.Intent.DROP
	var spot := _lot_ahead(v)
	var stop := curb_stop_mm()
	if spot >= 0:
		stop = definition.lots[spot].branch_mm
	var held := _drive(v, leader, stop)
	if v.pos_mm < stop:
		_set_moving(v, held)
		return v.pos_mm
	if spot >= 0:
		if _turn_into_lot(v, spot):
			return FAR_MM
		# Waiting for room on the access lane, or (the lot full) driving on.
		_set_moving(v, v.intent == LandsideVehicle.Intent.PARK)
		return v.pos_mm
	var berth := _free_berth(v.pos_mm, waiting)
	if berth < 0:
		_set_moving(v, true)
		return v.pos_mm
	_berths[berth] = v.id
	v.lane = LandsideVehicle.Lane.BERTH
	v.stop = berth
	_set_stage(v, LandsideVehicle.Stage.DRIVE)
	return v.pos_mm


## A car pulling into its berth: along the road line it keeps a gap behind
## `leader`; once it has pulled in it lets its passengers out (or, empty,
## pulls through at once).
func _pull_in(
	v: LandsideVehicle, leader: int, can_release: bool, released: Array[Dictionary]
) -> int:
	var stand := paths.berth_stand[v.stop]
	var split := paths.berth_split[v.stop]
	var reach := mini(v.pos_mm + SPEED_MM, stand)
	if v.pos_mm <= split and leader - GAP_MM < split:
		reach = maxi(v.pos_mm, mini(reach, leader - GAP_MM))
	v.pos_mm = reach
	if v.pos_mm < stand:
		return v.pos_mm if v.pos_mm <= split else leader
	_set_stage(v, LandsideVehicle.Stage.DWELL)
	if v.bookings.is_empty():
		v.stage_tick = tick - DWELL_TICKS
	elif can_release:
		_release(v, [definition.berth_get_out(v.stop)], released)
	return leader


## A car pulling out of its berth, a gap behind `leader`; the berth is free
## once it is back on the road line, and at its path's end it joins road_out
## when that is clear.
func _pull_out(v: LandsideVehicle, leader: int) -> int:
	var end := paths.berth_end[v.stop]
	var room := paths.berth_join[v.stop] + leader - GAP_MM - paths.berth_join_mm[v.stop]
	v.pos_mm = maxi(v.pos_mm, mini(mini(v.pos_mm + SPEED_MM, end), room))
	if v.pos_mm >= paths.berth_join[v.stop] and _berths[v.stop] == v.id:
		_berths[v.stop] = 0
	if v.pos_mm == end and _lane_clear(LandsideVehicle.Lane.ROAD_OUT, -1):
		_enter(v, LandsideVehicle.Lane.ROAD_OUT, LandsideVehicle.Stage.LEAVE)
		return paths.out_mm
	return _axis(v)


## Where a car on road_in or a berth path is along the road line, in mm along
## road_in (carried on): its position while on the line; tapering out, the road
## point level with the rest of its way out; tapering in or standing, its
## berth's.
func _axis(v: LandsideVehicle) -> int:
	if v.lane != LandsideVehicle.Lane.BERTH:
		return v.pos_mm
	var i := v.stop
	if v.pos_mm <= paths.berth_split[i]:
		return v.pos_mm
	if v.pos_mm > paths.berth_stand[i]:
		return paths.berth_join_mm[i] + v.pos_mm - paths.berth_join[i]
	return _berth_mm[i] - (paths.berth_stand[i] - v.pos_mm)


## Whether the car standing in its berth may pull out now: nothing on the road
## line from beside its berth to a gap past where it rejoins it, no car
## tapering there, and no car moving up behind that would pass it within a gap
## (the way out's extra length counted, as the car behind gains it).
## A car waiting at the stop is not in its way: it stands still and keeps its
## gap once it moves.
func _merge_clear(v: LandsideVehicle) -> bool:
	var b := _berth_mm[v.stop]
	var ahead_to := paths.berth_join_mm[v.stop] + GAP_MM
	var behind_from := b - GAP_MM - paths.berth_slack[v.stop] - SPEED_MM
	for o in _vehicles:
		if o == v or not (o.lane in [LandsideVehicle.Lane.ROAD_IN, LandsideVehicle.Lane.BERTH]):
			continue
		if o.lane == LandsideVehicle.Lane.BERTH and o.stage == LandsideVehicle.Stage.DWELL:
			continue
		var axis := _axis(o)
		if axis >= b and axis <= ahead_to:
			return false
		if axis < behind_from or axis >= b or o.stage == LandsideVehicle.Stage.QUEUE:
			continue
		var stops_short := (
			o.lane == LandsideVehicle.Lane.BERTH
			and o.stage == LandsideVehicle.Stage.DRIVE
			and _berth_mm[o.stop] < b
		)
		if not stops_short:
			return false
	return true


## At its lot's turn: reserve the lowest free slot and turn onto the access
## lane once it has room, or (the lot full) give up parking. True when it
## turned.
func _turn_into_lot(v: LandsideVehicle, spot: int) -> bool:
	var slot := (_slots[spot] as Array).find(0)
	if slot < 0:
		v.intent = LandsideVehicle.Intent.DROP
		diverted.emit(v.id)
		return false
	if not _lane_clear(LandsideVehicle.Lane.ACCESS, spot):
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
	v.leave_tick = tick + rng.randi_range(STAY_MIN_TICKS, STAY_MAX_TICKS)
	_set_stage(v, LandsideVehicle.Stage.PARKED)
	if wallet == null:
		push_error("LandsideSim: no wallet to pay vehicle %d's parking fee into" % v.id)
		return
	if not wallet.credit(SURFACE_LOT_FEE, Wallet.Category.PARKING):
		push_error("LandsideSim: the wallet refused vehicle %d's parking fee" % v.id)
		return
	parked.emit(v.id, v.lot)


## The first passenger aboard gets out; the next may RELEASE_GAP_TICKS later.
## When the last would step out at or after the doors-close tick of the flight
## (`_closes`), all get out at once, as before the stagger, so the stagger never
## costs a flight.
func _release(v: LandsideVehicle, walk: Array, released: Array[Dictionary]) -> void:
	var points: Array[Vector3] = []
	points.assign(walk)
	var close: int = _closes.get(v.bookings[0], FAR_MM)
	var last := tick + v.release_wait + (v.bookings.size() - 1) * RELEASE_GAP_TICKS
	var out: Array[int] = []
	while not v.bookings.is_empty() and (out.is_empty() or last >= close):
		out.append(v.bookings.pop_front())
	released.append({"vehicle": v.id, "bookings": out, "walk": points})
	v.release_wait = 0 if v.bookings.is_empty() else RELEASE_GAP_TICKS


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


## Ticks to drive `mm` at SPEED_MM.
static func _ticks(mm: int) -> int:
	return ceili(float(mm) / SPEED_MM)


## A car that means to park: the lot it will take from `pos_mm`, or -1 (it
## drops off at the curb then).
func _lot_ahead(v: LandsideVehicle) -> int:
	if v.intent != LandsideVehicle.Intent.PARK:
		return -1
	var spot := _lot_for(v.pos_mm)
	if spot < 0:
		v.intent = LandsideVehicle.Intent.DROP
	return spot


## The lot a car at `pos_mm` on road_in takes: the open lot it reaches first
## whose turn it has not passed and which has a free slot, or the first it
## reaches when every one is full (it finds that out at the turn and drops at
## the curb), or -1. lead_ticks() and resolve_intent() ask this for a new car
## (position 0), so what they promise is what the car then does.
func _lot_for(pos_mm: int) -> int:
	var first := -1
	for spot in _lots_by_turn():
		if definition.lots[spot].branch_mm < pos_mm:
			continue
		if free_slots(spot) > 0:
			return spot
		if first < 0:
			first = spot
	return first


## The open lots in the order a car on road_in reaches their turns.
func _lots_by_turn() -> Array[int]:
	var spots: Array[int] = []
	for spot in lots_built.size():
		if lot_open(spot):
			spots.append(spot)
	spots.sort_custom(
		func(a: int, b: int) -> bool:
			var by_turn := definition.lots[a].branch_mm - definition.lots[b].branch_mm
			return a < b if by_turn == 0 else by_turn < 0
	)
	return spots


## The free berth, of the starter curb and the built curb bays, that a car at
## `pos_mm` reaches first driving on, standing before `before_mm`, or -1. A
## berth whose path leaves the road behind the car is never taken: it would
## reverse.
func _free_berth(pos_mm: int, before_mm: int) -> int:
	var best := -1
	for i in _berths.size():
		if _berths[i] != 0 or not _berth_built(i) or paths.berth_split[i] < pos_mm:
			continue
		if _berth_mm[i] >= before_mm:
			continue
		if best < 0 or _berth_mm[i] < _berth_mm[best]:
			best = i
	return best


## The built berth whose path a car at `pos_mm` reaches first, taken or not.
func _nearest_berth(pos_mm: int) -> int:
	var best := -1
	for i in _berths.size():
		if not _berth_built(i) or paths.berth_split[i] < pos_mm:
			continue
		if best < 0 or _berth_mm[i] < _berth_mm[best]:
			best = i
	return best


func _berth_built(i: int) -> bool:
	var spot := definition.berth_spot(i)
	return spot < 0 or curbs_built[spot]


static func _filled(count: int, value: Variant) -> Array:
	var out := []
	out.resize(count)
	out.fill(value)
	return out


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


## Berth and slot holders from the vehicle records, after a load or a reset:
## a berth is held until its car is back on the road line, a slot until its car
## starts to pull out.
func _rederive() -> void:
	_berths.resize(definition.berth_count())
	_berths.fill(0)
	_berth_mm.clear()
	for i in _berths.size():
		_berth_mm.append(definition.berth_mm(i))
	_slots.clear()
	for spot in definition.lots:
		var holders: Array[int] = []
		holders.resize(spot.slots.size())
		holders.fill(0)
		_slots.append(holders)
	for v in _vehicles:
		if v.lane == LandsideVehicle.Lane.BERTH and v.pos_mm < paths.berth_join[v.stop]:
			_berths[v.stop] = v.id
		elif LandsideSnapshot.holds_slot(v):
			_slots[v.lot][v.stop] = v.id
