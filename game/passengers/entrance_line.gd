class_name EntranceLine
extends RefCounted
## The line arrivals wait in outside the entrance while check-in is full
## (decision arrivals-wait-in-a-tidy-line-outside-the-entrance-when-check).
##
## Places: one per grid cell, in a straight column one cell to the side of the
## entrance's walk in (TerminalLayout.outside_routes), from START_STEPS cells
## out to at most MAX_PLACES, so the doorway and the walk in stay clear. On the
## site a place needs open ground (SiteRoutes.is_open_ground()) off every
## door's walk outside, beside a cell of the straight first run of the walk in;
## the side with more places wins, ties to the left of the way out. With no
## site (a test grid) the places are the same cells, unchecked. The places are
## derived from the layout on every step, so an edit that moves, removes or
## blocks the entrance re-places the line on the next tick.
##
## Every new passenger (PassengerLifecycle.spawn()) is taken in here. With no
## one waiting and a check-in place free for it (admit_room()), it is admitted:
## it holds a claim on a place of one desk that a walk from the door cell
## reaches (stations), until it walks in (entered()), and inside passengers
## looking for a desk cannot take it (PassengerStations.choose()). Only places
## the door reaches count, so one reachable place admits one passenger however
## many places stand on desks no walk reaches.
## Otherwise it takes the next place in the line and walks to it, the line
## order is its arrival order, and it stays outside until it is the head and a
## place frees, when it is admitted and walks to the door. Arrivals are let in
## only while the line has a place for each (room_for_arrivals()): cars and
## taxis hold their passengers otherwise (LandsideSim, one place per passenger
## in their release order), the debug schedule waits, and spawn_now() refuses.
## Deadline urgency never lets anyone past: the line is the only way in.
##
## Every tick each claim is checked again, in admission order (_revalidate()):
## it keeps its desk while that desk still has a reachable place for it, or
## moves to the reachable desk with the most places left. A claim left with no
## place, and one whose walker is bound for a door that is no longer the
## entrance (the entrance moved or went), goes back to the front of the line,
## last admitted first, while the line has places. Not guaranteed: with every
## place taken, such a walker keeps an empty claim and goes on in (to the new
## door when the entrance moved), and waits on the door cell. Desks that are
## all closed count as no free place, so arrivals wait outside; only a
## terminal with no check-in desk lets everyone in, to wait inside with
## NO_CHECKIN as before. Admitted walkers keep a gap on the
## way to the door (step_of()), so they reach it one at a time.

## The first place is this many cells out from the door cell.
const START_STEPS := 2
## The most places a line has.
const MAX_PLACES := 16
## The most arrivals let in at once when the room is not counted (no check-in
## desk open).
const UNLIMITED := 1 << 30
## Admitted walkers keep this far apart on the way to the door (step_of()),
## the boarding files' gap.
const GAP_MM := 700
## How far off a line a point may lie and still be on it, in metres.
const ON_LINE_M := 0.25
## The empty saved line.
const EMPTY := {
	"order": [], "claims": [], "stations": [], "marked": [], "held": [], "held_missed": {}
}

## The waiting passengers, head first; each stands at or walks to
## places[its index].
var order: Array[int] = []
## Admitted passengers still outside, in admission order.
var claims: Array[int] = []
## Admitted passenger id -> the desk its claim holds a place on; 0 for none
## (an empty claim, or a terminal with no check-in desk).
var stations := {}
## Waiting passenger id -> true: the NO_ROUTE marks this line set
## (_mark_unreachable()), taken off again at the start of every step() and by
## an edit (unmark()), so a mark another part set is never taken for one.
var marked := {}
## Booking id -> true: bookings LandsideSim kept aboard because the line was
## full (released, settled or missed, they are dropped).
var held := {}
## Flight id -> bookings that missed it while held aboard for a full line
## (FlightResult reports them as check-in congestion).
var held_missed := {}
## Derived on every step(): the place points and the points beside them on
## the walk in.
var places: Array[Vector3] = []
var beside: Array[Vector3] = []
## Admitted walker id -> its walk left to the door as the tick began
## (step_of()); rebuilt every step().
var _left := {}

var _door := Vector3.ZERO
var _edge := Vector3.ZERO
var _door_cell := Vector2i.ZERO
var _out := Vector2.ZERO
var _side := Vector2.ZERO
## How far out along the way out the straight walk in runs, in metres.
var _run_far := 0.0


## The places from the layout as it stands now.
func derive(sim: PassengerSim) -> void:
	places.clear()
	beside.clear()
	if sim.grid == null or sim.layout.passenger_entrances.is_empty():
		return
	var grid := sim.grid
	var door_id := sim.layout.passenger_entrances[0]
	var door := sim.layout.door_cell(grid, door_id)
	var out := sim.layout.door_outward(grid, door_id)
	_door_cell = door
	_door = grid.cell_to_world(door)
	_edge = _door + Vector3(out.x, 0.0, out.y) * 0.5
	_out = Vector2(out)
	var route: Array = sim.layout.outside_routes.get(door_id, [])
	var straight := 0
	while straight + 1 < route.size() and route[straight + 1] == door + out * (straight + 1):
		straight += 1
	_run_far = INF if sim.site == null or straight + 1 == route.size() else straight + 0.5
	var taken := {}
	for cells: Array in sim.layout.outside_routes.values():
		for cell: Vector2i in cells:
			taken[cell] = true
	var best: Array[Vector2i] = []
	var best_side := Vector2i(-out.y, out.x)
	for side in [Vector2i(-out.y, out.x), Vector2i(out.y, -out.x)]:
		var cells: Array[Vector2i] = []
		for k in MAX_PLACES:
			var step := START_STEPS + k
			var cell: Vector2i = door + out * step + side
			if sim.site != null:
				if step > straight or taken.has(cell):
					break
				if not SiteRoutes.is_open_ground(grid, sim.site, cell):
					break
			cells.append(cell)
		if cells.size() > best.size():
			best = cells
			best_side = side
	_side = Vector2(best_side)
	for cell in best:
		places.append(_point(sim, cell))
		beside.append(_point(sim, cell - best_side))


func capacity() -> int:
	return places.size()


## Whether passenger `id` waits in the line (or walks to its place).
func waiting(id: int) -> bool:
	return order.has(id)


## Whether passenger `id` is admitted and still outside.
func has_claim(id: int) -> bool:
	return claims.has(id)


## The check-in places free for a passenger walking in now: free places on
## the lines of the open desks that a walk from the door cell reaches
## (_reachable_free()), less the passengers inside looking for one and the
## claims of those admitted and still outside. Desks that are all closed,
## unusable or out of reach have no free place (0 or less, so arrivals wait
## outside); only a terminal with no check-in desk at all lets everyone in
## (UNLIMITED), and they wait inside with NO_CHECKIN as before.
func admit_room(sim: PassengerSim) -> int:
	if sim.layout.desks.is_empty():
		return UNLIMITED
	var free := _reachable_free(sim)
	var room := 0
	for desk: int in free:
		room += free[desk]
	return room - _seekers(sim) - claim_count(sim)


## The claims of admitted passengers still outside that hold a place on desk
## `station`.
func claims_on(sim: PassengerSim, station: int) -> int:
	var count := 0
	for id in claims:
		if int(stations.get(id, 0)) == station and _outside(sim, id):
			count += 1
	return count


## Takes the line's NO_ROUTE marks off its passengers (marked). PassengerEdits
## calls it before OutsideWalks checks the walks after an edit, so a NO_ROUTE
## set there is that check's own; the next step() marks again where it holds.
func unmark(sim: PassengerSim) -> void:
	for id: int in marked:
		var p: Passenger = sim.get_passenger(id)
		if p != null and p.stuck == Passenger.Stuck.NO_ROUTE:
			p.stuck = Passenger.Stuck.NONE
	marked.clear()


## The claims of admitted passengers still outside on the road in.
func claim_count(sim: PassengerSim) -> int:
	var count := 0
	for id in claims:
		count += int(_outside(sim, id))
	return count


## How many new arrivals may come in now: a free line place each, and while
## nobody waits, the check-in places free as well. 0 with no entrance.
func room_for_arrivals(sim: PassengerSim) -> int:
	if sim.layout.passenger_entrances.is_empty():
		return 0
	derive(sim)
	_prune(sim)
	var free := maxi(capacity() - order.size(), 0)
	if not order.is_empty():
		return free
	var room := admit_room(sim)
	if room >= UNLIMITED:
		return UNLIMITED
	return free + maxi(room, 0)


## A new passenger `p`, its walk in set: admitted when nobody waits and a
## check-in place is free, otherwise the next place in the line.
func take(sim: PassengerSim, p: Passenger) -> void:
	derive(sim)
	_prune(sim)
	var station := _next_station(sim) if order.is_empty() else -1
	if station >= 0:
		claims.append(p.id)
		stations[p.id] = station
		_left[p.id] = p.apron_total_mm() - p.apron_mm
		return
	order.append(p.id)
	if order.size() <= capacity():
		_walk_to_place(sim, p, order.size() - 1)


## `p` reached the door and walks in: true when it held a claim.
func entered(p: Passenger) -> bool:
	var had := claims.has(p.id)
	claims.erase(p.id)
	stations.erase(p.id)
	return had


## `p` is made, missed or gone: it holds nothing here any more.
func forget(id: int) -> void:
	order.erase(id)
	claims.erase(id)
	stations.erase(id)
	marked.erase(id)


## One tick, before arrivals: the places from the layout, the line's marks
## taken off, the claims checked again (_revalidate()), the heads admitted
## while reachable places free, every waiting passenger sent to its place, and
## those standing on theirs marked while the free places are out of reach.
func step(sim: PassengerSim) -> void:
	derive(sim)
	_prune(sim)
	unmark(sim)
	_revalidate(sim)
	var unreachable := not order.is_empty() and _open_room(sim) > 0
	unreachable = unreachable and _reachable_free(sim).is_empty()
	while not order.is_empty():
		var station := _next_station(sim)
		if station < 0:
			break
		var head: Passenger = sim.get_passenger(order.pop_front())
		claims.append(head.id)
		stations[head.id] = station
		_walk_to_door(sim, head)
	_send_to_places(sim)
	_mark_unreachable(sim, unreachable)
	_left.clear()
	for id in claims:
		var p: Passenger = sim.get_passenger(id)
		_left[id] = p.apron_total_mm() - p.apron_mm


## How far admitted walker `p` may walk this tick at `speed`: no closer to
## the door, along its walk, than GAP_MM behind the admitted walker ahead of
## it as the tick began (the nearest with less walk left, ties to the lower
## id). Their walks all end on the door cell, so two never reach it together.
func step_of(p: Passenger, speed: int) -> int:
	var mine := p.apron_total_mm() - p.apron_mm
	var start: int = _left.get(p.id, mine)
	var ahead := -1
	for id: int in _left:
		var left: int = _left[id]
		if id != p.id and (left < start or (left == start and id < p.id)):
			ahead = maxi(ahead, left)
	if ahead < 0:
		return speed
	return clampi(mine - ahead - GAP_MM, 0, speed)


## Ticks the line adds to `p`'s forecast: the walk from its place to the door
## and the wait for a check-in place, the passengers on the desks' lines, the
## claims and the ones ahead of it in the line shared over the open desks,
## CHECKIN_TICKS each. 0 for a passenger not waiting.
func forecast_ticks(sim: PassengerSim, p: Passenger) -> int:
	var index := order.find(p.id)
	if index < 0:
		return 0
	var open := 0
	var ahead := claim_count(sim) + index
	for desk in sim.layout.desks:
		if sim._is_open(desk) and sim.layout.is_usable(desk):
			open += 1
			ahead += PassengerStations.slot(sim, desk)
	if open == 0:
		return JourneyForecast.NEVER
	var walk_mm := 0
	if index < capacity():
		var at := places[index]
		walk_mm = roundi(
			(at.distance_to(beside[index]) + beside[index].distance_to(_edge) + 0.5) * 1000.0
		)
	@warning_ignore("integer_division")
	var turns := (ahead + open - 1) / open
	return JourneyForecast.walk_ticks(walk_mm) + turns * PassengerSim.CHECKIN_TICKS


## JSON-safe state for a save, with only the passengers still outside (one
## moved on since the last tick is dropped, as the next step() would). Reads only.
func to_dict(sim: PassengerSim) -> Dictionary:
	var missed := {}
	for flight_id: String in held_missed:
		missed[flight_id] = held_missed[flight_id]
	var held_ids := held.keys()
	held_ids.sort()
	var kept := order.filter(func(id: int) -> bool: return _outside(sim, id))
	var claimed := claims.filter(func(id: int) -> bool: return _outside(sim, id))
	var marks := marked.keys().filter(func(id: int) -> bool: return kept.has(id))
	marks.sort()
	return {
		"order": kept,
		"claims": claimed,
		"stations": claimed.map(func(id: int) -> int: return int(stations.get(id, 0))),
		"marked": marks,
		"held": held_ids,
		"held_missed": missed,
	}


## A line restored from to_dict() `data`, checked against `by_id` (the loaded
## passengers by id): {"line": EntranceLine} or {"error": why}.
static func checked(data: Variant, by_id: Dictionary) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "entrance line must be a dictionary"}
	for key in EMPTY:
		if not (data as Dictionary).has(key):
			return {"error": "entrance line has no %s" % key}
	var line := EntranceLine.new()
	var seen := {}
	for key in ["order", "claims"]:
		if typeof(data[key]) != TYPE_ARRAY:
			return {"error": "entrance line %s must be a list" % key}
		for id: Variant in data[key]:
			if not WholeNumber.is_whole(id) or not by_id.has(int(id)) or seen.has(int(id)):
				return {"error": "entrance line %s holds %s, not one saved passenger" % [key, id]}
			if (by_id[int(id)] as Passenger).stage != Passenger.Stage.SPAWNED:
				return {"error": "entrance line passenger %d is not outside" % int(id)}
			seen[int(id)] = true
			(line.order if key == "order" else line.claims).append(int(id))
	var problem := _checked_marks(line, data, by_id)
	if problem != "":
		return {"error": problem}
	if typeof(data["held"]) != TYPE_ARRAY or typeof(data["held_missed"]) != TYPE_DICTIONARY:
		return {"error": "entrance line held bookings are malformed"}
	for id: Variant in data["held"]:
		if not WholeNumber.is_whole(id):
			return {"error": "entrance line held booking %s is not an id" % [id]}
		line.held[int(id)] = true
	for flight_id: Variant in data["held_missed"]:
		var count: Variant = data["held_missed"][flight_id]
		if not WholeNumber.is_whole(count) or int(count) < 0:
			return {"error": "entrance line held misses of %s are malformed" % [flight_id]}
		line.held_missed[str(flight_id)] = int(count)
	return {"line": line}


## The saved claims' desks ("stations", one per claim) and the line's marks
## ("marked", waiting passengers standing NO_ROUTE) into `line`: "" or why not.
static func _checked_marks(line: EntranceLine, data: Dictionary, by_id: Dictionary) -> String:
	if typeof(data["stations"]) != TYPE_ARRAY or typeof(data["marked"]) != TYPE_ARRAY:
		return "entrance line stations and marks must be lists"
	if (data["stations"] as Array).size() != line.claims.size():
		return (
			"entrance line has %d claims but %d stations"
			% [line.claims.size(), (data["stations"] as Array).size()]
		)
	for i in line.claims.size():
		var station: Variant = data["stations"][i]
		if not WholeNumber.is_whole(station) or int(station) < 0:
			return "entrance line claim station %s is not a station id" % [station]
		line.stations[line.claims[i]] = int(station)
	for id: Variant in data["marked"]:
		if not WholeNumber.is_whole(id) or not line.order.has(int(id)):
			return "entrance line mark %s is not a waiting passenger" % [id]
		if (by_id[int(id)] as Passenger).stuck != Passenger.Stuck.NO_ROUTE:
			return "entrance line marked passenger %d is not NO_ROUTE" % int(id)
		line.marked[int(id)] = true
	return ""


## Desk -> its free places that a passenger walking in now could reach: for
## every open, usable desk, the places left on its line when one setting off
## from the door cell finds a way to the place it would join
## (StationQueue.set_off(), as PassengerStations.choose() does), so the one
## admitted does not stand on the door cell for want of a way to its place.
## Empty with no entrance.
func _reachable_free(sim: PassengerSim) -> Dictionary:
	var free := {}
	if sim.grid == null or sim.layout.passenger_entrances.is_empty():
		return free
	for desk in sim.layout.desks:
		if not sim._is_open(desk) or not sim.layout.is_usable(desk):
			continue
		var line := sim.layout.line_of(desk)
		var at := PassengerStations.slot(sim, desk)
		if at >= line.size():
			continue
		var queue := sim._queue(desk)
		if not StationQueue.set_off(sim.grid, queue, line, sim._by_id, _door_cell, at).is_empty():
			free[desk] = line.size() - at
	return free


## The check-in places free on every open desk's line, reached or not, less
## the seekers inside and the claims outside (the room before the fix round's
## reach rule): above 0 with free places only out of reach, the line's marks
## say so (step()).
func _open_room(sim: PassengerSim) -> int:
	var room := maxi(PassengerStations._room(sim, sim.layout.desks), 0)
	return room - _seekers(sim) - claim_count(sim)


## The passengers inside looking for a desk (PassengerStations.is_seeking()).
func _seekers(sim: PassengerSim) -> int:
	var count := 0
	for p in sim._passengers:
		if not p.is_done() and PassengerStations.is_seeking(sim, p, true):
			count += 1
	return count


## The desk the next passenger admitted claims a place on: the reachable desk
## with the most places left after its claims (ties to the lower id), while
## admit_room() is above 0; 0 with no check-in desk at all; -1 for none.
func _next_station(sim: PassengerSim) -> int:
	if sim.layout.desks.is_empty():
		return 0
	if admit_room(sim) <= 0:
		return -1
	return _best_desk(_reachable_free(sim), _claims_by_desk(sim))


## The desk in `free` with the most places left over `used` (desk -> places
## taken), ties to the lower id; -1 when none has one left.
static func _best_desk(free: Dictionary, used: Dictionary) -> int:
	var best := -1
	var best_left := 0
	var desks := free.keys()
	desks.sort()
	for desk: int in desks:
		var left: int = free[desk] - int(used.get(desk, 0))
		if left > best_left:
			best = desk
			best_left = left
	return best


## Desk -> the claims outside holding a place on it.
func _claims_by_desk(sim: PassengerSim) -> Dictionary:
	var used := {}
	for id in claims:
		var station: int = stations.get(id, 0)
		if station != 0 and _outside(sim, id):
			used[station] = int(used.get(station, 0)) + 1
	return used


## Drops the ids of passengers no longer outside on the road in: gone, settled
## or moved on by something other than walking in (a test placing one).
func _prune(sim: PassengerSim) -> void:
	for list: Array[int] in [order, claims]:
		for i in range(list.size() - 1, -1, -1):
			if not _outside(sim, list[i]):
				list.remove_at(i)
	for table: Dictionary in [stations, marked]:
		for id: int in table.keys():
			if not _outside(sim, id):
				table.erase(id)


func _outside(sim: PassengerSim, id: int) -> bool:
	var p: Passenger = sim.get_passenger(id)
	return p != null and not p.is_done() and p.stage == Passenger.Stage.SPAWNED


## Each claim, in admission order, keeps its desk while that desk has a
## reachable place left for it (and the reachable room, less the seekers
## inside, is not spent), or moves to the reachable desk with the most places
## left; failing both it is empty (0). Then, last admitted first while the line
## has a place each, a walker with an empty claim, or one bound for a door
## that is no longer the entrance's, goes back to the front of the line; one
## bound for an old door that cannot goes on to the new door.
func _revalidate(sim: PassengerSim) -> void:
	var desks := not sim.layout.desks.is_empty()
	if desks:
		var free := _reachable_free(sim)
		var budget := -_seekers(sim)
		for desk: int in free:
			budget += free[desk]
		var used := {}
		for id in claims:
			var station: int = stations.get(id, 0)
			var left := int(free.get(station, 0)) - int(used.get(station, 0))
			if budget <= 0:
				station = 0
			elif left <= 0:
				station = maxi(_best_desk(free, used), 0)
			stations[id] = station
			if station != 0:
				used[station] = int(used.get(station, 0)) + 1
				budget -= 1
	var entrance := not sim.layout.passenger_entrances.is_empty()
	for i in range(claims.size() - 1, -1, -1):
		var id := claims[i]
		var p: Passenger = sim.get_passenger(id)
		var moved := entrance and p.at != _door_cell
		var empty := desks and int(stations.get(id, 0)) == 0
		# Off the grid's walks (no site) a walker stopped at a door that went is
		# NO_ROUTE for want of that door (PassengerSim._advance()); sent on from
		# here, it has a walk again. On the site OutsideWalks owns that mark.
		if moved and sim.site == null and p.stuck == Passenger.Stuck.NO_ROUTE:
			p.stuck = Passenger.Stuck.NONE
		if (moved or empty) and order.size() < capacity():
			claims.remove_at(i)
			stations.erase(id)
			order.push_front(id)
		elif moved:
			_walk_to_door(sim, p)


## Free check-in places that no walk from the entrance reaches are a build
## problem, not congestion: each waiting passenger standing on its place is
## marked NO_ROUTE ("I can't get there") while `unreachable` (decision
## arrivals-wait-in-a-tidy-line-outside-the-entrance-when-check, conductor
## ruling of the fix round). The marks are the line's own (marked), taken off
## at the start of the next step(). A walker still on its way is never marked,
## so nobody stops short of its place.
func _mark_unreachable(sim: PassengerSim, unreachable: bool) -> void:
	if not unreachable:
		return
	for index in mini(order.size(), capacity()):
		var p: Passenger = sim.get_passenger(order[index])
		if _standing_on(p, index) and p.stuck == Passenger.Stuck.NONE:
			p.stuck = Passenger.Stuck.NO_ROUTE
			marked[p.id] = true


## Whether `p` stands at the end of its walk on place `index`.
func _standing_on(p: Passenger, index: int) -> bool:
	if index < 0 or index >= capacity() or p.apron.is_empty():
		return false
	return p.apron_mm >= p.apron_total_mm() and p.apron.back().is_equal_approx(places[index])


## Each waiting passenger walks to its place when its walk does not end there
## already; past the last place it stands where it is.
func _send_to_places(sim: PassengerSim) -> void:
	for index in order.size():
		var p: Passenger = sim.get_passenger(order[index])
		# The line's own marks are off by now (step()); a NO_ROUTE left is
		# OutsideWalks' (no walk to any entrance), and it stays where it is.
		if p.stuck == Passenger.Stuck.NO_ROUTE:
			continue
		if index >= capacity():
			if p.apron.size() > 1 and p.apron_mm < p.apron_total_mm():
				_take(p, [p.apron_position()])
				p.apron_mm = 0
			continue
		if p.apron.is_empty() or not p.apron.back().is_equal_approx(places[index]):
			_walk_to_place(sim, p, index)


## `p` walks to place `index`: from the line's column straight along it, from
## the walk in along it to the cell beside the place and then aside, and from
## further out by its own walk to where that meets the walk in. With no walk
## (a test grid) it stands on its place at once.
func _walk_to_place(_sim: PassengerSim, p: Passenger, index: int) -> void:
	p.at = _door_cell
	var target := places[index]
	if p.apron.is_empty():
		_take(p, [target])
		p.apron_mm = 0
		return
	var pos := p.apron_position()
	if _in_column(pos):
		_take(p, [pos, target])
	elif _on_axis(pos):
		_take(p, [pos, beside[index], target])
	else:
		_join_axis(p, [beside[index], target])


## The head walks in: back onto the walk in level with where it stands, then
## through the doorway to the door cell.
func _walk_to_door(_sim: PassengerSim, p: Passenger) -> void:
	p.at = _door_cell
	if p.apron.is_empty():
		return
	var pos := p.apron_position()
	var flat := Vector2(pos.x - _door.x, pos.z - _door.z)
	var out := _out.dot(flat)
	if _in_column(pos):
		var level := _door + Vector3(_out.x, 0.0, _out.y) * out
		level.y = pos.y
		_take(p, [pos, level, _edge, _door])
	elif _on_axis(pos):
		_take(p, [pos, _edge, _door] if out > 0.5 else [pos, _door])
	else:
		_join_axis(p, [_edge, _door])


## Keeps `p`'s walk up to its first point ahead on the walk in, then `tail`;
## with no such point, straight from where it is.
func _join_axis(p: Passenger, tail: Array) -> void:
	var left := p.apron_mm
	var first := p.apron.size()
	for i in range(1, p.apron.size()):
		var length := p.apron_segment_mm(i)
		if left <= length:
			first = i
			break
		left -= length
	for i in range(first, p.apron.size()):
		if _on_axis(p.apron[i]):
			var kept: Array[Vector3] = []
			kept.assign(p.apron.slice(0, i + 1))
			kept.append_array(tail)
			p.apron = kept
			return
	var walk: Array[Vector3] = [p.apron_position()]
	walk.append_array(tail)
	_take(p, walk)


func _take(p: Passenger, walk: Array) -> void:
	var typed: Array[Vector3] = []
	typed.assign(walk)
	p.apron = typed
	p.apron_mm = 0


func _on_axis(at: Vector3) -> bool:
	var flat := Vector2(at.x - _door.x, at.z - _door.z)
	var out := _out.dot(flat)
	return absf(_side.dot(flat)) < ON_LINE_M and out > -0.5 and out <= _run_far


func _in_column(at: Vector3) -> bool:
	var flat := Vector2(at.x - _door.x, at.z - _door.z)
	var out := _out.dot(flat)
	var last := START_STEPS + capacity() - 1
	return absf(_side.dot(flat) - 1.0) < ON_LINE_M and out > START_STEPS - 0.5 and out < last + 0.5


func _point(sim: PassengerSim, cell: Vector2i) -> Vector3:
	if sim.site != null:
		return SiteRoutes.ground(sim.grid, sim.site, cell)
	return sim.grid.cell_to_world(cell)
