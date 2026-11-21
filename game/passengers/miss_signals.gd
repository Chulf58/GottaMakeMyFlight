class_name MissSignals
extends RefCounted
## Why passengers miss, read from PassengerSim for the queue-full and closed
## signs. It only reads the sim. A station is full when its lane is at capacity or
## passengers wait in its holding area (stuck QUEUE_FULL). A desk refills its
## lane from holding on the tick a slot frees, so a full desk stays full while
## anyone is held; a scanner can be one short for the rest of a tick, after it
## moves its front into the passage, and the holding count covers that tick.

## Why a closed station is closed: the player closed it (StationClosures),
## its staff spot is blocked (only an old save can hold one), staff have no way
## from an entrance to the spot, or nobody is on duty.
const PLAYER_CLOSED_REASON := "Closed by you"
const SPOT_BLOCKED_REASON := "Staff spot blocked"
const UNREACHABLE_REASON := "Staff can't reach the staff spot"
const NO_STAFF_REASON := "No staff on duty"
## A scanner fault stops the station until its repair (StationFaults).
const FAULT_REASON := "Scanner fault"


static func is_full(capacity: int, lane: int, holding: int) -> bool:
	if capacity <= 0:
		return false
	return holding > 0 or lane >= capacity


## Whether `station`'s lane is shorter than a full one (TerminalLayout.LANE_SLOTS):
## a wall, a door or another lane cut it short, so it fills at one or two waiting.
## The queue-full alert and the sign text both name this cause.
static func is_short(sim: PassengerSim, station: int) -> bool:
	return (sim.layout.lanes[station] as Array).size() < TerminalLayout.LANE_SLOTS


## Station id -> passengers held outside its lane, for every full desk or
## scanner.
static func full_stations(sim: PassengerSim) -> Dictionary:
	var out := {}
	for station: int in sim.layout.lanes:
		var capacity := (sim.layout.lanes[station] as Array).size()
		var held := sim.holding_of(station).size()
		if is_full(capacity, sim.queue_of(station).size(), held):
			out[station] = held
	return out


## Every usable desk, scanner and linked gate desk with nobody on duty
## (StaffSim.is_open()), in id order. A station the layout cannot use (walled
## in, no open passage, unlinked gate desk) is broken rather than closed, so it
## is not listed. Without a StaffSim nothing is staffed by design, so nothing
## is listed.
static func closed_stations(sim: PassengerSim) -> Array[int]:
	var out: Array[int] = []
	if sim.staff == null:
		return out
	var stations: Array[int] = []
	stations.append_array(sim.layout.desks)
	stations.append_array(sim.layout.scanners)
	stations.append_array(GateDesks.desk_ids(sim.grid))
	stations.sort()
	for station in stations:
		if StaffPosts.usable(sim.grid, sim.layout, station) and not sim.staff.is_open(station):
			out.append(station)
	return out


## Why `station` is closed (PLAYER_CLOSED_REASON, FAULT_REASON,
## SPOT_BLOCKED_REASON, UNREACHABLE_REASON or NO_STAFF_REASON), or "" when it
## is not one of closed_stations().
static func closed_reason(sim: PassengerSim, station: int) -> String:
	if not closed_stations(sim).has(station):
		return ""
	return staff_reason(sim, station)


## Why the closed desk, scanner or counter `station` takes nobody, the
## player's closure first: PLAYER_CLOSED_REASON, FAULT_REASON,
## SPOT_BLOCKED_REASON, UNREACHABLE_REASON or NO_STAFF_REASON.
static func staff_reason(sim: PassengerSim, station: int) -> String:
	if sim.staff.closures.is_closed(station):
		return PLAYER_CLOSED_REASON
	if sim.staff.faults.is_faulted(station):
		return FAULT_REASON
	if sim.staff.spot_blocked(station):
		return SPOT_BLOCKED_REASON
	if sim.staff.spot_unreachable(station):
		return UNREACHABLE_REASON
	return NO_STAFF_REASON


## Every arch without a whole lane, in id order. An incomplete arch is no
## station (TerminalLayout lists neither it nor its parts), so it is neither
## full nor closed: its sign says what is missing instead.
static func incomplete_arches(sim: PassengerSim) -> Array[int]:
	var out: Array[int] = []
	var lanes := sim.layout.security_lanes
	for arch in lanes.arches:
		if not lanes.is_complete(arch):
			out.append(arch)
	return out


## What an incomplete arch lacks first, as the English key (SecurityLanes.status_text).
## MissMarkers translates it at the moment it sets the sign text.
static func lane_hint(sim: PassengerSim, arch: int) -> String:
	return sim.layout.security_lanes.status_text(arch)
