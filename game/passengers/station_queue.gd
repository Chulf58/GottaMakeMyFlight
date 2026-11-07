class_name StationQueue
extends RefCounted
## The external queue rules of a desk or security station, on PassengerSim's
## {"lane", "holding"} record: shared with SecurityForecast's replay, so the
## forecast moves a queue as the sim does.
##
## A station's line is its lane cells then its hold cells
## (TerminalLayout.line_of()); member i of its queue (the lane, then the
## holding list) has line[i] as its place (decision full-queue-design-a-derived-
## hold-line-behind-each-lane-gives). The line's order is the order people
## stand in (decision hold-line-rebuild-the-security-line-follows-where-people-
## sta): one walker at a time holds the claim on the tail, the one that would
## reach it soonest when the claim is free, latched until it enters there as
## the queue's last member; every other walker keeps its reservation and waits
## short of the line. All of it is settled once a tick, before anyone steps
## (arrive()), by PassengerSim and SecurityForecast alike.

## Moves passengers from the holding list into free places at the back of
## the lane, first come first; returns them. Each keeps its index in the
## queue, so its place on the line.
## How much sooner another walker must be able to reach the tail than the one
## holding the claim for the claim to pass to it (_pass_claim()): two cells at
## a walk. Once passed, the new claimant heads straight for the tail and the
## old one stops at least a step short of it, so the old one can never come
## back that far ahead and the claim does not flip back.
const PASS_TICKS := 20


static func promote(queue: Dictionary, cells: Array) -> Array[int]:
	var moved: Array[int] = []
	var lane: Array = queue["lane"]
	var holding: Array = queue["holding"]
	while not holding.is_empty() and lane.size() < cells.size():
		var id: int = holding.pop_front()
		lane.append(id)
		moved.append(id)
	return moved


## Puts passenger `id` at the back of the lane, or in the holding list when
## the lane is full; returns whether it got a lane place.
static func join(queue: Dictionary, cells: Array, id: int) -> bool:
	if (queue["lane"] as Array).size() < cells.size():
		(queue["lane"] as Array).append(id)
		return true
	(queue["holding"] as Array).append(id)
	return false


## The passengers in `queue`: its lane, then its holding list.
static func members(queue: Dictionary) -> Array:
	return (queue["lane"] as Array) + (queue["holding"] as Array)


static func size_of(queue: Dictionary) -> int:
	return (queue["lane"] as Array).size() + (queue["holding"] as Array).size()


## The path from `from` to `line[index]`: along the line when `from` is on it
## (the line's steps are routable, and a turn is walked as the line turns),
## otherwise the grid's path.
static func path_to(grid: BuildGrid, line: Array, from: Vector2i, index: int) -> Array[Vector2i]:
	var at := line.find(from)
	if at < 0:
		return grid.find_path(from, line[index])
	var path: Array[Vector2i] = []
	var step := -1 if index < at else 1
	for i in range(at, index + step, step):
		path.append(line[i])
	return path


## The index of the next free cell of `line` for a walker to join on: past
## the queue's size and past every line cell a member stands on or is
## stepping onto, so a newcomer never joins on a cell a member has not left
## yet. It then joins as the queue's last member behind its place and moves
## up with the ripple (QueueRipple). `by_id` maps ids to passengers; `index`,
## when given, maps each cell of `line` to its index (line_index()).
static func free_index(queue: Dictionary, line: Array, by_id: Dictionary, index := {}) -> int:
	if index.is_empty():
		index = line_index(line)
	var free := size_of(queue)
	for at: int in 2:
		for id: int in queue["holding" if at == 1 else "lane"]:
			var p: Passenger = by_id[id]
			free = maxi(free, int(index.get(p.at, -1)) + 1)
			if p.is_moving():
				free = maxi(free, int(index.get(p.path[p.path_index + 1], -1)) + 1)
	return free


## Cell -> its index on `line`, the first when a cell repeats.
static func line_index(line: Array) -> Dictionary:
	var index := {}
	for i in line.size():
		if not index.has(line[i]):
			index[line[i]] = i
	return index


## The path from `from` to `line[index]` for a walker joining there: one that
## steps onto it facing the front of the line or across it (_faces_front()).
## When the plain way would come at it from the front side it comes round by
## line[index + 1], or, for the line's last cell, by a neighbour beside or
## behind it off the line. A walker stopping with its back to the front would
## leave its pulled roller trailing into the passenger ahead.
static func approach(grid: BuildGrid, line: Array, from: Vector2i, index: int) -> Array[Vector2i]:
	var path := path_to(grid, line, from, index)
	if path.size() < 2 or _faces_front(line, index, path[path.size() - 2]):
		return path
	var cell: Vector2i = line[index]
	var rounds: Array[Vector2i] = []
	if index + 1 < line.size():
		rounds.append(line[index + 1])
	else:
		for step: Vector2i in BuildGrid.SIDE_STEP:
			var near := cell + step
			if not line.has(near) and _faces_front(line, index, near):
				rounds.append(near)
	for near in rounds:
		if near != from and not grid.can_passenger_route(near, cell):
			continue
		var round := (
			path_to(grid, line, from, index + 1)
			if line.find(near) == index + 1
			else grid.find_path(from, near)
		)
		if not round.is_empty():
			round.append(cell)
			return round
	return path


## Whether a step from `from` onto line[index] faces the front of the line, or
## across it: never away from line[index - 1].
static func _faces_front(line: Array, index: int, from: Vector2i) -> bool:
	if index == 0:
		return true
	var step: Vector2i = line[index] - from
	var front: Vector2i = line[index - 1] - line[index]
	return step.x * front.x + step.y * front.y >= 0


## The cell index a walker to `station` waits behind: past every cell of
## `line` a passenger admitted there (Stage.SECURITY) still stands on, such as
## a security lane's first cell, where the admitted passenger unpacks; -1 when
## none does. A walker enters only behind that cell (tail()).
static func admitted_at(by_id: Dictionary, station: int, line: Array) -> int:
	var at := -1
	for p: Passenger in by_id.values():
		if p.stage == Passenger.Stage.SECURITY and p.station == station:
			at = maxi(at, line.find(p.at))
	return at


## The tail cell's index, where the claimant enters the queue: past the
## queue's members (free_index()) and past an admitted passenger still on the
## line (admitted_at()).
static func tail(free: int, admitted: int) -> int:
	return maxi(free, admitted + 1)


## One tick's line rules, before anyone steps, with one entrant at a time
## (decision hold-line-rebuild-the-security-line-follows-where-people-sta,
## the latched claim). `walkers` (in id order) are committed to a station of
## `queues`, whose lane cells are `lanes` and whose line is `lines`, by
## station; `by_id` maps ids to passengers; `claims` maps a station to the
## walker that holds its claim on the tail (it is changed here).
## - The claimant enters the queue, as its last member, when it stands on the
##   tail cell (tail()) or reaches it at its pace on this tick, and stops
##   there; behind an admitted passenger still unpacking on the lane's first
##   cell it enters one cell back and moves up while that one unpacks
##   (decision hold-line-rebuild-the-security-line-follows-where-people-sta:
##   the line, not the lane, gives back the time the hold line costs). Then
##   the next claimant is chosen, and it too enters on this tick when it can.
## - With no claimant, the walker that would reach the tail soonest (the walk
##   still to go, then id) is latched as it: it heads for the tail and keeps
##   heading for it as the tail moves up, on from the cell it steps to, never
##   back, until it enters, leaves the station, or has no way there
##   (`stranded`).
## - Every other walker keeps its reservation (PassengerStations.slot()) but
##   no cell: it follows on toward the tail and stops a step short of it
##   (_stop_short()). No one enters by passing over a line cell.
## Returns the walkers that entered, a moving one with halt_tick `now`.
static func arrive(
	grid: BuildGrid,
	queues: Dictionary,
	lanes: Dictionary,
	lines: Dictionary,
	walkers: Array,
	by_id: Dictionary,
	now: int,
	stranded: Array = [],
	claims: Dictionary = {}
) -> Array[Passenger]:
	var by_station := {}
	for w: Passenger in walkers:
		if lines.has(w.station) and queues.has(w.station):
			if not by_station.has(w.station):
				by_station[w.station] = []
			(by_station[w.station] as Array).append(w)
	for station: int in claims.keys():
		var held_by: int = claims[station]
		var still := (
			by_station.has(station)
			and (by_station[station] as Array).any(
				func(w: Passenger) -> bool: return w.id == held_by
			)
		)
		if not still:
			claims.erase(station)
	var joined: Array[Passenger] = []
	for station: int in by_station:
		var line: Array = lines[station]
		var queue: Dictionary = queues[station]
		var index := line_index(line)
		var admitted := admitted_at(by_id, station, line)
		var mine: Array = by_station[station]
		var free := free_index(queue, line, by_id, index)
		var to := tail(free, admitted)
		while true:
			if not claims.has(station):
				var best := _soonest(grid, mine, line, to)
				if best == null:
					break
				claims[station] = best.id
			var claimant: Passenger = by_id[claims[station]]
			if not _enter(queue, lanes[station], line, index, admitted, claimant, by_id, now):
				break
			joined.append(claimant)
			mine.erase(claimant)
			claims.erase(station)
			free = free_index(queue, line, by_id, index)
			to = tail(free, admitted)
		if claims.has(station):
			_pass_claim(grid, claims, station, by_id, mine, line, to)
		for w: Passenger in mine:
			if claims.get(station, 0) == w.id:
				var onto: int = index.get(w.path[w.path_index + 1], -1) if w.is_moving() else -1
				if onto >= 0 and onto < free and w.path_index + 2 == w.path.size():
					# Stepping onto the cell it headed for, now a member's: back
					# first. One passing over a member's cell walks on.
					turn_back(w)
				_head_for_tail(grid, w, line, to, stranded)
			else:
				_stop_short(grid, w, line, index, to, free)
	_pass_centres(queues, walkers, {}, by_id)
	return joined


## Claimant `w` enters `queue` when it stands on the tail cell or reaches it on
## this tick: true when it joined.
static func _enter(
	queue: Dictionary,
	cells: Array,
	line: Array,
	index: Dictionary,
	admitted: int,
	w: Passenger,
	by_id: Dictionary,
	now: int
) -> bool:
	var to := tail(free_index(queue, line, by_id, index), admitted)
	if to >= line.size():
		return false
	var cell: Vector2i = line[to]
	var need := 0
	if w.is_moving():
		if w.path[w.path_index + 1] != cell:
			return false
		need = Passenger.segment_mm(w.at, cell) - w.seg_mm
		if need > w.pace_mm():
			return false
	elif w.at != cell:
		return false
	if w.is_moving():
		w.walk(need)
		_stop_here(w)
		w.halt_tick = now
	join(queue, cells, w.id)
	return true


## The claim on `station`'s tail passes to another walker of `walkers` that
## would reach line[`to`] at least PASS_TICKS sooner than its claimant, by the
## routed walk _soonest() uses (_ticks_to()), the soonest such one (ties to
## the lower id), and stays latched on it; one with no way there never takes
## it, and the old claimant waits on as the others do. A straight-line bound
## (_ticks_at_least()) skips the walkers that cannot be that much sooner
## without finding their route.
static func _pass_claim(
	grid: BuildGrid,
	claims: Dictionary,
	station: int,
	by_id: Dictionary,
	walkers: Array,
	line: Array,
	to: int
) -> void:
	if to >= line.size():
		return
	var holder: Passenger = by_id[claims[station]]
	# The claimant heading for the tail walks its route there already.
	var mine := (
		holder.pace_ticks(_rest_mm(holder))
		if holder.is_moving() and holder.path_end() == line[to]
		else _ticks_to(grid, holder, line, to)
	)
	if mine < 0:
		return
	var beat := mine - PASS_TICKS
	var best: Passenger = null
	var best_ticks := 0
	for w: Passenger in walkers:
		if w == holder or _ticks_at_least(w, line[to]) > beat:
			continue
		var ticks := _ticks_to(grid, w, line, to)
		if ticks >= 0 and ticks <= beat and (best == null or ticks < best_ticks):
			best = w
			best_ticks = ticks
	if best != null:
		claims[station] = best.id


## The walk left on moving walker `w`'s path, in mm.
static func _rest_mm(w: Passenger) -> int:
	var mm := Passenger.segment_mm(w.at, w.path[w.path_index + 1]) - w.seg_mm
	for i in range(w.path_index + 1, w.path.size() - 1):
		mm += Passenger.segment_mm(w.path[i], w.path[i + 1])
	return mm


## A bound below the ticks walker `w` takes to reach `cell` by any route
## (_ticks_to()): the rest of its step, then a straight walk (octile) from the
## cell it steps to, at its pace.
static func _ticks_at_least(w: Passenger, cell: Vector2i) -> int:
	var mm := 0
	var from := w.at
	if w.is_moving():
		from = w.path[w.path_index + 1]
		mm = Passenger.segment_mm(w.at, from) - w.seg_mm
	var dx := absi(from.x - cell.x)
	var dy := absi(from.y - cell.y)
	mm += mini(dx, dy) * Passenger.DIAGONAL_MM + absi(dx - dy) * Passenger.STRAIGHT_MM
	return w.pace_ticks(mm)


## Of `walkers`, the one that would reach line[`to`] soonest (ties to the
## lower id, as they come in id order), or null when none can.
static func _soonest(grid: BuildGrid, walkers: Array, line: Array, to: int) -> Passenger:
	if to >= line.size():
		return null
	var best: Passenger = null
	var best_ticks := 0
	for w: Passenger in walkers:
		var ticks := _ticks_to(grid, w, line, to)
		if ticks >= 0 and (best == null or ticks < best_ticks):
			best = w
			best_ticks = ticks
	return best


## The ticks walker `w` would take to reach line[`to`] from where it is, or -1
## with no way there.
static func _ticks_to(grid: BuildGrid, w: Passenger, line: Array, to: int) -> int:
	if not w.is_moving():
		if w.at == line[to]:
			return 0
		var path := approach(grid, line, w.at, to)
		return -1 if path.is_empty() else w.pace_ticks(Passenger.path_mm(path))
	var next := w.path[w.path_index + 1]
	var step := Passenger.segment_mm(w.at, next) - w.seg_mm
	var on := _approach_or_here(grid, line, next, to)
	return -1 if on.is_empty() else w.pace_ticks(step + Passenger.path_mm(on))


## The claimant heads for line[`to`]: on from the cell it steps to when it is
## moving, never back; one with no way there is put in `stranded`.
static func _head_for_tail(
	grid: BuildGrid, w: Passenger, line: Array, to: int, stranded: Array
) -> void:
	if to >= line.size() or w.path_end() == line[to]:
		return
	if not w.is_moving():
		var path := approach(grid, line, w.at, to)
		if path.is_empty():
			stranded.append(w)
		elif path.size() >= 2:
			w.set_path(path)
		return
	var on := _approach_or_here(grid, line, w.path[w.path_index + 1], to)
	if on.is_empty():
		stranded.append(w)
		return
	var path: Array[Vector2i] = []
	path.assign(w.path.slice(0, w.path_index + 1))
	path.append_array(on)
	_keep_step(w, path)


## A walker with a reservation but no claim follows on toward the tail and
## stops a step short of it: of the tail cell and of every cell a member holds.
## One stepping onto such a cell turns back on its step (turn_back()); one
## whose next step would is cut where its step ends; one standing on one steps
## off it (step_off()); one standing elsewhere further off sets off toward the
## tail again.
static func _stop_short(
	grid: BuildGrid, w: Passenger, line: Array, index: Dictionary, to: int, free: int
) -> void:
	var limit := mini(to, line.size() - 1)
	if w.is_moving():
		var after := w.path_index + 2
		if int(index.get(w.path[w.path_index + 1], -1)) in range(0, free):
			# Stepping onto a cell a member holds: it turns back on its step.
			turn_back(w)
		elif after < w.path.size() and _short_of(index, w.path[after], to, free):
			_stop_after_step(w)
		return
	if _short_of(index, w.at, to, free):
		step_off(grid, w, line)
		return
	var cell: Vector2i = line[limit]
	if maxi(absi(w.at.x - cell.x), absi(w.at.y - cell.y)) <= 1:
		return
	# The whole way to the tail cell: the step before it is cut on the way
	# (above), so its path never ends off the line before that (fit_line()).
	var path := approach(grid, line, w.at, limit)
	if path.size() >= 3 and not _short_of(index, path[1], to, free):
		w.set_path(path)


## Whether `cell` is the tail cell or one a member holds (index below `free`).
static func _short_of(index: Dictionary, cell: Vector2i, to: int, free: int) -> bool:
	var at: int = index.get(cell, -1)
	return at >= 0 and (at < free or at == to)


## Turns walker `w` back on the step it is on, where it is: the same point,
## now walked from the cell ahead back to the one it came from, where it
## stops. A walker still on its cell just stays there.
static func turn_back(w: Passenger) -> void:
	if w.seg_mm == 0:
		w.clear_path()
		return
	var next := w.path[w.path_index + 1]
	var walked := Passenger.segment_mm(w.at, next) - w.seg_mm
	var turned: Array[Vector2i] = [next, w.at]
	w.at = next
	w.set_path(turned)
	w.seg_mm = walked


## Cuts walker `w`'s path at the end of the step it is on.
static func _stop_after_step(w: Passenger) -> void:
	var stop: Array[Vector2i] = []
	stop.assign(w.path.slice(0, w.path_index + 2))
	_keep_step(w, stop)


## Stops walker `w` on the cell it has just reached, keeping the cells it
## walked.
static func _stop_here(w: Passenger) -> void:
	var walked: Array[Vector2i] = []
	walked.assign(w.path.slice(0, w.path_index + 1))
	w.path = walked


## A walker that would end this tick exactly on the centre of a cell a queue
## member stands on, and walk on from it, is taken 1 mm further now, so it is
## never left standing on that centre between two ticks.
static func _pass_centres(
	queues: Dictionary, walkers: Array, lost: Dictionary, by_id: Dictionary
) -> void:
	var held := {}
	for queue: Dictionary in queues.values():
		for id: int in members(queue):
			if by_id.has(id):
				held[(by_id[id] as Passenger).at] = true
	for w: Passenger in walkers:
		if lost.has(w.id) or not w.is_moving() or w.path_index + 2 >= w.path.size():
			continue
		var next := w.path[w.path_index + 1]
		if held.has(next) and Passenger.segment_mm(w.at, next) - w.seg_mm == w.pace_mm():
			w.walk(1)


## Sends standing walker `w` off its cell of `line`: back to the cell it came
## from when that is off the line, else to the first neighbour off the line it
## may step to, straight ones first. It stays when there is none.
static func step_off(grid: BuildGrid, w: Passenger, line: Array) -> void:
	var cells: Array[Vector2i] = []
	if w.path_index >= 1:
		cells.append(w.path[w.path_index - 1])
	for step: Vector2i in BuildGrid.SIDE_STEP:
		cells.append(w.at + step)
	for step: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		cells.append(w.at + step)
	for cell in cells:
		if not line.has(cell) and grid.can_passenger_route(w.at, cell):
			var off: Array[Vector2i] = [w.at, cell]
			w.set_path(off)
			return


## Gives walker `w` the new `path`, which starts with the cells it walked, and
## keeps it where it is along its step.
static func _keep_step(w: Passenger, path: Array[Vector2i]) -> void:
	var index := w.path_index
	var walked := w.seg_mm
	w.path = path
	w.path_index = index
	w.seg_mm = walked


## approach(), or just [from] when it stands on line[index] already.
static func _approach_or_here(
	grid: BuildGrid, line: Array, from: Vector2i, index: int
) -> Array[Vector2i]:
	if from == line[index]:
		var here: Array[Vector2i] = [from]
		return here
	return approach(grid, line, from, index)
