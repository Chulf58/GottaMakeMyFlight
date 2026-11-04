class_name StationClosures
extends RefCounted
## The staffed stations the player closed, kept in StaffSim (StaffSim.closures;
## decision select-placed-items-design-click-order-gold-footprint-highli). The
## player can close a check-in desk, a scanner, a whole security lane (one
## station: its arch), a food counter, a shop till or counter (an exchange and
## a pharmacy included) or an info desk, and open it again; never a gate desk,
## a self-service room or decor. The toggle is free and is no build action, so
## build undo never touches it.
##
## Three checks stay apart. Admission: StaffSim.is_open() is false for a closed
## station at once, so passengers stop joining and the sims send its queue to
## choose again (PassengerSim; the cafe and the shop keep their own paths).
## Eligibility for a new posting: StaffPosts.is_vacant() refuses a closed
## station. Permission to finish: a member on duty there stays while the
## service admitted before the closure lasts (StaffPosts.in_service(); at a
## lane every admitted passenger, so its helper stays too), then StaffSim's
## step releases it idle where it stands (release_due()), still on the roster
## and paid, free for the posting pass. Closure is not part of physical
## workability (StaffPosts.workable()), which would let a member go
## mid-service. Opening before that release keeps the same members serving;
## after it the station waits for the posting pass, which may not staff it.
##
## The id of a removed object stays closed, so an undo that brings the object
## back under its id brings it back closed; ids are never reused, and a
## template paste places new objects, which are open. A save writes only the
## ids of objects still on the grid (live_ids()).

## What the inspect window shows for a closable station (status()).
enum Status { CLOSED_BY_YOU, FINISHING, WAITING_FOR_STAFF, STAFF_ON_THE_WAY, SERVING }

const STATUS_TEXT := {
	Status.CLOSED_BY_YOU: "Closed by you",
	Status.FINISHING: "Finishing current service",
	Status.WAITING_FOR_STAFF: "Waiting for staff",
	Status.STAFF_ON_THE_WAY: "Staff on the way",
	Status.SERVING: "Serving",
}

## The pieces besides the counters that are closable stations.
const CLOSABLE_DEFS: Array[StringName] = [&"checkin_desk", &"security_scanner", SecurityLanes.ARCH]

var staff: StaffSim

## Closed station id -> true.
var _ids: Dictionary = {}


func _init(of_staff: StaffSim) -> void:
	staff = of_staff


## Whether the player closed `station`.
func is_closed(station: int) -> bool:
	return _ids.has(station)


## Closes `station` (`closed` true) or opens it again, and emits
## StaffSim.staff_changed when that changed anything. Returns false, with an
## error and nothing changed, when asked to close a station that is not
## closable (is_closable()); opening one that is not closed changes nothing.
func set_closed(station: int, closed: bool) -> bool:
	if closed == _ids.has(station):
		return true
	if closed and not is_closable(station):
		push_error("StationClosures.set_closed: %d is no station the player can close" % station)
		return false
	if closed:
		_ids[station] = true
	else:
		_ids.erase(station)
	staff.staff_changed.emit()
	return true


## Every closed id, in id order, removed objects an undo may bring back
## included.
func ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_ids.keys())
	out.sort()
	return out


## The closed ids of objects still on the grid, in id order: what a save holds.
func live_ids() -> Array[int]:
	var out: Array[int] = []
	for id in ids():
		if not staff.sim.grid.get_object(id).is_empty():
			out.append(id)
	return out


## Replaces the closed set with `closed` (a load, checked by StaffSnapshot).
func assign(closed: Array[int]) -> void:
	_ids.clear()
	for id in closed:
		_ids[id] = true


## Whether a piece of `def_id` is a station the player could close: a
## check-in desk, a basic scanner, a lane's arch or a ShopCounters counter.
## A save is checked with it: an arch whose lane is broken now is no station
## (is_closable() is false), yet it may stay closed for when the lane is whole
## again.
static func closable_def(def_id: StringName) -> bool:
	return CLOSABLE_DEFS.has(def_id) or ShopCounters.COUNTER_ROOMS.has(def_id)


## Whether the player can close `station`: a check-in desk, a scanner or a
## lane's arch, or a counter of ShopCounters (an info desk included).
func is_closable(station: int) -> bool:
	if ShopCounters.is_counter(staff.sim.grid, station):
		return true
	var layout := staff.sim.layout
	return layout.desks.has(station) or layout.scanners.has(station)


## The station the player closes by picking object `object_id`: the arch for
## a part of a whole security lane, the object itself when it is closable,
## else 0.
func station_of(object_id: int) -> int:
	var arch := staff.sim.layout.security_lanes.lane_of_piece(object_id)
	if arch != 0:
		return arch
	return object_id if is_closable(object_id) else 0


## Whether StaffSim's step lets `m` go from its closed station now: it holds
## a post there, is not leaving (a fired member walks out its own way) and is
## not on duty with a service still running there.
func release_due(m: StaffMember) -> bool:
	if m.station == 0 or m.leaving or not _ids.has(m.station):
		return false
	if m.state != StaffMember.State.ON_DUTY:
		return true
	return not StaffPosts.in_service(staff.sim, m.station)


## What the window shows for `station`: CLOSED_BY_YOU, or FINISHING while a
## member on duty there still finishes a service admitted before the closure
## (or before a firing); SERVING while it is open; STAFF_ON_THE_WAY while its
## primary walks there; else WAITING_FOR_STAFF.
func status(station: int) -> Status:
	if _ids.has(station):
		return Status.FINISHING if _finishing(station) else Status.CLOSED_BY_YOU
	if staff.is_open(station):
		return Status.SERVING
	var id := staff.staff_at(station)
	if id != 0:
		var m := staff.get_member(id)
		if m.state == StaffMember.State.TO_STATION:
			return Status.STAFF_ON_THE_WAY
		if m.leaving and _finishing(station):
			return Status.FINISHING
	return Status.WAITING_FOR_STAFF


## status() in the window's words (STATUS_TEXT).
func status_text(station: int) -> String:
	return STATUS_TEXT[status(station)]


## Whether closing `station` would leave passengers no check-in desk (role
## CHECKIN) or no scanner (SECURITY): none other than `station` is usable and
## not closed. The window warns then; closing is still allowed. With
## `station` 0, whether none is left now. Always false for shop servers and
## cleaners, whose stations passengers can do without.
func would_strand(role: StaffMember.Role, station := 0) -> bool:
	if role != StaffMember.Role.CHECKIN and role != StaffMember.Role.SECURITY:
		return false
	var sim := staff.sim
	for other in staff.stations_of(role):
		if other != station and not _ids.has(other):
			if StaffPosts.usable(sim.grid, sim.layout, other):
				return false
	return true


## Whether a member on duty at `station` (its primary or a lane's helper) is
## still finishing a service there.
func _finishing(station: int) -> bool:
	if not (staff.is_staffed(station) or staff.is_staffed(station, StaffMember.Slot.HELPER)):
		return false
	return StaffPosts.in_service(staff.sim, station)
