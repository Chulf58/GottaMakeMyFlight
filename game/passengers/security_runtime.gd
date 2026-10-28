class_name SecurityRuntime
extends RefCounted
## Security service at both tiers (decision security-lane-technical-design-
## one-station-per-lane-with-int, points 1, 2 and 4): admissions, the phases
## inside Passenger.Stage.SECURITY, the main service position, the one repack
## berth, the returns and completion. PassengerSim keeps the external queue
## (lane and holding list); this owns everything after admission.
##
## THE BASIC SCANNER serves one passenger at a time. SCAN: the passenger walks
## the passage while BASIC_SCAN_TICKS plus BASIC_BAG_TICKS per carry-on bag
## run down. A passenger with liquids or an alarm then repacks in place
## (REPACK), and the scanner stays held, so a repack blocks it. The passenger
## is cleared at the passage end.
##
## A SECURITY LANE (SecurityLanes geometry) overlaps passengers. UNPACK at the
## unpack cell, ARCH through the passage to the pickup cell, PICKUP, LEAVE to
## the exit cell, where the passenger is cleared. The main service position
## (unpack and arch) is held from admission until the passenger has passed
## the arch (reached the pickup cell); then the next one starts. A passenger
## with liquids or an alarm reserves the berth before it is admitted; when the
## berth is taken it waits at the queue front and nobody skips it. After the
## arch it steps aside (TO_BERTH), repacks there (REPACK), and walks the return
## route (RETURN), releasing the berth once it has stepped off it. A returning
## passenger is never put back in the queue: once it stands at the end of the
## return route it takes the next free main position ahead of a fresh
## admission, never interrupting a started one, and walks through the arch
## again from there. An incident resolves once (Passenger.incident_resolved).
##
## Work phases (SCAN, UNPACK, REPACK, PICKUP) keep their remaining integer work
## on the passenger and lose rate() each tick, so a helper (Security 5/8) can
## raise the rate without a saved deadline going stale. Walking phases end
## when the passenger stops walking. Everything happens in admission order on
## PassengerSim's tick, and the same code replays a copy of the state for the
## forecast (SecurityForecast).
##
## The host is PassengerSim, or a SecurityForecast replaying a copy: it gives
## `layout` and get_passenger(id), and bind() takes what to call when a
## passenger is admitted and when it is cleared.

enum Phase { NONE, SCAN, UNPACK, ARCH, TO_BERTH, REPACK, RETURN, PICKUP, LEAVE }

## Basic scanner, zero bags: today's 40-tick service, the passage walk in it.
const BASIC_SCAN_TICKS := 40
## Each bag is unpacked, X-rayed and packed again at the one scanner.
const BASIC_BAG_TICKS := 15
## Repacking after liquids or an alarm, at either tier (at rate 1).
const REPACK_TICKS := 80
## Lane: stepping up to the tray table, and each bag into a tray.
const LANE_UNPACK_TICKS := 6
const LANE_UNPACK_BAG_TICKS := 8
## Lane: collecting the trays at the pickup table.
const LANE_PICKUP_TICKS := 2
const LANE_PICKUP_BAG_TICKS := 4
const WORK_PHASES: Array[Phase] = [Phase.SCAN, Phase.UNPACK, Phase.REPACK, Phase.PICKUP]
const BASIC_PHASES: Array[Phase] = [Phase.SCAN, Phase.REPACK]
const LANE_PHASES: Array[Phase] = [
	Phase.UNPACK,
	Phase.ARCH,
	Phase.TO_BERTH,
	Phase.REPACK,
	Phase.RETURN,
	Phase.PICKUP,
	Phase.LEAVE,
]
## Lane phases that hold the main position: until the arch is passed.
const MAIN_PHASES: Array[Phase] = [Phase.UNPACK, Phase.ARCH]

## Station id -> {"admitted": Array (ids, admission order), "returns": Array
## (ids, return order), "main": id holding the main position or 0, "berth":
## id holding or reserving the berth or 0}. A station with nobody admitted
## has no record.
var records := {}
var _host: Object
var _admitted: Callable
var _cleared: Callable


## `admitted(p)` puts an admitted passenger in Stage.SECURITY; `cleared(p)`
## sends a cleared one on to the gate. A null host lets go of it.
func bind(host: Object, admitted := Callable(), cleared := Callable()) -> void:
	_host = host
	_admitted = admitted
	_cleared = cleared


## How much work a phase loses per tick at `station`: 1 for now. The hook for
## a helper officer (Security 5/8), who raises it for the phases it helps.
func rate(_station: int, _phase: int) -> int:
	return 1


static func incident_open(p: Passenger) -> bool:
	return (p.liquids or p.alarm) and not p.incident_resolved


## The work a phase starts with for `p`, at rate 1.
static func work_for(phase: Phase, p: Passenger) -> int:
	match phase:
		Phase.SCAN:
			return BASIC_SCAN_TICKS + BASIC_BAG_TICKS * p.carry_on
		Phase.UNPACK:
			return LANE_UNPACK_TICKS + LANE_UNPACK_BAG_TICKS * p.carry_on
		Phase.PICKUP:
			return LANE_PICKUP_TICKS + LANE_PICKUP_BAG_TICKS * p.carry_on
		Phase.REPACK:
			return REPACK_TICKS
	return 0


## What breaks the scheduler's rules in a station's record (see `records`)
## whose admitted passengers are `units`, between ticks, or "". `lane` says
## which tier. A basic scanner serves exactly one passenger, in SCAN or
## REPACK, who holds the main position, and has no berth or returns. At a
## lane the one passenger in UNPACK or ARCH holds the main position, or
## nobody does when there is none; a passenger stepping aside or repacking
## has an open incident and holds the berth, and so does one in UNPACK or ARCH
## with an open incident (reserved); otherwise only a returning passenger may
## still hold it (it is released on the tick after it steps off); a returning
## passenger's incident is resolved.
static func record_problem(record: Dictionary, units: Array, lane: bool) -> String:
	var in_main: Array[int] = []
	var needs_berth: Array[int] = []
	var by_id := {}
	for p: Passenger in units:
		by_id[p.id] = p
		var phase := p.security_phase as Phase
		if not (LANE_PHASES if lane else BASIC_PHASES).has(phase):
			return "passenger %d is in a phase this tier does not have" % p.id
		# Work only runs down from what its phase started with, and a walking
		# phase has none. Zero is allowed: a basic scanner's passenger can
		# still be walking the passage when its scan work has run out. A
		# version 7 save migrates to SCAN work of its old service end minus
		# the tick, at most the old 40-tick scan, which is within the cap.
		if p.security_work < 0 or p.security_work > work_for(phase, p):
			return "passenger %d has more work left than its phase starts with" % p.id
		var aside := phase == Phase.TO_BERTH or phase == Phase.REPACK
		if aside and not incident_open(p):
			return "passenger %d repacks with no open incident" % p.id
		if phase == Phase.RETURN and not p.incident_resolved:
			return "passenger %d returns with its incident open" % p.id
		if not lane or MAIN_PHASES.has(phase):
			in_main.append(p.id)
		if lane and (aside or (MAIN_PHASES.has(phase) and incident_open(p))):
			needs_berth.append(p.id)
	if not lane and (units.size() != 1 or record["berth"] != 0 or not record["returns"].is_empty()):
		return "a basic scanner serves one passenger, with no berth or returns"
	if in_main.size() > 1 or record["main"] != (in_main[0] if in_main.size() == 1 else 0):
		return "the main position is not held by its one passenger in service"
	if needs_berth.size() > 1:
		return "two passengers need the one berth"
	var berth: int = record["berth"]
	if not needs_berth.is_empty() and berth != needs_berth[0]:
		return "passenger %d needs the berth it does not hold" % needs_berth[0]
	if needs_berth.is_empty() and berth != 0 and by_id[berth].security_phase != Phase.RETURN:
		return "the berth is held by passenger %d, who does not need it" % berth
	return ""


## Whether `station` is a whole security lane (otherwise a basic scanner).
func is_lane(station: int) -> bool:
	return (_host.layout as TerminalLayout).security_lanes.is_complete(station)


## The cell where a passenger of `station` is cleared: a lane's exit cell, a
## basic scanner's passage end. NO_CELL when it has neither.
func exit_cell(station: int) -> Vector2i:
	var layout: TerminalLayout = _host.layout
	if is_lane(station):
		return layout.security_lanes.lane(station)["exit"]
	var passage: Array = layout.passages.get(station, [])
	return passage[passage.size() - 1] if not passage.is_empty() else BuildObjectDef.NO_CELL


## Whether a passenger is admitted at any station.
func holds(id: int) -> bool:
	for record in records.values():
		if (record["admitted"] as Array).has(id):
			return true
	return false


## The record of `station` (see `records`), or an empty dictionary.
func record_of(station: int) -> Dictionary:
	return records.get(station, {})


## Phase changes and completions of the admitted passengers, in admission
## order. Runs before admit() on each tick.
func advance(station: int) -> void:
	if not records.has(station):
		return
	var record: Dictionary = records[station]
	for id: int in (record["admitted"] as Array).duplicate():
		_advance_one(station, record, _host.get_passenger(id))


## Gives a free main position to the first returning passenger who stands at
## the end of the return route, else (when `open`) to the queue front once it
## stands on the first lane cell, unless it needs the berth and the berth is
## taken. `queue` is PassengerSim's {"lane", "holding"} and `cells` the lane.
func admit(station: int, queue: Dictionary, cells: Array, open: bool) -> void:
	var record: Dictionary = records.get(station, {})
	if not record.is_empty() and record["main"] != 0:
		return
	if not record.is_empty():
		for id: int in record["returns"]:
			var back: Passenger = _host.get_passenger(id)
			if back.security_phase == Phase.RETURN and not back.is_moving():
				(record["returns"] as Array).erase(id)
				record["main"] = id
				var path: Array[Vector2i] = [back.at]
				path.append_array(_lane(station)["passage"])
				_enter(back, Phase.ARCH, path)
				return
	var lane: Array = queue["lane"]
	if not open or lane.is_empty():
		return
	var front: Passenger = _host.get_passenger(lane[0])
	if front.at != cells[0] or front.is_moving():
		return
	var on_lane := is_lane(station)
	if on_lane and incident_open(front) and not record.is_empty() and record["berth"] != 0:
		return
	lane.pop_front()
	if record.is_empty():
		record = {"admitted": [], "returns": [], "main": 0, "berth": 0}
		records[station] = record
	(record["admitted"] as Array).append(front.id)
	record["main"] = front.id
	front.station = station
	_admitted.call(front)
	if on_lane:
		if incident_open(front):
			record["berth"] = front.id
		_enter(front, Phase.UNPACK)
	else:
		var passage: Array[Vector2i] = []
		passage.assign(_host.layout.passages[station])
		_enter(front, Phase.SCAN, passage)


## Takes a passenger out of its station's service (it missed its flight or
## was sent away): its main position, berth and return place are freed.
func release(p: Passenger) -> void:
	for station: int in records.keys():
		var record: Dictionary = records[station]
		if not (record["admitted"] as Array).has(p.id):
			continue
		_forget(station, record, p.id)
		_reset(p)
		return


## Ends a station's service (it is gone or its lane changed): every admitted
## passenger loses its phase, without clearance. Returns their ids in
## admission order, for the caller to send back to security selection.
func drop(station: int) -> Array[int]:
	var out: Array[int] = []
	if not records.has(station):
		return out
	out.assign(records[station]["admitted"])
	records.erase(station)
	for id in out:
		_reset(_host.get_passenger(id))
	return out


## The records as JSON-safe entries, in station order.
func to_list() -> Array:
	var out := []
	var stations: Array = records.keys()
	stations.sort()
	for station: int in stations:
		var record: Dictionary = records[station]
		(
			out
			. append(
				{
					"station": station,
					"admitted": (record["admitted"] as Array).duplicate(),
					"returns": (record["returns"] as Array).duplicate(),
					"main": record["main"],
					"berth": record["berth"],
				}
			)
		)
	return out


## Replaces the records with checked ones (PassengerSnapshot) or a copy.
func restore(with_records: Dictionary) -> void:
	records = with_records.duplicate(true)


func _advance_one(station: int, record: Dictionary, p: Passenger) -> void:
	var phase := p.security_phase as Phase
	if WORK_PHASES.has(phase):
		p.security_work = maxi(p.security_work - rate(station, phase), 0)
	var on_lane := is_lane(station)
	var lane := _lane(station) if on_lane else {}
	if record["berth"] == p.id and phase == Phase.RETURN and p.at != lane["berth"]:
		record["berth"] = 0
	if p.is_moving() or (WORK_PHASES.has(phase) and p.security_work > 0):
		return
	match phase:
		Phase.SCAN:
			if incident_open(p):
				_enter(p, Phase.REPACK)
			else:
				_clear(station, record, p)
		Phase.UNPACK:
			var passage: Array[Vector2i] = []
			passage.assign(lane["passage"])
			_enter(p, Phase.ARCH, passage)
		Phase.ARCH:
			record["main"] = 0
			if incident_open(p):
				var aside: Array[Vector2i] = [p.at, lane["berth"]]
				_enter(p, Phase.TO_BERTH, aside)
			else:
				_enter(p, Phase.PICKUP)
		Phase.TO_BERTH:
			_enter(p, Phase.REPACK)
		Phase.REPACK:
			p.incident_resolved = true
			if not on_lane:
				_clear(station, record, p)
				return
			var back: Array[Vector2i] = [p.at]
			back.append_array(lane["return_route"])
			(record["returns"] as Array).append(p.id)
			_enter(p, Phase.RETURN, back)
		Phase.PICKUP:
			var out: Array[Vector2i] = [p.at, lane["exit"]]
			_enter(p, Phase.LEAVE, out)
		Phase.LEAVE:
			_clear(station, record, p)


func _lane(station: int) -> Dictionary:
	return (_host.layout as TerminalLayout).security_lanes.lane(station)


## Starts a phase with its work, and walks `path` when one is given.
func _enter(p: Passenger, phase: Phase, path: Array[Vector2i] = []) -> void:
	p.security_phase = phase
	p.security_work = work_for(phase, p)
	if not path.is_empty():
		p.set_path(path)


func _clear(station: int, record: Dictionary, p: Passenger) -> void:
	_forget(station, record, p.id)
	_reset(p)
	_cleared.call(p)


func _forget(station: int, record: Dictionary, id: int) -> void:
	(record["admitted"] as Array).erase(id)
	(record["returns"] as Array).erase(id)
	if record["main"] == id:
		record["main"] = 0
	if record["berth"] == id:
		record["berth"] = 0
	if (record["admitted"] as Array).is_empty():
		records.erase(station)


static func _reset(p: Passenger) -> void:
	p.security_phase = Phase.NONE
	p.security_work = 0
