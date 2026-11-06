class_name StationQueue
extends RefCounted
## The external queue rules of a desk or security station, on PassengerSim's
## {"lane", "holding"} record: shared with SecurityForecast's replay, so the
## forecast moves a queue as the sim does.
##
## A station's line is its lane cells then its hold cells
## (TerminalLayout.line_of()); member i of its queue (the lane, then the
## holding list) stands on line[i] (decision full-queue-design-a-derived-
## hold-line-behind-each-lane-gives). A walker committed to the station joins
## when it stands on, or reaches, line[n], n being the queue's size: the next
## free cell (arrive(), head_for()). A walker passing over line[n] on its way
## further back takes it only when no other walker is heading for it, and one
## standing further back waits while another is heading for a cell between,
## so walkers keep to the cells they chose unless one would stay empty: no
## one turns back for a cell another took.


## Moves passengers from the holding list into free places at the back of
## the lane, first come first; returns them. Each keeps its index in the
## queue, so its place on the line.
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


## Sends a standing walker `w` toward line[n], the next free cell of its
## station's `line`, unless it stands further back on the line and another
## walker is heading for a cell between (`ends`: the path ends of the other
## walkers to the station): it then waits where it is. True when it is on its
## way, waits, or stands on line[n]; false when the line has no free cell or
## no path leads to it.
static func head_for(grid: BuildGrid, w: Passenger, line: Array, n: int, ends: Array) -> bool:
	if n >= line.size():
		return false
	var here := line.find(w.at)
	if here == n:
		return true
	for end: Vector2i in ends:
		var there := line.find(end)
		if here > n and there >= n and there < here:
			return true
	var path := path_to(grid, line, w.at, n)
	if path.size() < 2:
		return false
	w.set_path(path)
	return true


## One tick's joins, before anyone steps. `walkers` (in id order) are
## committed to a station of `queues`, whose lane cells are `lanes` and whose
## line is `lines`, by station. A walker standing on a line cell, or reaching
## one at its pace on this tick (it never covers more than one cell a tick),
## joins when that cell is line[n], one reaching it on its way further back
## only when no other walker's path ends there. Those standing go first, then by line
## index, then id, so of two reaching the line on one tick the one nearer the
## front joins first and the next cell is then free for the other. A joiner
## that reaches its cell walks just onto it and stops there: the rest of its
## step is dropped, it is not drawn back. Then a walker whose path ends on a
## cell the queue now holds is sent on toward line[n] (send_on()), never to
## stop on that cell. Returns the joiners in join order, standing, a moving
## one with halt_tick `now`.
static func arrive(
	grid: BuildGrid,
	queues: Dictionary,
	lanes: Dictionary,
	lines: Dictionary,
	walkers: Array,
	now: int
) -> Array[Passenger]:
	var arrivals := []
	var ends := {}
	for w: Passenger in walkers:
		if w.is_moving():
			var key := [w.station, w.path_end()]
			ends[key] = ends.get(key, 0) + 1
	for w: Passenger in walkers:
		if not lines.has(w.station) or not queues.has(w.station):
			continue
		var line: Array = lines[w.station]
		if not w.is_moving():
			var here := line.find(w.at)
			if here >= 0:
				arrivals.append([w.station, here, 0, w.id, w, 0])
			continue
		var next := w.path[w.path_index + 1]
		var need := Passenger.segment_mm(w.at, next) - w.seg_mm
		var there := line.find(next)
		if there >= 0 and need <= w.pace_mm():
			arrivals.append([w.station, there, 1, w.id, w, need])
	arrivals.sort_custom(_before)
	var joined: Array[Passenger] = []
	for entry: Array in arrivals:
		var queue: Dictionary = queues[entry[0]]
		if entry[1] != size_of(queue):
			continue
		var w: Passenger = entry[4]
		var cell: Vector2i = lines[entry[0]][entry[1]]
		if entry[2] == 1 and w.path_end() != cell and ends.get([entry[0], cell], 0) > 0:
			continue
		if entry[2] == 1:
			w.walk(entry[5])
			w.clear_path()
			w.halt_tick = now
		join(queue, lanes[entry[0]], w.id)
		joined.append(w)
	for w: Passenger in walkers:
		if w.is_moving() and lines.has(w.station) and queues.has(w.station):
			send_on(grid, w, lines[w.station], size_of(queues[w.station]))
	return joined


## Ordering of arrive()'s entries [station, line index, moving, id, ...].
static func _before(a: Array, b: Array) -> bool:
	for i in 4:
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## A walker `w` whose path ends on a cell of its station's `line` that a
## queue member holds (index below `n`, the queue's size) heads for line[n]
## instead: on from the cell it steps to, or turning back where it is when
## that way is shorter, so it never stops on the held cell. A walker heading
## for a free cell, off the line, or with no free cell left (it chooses again
## at its path's end) is left as it is.
static func send_on(grid: BuildGrid, w: Passenger, line: Array, n: int) -> void:
	var end := line.find(w.path_end())
	if end < 0 or end >= n or n >= line.size():
		return
	var target: Vector2i = line[n]
	var next := w.path[w.path_index + 1]
	var seg := Passenger.segment_mm(w.at, next)
	var ahead := _path(grid, next, target)
	var back := _path(grid, w.at, target)
	var via_ahead := seg - w.seg_mm + Passenger.path_mm(ahead)
	var via_back := w.seg_mm + Passenger.path_mm(back)
	if not back.is_empty() and (ahead.is_empty() or via_back < via_ahead):
		if w.seg_mm == 0:
			w.set_path(back)
			return
		# Turned round mid-step: the same point, seen from the cell ahead.
		var turned: Array[Vector2i] = [next]
		turned.append_array(back)
		var walked := seg - w.seg_mm
		w.at = next
		w.set_path(turned)
		w.seg_mm = walked
	elif not ahead.is_empty():
		var path: Array[Vector2i] = []
		path.assign(w.path.slice(0, w.path_index + 1))
		path.append_array(ahead)
		var index := w.path_index
		var walked := w.seg_mm
		w.path = path
		w.path_index = index
		w.seg_mm = walked


## The grid's path from `from` to `to`, or just [from] when they are one cell.
static func _path(grid: BuildGrid, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		var here: Array[Vector2i] = [from]
		return here
	return grid.find_path(from, to)
