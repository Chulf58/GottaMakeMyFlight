class_name StationFaults
extends RefCounted
## The security stations a scanner fault stopped (decision scanner-fault-
## incident-design-stationfaults-beside-stationcl), kept in StaffSim
## (StaffSim.faults) beside the player's closures and apart from them, so a
## faulted station never says "Closed by you". A basic scanner or a lane's
## X-ray (the lane's station, its arch) can fault. IncidentDirector adds a
## fault with its repair tick; nobody else does.
##
## A faulted station admits nobody: StaffSim.is_open() is false, so on the
## next tick PassengerSim sends its queue and the passengers walking to it to
## choose again, and those it admitted before finish. Its staff stay posted:
## a fault is no closure, so nothing releases them and the posting pass may
## still staff it. clear_due() runs first in StaffSim.step(), so on the repair
## tick the station admits again from that step on: PassengerSim steps the
## staff before its station steps, admissions, the line rules and the
## passenger steps of that tick (the entrance, the arrivals and the spawns
## before it read no scanner). SecurityForecast replays the repair on that
## same tick.
##
## A save writes the faults of objects still on the grid (live()); a fault
## whose repair tick is at or behind the clock clears on the next step.

## Station id -> its repair tick.
var _until: Dictionary = {}
var _staff: StaffSim


func _init(of_staff: StaffSim) -> void:
	_staff = of_staff


## Whether `station` is faulted now.
func is_faulted(station: int) -> bool:
	return _until.has(station)


## Whether `station` would be open (StaffSim.is_open()) if it had no fault:
## usable, staffed, its member not leaving and not closed by the player.
## SecurityForecast reopens a faulted station on its repair tick only then.
func open_but_for_fault(station: int) -> bool:
	return _staff._serves(station)


## The tick `station` is repaired on, or -1 when it has no fault.
func repair_tick(station: int) -> int:
	return _until.get(station, -1)


## Stops `station` until `repair`, and emits StaffSim.staff_changed. Returns
## false, with an error and nothing changed, for a station that is no scanner
## or lane of the layout, one already faulted or a repair tick not after the
## clock.
func add(station: int, repair: int) -> bool:
	var sim := _staff.sim
	if not sim.layout.scanners.has(station) or _until.has(station) or repair <= sim.tick:
		push_error("StationFaults.add: station %d cannot fault until %d" % [station, repair])
		return false
	_until[station] = repair
	_staff.staff_changed.emit()
	return true


## Clears every fault repaired by `tick`, and emits StaffSim.staff_changed
## when one cleared. StaffSim.step() calls it first.
func clear_due(tick: int) -> void:
	var due: Array = []
	for station: int in _until:
		if _until[station] <= tick:
			due.append(station)
	if due.is_empty():
		return
	for station: int in due:
		_until.erase(station)
	_staff.staff_changed.emit()


## The faults of objects still on the grid, in station order: what a save
## holds, [[station, repair tick], ...].
func live() -> Array:
	var out: Array = []
	var ids: Array = _until.keys()
	ids.sort()
	for station: int in ids:
		if not _staff.sim.grid.get_object(station).is_empty():
			out.append([station, _until[station]])
	return out


## Replaces the faults with `faults` (a load, checked by checked()).
func assign(faults: Array) -> void:
	_until.clear()
	for entry: Array in faults:
		_until[entry[0]] = entry[1]


## Whether a piece of `def_id` can fault: a basic scanner or a lane's arch.
static func faultable_def(def_id: StringName) -> bool:
	return def_id == &"security_scanner" or def_id == SecurityLanes.ARCH


## The saved faults with ints, [[station, repair tick], ...], or a String
## naming what is wrong: a list of pairs of whole numbers in rising station
## order, each station an object on `grid` that can fault, each repair tick 1
## or more.
static func checked(value: Variant, grid: BuildGrid) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return "faults is not a list"
	var out: Array = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 2:
			return "a fault is not a [station, repair tick] pair"
		var pair: Array = entry
		if not WholeNumber.is_whole(pair[0]) or not WholeNumber.is_whole(pair[1]):
			return "a fault holds a value that is not a whole number"
		var id := int(pair[0])
		if not out.is_empty() and id <= int(out[out.size() - 1][0]):
			return "faulted station %d is out of order or listed twice" % id
		if int(pair[1]) < 1:
			return "faulted station %d has no repair tick" % id
		var record := grid.get_object(id)
		if record.is_empty():
			return "faulted station %d is no object on the grid" % id
		if not faultable_def(StringName(record["def"])):
			return "faulted station %d is no scanner or lane" % id
		out.append([id, int(pair[1])])
	return out
