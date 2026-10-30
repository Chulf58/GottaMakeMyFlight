class_name BoardingFiles
extends RefCounted
## The ordered boarding files (decision passenger-spacing-fixed-per-cause-
## standing-spots-staggered-unloading-ordered-files, part 3). Indoors each exit
## door has a file of the passengers walking to it (TO_EXIT), ordered by the
## walk left to the door cell. Outside, each plane door has a file of the
## passengers on the apron (APRON), ordered by the walk left to the plane, so
## walkers from different exit doors are spaced where their routes share a
## tail. A walker's step is capped so that it stays GAP_MM of walk behind the
## walker ahead of it in each file it is in. A walker that steps out onto the
## apron stays last in its door file, walk left -apron_mm, until it is GAP_MM
## out, so the next one indoors cannot catch it at the door.
##
## Admission: a walker joins a file, in order of walk left, as soon as the
## walker that would be ahead of it is at least GAP_MM ahead. Until then it is
## pending and stands where it is: a walker that has chosen its exit waits for
## its door file, and the head of a door file waits at the door for the apron
## file. The walker that comes to be behind a newcomer is capped by it from
## then on, so a waiting walker is never walked through. Pending walkers are
## admitted at the start of each tick (PassengerSim), file by file in (walk
## left, id) order. Nothing is released on a timer: the head of a file always
## walks on or leaves it, so every wait ends.
##
## Not guaranteed: right after a walker joins, the one behind it can be closer
## than GAP_MM for a few ticks; it is capped at once, so it never moves closer
## and the gap only grows. Walkers in different files are not spaced from each
## other,
## so an indoor corridor shared by two doors' routes and the apron before the
## routes join stay unspaced, and walkers not heading out (seated, standing,
## queuing) are not spaced from walkers in a file.

## The least walk between two walkers in one file, in mm.
const GAP_MM := 700
## A save with no walker in any file.
const EMPTY := {"doors": [], "planes": [], "pending": [], "delayed": []}

## Exit door id -> passenger ids, the one nearest the door first.
var _doors: Dictionary = {}
## Plane key (plane_key()) -> passenger ids, the one nearest the plane first.
var _planes: Dictionary = {}
var _door_of: Dictionary = {}
var _plane_of: Dictionary = {}
## Passenger id -> true, while it waits for admission to its next file.
var _pending: Dictionary = {}
## Passenger id -> true once the files held it back while it was late (a
## runner caught behind a slower walker, or waiting to join), until it leaves
## the walk out (forget()): a miss then counts as the terminal's crowding.
var _delayed: Dictionary = {}
## Derived: exit door -> {"points", "mm", "plane"}, its walk to the plane.
var _aprons: Dictionary = {}
var _aprons_shell: ShellDefinition
## Derived: the forecast's known walkers (own_times() entries) on _known_tick.
var _known: Array = []
var _known_tick := -1


## The key of the plane door a walk outside ends at.
static func plane_key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * 1000.0), roundi(point.y * 1000.0), roundi(point.z * 1000.0))


## The walk left in the door file: to the door cell indoors, and minus the
## distance out on the apron.
static func door_left(p: Passenger) -> int:
	if p.stage == Passenger.Stage.APRON:
		return -p.apron_mm
	return p.remaining_mm()


static func plane_left(p: Passenger) -> int:
	return p.apron_total_mm() - p.apron_mm


## Ticks one walker adds behind another in a file, at a walk: the gap, plus
## one tick because a follower stepped before its predecessor in a tick sees
## where the predecessor was on the tick before.
static func step_ticks() -> int:
	return JourneyForecast.walk_ticks(GAP_MM) + 1


## Clears what is derived from the layout and the passengers.
func clear_derived() -> void:
	_aprons.clear()
	_known.clear()
	_known_tick = -1


## The walk outside from exit door `door`: {"points", "mm", "plane"}, with
## "plane" null when the door has no walk.
func apron_of(sim: PassengerSim, door: int) -> Dictionary:
	if _aprons_shell != sim.shell:
		_aprons.clear()
		_aprons_shell = sim.shell
	if not _aprons.has(door):
		var walk := Passenger.new()
		walk.apron = ShellRoutes.departure(sim, door)
		var plane: Variant = null
		if not walk.apron.is_empty():
			plane = plane_key(walk.apron.back())
		_aprons[door] = {"points": walk.apron, "mm": walk.apron_total_mm(), "plane": plane}
	return _aprons[door]


## Whether passenger `id` is in a file or waiting to join one.
func holds(id: int) -> bool:
	return _door_of.has(id) or _plane_of.has(id) or _pending.has(id)


func is_pending(id: int) -> bool:
	return _pending.has(id)


## The exit door whose file holds `id`, or 0.
func door_of(id: int) -> int:
	return _door_of.get(id, 0)


## The ids in exit door `door`'s file, the one nearest the door first.
func door_file(door: int) -> Array[int]:
	var out: Array[int] = []
	out.assign(_doors.get(door, []))
	return out


## The ids in the apron file that holds `id`, the one nearest the plane first;
## empty when `id` is in none.
func plane_file_of(id: int) -> Array[int]:
	var out: Array[int] = []
	if _plane_of.has(id):
		out.assign(_planes[_plane_of[id]])
	return out


## `p`, which has just chosen its exit, joins that door's file, or is pending.
## Returns whether it joined.
func join_door(sim: PassengerSim, p: Passenger) -> bool:
	var door := p.exit_object
	var ids: Array = _doors.get(door, [])
	var at := _slot(sim, ids, door_left(p), p.id, true)
	if at < 0:
		_pending[p.id] = true
		return false
	ids.insert(at, p.id)
	_doors[door] = ids
	_door_of[p.id] = door
	_pending.erase(p.id)
	return true


## `p`, the head of its door file standing at the door, joins the apron file
## of its door's walk, or waits at the door. Returns whether it joined (a door
## with no walk outside has no apron file to join).
func join_plane(sim: PassengerSim, p: Passenger) -> bool:
	var apron := apron_of(sim, p.exit_object)
	if apron["plane"] == null:
		_pending.erase(p.id)
		return true
	var ids: Array = _planes.get(apron["plane"], [])
	var at := _slot(sim, ids, apron["mm"], p.id, false)
	if at < 0:
		_pending[p.id] = true
		return false
	ids.insert(at, p.id)
	_planes[apron["plane"]] = ids
	_plane_of[p.id] = apron["plane"]
	_pending.erase(p.id)
	return true


## `p`'s route changed: it leaves its door file and joins again by its new
## walk left, or waits.
func reroute(sim: PassengerSim, p: Passenger) -> void:
	leave(p.id)
	join_door(sim, p)


## Takes `id` out of every file and the pending set.
func leave(id: int) -> void:
	_pending.erase(id)
	_take(_doors, _door_of, id)
	_take(_planes, _plane_of, id)


## After `p` stepped: once GAP_MM out on the apron it leaves its door file.
func moved(p: Passenger) -> void:
	if p.stage == Passenger.Stage.APRON and _door_of.has(p.id) and p.apron_mm >= GAP_MM:
		_take(_doors, _door_of, p.id)


## How far `p` may walk this tick, at most `speed`: nothing while pending, and
## never closer than GAP_MM behind the walker ahead in each of its files.
func allowed(sim: PassengerSim, p: Passenger, speed: int) -> int:
	if _pending.has(p.id):
		return 0
	var step := speed
	if _door_of.has(p.id):
		step = mini(step, _room(sim, _doors[_door_of[p.id]], p, true))
	if _plane_of.has(p.id):
		step = mini(step, _room(sim, _planes[_plane_of[p.id]], p, false))
	return step


## The step `p`, at `speed`, takes this tick (allowed()), noting when the
## files held it back while it was late.
func step_of(sim: PassengerSim, p: Passenger, speed: int) -> int:
	var step := allowed(sim, p, speed)
	if p.late and step < speed:
		_delayed[p.id] = true
	return step


## Whether the files held `p` back while it was late, on its way out.
func was_delayed(id: int) -> bool:
	return _delayed.has(id)


## `id` has left the walk out (made, missed or turned away): its delay is
## forgotten.
func forget(id: int) -> void:
	_delayed.erase(id)


## The pending walkers in admission order: those waiting at a door for the
## apron (in their door file, at the door), by plane, walk left and id, then
## those waiting for a door file, by door, walk left and id.
func pending_order(sim: PassengerSim) -> Array[Passenger]:
	var keyed := []
	for id: int in _pending:
		var p := sim.get_passenger(id)
		if _door_of.has(id):
			var apron := apron_of(sim, p.exit_object)
			var plane: Vector3i = apron["plane"] if apron["plane"] != null else Vector3i.ZERO
			keyed.append([0, plane.x, plane.y, plane.z, apron["mm"], id])
		else:
			keyed.append([1, p.exit_object, 0, 0, door_left(p), id])
	keyed.sort()
	var out: Array[Passenger] = []
	for entry: Array in keyed:
		out.append(sim.get_passenger(entry[5]))
	return out


## The files for a save: door files by door id, apron files by plane, pending
## ids in id order.
func to_dict() -> Dictionary:
	var doors := []
	var door_ids: Array = _doors.keys()
	door_ids.sort()
	for door: int in door_ids:
		doors.append({"door": door, "passengers": (_doors[door] as Array).duplicate()})
	var planes := []
	var keys: Array = _planes.keys()
	keys.sort()
	for key: Vector3i in keys:
		planes.append({"passengers": (_planes[key] as Array).duplicate()})
	var pending: Array = _pending.keys()
	pending.sort()
	var delayed: Array = _delayed.keys()
	delayed.sort()
	return {"doors": doors, "planes": planes, "pending": pending, "delayed": delayed}


## A saved to_dict() checked against the loaded passengers by id (with the
## sim's layout rebuilt from the loaded grid): {"files": BoardingFiles} or
## {"error": text}. Every walker heading out with an exit chosen must be in its
## door file or pending, every apron walker in the apron file of its walk's
## plane and, while under GAP_MM out, in its door file; walk left never goes
## down along a file (the gap a walker had to the one ahead when it joined is
## not checked again, since the one behind a newcomer may stand closer for a
## few ticks); every walker heading for an exit, filed or pending, heads for
## an open exit of the loaded layout along a path that ends at its cell; a
## pending walker in a door file stands at the door, with only apron walkers
## ahead of it; a delayed walker is on its way out.
static func checked(data: Variant, by_id: Dictionary, sim: PassengerSim) -> Dictionary:
	if (
		typeof(data) != TYPE_DICTIONARY
		or (data as Dictionary).size() != 4
		or typeof(data.get("doors")) != TYPE_ARRAY
		or typeof(data.get("planes")) != TYPE_ARRAY
		or typeof(data.get("pending")) != TYPE_ARRAY
		or typeof(data.get("delayed")) != TYPE_ARRAY
	):
		return {"error": "boarding must hold the lists doors, planes, pending and delayed"}
	var files := BoardingFiles.new()
	for entry: Variant in data["doors"]:
		var problem := files._load_door(entry, by_id, sim)
		if problem != "":
			return {"error": problem}
	for entry: Variant in data["planes"]:
		var problem := files._load_plane(entry, by_id)
		if problem != "":
			return {"error": problem}
	for value: Variant in data["pending"]:
		var problem := files._load_pending(value, by_id, sim)
		if problem != "":
			return {"error": problem}
	for value: Variant in data["delayed"]:
		var id := int(value) if WholeNumber.is_whole(value) else 0
		var p: Passenger = by_id.get(id)
		var out := p != null and p.stage in [Passenger.Stage.TO_EXIT, Passenger.Stage.APRON]
		if not out or files._delayed.has(id):
			return {"error": "delayed walker %s is unknown, repeated or not on its way out" % value}
		files._delayed[id] = true
	var missing := files._unfiled(by_id)
	if missing != "":
		return {"error": missing}
	return {"files": files}


## The tick `p` reaches the plane door, from its own times (`own`,
## JourneyForecast.own_times()) and the walkers known on this tick that reach
## the same plane door ahead of it. The model has two places walkers pass one
## at a time: each exit door and the plane door. They pass a door in the order
## of their own times, ties to the lower id, each at least step_ticks() after
## the one before, and a walker held for the apron waits at its door, which
## holds back the next one indoors. Walkers yet to come that the sim does not
## have now are not predicted.
func queued(sim: PassengerSim, p: Passenger, own: Dictionary) -> int:
	if own["plane"] == null:
		return own["plane_tick"]
	var mine := own.duplicate()
	mine["id"] = p.id
	var entries := [mine]
	for e: Dictionary in known(sim):
		if e["plane"] == own["plane"] and e["id"] != p.id:
			entries.append(e)
	if entries.size() == 1:
		return own["plane_tick"]
	var outside := []
	var inside := {}
	var door_free := {}
	var gap := step_ticks()
	for e: Dictionary in entries:
		if e["door_tick"] < 0:
			outside.append([e["plane_tick"], e["id"], e])
			# Still in its door file: the next walker indoors waits for it.
			if e["trail"] < GAP_MM and e["id"] != p.id:
				var free: int = sim.tick + JourneyForecast.walk_ticks(GAP_MM - e["trail"]) + 1
				door_free[e["door"]] = maxi(door_free.get(e["door"], free), free)
		else:
			var list: Array = inside.get(e["door"], [])
			list.append([e["door_tick"], e["id"], e])
			inside[e["door"]] = list
	outside.sort()
	var doors: Array = inside.keys()
	doors.sort()
	for door: int in doors:
		(inside[door] as Array).sort()
	var next := {}
	var o := 0
	var plane_free := -JourneyForecast.NEVER
	while true:
		# The next walker to the plane door: the first outside, or the first
		# indoors at each door, whichever is due soonest.
		var best: Array = []
		if o < outside.size():
			best = [outside[o][0], outside[o][1], 0, 0]
		for door: int in doors:
			var k: int = next.get(door, 0)
			if k >= (inside[door] as Array).size():
				continue
			var e: Dictionary = inside[door][k][2]
			var at_door := maxi(e["door_tick"], door_free.get(door, e["door_tick"]))
			var due: int = e["plane_tick"] + at_door - e["door_tick"]
			if best.is_empty() or due < best[0] or (due == best[0] and e["id"] < best[1]):
				best = [due, e["id"], door, at_door]
		if best.is_empty():
			break
		var arrive := maxi(best[0], plane_free + gap)
		plane_free = arrive
		if best[2] == 0:
			o += 1
		else:
			next[best[2]] = next.get(best[2], 0) + 1
			# It leaves the door when the apron has room, and the next one
			# indoors reaches the door a gap after that.
			door_free[best[2]] = best[3] + arrive - best[0] + gap
		if best[1] == p.id:
			return arrive
	return own["plane_tick"]


## The walkers the forecast knows of, each with its own times
## (JourneyForecast.own_times() at a walk, unrouted, plus "id"), worked out
## once per tick: every passenger out to the plane, or airside and not on a
## facility visit.
func known(sim: PassengerSim) -> Array:
	if _known_tick == sim.tick:
		return _known
	_known_tick = sim.tick
	_known = []
	for id in sim.passenger_ids():
		var q := sim.get_passenger(id)
		var leg := StageKinds.leg(q.stage)
		if q.is_done() or not (leg == StageKinds.Leg.AIRSIDE or leg == StageKinds.Leg.APRON):
			continue
		var own := JourneyForecast.own_times(sim, q, sim.tick, false)
		if not own.is_empty():
			own["id"] = id
			_known.append(own)
	return _known


## The step `p` may take behind the walker ahead of it in `ids`.
func _room(sim: PassengerSim, ids: Array, p: Passenger, in_door: bool) -> int:
	var k := ids.find(p.id)
	if k <= 0:
		return JourneyForecast.NEVER_MM
	var ahead := sim.get_passenger(ids[k - 1])
	var mine := door_left(p) if in_door else plane_left(p)
	var theirs := door_left(ahead) if in_door else plane_left(ahead)
	return maxi(0, mine - theirs - GAP_MM)


## Where a walker with walk left `left` and id `id` goes in `ids`, or -1 when
## it would be closer than GAP_MM to the walker ahead. The walker behind it
## may be closer: it is capped by the newcomer from the next step on.
func _slot(sim: PassengerSim, ids: Array, left: int, id: int, in_door: bool) -> int:
	var at := ids.size()
	for k in ids.size():
		var other := sim.get_passenger(ids[k])
		var theirs := door_left(other) if in_door else plane_left(other)
		if left < theirs or (left == theirs and id < other.id):
			at = k
			break
	if at > 0:
		var ahead := sim.get_passenger(ids[at - 1])
		if left - (door_left(ahead) if in_door else plane_left(ahead)) < GAP_MM:
			return -1
	return at


static func _take(files: Dictionary, index: Dictionary, id: int) -> void:
	if not index.has(id):
		return
	var key: Variant = index[id]
	index.erase(id)
	var ids: Array = files[key]
	ids.erase(id)
	if ids.is_empty():
		files.erase(key)


## The ids of a saved file, or a problem.
func _ids(list: Variant, by_id: Dictionary, label: String) -> Variant:
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		return "%s must be a list of passengers" % label
	var ids: Array[int] = []
	for value: Variant in list:
		if not WholeNumber.is_whole(value):
			return "%s holds %s, not a passenger id" % [label, str(value).left(40)]
		var id := int(value)
		var p: Passenger = by_id.get(id)
		if p == null or p.is_done() or ids.has(id):
			return "%s names passenger %d, unknown, settled or repeated" % [label, id]
		ids.append(id)
	return ids


func _load_door(entry: Variant, by_id: Dictionary, sim: PassengerSim) -> String:
	if (
		typeof(entry) != TYPE_DICTIONARY
		or (entry as Dictionary).size() != 2
		or not WholeNumber.is_whole(entry.get("door"))
	):
		return "boarding door file %s is malformed" % str(entry).left(80)
	var door := int(entry["door"])
	var ids: Variant = _ids(entry.get("passengers"), by_id, "door file %d" % door)
	if typeof(ids) == TYPE_STRING:
		return ids
	if door == 0 or _doors.has(door):
		return "door file %d is repeated or names no door" % door
	var last: Passenger = null
	for id: int in ids:
		var p: Passenger = by_id[id]
		var problem := _member_problem(sim, p, door, last)
		if problem != "":
			return problem
		_door_of[id] = door
		last = p
	_doors[door] = ids
	return ""


## Why `p` cannot follow `last` (null for the first) in door `door`'s file,
## or "".
func _member_problem(sim: PassengerSim, p: Passenger, door: int, last: Passenger) -> String:
	var heading := p.stage == Passenger.Stage.TO_EXIT
	var out := p.stage == Passenger.Stage.APRON and p.apron_mm < GAP_MM
	if p.exit_object != door or not (heading or out) or _door_of.has(p.id):
		return "passenger %d cannot be in door file %d" % [p.id, door]
	if heading and not _heads_for(sim, p):
		return "passenger %d in door file %d is not walking to that open exit" % [p.id, door]
	if last != null and door_left(p) < door_left(last):
		return "passengers %d and %d in door file %d are out of order" % [last.id, p.id, door]
	return ""


func _load_plane(entry: Variant, by_id: Dictionary) -> String:
	if typeof(entry) != TYPE_DICTIONARY or (entry as Dictionary).size() != 1:
		return "boarding apron file %s is malformed" % str(entry).left(80)
	var ids: Variant = _ids(entry.get("passengers"), by_id, "apron file")
	if typeof(ids) == TYPE_STRING:
		return ids
	var key: Variant = null
	var last: Passenger = null
	for id: int in ids:
		var p: Passenger = by_id[id]
		if p.stage != Passenger.Stage.APRON or p.apron.is_empty() or _plane_of.has(id):
			return "passenger %d cannot be in an apron file" % id
		var mine := plane_key(p.apron.back())
		if key == null:
			key = mine
		if mine != key or _planes.has(key):
			return "passenger %d's walk ends at another plane than its apron file" % id
		if last != null and plane_left(p) < plane_left(last):
			return "passengers %d and %d in an apron file are out of order" % [last.id, id]
		last = p
	for id: int in ids:
		_plane_of[id] = key
	_planes[key] = ids
	return ""


func _load_pending(value: Variant, by_id: Dictionary, sim: PassengerSim) -> String:
	if not WholeNumber.is_whole(value):
		return "boarding pending holds %s, not a passenger id" % str(value).left(40)
	var id := int(value)
	var p: Passenger = by_id.get(id)
	if p == null or _pending.has(id):
		return "pending passenger %d is unknown or repeated" % id
	if p.stage != Passenger.Stage.TO_EXIT or p.exit_object == 0 or not _heads_for(sim, p):
		return "pending passenger %d is not heading for an open exit" % id
	# In its door file it is the walker standing at the door: only walkers
	# already out on the apron are ahead of it.
	if _door_of.has(id):
		var at_door := p.at == sim.layout.door_cell(sim.grid, p.exit_object)
		var ahead: Array = _doors[_door_of[id]].slice(0, _doors[_door_of[id]].find(id))
		var out := ahead.all(
			func(other: int) -> bool: return by_id[other].stage == Passenger.Stage.APRON
		)
		if p.is_moving() or not at_door or not out:
			return "pending passenger %d is in a door file but not waiting at its door" % id
	_pending[id] = true
	return ""


## Whether `p`'s exit is an open exit in the sim's layout and its committed
## path ends at that exit's cell.
static func _heads_for(sim: PassengerSim, p: Passenger) -> bool:
	if not sim.layout.open_exits(sim.grid).has(p.exit_object):
		return false
	return p.path_end() == sim.layout.door_cell(sim.grid, p.exit_object)


## A walker that should be in a file and is not, or "".
func _unfiled(by_id: Dictionary) -> String:
	for id: int in by_id:
		var p: Passenger = by_id[id]
		if p.stage == Passenger.Stage.TO_EXIT and p.exit_object != 0:
			if not _door_of.has(id) and not _pending.has(id):
				return "passenger %d heading for exit %d is in no file" % [id, p.exit_object]
		elif p.stage == Passenger.Stage.APRON:
			if not _plane_of.has(id) or (p.apron_mm < GAP_MM) != _door_of.has(id):
				return "apron passenger %d is not in the files its walk puts it in" % id
	return ""
